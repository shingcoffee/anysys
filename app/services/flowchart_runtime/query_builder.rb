# frozen_string_literal: true

module FlowchartRuntime
  class QueryBuilder
    class Error < StandardError; end

    Result = Struct.new(:records, :total_count, :page, :per_page, :total_pages, :has_next, :sql, keyword_init: true)

    SAFE_COLUMN_RE = /\A[a-z_][a-z0-9_]*\z/
    SAFE_ASSOC_RE = /\A[a-z_][a-z0-9_]*\z/
    # Computed-column aliases come from author-controlled property_schema
    # name_slugs and are interpolated into the SELECT list, so they are
    # allowlisted here as well as validated on write. Digit-leading segments are
    # permitted because String#parameterize legitimately produces them
    # (e.g. "2024_revenue"), matching JsonPathValidator's per-segment rule.
    SAFE_ALIAS_RE = /\A\w+\z/
    # Allowlisted HAVING: COUNT(*) or AGG(safe_ident) compared to a number.
    SAFE_HAVING_RE = /\A(?:COUNT\(\*\)|(?:SUM|AVG|MIN|MAX|COUNT)\([a-z_][a-z0-9_]*\))\s*(?:>|<|>=|<=|=|!=)\s*-?\d+(?:\.\d+)?\z/i

    attr_reader :entity, :customer_id

    def initialize(entity:, customer_id:, scope: nil)
      raise Error, "customer id is required" if customer_id.nil?

      @entity = entity
      @customer_id = customer_id
      @row_scope = scope
      @conditions = []
      @order_field = nil
      @order_direction = nil
      @page_number = nil
      @page_size = nil
      @limit_value = nil
      @joins = []
      @computed_fields = []
      @group_fields = []
      @having_clause = nil
      @auto_calculated_fields = {}
      @calculated_injected = false
      @select_columns = nil
      @distinct = false
      @includes = []
      @preload = []
      @lock = false
      @readonly = false
    end

    def self.for_entity(entity, customer_id:, scope: nil)
      new(entity: entity, customer_id: customer_id, scope: scope)
    end

    def where(conditions, ctx)
      @conditions << { conditions: conditions, ctx: ctx }
      self
    end

    def order(field, direction = "asc")
      @order_field = field
      @order_direction = direction&.downcase == "desc" ? :desc : :asc
      self
    end

    # Same ceiling as ModuleEntriesResolver / EntityIndexSetting. A 0 or
    # negative page size is falsy in apply_pagination and would skip LIMIT,
    # dumping every matching row (including on public list modules).
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 200

    def paginate(page:, per_page:)
      @page_number = (page || 1).to_s.to_i
      @page_number = 1 if @page_number < 1
      requested = per_page.to_s.to_i
      @page_size = requested.positive? ? [requested, MAX_PER_PAGE].min : DEFAULT_PER_PAGE
      self
    end

    def limit(count)
      count = count.to_i
      @limit_value = count if count.positive?
      self
    end

    # Manual SQL computed columns are rejected. Entity schema calculated fields
    # are injected via FormulaCompiler in #inject_calculated_fields.
    def computed_field(_name, _expression)
      raise Error, "manual computed SQL expressions are not supported; use entity calculated fields"
    end

    def group(*fields)
      fields.flatten.each do |f|
        @group_fields << sanitize_group_field!(f.to_s)
      end
      self
    end

    def having(clause)
      text = clause.to_s.strip
      raise Error, "unsafe HAVING clause rejected" unless text.match?(SAFE_HAVING_RE)

      @having_clause = text
      self
    end

    def aggregate(function, field = nil)
      @aggregate_function = function
      @aggregate_field = field
      self
    end

    def select(*columns)
      cols = columns.flatten.flat_map { |c| c.to_s.split(",") }.map(&:strip).reject(&:empty?)
      cols.each do |col|
        raise Error, "unsafe select column: #{col.inspect}" unless col.match?(SAFE_COLUMN_RE)
      end
      @select_columns = cols
      self
    end

    def distinct
      @distinct = true
      self
    end

    def includes(*assocs)
      @includes = normalize_assocs(assocs)
      self
    end

    def preload(*assocs)
      @preload = normalize_assocs(assocs)
      self
    end

    def lock(mode = true)
      @lock = mode
      self
    end

    def readonly
      @readonly = true
      self
    end

    def join_entity(target_entity, via: nil, join_type: "inner")
      bridge = via || JoinResolver.detect_bridge(entity, target_entity)
      raise ArgumentError, "No bridge entity found linking #{entity.display_label} to #{target_entity.display_label}" unless bridge

      @joins << {
        target_entity: target_entity,
        bridge_entity: bridge,
        join_type: join_type
      }
      self
    end

    # Multi-agg helpers used by AggregateQueryGenerator — always tenant-scoped.
    # Each call resets aggregate state so multiple metrics can share one builder.
    def sum(field = nil)
      run_aggregate_metric(:sum, field)
    end

    def average(field = nil)
      run_aggregate_metric(:average, field)
    end

    def minimum(field = nil)
      run_aggregate_metric(:minimum, field)
    end

    def maximum(field = nil)
      run_aggregate_metric(:maximum, field)
    end

    def count(field = nil)
      run_aggregate_metric(:count, field)
    end

    def run_aggregate_metric(function, field)
      aggregate(function, field&.to_s)
      result = execute.records
      @aggregate_function = nil
      @aggregate_field = nil
      result
    end
    private :run_aggregate_metric

    def execute
      raise Error, "entity is required" if entity.nil?

      inject_calculated_fields
      scope = base_scope
      scope = apply_joins(scope)
      scope = apply_conditions(scope)
      scope = apply_select_modifiers(scope)

      if @aggregate_function
        return execute_aggregate(scope)
      end

      total = @computed_fields.any? || @select_columns ? scope.unscope(:select).count : scope.count
      scope = apply_order(scope)
      scope = apply_pagination(scope, total)

      Result.new(
        records: scope.to_a,
        total_count: total,
        page: @page_number,
        per_page: @page_size,
        total_pages: @page_size ? (total.to_f / @page_size).ceil : nil,
        has_next: @page_number && @page_size ? (@page_number * @page_size < total) : nil,
        sql: scope.to_sql
      )
    end

    private

    def normalize_assocs(assocs)
      assocs.flatten.map(&:to_s).map { |a| a.delete_prefix(":") }.map do |a|
        raise Error, "unsafe association: #{a.inspect}" unless a.match?(SAFE_ASSOC_RE)

        a.to_sym
      end
    end

    def sanitize_group_field!(field)
      if field.start_with?("data.")
        JsonPathValidator.safe_json_path!(field.sub("data.", ""))
        return field
      end
      raise Error, "unsafe group field: #{field.inspect}" unless field.match?(SAFE_COLUMN_RE)

      field
    end

    def base_scope
      scope = Entries.scope({ bound_entity: entity, customer_id: customer_id })
      scope = scope.merge(@row_scope) if @row_scope
      if @computed_fields.any?
        select_clause = ["entity_entries.*"]
        @computed_fields.each do |cf|
          # expressions originate only from FormulaCompiler
          select_clause << "#{cf[:expression]} AS #{cf[:name]}"
        end
        scope = scope.select(select_clause.join(", "))
      elsif @select_columns
        cols = (@select_columns + %w[id customer_id entity_id]).uniq
        scope = scope.select(cols.map { |c| "entity_entries.#{c}" }.join(", "))
      end
      scope
    end

    def apply_select_modifiers(scope)
      scope = scope.distinct if @distinct
      scope = scope.includes(*@includes) if @includes.any?
      scope = scope.preload(*@preload) if @preload.any?
      scope = scope.lock if @lock
      scope = scope.readonly if @readonly
      scope
    end

    def apply_joins(scope)
      @joins.each do |join_config|
        resolver = JoinResolver.new(
          source_entity: entity,
          target_entity: join_config[:target_entity],
          bridge_entity: join_config[:bridge_entity],
          customer_id: customer_id
        )
        scope = resolver.apply_sql_join(scope, join_type: join_config[:join_type])
      end
      scope
    end

    def apply_conditions(scope)
      @conditions.each do |cond|
        scope = WhereClauseBuilder.apply(scope, cond[:conditions], cond[:ctx], calculated_fields: @auto_calculated_fields)
      end
      scope
    end

    def apply_order(scope)
      return scope unless @order_field

      computed_expr = @auto_calculated_fields[@order_field] ||
                      @computed_fields.find { |cf| cf[:name] == @order_field }&.dig(:expression)
      if computed_expr
        return scope.order(Arel.sql("(#{computed_expr}) #{@order_direction}"))
      end

      if @order_field.start_with?("data.")
        json_field = JsonPathValidator.safe_json_path!(@order_field.sub("data.", ""))
        scope.order(Arel.sql("json_extract(entity_entries.data, '$.#{json_field}') #{@order_direction}"))
      else
        raise Error, "unsafe order field: #{@order_field.inspect}" unless @order_field.to_s.match?(SAFE_COLUMN_RE)

        scope.order(@order_field => @order_direction)
      end
    end

    def apply_pagination(scope, _total)
      return scope.limit(@limit_value) if @limit_value && !(@page_number && @page_size)
      return scope unless @page_number && @page_size

      offset = (@page_number - 1) * @page_size
      scope.limit(@page_size).offset(offset)
    end

    def execute_aggregate(scope)
      scope = apply_group(scope)
      scope = apply_having(scope)

      records = case @aggregate_function
      when :count then scope.count
      when :sum then scope.sum(aggregate_expression)
      when :average then scope.average(aggregate_expression)
      when :minimum then scope.minimum(aggregate_expression)
      when :maximum then scope.maximum(aggregate_expression)
      else scope.count
      end

      Result.new(
        records: records,
        total_count: records.is_a?(Hash) ? records.size : 1,
        page: nil, per_page: nil, total_pages: nil, has_next: nil, sql: nil
      )
    end

    def aggregate_expression
      if @aggregate_field
        safe_field = JsonPathValidator.safe_json_path!(@aggregate_field)
        Arel.sql("CAST(json_extract(entity_entries.data, '$.#{safe_field}') AS NUMERIC)")
      else
        Arel.star
      end
    end

    def apply_group(scope)
      return scope if @group_fields.empty?

      group_exprs = @group_fields.map do |f|
        if f.start_with?("data.")
          json_field = JsonPathValidator.safe_json_path!(f.sub("data.", ""))
          Arel.sql("json_extract(entity_entries.data, '$.#{json_field}')")
        else
          f
        end
      end
      scope.group(*group_exprs)
    end

    def apply_having(scope)
      return scope unless @having_clause

      scope.having(@having_clause)
    end

    def inject_calculated_fields
      return if @entity.nil? || @calculated_injected

      ::Entities::DerivedExpressions.for(@entity, customer_id: customer_id).each { |expression| register_computed_field(expression) }
      @calculated_injected = true
    end

    def register_computed_field(cf)
      @computed_fields << { name: cf[:name], expression: cf[:sql] }
      @auto_calculated_fields[cf[:name]] = cf[:sql]
    end

    def safe_alias?(name)
      name.to_s.match?(SAFE_ALIAS_RE)
    end
  end
end
