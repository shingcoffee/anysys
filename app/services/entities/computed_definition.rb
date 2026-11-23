# frozen_string_literal: true

module Entities
  # Resolved computed: live join slug + aggregate pieces behind the subquery that sorting, filtering and display (Entities::DerivedExpressions) all select.
  class ComputedDefinition
    attr_reader :name, :bridge, :join_slug, :source_slug, :function, :precision, :filter, :customer_id

    def self.resolve(field, _entity, customer_id:)
      return unless field.is_a?(Hash)

      config = field["config"]
      return unless config.is_a?(Hash)

      function = config["function"].to_s
      return unless ComputedCompiler::FUNCTIONS.include?(function)

      bridge = Entity.where(customer_id: customer_id, category: :bridge)
                     .find_by(id: config["bridge_entity_id"].to_i)
      return unless bridge

      idx = role_index(config["bridge_role"])
      return if idx.nil?

      schema = Array(bridge.property_schema_json)
      ref = schema[idx]
      return unless ref.is_a?(Hash)

      join_slug = FlowchartRuntime::JsonPathValidator.safe_json_path!(ref["name_slug"])
      source_slug = resolve_source_slug(config["source_slug"], function, schema)
      return if source_slug == :invalid

      precision = resolve_precision(config["precision"], function)
      filter = resolve_filter(config["filter"], schema)

      new(
        name: field["name_slug"].to_s,
        bridge: bridge,
        join_slug: join_slug,
        source_slug: source_slug,
        function: function,
        precision: precision,
        filter: filter,
        customer_id: customer_id.to_i
      )
    rescue StandardError
      nil
    end

    def self.role_index(role)
      case role.to_s
      when "source" then 0
      when "target" then 1
      end
    end

    # Returns the validated slug, nil for COUNT(*) (blank source), or :invalid.
    def self.resolve_source_slug(raw, function, schema)
      slug = raw.to_s
      return nil if function == "count" && slug.blank?
      return :invalid unless schema.any? { |attr| attr.is_a?(Hash) && attr["name_slug"] == slug }

      FlowchartRuntime::JsonPathValidator.safe_json_path!(slug)
    rescue FlowchartRuntime::JsonPathValidator::Error
      :invalid
    end
    private_class_method :resolve_source_slug

    # Clamped rather than rejected: a definition that bypassed validation (seed,
    # console, imported schema) must still emit sane SQL.
    def self.resolve_precision(raw, function)
      return if function == "count"
      return if raw.nil?

      raw.to_i.clamp(0, ComputedCompiler::MAX_PRECISION)
    end
    private_class_method :resolve_precision

    # Invalid filter → dropped (computed itself is kept).
    def self.resolve_filter(filter, schema)
      return unless filter.is_a?(Hash)

      slug = filter["slug"].to_s
      op = filter["op"].to_s
      return unless ComputedCompiler::FILTER_OPS.include?(op)

      attr = schema.find { |a| a.is_a?(Hash) && a["name_slug"] == slug }
      return unless attr

      {
        slug: FlowchartRuntime::JsonPathValidator.safe_json_path!(slug),
        op: op,
        value: filter["value"],
        numeric: ComputedCompiler::NUMERIC_HTML_TYPES.include?(attr["html_type"].to_s)
      }
    rescue FlowchartRuntime::JsonPathValidator::Error
      nil
    end
    private_class_method :resolve_filter

    def initialize(name:, bridge:, join_slug:, source_slug:, function:, precision:, filter:, customer_id:)
      @name = name
      @bridge = bridge
      @join_slug = join_slug
      @source_slug = source_slug
      @function = function
      @precision = precision
      @filter = filter
      @customer_id = customer_id
      freeze
    end

    def empty_default
      %w[sum count].include?(function) ? 0 : nil
    end

    def aggregate_sql(raw_alias)
      table_alias = safe_alias(raw_alias)
      expr = case function
      when "avg" then "AVG(#{numeric_extract(table_alias)})"
      when "sum" then "COALESCE(SUM(#{numeric_extract(table_alias)}), 0)"
      when "min" then "MIN(#{numeric_extract(table_alias)})"
      when "max" then "MAX(#{numeric_extract(table_alias)})"
      when "count"
        source_slug.present? ? "COUNT(#{json_extract(table_alias, source_slug)})" : "COUNT(*)"
      end

      if function != "count" && !precision.nil?
        "ROUND(#{expr}, #{precision.to_i})"
      else
        expr
      end
    end

    def subquery_sql(raw_alias)
      table_alias = safe_alias(raw_alias)
      <<~SQL.squish
        (SELECT #{aggregate_sql(table_alias)}
           FROM entity_entries #{table_alias}
          WHERE #{table_alias}.entity_id = #{bridge.id.to_i}
            AND #{table_alias}.customer_id = #{customer_id.to_i}
            AND #{join_predicate(table_alias)}
            #{filter_sql(table_alias)})
      SQL
    end

    private

    def json_extract(table_alias, slug)
      "json_extract(#{table_alias}.data, '$.#{slug}')"
    end

    # The emitters are public, so the alias is allowlisted here rather than
    # relying on every caller to have sanitized it first.
    def safe_alias(table_alias)
      alias_name = table_alias.to_s
      alias_name.match?(/\A[a-z]\d*\z/) ? alias_name : "b0"
    end

    def numeric_extract(table_alias)
      "CAST(#{json_extract(table_alias, source_slug)} AS NUMERIC)"
    end

    def join_predicate(table_alias)
      "#{json_extract(table_alias, join_slug)} = CAST(entity_entries.id AS TEXT)"
    end

    def filter_sql(table_alias)
      return "" unless filter

      lhs = json_extract(table_alias, filter[:slug])
      # SQLite orders INTEGER/REAL before TEXT, so comparing an extracted number
      # against a quoted string is false for every row. Numeric attributes must
      # be compared as numbers on both sides.
      if filter[:numeric]
        quoted = ActiveRecord::Base.connection.quote(filter[:value].to_f)
        "AND CAST(#{lhs} AS NUMERIC) #{filter[:op]} #{quoted}"
      else
        quoted = ActiveRecord::Base.connection.quote(filter[:value].to_s)
        "AND #{lhs} #{filter[:op]} #{quoted}"
      end
    end
  end
end
