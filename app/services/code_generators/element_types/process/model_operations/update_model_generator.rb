# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class UpdateModelGenerator < BaseGenerator
          BoundView = Data.define(:name, :attribute_slugs)

          generator_metadata do
            description "Updates an already loaded EntityEntry (modelVariable, default model) and saves " \
                        "it through Entries::Save. valuesFrom assignments (default) writes only the " \
                        "assignments mapping — the usual follow-up after save_model for system-filled " \
                        "fields on the page record, or to patch another loaded row such as ctx[:cart]. " \
                        "valuesFrom params mass-assigns ctx[:params] onto the page record; valuesFrom " \
                        "contract syncs ctx[:contract] onto the page record. skipIfUnchanged skips the " \
                        "write when nothing changed; changesVar receives saved_changes. Fails with " \
                        "record_missing when the variable is empty. Use set_record_fields to assign " \
                        "without saving, and save_model to persist a validated Reform contract."
            category :model_operations
            version "6.0.0"
            presentation icon: "M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z",
              color: "indigo", single_use: false, privileged: false
          end

          config_schema do
            input :modelVariable, default: "model",
                  description: "Context path of the record to update. Default model (the page record). " \
                               "Use cart or another loaded variable for a different row; then valuesFrom " \
                               "must stay assignments."
            enum :valuesFrom, %w[assignments contract params], default: "assignments",
                 description: "Which values to write before saving. assignments (default) applies only " \
                              "the assignments mapping. params copies ctx[:params] onto the page record. " \
                              "contract syncs ctx[:contract] onto the page record. params and contract " \
                              "are rejected when modelVariable is not model."
            mapping :assignments, key: :entity_attribute, value: :expression, default: [],
                    example: [{ "key" => "email", "value" => "ctx[:params][:email]" }],
                    description: "Bound-entity attributes to set after the valuesFrom source, before " \
                                 "save. Each key is an attribute slug; each value is a Ruby expression " \
                                 "such as Time.current. Empty by default."
            flag :skipIfUnchanged, default: false,
                 description: "When true, skip Entries::Save if the record has no pending changes after " \
                              "assignments. Default false (always persist, which refreshes updated_at)."
            output :changesVar,
                   description: "Optional variable that receives the record's saved_changes hash after a " \
                                "successful save. Leave blank to skip."

            validate do |cfg, errors|
              source = (cfg["valuesFrom"] || cfg[:valuesFrom] || "assignments").to_s
              next if source == "assignments"

              variable = (cfg["modelVariable"] || cfg[:modelVariable] || "model").to_s
              next if variable.blank? || variable == "model"

              errors.add(:valuesFrom, :page_record_only)
            end
          end

          def generate_body
            model_expr = read(:modelVariable)
            lines = source_lines(model_expr)
            pairs = mapping_source(value(:assignments))
            lines << "FlowchartRuntime::Entries.assign(#{model_expr}, #{pairs}, strict: true)" if pairs
            lines << "return true unless #{model_expr}.has_changes_to_save?" if value(:skipIfUnchanged)
            lines.concat(save_lines(model_expr))
            body(
              missing_guard(model_expr),
              *pre_attempt_lines,
              attempt('"update_model.failed"', FlowchartRuntime::Entries::Error) { lines }
            )
          end

          # Assignment keys are checked only on the page's own record, whose
          # entity is known here.
          def bound_entity
            raw = context.is_a?(Hash) ? (context[:bound_entity] || context["bound_entity"]) : nil
            return unless raw.respond_to?(:property_schema_json) && value(:modelVariable).to_s.in?(["", "model"])

            BoundView.new(raw.name, Array(raw.property_schema_json).filter_map { |row| row["name_slug"].to_s.presence if row.is_a?(Hash) })
          end

          private

          def missing_guard(model_expr)
            <<~RUBY.chomp
              unless #{model_expr}
                return FlowchartRuntime::Step.fail(ctx, :record_missing, field: :modelVariable)
              end
            RUBY
          end

          def pre_attempt_lines
            return [] unless value(:valuesFrom) == "contract"

            [fail_with(:contract_missing, unless: "ctx[:contract]")]
          end

          def source_lines(model_expr)
            case value(:valuesFrom)
            when "contract"
              ["ctx[:contract].sync"]
            when "params"
              ["FlowchartRuntime::Entries.assign(#{model_expr}, ctx[:params] || {})"]
            else
              []
            end
          end

          def save_lines(model_expr)
            if value(:changesVar).present?
              [
                "saved = FlowchartRuntime::Entries.save(ctx, #{model_expr})",
                "#{assign(:changesVar, "#{model_expr}.saved_changes")} if saved",
                "saved"
              ]
            else
              ["FlowchartRuntime::Entries.save(ctx, #{model_expr})"]
            end
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
        end
      end
    end
  end
end
