# frozen_string_literal: true

module FlowchartRuntime
  # WhereClauseBuilder
  #
  # Builds ActiveRecord where chains from condition configuration JSON.
  # Inspired by CiviCore's WhereClause.php system.
  #
  # Supports AND/OR compound groups, nested sub-groups, SQLite json_extract
  # for JSON data fields, and dynamic value resolution via ContextResolver.
  #
  # Field routing:
  #   - "data.field_name" → json_extract(data, '$.field_name')  (JSON column)
  #   - "customer_id"     → direct column query
  #
  # @example
  #   conditions = {
  #     "operator" => "AND",
  #     "rules" => [
  #       { "field" => "data.status", "op" => "==",  "value" => "approved" },
  #       { "field" => "data.amount", "op" => ">",   "value" => "1000" }
  #     ]
  #   }
  #   FlowchartRuntime::WhereClauseBuilder.apply(EntityEntry.all, conditions, ctx)
  #
  module WhereClauseBuilder
    class Error < StandardError; end

    DATA_PREFIX = "data."
    AGGREGATE_FUNCTIONS = %w[avg sum count min max].freeze

    module_function

    # Apply condition configuration to an ActiveRecord scope.
    #
    # @param scope      [ActiveRecord::Relation] base scope to filter
    # @param conditions [Hash, nil]              condition config with operator/rules
    # @param ctx        [Hash]                   runtime context for dynamic value resolution
    # @return [ActiveRecord::Relation] filtered scope
    def apply(scope, conditions, ctx, calculated_fields: {})
      return scope if conditions.blank?
      return scope unless conditions.is_a?(Hash)
      raise Error, "scope must support where" unless scope.respond_to?(:where)
      raise Error, "context must be a hash" unless ctx.is_a?(Hash)

      rules = conditions["rules"].presence
      return scope if rules.blank?

      operator = conditions.fetch("operator", "AND").upcase
      sql_fragment, bindings = build_group(rules, operator, ctx, calculated_fields)

      return scope if sql_fragment.blank?

      scope.where(sql_fragment, *bindings)
    end

    private

    module_function

    # Build a SQL fragment and binding array for a group of rules.
    #
    # @param rules    [Array]  array of rule hashes or nested group hashes
    # @param operator [String] "AND" or "OR"
    # @param ctx      [Hash]   runtime context
    # @return [Array(String, Array)] [sql_string, bindings]
    def build_group(rules, operator, ctx, calculated_fields = {})
      fragments = []
      bindings  = []

      rules.each do |rule|
        if nested_group?(rule)
          sub_operator = rule.fetch("operator", "AND").upcase
          sql, sub_bindings = build_group(rule["rules"], sub_operator, ctx, calculated_fields)
          next if sql.blank?

          fragments << "(#{sql})"
          bindings.concat(sub_bindings)
        else
          sql, rule_bindings = build_rule(rule, ctx, calculated_fields)
          next if sql.blank?

          fragments << sql
          bindings.concat(rule_bindings)
        end
      end

      return ["", []] if fragments.empty?

      joiner = operator == "OR" ? " OR " : " AND "
      [fragments.join(joiner), bindings]
    end

    # Determine whether a rule hash is a nested group (has its own operator/rules).
    def nested_group?(rule)
      rule.key?("rules")
    end

    # Build a single SQL condition fragment for one rule.
    #
    # @param rule [Hash] rule with "field", "op", "value" keys (or "subQuery" key)
    # @param ctx  [Hash] runtime context
    # @return [Array(String, Array)] [sql_fragment, bindings]
    def build_rule(rule, ctx, calculated_fields = {})
      field = rule["field"].to_s
      op    = rule["op"].to_s

      # Check if this is a calculated field reference
      if field.start_with?(DATA_PREFIX)
        json_field = field.sub(DATA_PREFIX, "")
        if calculated_fields.key?(json_field)
          calc_expr = calculated_fields[json_field]
          if rule.key?("subQuery")
            sub_query_sql = build_sub_query(rule["subQuery"], ctx)
            return build_comparison_raw(calc_expr, op, sub_query_sql)
          end
          value = resolve_value(rule["value"], ctx)
          return build_condition(calc_expr, op, value)
        end
      end

      if rule.key?("subQuery")
        sub_query_sql = build_sub_query(rule["subQuery"], ctx)
        expr = if field.start_with?(DATA_PREFIX)
                 safe_key = JsonPathValidator.safe_json_path!(field.sub(DATA_PREFIX, ""))
                 "json_extract(entity_entries.data, '$.#{safe_key}')"
        else
                 field
        end
        return build_comparison_raw(expr, op, sub_query_sql)
      end

      value = resolve_value(rule["value"], ctx)

      if field.start_with?(DATA_PREFIX)
        json_field = field.sub(DATA_PREFIX, "")
        build_json_condition(json_field, op, value)
      else
        build_column_condition(field, op, value)
      end
    end

    # Build a condition targeting a SQLite JSON column via json_extract.
    #
    # @param field [String] the key within the data JSON object
    # @param op    [String] operator string
    # @param value [Object] resolved comparison value
    # @return [Array(String, Array)]
    def build_json_condition(field, op, value)
      safe_field = JsonPathValidator.safe_json_path!(field)
      expr = "json_extract(entity_entries.data, '$.#{safe_field}')"
      build_condition(expr, op, value)
    end

    # Build a condition targeting a regular table column.
    #
    # @param field [String] column name
    # @param op    [String] operator string
    # @param value [Object] resolved comparison value
    # @return [Array(String, Array)]
    SAFE_COLUMN_RE = /\A[a-z_][a-z0-9_]*\z/

    def build_column_condition(field, op, value)
      safe = field.to_s
      raise Error, "unsafe column: #{field.inspect}" unless safe.match?(SAFE_COLUMN_RE)

      build_condition(safe, op, value)
    end

    # Build the SQL fragment and bindings for a given expression, operator, and value.
    # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
    def build_condition(expr, op, value)
      case op
      when "=="
        ["#{expr} = ?", [value]]
      when "!="
        ["#{expr} != ?", [value]]
      when ">"
        build_comparison(expr, ">", value)
      when ">="
        build_comparison(expr, ">=", value)
      when "<"
        build_comparison(expr, "<", value)
      when "<="
        build_comparison(expr, "<=", value)
      when "blank?"
        ["(#{expr} IS NULL OR #{expr} = '')", []]
      when "present?"
        ["(#{expr} IS NOT NULL AND #{expr} != '')", []]
      when "includes?", "contains"
        ["#{expr} LIKE ?", ["%#{value}%"]]
      when "in"
        values = Array(value)
        placeholders = values.map { "?" }.join(", ")
        ["#{expr} IN (#{placeholders})", values]
      when "not_in"
        values = Array(value)
        placeholders = values.map { "?" }.join(", ")
        ["#{expr} NOT IN (#{placeholders})", values]
      when "matches?"
        # SQLite has no native regex; use LIKE for simple wildcard patterns
        ["#{expr} LIKE ?", [value]]
      else
        ["", []]
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity

    # Build a numeric-aware comparison. If the value looks numeric, wrap with CAST.
    def build_comparison(expr, operator, value)
      if numeric_value?(value)
        ["CAST(#{expr} AS NUMERIC) #{operator} ?", [value.to_s]]
      else
        ["#{expr} #{operator} ?", [value]]
      end
    end

    # Build an aggregate sub-query SQL fragment from a subQuery config hash.
    #
    # @param sub_query_config [Hash] with keys: entityId, aggregateFunction, aggregateField, conditions
    # @param _ctx             [Hash] runtime context (reserved for future use)
    # @return [String] parenthesized SELECT sub-query SQL
    # rubocop:disable Metrics/MethodLength
    def build_sub_query(sub_query_config, _ctx)
      entity_id = sub_query_config["entityId"]
      func = sub_query_config["aggregateFunction"]&.downcase
      field = sub_query_config["aggregateField"] || "id"

      return "(0)" unless entity_id && AGGREGATE_FUNCTIONS.include?(func)

      agg_expr = if func == "count"
                   "COUNT(*)"
      else
                   safe_field = JsonPathValidator.safe_json_path!(field)
                   "#{func.upcase}(CAST(json_extract(ee.data, '$.#{safe_field}') AS NUMERIC))"
      end

      # Alias the inner table so customer_id correlates to the OUTER entity_entries
      # row. Without the alias, `customer_id = entity_entries.customer_id` is a
      # tautology against the inner FROM and silently aggregates across tenants.
      "(SELECT #{agg_expr} FROM entity_entries ee WHERE ee.entity_id = #{entity_id.to_i} AND ee.customer_id = entity_entries.customer_id)"
    end
    # rubocop:enable Metrics/MethodLength

    # Build a raw SQL comparison between an expression and a sub-query SQL fragment.
    # Always wraps the left-hand expression in CAST ... AS NUMERIC for sub-query comparisons.
    #
    # @param expr          [String] left-hand SQL expression
    # @param op            [String] operator string (e.g. ">", "==")
    # @param sub_query_sql [String] right-hand sub-query SQL
    # @return [Array(String, Array)] [sql_fragment, empty_bindings]
    def build_comparison_raw(expr, op, sub_query_sql)
      operator = case op
      when "==" then "="
      when "!=" then "!="
      when ">"  then ">"
      when ">=" then ">="
      when "<"  then "<"
      when "<=" then "<="
      else "="
      end
      ["CAST(#{expr} AS NUMERIC) #{operator} #{sub_query_sql}", []]
    end

    # Return true when value is a number or a string representing a number.
    def numeric_value?(value)
      case value
      when Numeric
        true
      when String
        value.match?(/\A-?\d+(\.\d+)?\z/)
      else
        false
      end
    end

    # Resolve a rule's value against the runtime context when it references "ctx.*".
    BRACKET_CTX = /\Actx\[:([a-zA-Z_]\w*)\]\z/

    def resolve_value(value, ctx)
      return resolve_ctx_path(value, ctx) if value.is_a?(String) && value.start_with?("ctx.")
      if value.is_a?(String) && (match = BRACKET_CTX.match(value))
        key = match[1]
        return ctx[key.to_sym] if ctx.key?(key.to_sym)
        return ctx[key] if ctx.key?(key)

        return nil
      end
      return value.map { |v| resolve_value(v, ctx) } if value.is_a?(Array)

      value
    end

    def resolve_ctx_path(value, ctx)
      keys = value.delete_prefix("ctx.").split(".").map { |part| part.match?(/\A\d+\z/) ? part.to_i : part.to_sym }
      Step.dig(ctx, *keys)
    end
  end
end
