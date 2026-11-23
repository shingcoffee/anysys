# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class ReferencedRecordGenerator < BaseGenerator
          BoundView = Data.define(:name, :attribute_slugs)

          generator_metadata do
            description "Loads, or updates and saves, the EntityEntry a reference field on a loaded record points at, such as a line's product or a row's parent order. Use child_records when other records point at this one, related_record to walk a many-to-many association, and adjust_number to change a number on the referenced row under a concurrency lock. Reads modelVariable, field, and operation. Writes the referenced row to resultVar. Fails as referenced_record.not_found when the field is blank or the row is gone and onNotFound is fail, or referenced_record.failed on a non-reference field or save error. Update with onNotFound nil skips assignments when nothing is referenced."
            category :model_operations
            version "1.1.0"
            presentation icon: "M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1",
              color: "teal", single_use: false, privileged: false
          end

          config_schema do
            input :modelVariable, default: "model",
                  description: "Ctx path of the record that holds the reference, such as model (the submitted line) or cart. Must be a loaded EntityEntry."
            literal :field, required: true, example: "product",
                    description: "Slug of the reference field on that record, such as product or order. Must be an EntityReference or a choice list filled from another entity's records."
            enum :operation, %w[find update], default: "find",
                 description: "find loads the referenced row and stops. update then assigns assignments and saves that row through Entries::Save."
            mapping :assignments, key: :entity_attribute, value: :expression, default: [],
                    visible: { operation: "update" }, example: [{ "key" => "status", "value" => '"reserved"' }],
                    description: "Referenced-entity attributes to set on update, such as status => \"reserved\". Keys belong to the referenced entity, not the source record."
            enum :onNotFound, %w[fail nil], default: "fail",
                 description: "When the field is blank or the row is gone: fail refuses the run as referenced_record.not_found (default). nil stores nil on resultVar; update then skips assignments and succeeds."
            output :resultVar, default: "referenced_record", example: "product",
                   description: "Ctx variable that receives the referenced EntityEntry, such as product. Later steps read it as ctx[:product].stock."

            validate do |cfg, errors|
              slug = cfg["field"].to_s.strip
              next if slug.empty?
              next errors.add(:field, :invalid_identifier) unless ConfigSchema::IDENT_SEGMENT.match?(slug)
              next unless respond_to?(:page_entity, true) && cfg["modelVariable"].to_s.in?(["", "model"])

              source = page_entity
              next unless source.respond_to?(:property_schema_json)
              next if FlowchartRuntime::Entries.reference_target(source, slug)

              errors.add(:field, :not_a_reference, attribute: slug, entity: source.try(:display_label) || source.try(:name))
            end
          end

          def generate_body
            attempt('"referenced_record.failed"', FlowchartRuntime::Entries::Error) do
              [
                "record = FlowchartRuntime::Entries.referenced(ctx, #{read(:modelVariable)}, #{read(:field)})",
                assign(:resultVar, "record"),
                missing_guard,
                *update_lines,
                "true"
              ]
            end
          end

          # Update keys are the referenced entity's attributes, known only when
          # the reference is read from the page's own record.
          def bound_entity
            source = page_entity
            return unless source.respond_to?(:property_schema_json) && value(:modelVariable).to_s == "model"

            target = FlowchartRuntime::Entries.reference_target(source, value(:field))
            return unless target

            BoundView.new(target.name, Array(target.property_schema_json).filter_map { |row| row["name_slug"].to_s.presence if row.is_a?(Hash) })
          end

          private

          def update? = value(:operation) == "update"

          def missing_guard
            return fail_with('"referenced_record.not_found"', unless: "record") if value(:onNotFound) == "fail"

            "next true unless record" if update?
          end

          def update_lines
            return [] unless update?

            pairs = Array(value(:assignments)).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              "#{literal(key.to_s)} => #{emit_expression(row["value"] || row[:value])}" if key.to_s.present?
            end
            lines = pairs.empty? ? [] : ["FlowchartRuntime::Entries.assign(record, {#{pairs.join(', ')}}, strict: true)"]
            lines << "next false unless FlowchartRuntime::Entries.save(ctx, record)"
          end

          def page_entity
            context.is_a?(Hash) ? (context[:bound_entity] || context["bound_entity"]) : nil
          end
        end
      end
    end
  end
end
