# frozen_string_literal: true

module Entities
  # Derived (computed and calculated) values of an entity's entries for one
  # tenant, in one query for any number of entries. It selects the same
  # DerivedExpressions SQL the entries list sorts by, so a link stored with a
  # numeric parent id counts the same in both.
  module DerivedValues
    module_function

    # => { entry_id => { slug => value } } for every requested id.
    def call(entity:, customer_id:, entry_ids:)
      ids = Array(entry_ids).map(&:to_i).uniq
      return {} if ids.empty? || entity.nil?

      fields = entity.computed_fields + entity.calculated_fields
      return ids.index_with { {} } if fields.empty?

      expressions = DerivedExpressions.for(entity, customer_id: customer_id)
      defaults = fields.to_h { |field| [field["name_slug"].to_s, empty_default(field, expressions)] }
      result = ids.index_with { defaults.dup }
      return result if expressions.empty?

      EntityEntry.where(customer_id: customer_id, entity_id: entity.id, id: ids)
                 .pluck(:id, *expressions.map { |expression| Arel.sql(expression[:sql]) })
                 .each do |id, *values|
                   expressions.zip(values).each { |expression, raw| result[id][expression[:name]] = coerce(raw, expression) }
                 end
      result
    end

    # One query per entity for the entries of the tenant; other records and
    # other tenants' rows are skipped.
    def prime!(entries, customer_id:)
      cid = customer_id.to_i
      Array(entries).grep(EntityEntry).select { |entry| entry.customer_id.to_i == cid }
                    .group_by(&:entity_id).each_value do |group|
        values = call(entity: group.first.entity, customer_id: cid, entry_ids: group.map(&:id))
        group.each { |entry| entry.prime_derived_values!(values.fetch(entry.id, {})) }
      end
    end

    # Count is an integer and other aggregates are floats; calculated values
    # stay as SQLite returns them.
    def coerce(raw, expression)
      return raw unless expression[:kind] == :computed

      definition = expression[:definition]
      return definition.empty_default if raw.nil?
      return raw.to_i if definition.function == "count"

      Float(raw)
    rescue ArgumentError, TypeError
      raw
    end

    def empty_default(field, expressions)
      return unless field["type"] == Entity::COMPUTED_TYPE

      definition = expressions.find { |expression| expression[:name] == field["name_slug"].to_s }&.dig(:definition)
      return definition.empty_default if definition

      config = field["config"]
      %w[sum count].include?(config.is_a?(Hash) ? config["function"].to_s : "") ? 0 : nil
    end
  end
end
