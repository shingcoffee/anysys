# frozen_string_literal: true

require "date"

module Emails
  module Audience
    # Compiles a segment-rules AST into a tenant-scoped ActiveRecord::Relation
    # over Authentication::User.
    #
    # The AST is a recursive group modeled on the flowchart Decision condition
    # builder — each group carries an independent per-join AND/OR array:
    #   { "type" => "group",
    #     "joins" => ["AND"|"OR", ...],   # length == conditions.length - 1
    #     "conditions" => [ leaf | group, ... ] }
    #   leaf: { "field" =>, "operator" =>, "value" => }
    #
    # Members are combined LEFT-ASSOCIATIVELY: conditions [A, B, C] with
    # joins ["AND", "OR"] compile to ((A AND B) OR C) — matching the flowchart's
    # CodeGenerators::Shared::ConditionBuilder fold exactly.
    #
    # The flat shape ({ "match" => "all"|"any", "conditions" => [leaf...] })
    # fills every join with the same operator.
    #
    # SAFETY INVARIANTS:
    #   * Every field/operator/value and group shape must be valid. One invalid
    #     node rejects the entire tree; dropping AND nodes broadens an audience.
    #   * Values are bound as Arel parameters (never string-interpolated).
    #   * Only an intentionally empty ROOT selects all tenant users. Malformed
    #     trees select nobody, including on re-evaluation of persisted lists.
    #   * Depth/node budgets bound compilation; the root relation stays tenant-scoped.
    class SegmentQuery
      MAX_DEPTH = 12
      MAX_NODES = 500
      MAX_VALUE_BYTES = 4.kilobytes
      INTEGER_RANGE = (-(2**63)..(2**63 - 1)).freeze
      GROUP_KEYS = %w[type conditions joins match].freeze
      LEAF_KEYS = %w[type field operator value].freeze
      TIME_FORMAT = /\A\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d{1,9})?)?(?:Z|[+-]\d{2}:\d{2})?)?\z/
      InvalidRules = Class.new(StandardError)
      private_constant :InvalidRules

      def self.call(customer:, rules:)
        new(customer: customer, rules: rules).relation
      end

      def self.valid?(rules)
        new(customer: nil, rules: rules).valid?
      end

      def initialize(customer:, rules:)
        @customer = customer
        @rules    = rules
        @catalog  = Emails::SendActivities::FieldCatalog.new
        @nodes = 0
        @associations = []
        @valid = true
      end

      def relation
        rel = Authentication::User.for_customer(@customer.id)
        expression = predicate
        return rel.none unless valid?
        return rel unless expression

        rel = rel.left_outer_joins(*@associations.uniq) if @associations.any?
        rel.where(expression).distinct
      end

      def count
        relation.count
      end

      def valid?
        predicate
        @valid
      end

      private

      attr_reader :customer, :rules, :catalog

      def predicate
        return @predicate if defined?(@predicate)

        @predicate = compile_group(@rules, depth: 0)
      rescue InvalidRules
        @valid = false
        @predicate = nil
      end

      def compile_group(raw, depth:)
        raise InvalidRules unless raw.is_a?(Hash) && depth <= MAX_DEPTH

        group = raw.stringify_keys
        return nil if depth.zero? && group.empty?

        count_node!
        raise InvalidRules if (group.keys - GROUP_KEYS).any? || ![nil, "group"].include?(group["type"])
        members = group["conditions"]
        raise InvalidRules unless members.is_a?(Array) && members.size <= MAX_NODES && (depth.zero? || members.any?)

        joins = group.fetch("joins", [])
        raise InvalidRules unless joins.is_a?(Array)

        if group.key?("match")
          raise InvalidRules unless %w[all any].include?(group["match"])

          joins = Array.new([members.size - 1, 0].max, group["match"] == "any" ? "OR" : "AND") if joins.empty?
        end
        raise InvalidRules unless joins.size == [members.size - 1, 0].max &&
          joins.all? { |join| join.is_a?(String) && %w[AND OR].include?(join.upcase) }
        return nil if members.empty?

        nodes = members.map { |member| compile_member(member, depth: depth + 1) }
        nodes.drop(1).each_with_index.reduce(nodes.first) do |expression, (node, index)|
          joins[index].upcase == "OR" ? expression.or(node) : expression.and(node)
        end
      end

      def compile_member(raw, depth:)
        raise InvalidRules unless raw.is_a?(Hash) && depth <= MAX_DEPTH

        member = raw.stringify_keys
        return compile_group(member, depth: depth) if member["type"] == "group" || member.key?("conditions")

        count_node!
        raise InvalidRules if (member.keys - LEAF_KEYS).any? || ![nil, "condition"].include?(member["type"])

        compile_leaf(member)
      end

      def compile_leaf(cond)
        raise InvalidRules unless cond["field"].is_a?(String) && cond["operator"].is_a?(String)

        resolved = catalog.resolve(cond["field"])
        operators = resolved && Emails::SendActivities::FieldCatalog::OPERATORS_BY_TYPE[resolved[:type]]
        raise InvalidRules unless operators&.include?(cond["operator"])

        validate_scalar!(cond["value"])
        @associations << resolved[:association] if resolved[:association]
        predicate_for(resolved, cond["operator"], cond["value"])
      end

      def count_node!
        @nodes += 1
        raise InvalidRules if @nodes > MAX_NODES
      end

      def arel_column(resolved)
        klass = if resolved[:association]
                  Authentication::User.reflect_on_association(resolved[:association]).klass
        else
                  Authentication::User
        end
        klass.arel_table[resolved[:column]]
      end

      def predicate_for(resolved, operator, value)
        col  = arel_column(resolved)
        type = resolved[:type]

        case operator
        when "equals"       then col.eq(cast_value(type, value))
        when "not_equals"   then col.not_eq(cast_value(type, value))
        when "contains"     then col.matches("%#{sanitize_like(value)}%", "\\")
        when "not_contains" then col.does_not_match("%#{sanitize_like(value)}%", "\\")
        when "greater_than" then col.gt(cast_value(type, value))
        when "less_than"    then col.lt(cast_value(type, value))
        when "after"
          col.gt(parse_time(value))
        when "before"
          col.lt(parse_time(value))
        when "is_blank"
          string_type?(type) ? col.eq(nil).or(col.eq("")) : col.eq(nil)
        when "is_present"
          string_type?(type) ? col.not_eq(nil).and(col.not_eq("")) : col.not_eq(nil)
        end
      end

      def string_type?(type)
        type == :string
      end

      def cast_value(type, value)
        case type
        when :integer
          text = value.is_a?(String) ? value.strip : value.to_s
          raise InvalidRules unless (value.is_a?(String) || value.is_a?(Integer)) && text.match?(/\A[+-]?\d+\z/)

          parsed = Integer(text, 10)
          raise InvalidRules unless INTEGER_RANGE.cover?(parsed)

          parsed
        when :float
          raise InvalidRules unless value.is_a?(String) || value.is_a?(Numeric)

          parsed = Float(value, exception: false)
          raise InvalidRules unless parsed&.finite?

          parsed
        when :boolean
          raise InvalidRules unless [true, false, "true", "false", "1", "0", 1, 0].include?(value)

          ActiveModel::Type::Boolean.new.cast(value)
        when :datetime, :date then parse_time(value)
        else
          raise InvalidRules unless value.is_a?(String)

          value
        end
      end

      def parse_time(value)
        raise InvalidRules unless value.is_a?(String) && TIME_FORMAT.match?(value)

        normalized = value.tr(" ", "T")
        DateTime.iso8601(normalized)
        Time.zone.iso8601(normalized)
      rescue ArgumentError, TypeError
        raise InvalidRules
      end

      # Escape LIKE wildcards in user input; the value itself is still bound
      # by Arel#matches as a parameter.
      def sanitize_like(value)
        raise InvalidRules unless value.is_a?(String)

        Authentication::User.sanitize_sql_like(value)
      end

      def validate_scalar!(value)
        valid = value.nil? || value.is_a?(String) || value.is_a?(Integer) ||
          value == true || value == false || (value.is_a?(Float) && value.finite?)
        raise InvalidRules unless valid
        raise InvalidRules if value.is_a?(String) && value.bytesize > MAX_VALUE_BYTES
      end
    end
  end
end
