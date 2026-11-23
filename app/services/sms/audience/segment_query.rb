# frozen_string_literal: true

require "date"

module Sms
  module Audience
    # Bounded grouped AST; every request value is an Arel quoted value, and
    # every SQL identifier/function is chosen by this compiler, not the request.
    class SegmentQuery
      MAX_JSON_BYTES = 32.kilobytes
      MAX_DEPTH = 8
      MAX_NODES = 100
      MAX_VALUE_BYTES = 1024
      GROUP_KEYS = %w[type conditions joins].freeze
      LEAF_KEYS = %w[type field operator value].freeze
      InvalidRules = Class.new(StandardError)
      private_constant :InvalidRules

      def self.call(customer:, rules:, field_specs: nil)
        new(customer: customer, rules: rules, field_specs: field_specs).relation
      end

      def self.valid?(customer:, rules:, field_specs: nil)
        new(customer: customer, rules: rules, field_specs: field_specs).valid?
      end

      def initialize(customer:, rules:, field_specs: nil)
        @customer, @rules, @field_specs = customer, rules, field_specs
        @nodes = 0
      end

      def relation
        relation = Sms::Contact.for_customer(@customer&.id)
        return relation.none unless valid?

        @predicate ? relation.where(@predicate) : relation
      end

      def valid?
        return @valid if defined?(@valid)
        @valid = false
        return false unless @customer&.persisted? && Contracts::Bounds.object?(@rules, bytes: MAX_JSON_BYTES)
        validate_specs!
        @predicate = group(@rules, depth: 0)
        @valid = true
      rescue InvalidRules, JSON::GeneratorError, EncodingError, SystemStackError
        @valid = false
      end

      private

      def validate_specs!
        return if @field_specs.nil?
        raise InvalidRules unless @field_specs.is_a?(Hash) && @field_specs.size <= FieldCatalog::MAX_CUSTOM_FIELDS
        @field_specs.each do |field, type|
          raise InvalidRules unless field.is_a?(String) && field.start_with?("attributes.") &&
            field.delete_prefix("attributes.").match?(Contracts::Bounds::CUSTOM_KEY) && %w[string float boolean].include?(type)
        end
      end

      def count_node!(depth)
        @nodes += 1
        raise InvalidRules if depth > MAX_DEPTH || @nodes > MAX_NODES
      end

      def group(raw, depth:)
        count_node!(depth)
        raise InvalidRules unless raw.is_a?(Hash) && raw.keys.all? { |key| key.is_a?(String) }
        return nil if depth.zero? && raw.empty?
        raise InvalidRules unless (raw.keys - GROUP_KEYS).empty? && [nil, "group"].include?(raw["type"])
        children = raw["conditions"]
        joins = raw.fetch("joins", [])
        raise InvalidRules unless children.is_a?(Array) && joins.is_a?(Array) && (depth.zero? || children.any?) &&
          joins.size == [children.size - 1, 0].max && joins.all? { |join| %w[AND OR].include?(join) }
        return nil if children.empty?

        nodes = children.map { |child| member(child, depth: depth + 1) }
        nodes.drop(1).each_with_index.reduce(nodes.first) do |expression, (node, index)|
          Arel::Nodes::Grouping.new(joins[index] == "OR" ? expression.or(node) : expression.and(node))
        end
      end

      def member(raw, depth:)
        raise InvalidRules unless raw.is_a?(Hash)
        return group(raw, depth: depth) if raw["type"] == "group" || raw.key?("conditions")
        count_node!(depth)
        raise InvalidRules unless (raw.keys - LEAF_KEYS).empty? && [nil, "condition"].include?(raw["type"])
        field, operator, value = raw.values_at("field", "operator", "value")
        raise InvalidRules unless field.is_a?(String) && operator.is_a?(String)
        type = resolve_type(field)
        raise InvalidRules unless type && FieldCatalog::OPERATORS_BY_TYPE.fetch(type).include?(operator)
        raise InvalidRules unless Contracts::Bounds.scalar?(value) && (!value.is_a?(String) || value.bytesize <= MAX_VALUE_BYTES)
        column, guard = column_for(field, type)
        predicate = comparison(column, type, operator, value)
        guard ? guard.and(predicate) : predicate
      end

      def resolve_type(field)
        if FieldCatalog::ROOT_FIELDS.include?(field)
          return %w[created_at updated_at].include?(field) ? :datetime : :string
        end
        specs = @field_specs || (@catalog ||= FieldCatalog.new(customer: @customer)).custom_specs
        specs[field]&.to_sym
      end

      def column_for(field, type)
        table = Sms::Contact.arel_table
        return [table[field], nil] if FieldCatalog::ROOT_FIELDS.include?(field)

        key = field.delete_prefix("attributes.")
        raise InvalidRules unless key.match?(Contracts::Bounds::CUSTOM_KEY)
        case Sms::Contact.connection.adapter_name
        when "SQLite"
          args = [table[:custom_attributes], Arel::Nodes.build_quoted("$.#{key}")]
          column = Arel::Nodes::NamedFunction.new("json_extract", args)
          json_type = Arel::Nodes::NamedFunction.new("json_type", args)
          types = { string: %w[text], float: %w[integer real], boolean: %w[true false] }.fetch(type)
          [column, json_type.in(types)]
        when "PostgreSQL"
          json = Arel::Nodes::InfixOperation.new("::", table[:custom_attributes], Arel.sql("jsonb"))
          item = Arel::Nodes::InfixOperation.new("->", json, Arel::Nodes.build_quoted(key))
          text = Arel::Nodes::InfixOperation.new("->>", json, Arel::Nodes.build_quoted(key))
          json_type = Arel::Nodes::NamedFunction.new("jsonb_typeof", [item])
          guard = json_type.eq({ string: "string", float: "number", boolean: "boolean" }.fetch(type))
          cast = type == :string ? text : Arel::Nodes::InfixOperation.new("::", text, Arel.sql(type == :float ? "numeric" : "boolean"))
          # CASE, rather than a WHERE guard alone, prevents wrong-type casts.
          [Arel::Nodes::Case.new.when(guard).then(cast).else(nil), guard]
        else
          raise NotImplementedError, Sms::Contact.connection.adapter_name
        end
      end

      def comparison(column, type, operator, raw)
        case operator
        when "is_blank" then type == :string ? column.eq(nil).or(column.eq("")) : column.eq(nil)
        when "is_present" then type == :string ? column.not_eq(nil).and(column.not_eq("")) : column.not_eq(nil)
        when "contains", "not_contains"
          value = cast(:string, raw)
          pattern = "%#{Sms::Contact.sanitize_sql_like(value)}%"
          operator == "contains" ? column.matches(pattern, "\\") : column.does_not_match(pattern, "\\")
        else
          value = cast(type, raw)
          method = { "equals" => :eq, "not_equals" => :not_eq, "greater_than" => :gt, "less_than" => :lt,
            "after" => :gt, "before" => :lt }.fetch(operator)
          column.public_send(method, value)
        end
      end

      def cast(type, value)
        case type
        when :string
          raise InvalidRules unless Contracts::Bounds.text?(value, bytes: MAX_VALUE_BYTES) && value.is_a?(String)
          value
        when :float
          raise InvalidRules unless value.is_a?(String) || value.is_a?(Numeric)
          parsed = Float(value, exception: false)
          raise InvalidRules unless parsed&.finite?
          parsed
        when :boolean
          raise InvalidRules unless [true, false, "true", "false"].include?(value)
          value == true || value == "true"
        when :datetime
          raise InvalidRules unless value.is_a?(String) && Contracts::Bounds::TIME_FORMAT.match?(value)
          DateTime.iso8601(value)
          Time.iso8601(value).utc
        end
      rescue ArgumentError, TypeError
        raise InvalidRules
      end
    end
  end
end
