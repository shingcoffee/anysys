# frozen_string_literal: true

module Entities
  module ComputedCompiler
    FUNCTIONS = %w[avg sum count min max].freeze
    FILTER_OPS = %w[= != > >= < <=].freeze
    # Canonical for the whole computed feature: which bridge attributes may be
    # aggregated, and which filter comparisons must be made numerically.
    NUMERIC_HTML_TYPES = %w[number range].freeze
    MAX_PRECISION = 6
    TABLE_ALIAS_RE = /\Ab\d+\z/

    # => [{ name: "average_score", sql: "(SELECT ...)" or nil, definition: ComputedDefinition or nil }, ...]
    def self.compile_all(entity, customer_id:)
      Array(entity&.computed_fields).each_with_index.map do |field, idx|
        definition = ComputedDefinition.resolve(field, entity, customer_id: customer_id)
        { name: field["name_slug"].to_s, sql: subquery(definition, "b#{idx}"), definition: definition }
      end
    end

    # => "(SELECT ...)" or nil. Never raises.
    def self.compile(computed_field, entity, customer_id:, table_alias: "b0")
      subquery(ComputedDefinition.resolve(computed_field, entity, customer_id: customer_id), table_alias)
    end

    def self.subquery(definition, table_alias)
      definition&.subquery_sql(safe_table_alias(table_alias))
    rescue StandardError
      nil
    end
    private_class_method :subquery

    def self.safe_table_alias(table_alias)
      alias_name = table_alias.to_s
      alias_name.match?(TABLE_ALIAS_RE) ? alias_name : "b0"
    end
    private_class_method :safe_table_alias
  end
end
