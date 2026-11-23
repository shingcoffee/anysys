# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class NewModelGenerator < BaseGenerator
          generator_metadata do
            description "Creates an unsaved EntityEntry of the page's bound entity and stores it in " \
                        "resultVar (default model). Use this on create pages before build_contract when " \
                        "ctx[:model] is not already the page record, or to start another new row of the " \
                        "same entity. Assignments set attributes from Ruby expressions before any save. " \
                        "It does not persist; follow with build_contract, validate_contract and save_model " \
                        "(or update_model) to write. Prefer find_model when the row should already exist, " \
                        "and upsert_model to find-or-create in one step."
            category :model_operations
            version "5.2.0"
            presentation icon: "M12 4v16m8-8H4", color: "blue", single_use: true, privileged: false
          end

          config_schema do
            output :resultVar, default: "model",
                   description: "Context variable that receives the new unsaved record. Default model, " \
                                "which is also the page record seeded on submit."
            mapping :assignments, key: :entity_attribute, value: :expression, default: [],
                    example: [{ "key" => "email", "value" => "ctx[:params][:email]" }],
                    description: "Bound-entity attributes to set on the new row before save. Each key is " \
                                 "an attribute slug; each value is a Ruby expression such as " \
                                 "ctx[:params][:email]. Empty by default. Unknown slugs fail at runtime."
          end

          def generate_body
            lines = [assign(:resultVar, "FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])")]
            pairs = mapping_source(value(:assignments))
            lines << "FlowchartRuntime::Entries.assign(ctx[:#{value(:resultVar)}], #{pairs}, strict: true)" if pairs
            body(*lines)
          end

          private

          def mapping_source(rows)
            pairs = Array(rows).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              next if key.to_s.blank?

              "#{literal(key.to_s)} => #{emit_expression(row["value"] || row[:value])}"
            end
            "{#{pairs.join(', ')}}" unless pairs.empty?
          end
        end
      end
    end
  end
end
