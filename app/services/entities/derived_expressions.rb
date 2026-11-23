# frozen_string_literal: true

module Entities
  # The SQL of an entity's derived fields for one tenant: computed (bridge
  # aggregate) subqueries, then calculated formulas that may read them.
  # FlowchartRuntime::QueryBuilder, the entries-list sort and DerivedValues all
  # use it, so a value sorts, filters and displays the same way everywhere.
  module DerivedExpressions
    SAFE_NAME = FlowchartRuntime::QueryBuilder::SAFE_ALIAS_RE

    module_function

    # => [{ name:, sql:, kind: :computed | :calculated, definition: (computed only) }]
    def for(entity, customer_id:)
      return [] if entity.nil?

      computed = ComputedCompiler.compile_all(entity, customer_id: customer_id)
                                 .select { |row| usable?(row) }
                                 .map { |row| row.merge(kind: :computed) }
      computed + calculated(entity, computed.to_h { |row| [row[:name], row[:sql]] })
    end

    # A malformed formula degrades to "no calculated fields" rather than
    # failing the read; only the compiler's own error is absorbed.
    def calculated(entity, resolved)
      schema = Array(entity.property_schema_json).grep(Hash)
      FlowchartRuntime::FormulaCompiler.compile_all(schema, resolved: resolved)
                                       .select { |row| usable?(row) }
                                       .map { |row| row.merge(kind: :calculated) }
    rescue FlowchartRuntime::FormulaError
      []
    end

    def usable?(row)
      row[:sql].present? && SAFE_NAME.match?(row[:name].to_s)
    end
  end
end
