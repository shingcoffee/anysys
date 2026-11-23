# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class RelatedRecordGenerator < BaseGenerator
          EMPTY_CONDITIONS = { "type" => "group", "joins" => [], "conditions" => [] }.freeze
          BoundView = Data.define(:name, :attribute_slugs)
          LOOKUP_OPS = %w[find list count update].freeze
          ORDERED_OPS = %w[find list].freeze
          WRITE_OPS = %w[create update].freeze
          MISSING_OPS = %w[find update].freeze

          generator_metadata do
            description "Finds, lists, counts, creates, or updates EntityEntry rows linked through a declared association on the source record (the other end of a Student-Course link, never the bridge rows). association is that target entity's name; a numeric id is also accepted. Use child_records to read or write the link rows and their own fields, and referenced_record to follow a reference field on the source. Reads association, operation, and modelVariable. Writes the related row(s) or count to resultVar. Create writes the target and a tenant-scoped bridge row. Fails as related_record.failed on resolver errors, or related_record.not_found when find/update onNotFound is fail and nothing matches."
            category :model_operations
            version "1.2.0"
            presentation icon: "M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1",
              color: "teal", single_use: false, privileged: false
          end

          config_schema do
            reference :association, source: :entity_associations, required: true, example: "Course",
                      description: "Name of the entity at the other end of the source record's declared association, such as Course. A numeric entity id is also accepted. Not the bridge/link entity."
            enum :operation, %w[find create update list count], default: "find",
                 description: "find returns the first related row. list returns rows. count returns an integer. create writes a target and a bridge row. update assigns and saves the first match."
            input :modelVariable, default: "model",
                  description: "Ctx path of the source EntityEntry the association starts from, such as model or student. Must be a loaded record, not an id."
            conditions :conditions, default: EMPTY_CONDITIONS, visible: { operation: LOOKUP_OPS },
                       description: "Extra filters on the related target rows, such as status == Open. Ignored for create. Leave empty to include every related row."
            mapping :assignments, key: :entity_attribute, value: :expression, default: [],
                    visible: { operation: WRITE_OPS },
                    description: "Target-entity attributes to set on create or update, such as title => \"Physics\". Keys are the related entity's fields, not the source's."
            enum :onNotFound, %w[nil fail], default: "fail", visible: { operation: MISSING_OPS },
                 description: "When find or update matches nothing: fail refuses the run as related_record.not_found (default). nil stores nil on resultVar and the step succeeds (update then writes nothing)."
            integer :limit, min: 1, max: 1000, default: 100, visible: { operation: "list" },
                    description: "Maximum related rows list returns (1-1000, default 100). find and count ignore this."
            literal :orderBy, visible: { operation: ORDERED_OPS },
                    description: "Target attribute or column to sort by, such as title or id. Blank sorts by id. Used by list and find (first after sort)."
            enum :orderDirection, %w[asc desc], default: "asc", visible: { operation: ORDERED_OPS },
                 description: "asc is lowest/oldest first (default). desc is highest/newest first, including when orderBy is blank (then by id)."
            output :resultVar, default: "related_record",
                   description: "Ctx variable for the result: one row (find/create/update), an array (list), or an integer (count). Use a plural name such as courses for list."

            validate do |cfg, errors|
              next unless ORDERED_OPS.include?(cfg["operation"].to_s)

              order = cfg["orderBy"].to_s.strip
              next if order.empty?
              next if FlowchartRuntime::ConditionInput.safe_column?(order.delete_prefix("data."))

              errors.add(:orderBy, :unsafe_column, column: order)
            end
          end

          def generate_body
            attempt('"related_record.failed"', FlowchartRuntime::JoinResolver::Error) do
              [
                "related = #{related_call}",
                assign(:resultVar, "related"),
                "return false if related == false",
                missing_guard,
                "true"
              ]
            end
          end

          # Keys are checked only from the page's own record, whose entity is known here.
          def bound_entity
            source = context_entity
            return unless source && value(:modelVariable).to_s.in?(["", "model"])

            association = value(:association).to_s.strip
            return present_entity(source) if association.empty?

            present_entity(association_target(source, association) || source)
          end

          private

          def related_call
            "FlowchartRuntime::JoinResolver.related(ctx, #{related_kwargs})"
          end

          def related_kwargs
            parts = [
              "association: #{read(:association)}",
              "operation: #{read(:operation)}",
              "source: #{read(:modelVariable)}",
              conditions_arg
            ]
            assignments = mapping_source(value(:assignments))
            parts << "assignments: #{assignments}" if assignments
            op = value(:operation).to_s
            parts << "limit: #{read(:limit)}" if op == "list"
            if ORDERED_OPS.include?(op)
              parts << "order_by: #{read(:orderBy)}" unless value(:orderBy).to_s.strip.empty?
              parts << "order_direction: #{read(:orderDirection)}" unless value(:orderDirection) == "asc"
            end
            parts.compact.join(", ")
          end

          def conditions_arg
            conditions = value(:conditions)
            return if blank_conditions?(conditions)

            "conditions: #{literal(conditions)}"
          end

          def blank_conditions?(conditions)
            return true if conditions.blank?
            return true if conditions.is_a?(Array) && conditions.empty?
            return false unless conditions.respond_to?(:[])

            conditions["type"] == "group" && Array(conditions["conditions"]).empty?
          end

          def missing_guard
            op = value(:operation)
            return unless MISSING_OPS.include?(op)
            return fail_with('"related_record.not_found"', unless: "related") if value(:onNotFound) == "fail"

            nil
          end

          def mapping_source(rows)
            pairs = Array(rows).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              next if key.to_s.blank?

              "#{literal(key.to_s)} => #{emit_expression(row["value"] || row[:value])}"
            end
            "{#{pairs.join(', ')}}" unless pairs.empty?
          end

          def context_entity
            context.is_a?(Hash) ? (context[:bound_entity] || context["bound_entity"]) : nil
          end

          # The association's target, given by id or by entity name.
          def association_target(source, association)
            ids = Array(source.try(:associations_list)).map { |row| row["target_entity_id"].to_s }
            targets = Entity.where(id: ids)
            association.match?(/\A\d+\z/) ? targets.find_by(id: association) : targets.find_by(name: association)
          end

          def present_entity(entity)
            return unless entity
            return entity if entity.respond_to?(:attribute_slugs)

            slugs = Array(entity.try(:property_schema_json)).filter_map do |row|
              row["name_slug"].to_s.presence if row.is_a?(Hash)
            end
            BoundView.new(entity.try(:name), slugs)
          end
        end
      end
    end
  end
end
