# frozen_string_literal: true

require "date"

module PlatformAnnouncements
  # Compiles a segment-rules AST into an ActiveRecord::Relation over Customer.
  #
  # Same AST as Emails::Audience::SegmentQuery (recursive group, per-join
  # AND/OR, left-associative). Empty or unusable rules match nobody — unlike
  # email lists, an empty selected audience must not mean "all customers".
  #
  # Every node must be semantically valid. Dropping one bad AND condition can
  # broaden delivery, so invalid trees select nobody and are rejected on save
  # and audience preview. Values remain bound through Arel.
  class CustomerQuery
    MAX_DEPTH = 12
    MAX_NODES = 500
    INTEGER_RANGE = (-(2**63)..(2**63 - 1)).freeze
    GROUP_KEYS = %w[type conditions joins match].freeze
    LEAF_KEYS = %w[type field operator value].freeze
    TIME_FORMAT = /\A\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d{1,9})?)?(?:Z|[+-]\d{2}:\d{2})?)?\z/
    InvalidRules = Class.new(StandardError)
    private_constant :InvalidRules

    def self.call(rules:)
      new(rules: rules).relation
    end

    def self.matches?(customer_id:, rules:)
      call(rules: rules).where(id: customer_id).exists?
    end

    def self.usable?(rules)
      new(rules: rules).usable?
    end

    def self.valid?(rules)
      new(rules: rules).valid?
    end

    # Evaluates MANY rule sets against ONE customer in a single round trip.
    #
    # The banner renders on every admin page, so testing each announcement with
    # its own EXISTS query is an N+1 on the hot path. Each rule set is instead
    # projected as `CASE WHEN <predicate> THEN 1 ELSE 0 END` over the single
    # customer row, and the flags are read back positionally.
    #
    # @param rules_by_key [Hash] arbitrary key => rules AST
    # @return [Array] the subset of keys whose rules match the customer
    def self.matching_keys(customer_id:, rules_by_key:)
      compiled = rules_by_key.filter_map do |key, rules|
        predicate = new(rules: rules).predicate
        [ key, predicate ] if predicate
      end
      return [] if compiled.empty? || customer_id.blank?

      projections = compiled.each_with_index.map do |(_key, predicate), index|
        Arel::Nodes::Case.new.when(predicate).then(1).else(0).as("segment_match_#{index}")
      end

      flags = Array(Customer.where(id: customer_id).pick(*projections))
      return [] if flags.empty?

      compiled.each_with_index.filter_map { |(key, _predicate), index| key if flags[index].to_i == 1 }
    end

    def initialize(rules:)
      @rules   = rules
      @catalog = CustomerFieldCatalog.new
      @nodes = 0
      @valid = true
    end

    # The compiled Arel predicate, or nil when the rules select nobody.
    def predicate
      return @predicate if defined?(@predicate)

      @predicate = compile_group(@rules.nil? ? {} : @rules, depth: 0)
    rescue InvalidRules
      @valid = false
      @predicate = nil
    end

    def relation
      predicate ? Customer.where(predicate) : Customer.none
    end

    def usable?
      predicate.present?
    end

    def valid?
      predicate
      @valid
    end

    private

    attr_reader :rules, :catalog

    def compile_group(raw, depth:)
      raise InvalidRules unless raw.is_a?(Hash) && depth <= MAX_DEPTH

      group = raw.stringify_keys
      return nil if depth.zero? && group.empty?
      count_node!
      raise InvalidRules if (group.keys - GROUP_KEYS).any? || ![nil, "group"].include?(group["type"])

      members = group["conditions"]
      raise InvalidRules unless members.is_a?(Array) && (depth.zero? || members.any?)

      joins = group.fetch("joins", [])
      raise InvalidRules unless joins.is_a?(Array)
      if group.key?("match")
        raise InvalidRules unless %w[all any].include?(group["match"])

        joins = Array.new([members.length - 1, 0].max, group["match"] == "any" ? "OR" : "AND") if joins.empty?
      end
      raise InvalidRules unless joins.length == [members.length - 1, 0].max &&
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

    def count_node!
      @nodes += 1
      raise InvalidRules if @nodes > MAX_NODES
    end

    def compile_leaf(cond)
      resolved = catalog.resolve(cond["field"])
      raise InvalidRules unless cond["field"].is_a?(String) && resolved &&
        cond["operator"].is_a?(String) && resolved[:operators].include?(cond["operator"])

      predicate_for(resolved, cond["operator"], cond["value"])
    end

    def arel_column(resolved)
      Customer.arel_table[resolved[:column]]
    end

    def predicate_for(resolved, operator, value)
      col  = arel_column(resolved)
      type = resolved[:type]

      case operator
      when "equals"       then col.eq(cast_value(resolved, value))
      when "not_equals"   then col.not_eq(cast_value(resolved, value))
      when "contains"     then col.matches("%#{sanitize_like(value)}%", "\\")
      when "not_contains" then col.does_not_match("%#{sanitize_like(value)}%", "\\")
      when "greater_than" then col.gt(cast_value(resolved, value))
      when "less_than"    then col.lt(cast_value(resolved, value))
      when "after"
        col.gt(parse_time(value))
      when "before"
        col.lt(parse_time(value))
      when "is_blank"
        validate_scalar!(value)
        string_type?(type) && !resolved[:enum] ? col.eq(nil).or(col.eq("")) : col.eq(nil)
      when "is_present"
        validate_scalar!(value)
        string_type?(type) && !resolved[:enum] ? col.not_eq(nil).and(col.not_eq("")) : col.not_eq(nil)
      end
    end

    def string_type?(type)
      type == :string
    end

    def cast_value(resolved, value)
      return enum_db_value(resolved[:column], value) if resolved[:enum]

      case resolved[:type]
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

    def enum_db_value(column, value)
      mapping = Customer.defined_enums[column]
      raise InvalidRules unless mapping && (value.is_a?(String) || value.is_a?(Integer))

      key = value.to_s
      return mapping[key] if mapping.key?(key)

      int = Integer(key, 10, exception: false) if key.match?(/\A[+-]?\d+\z/)
      return int if int && mapping.value?(int)

      raise InvalidRules
    end

    def parse_time(value)
      raise InvalidRules unless value.is_a?(String) && TIME_FORMAT.match?(value)

      normalized = value.tr(" ", "T")
      DateTime.iso8601(normalized)
      Time.zone.iso8601(normalized)
    rescue ArgumentError, TypeError
      raise InvalidRules
    end

    def sanitize_like(value)
      raise InvalidRules unless value.is_a?(String)

      Customer.sanitize_sql_like(value)
    end

    def validate_scalar!(value)
      raise InvalidRules unless value.nil? || value.is_a?(String) || value.is_a?(Integer) ||
        value == true || value == false || (value.is_a?(Float) && value.finite?)
    end
  end
end
