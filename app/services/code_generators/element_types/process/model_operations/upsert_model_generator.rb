# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class UpsertModelGenerator < BaseGenerator
          generator_metadata do
            description "Finds one bound-entity row matching matchFields (attribute to expression, " \
                        "for example email from ctx[:params][:email]) and updates it, or creates it, " \
                        "under a tenant lock. valuesFrom assignments (default) writes only the " \
                        "assignments mapping plus the match keys; valuesFrom params also mass-assigns " \
                        "ctx[:params]. onMatch update (default) writes the found row, skip returns it " \
                        "unchanged, fail refuses with record_already_exists. Sets resultVar (default " \
                        "model) and createdVar (default created). Prefer find_model then update_model " \
                        "when the row must already exist, and new_model plus save_model for an always-new row."
            category :model_operations
            version "6.0.0"
            presentation icon: "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15",
              color: "teal", single_use: true, privileged: false
          end

          config_schema do
            mapping :matchFields, key: :entity_attribute, value: :expression, required: true,
                    example: [{ "key" => "email", "value" => "ctx[:params][:email]" }],
                    description: "Attributes that identify an existing row. Each key is a bound-entity " \
                                 "slug; each value is a Ruby expression, typically ctx[:params][:email]. " \
                                 "At least one pair is required. Match keys are also written on create."
            enum :valuesFrom, %w[assignments params], default: "assignments",
                 description: "Which values to write besides the match keys. assignments (default) uses " \
                              "only the assignments mapping. params mass-assigns ctx[:params] and then " \
                              "overlays assignments. Prefer assignments so a page submit cannot stamp " \
                              "unrelated posted fields onto the upserted row."
            mapping :assignments, key: :entity_attribute, value: :expression, default: [],
                    example: [{ "key" => "status", "value" => "ctx[:params][:status]" }],
                    description: "Bound-entity attributes to write on create or update. Each key is an " \
                                 "attribute slug; each value is a Ruby expression such as \"open\". " \
                                 "Empty by default. Overlay after params when valuesFrom is params."
            enum :onMatch, %w[update skip fail], default: "update",
                 description: "When a matching tenant row already exists: update (default) writes " \
                              "attributes onto it; skip returns it unchanged; fail refuses the submit " \
                              "with record_already_exists (useful for unique sign-up emails)."
            output :resultVar, default: "model",
                   description: "Context variable that receives the found or created row. Default model."
            output :createdVar, default: "created",
                   description: "Boolean variable set to true when a new row was created, false when an " \
                                "existing row was found. Default created."

            validate do |cfg, errors|
              rows = cfg["matchFields"] || cfg[:matchFields]
              next if rows.nil?

              pairs = Array(rows).select { |row| row.is_a?(Hash) && (row["key"] || row[:key]).to_s.present? }
              errors.add(:matchFields, :required) if pairs.empty?
            end
          end

          def generate_body
            parts = ["match: #{match_source}", "attributes: #{attributes_source}"]
            parts << "on_match: #{read(:onMatch)}" unless value(:onMatch) == "update"
            attempt('"upsert_model.failed"', FlowchartRuntime::Entries::Error) do
              [
                "record, created = FlowchartRuntime::Entries.upsert(ctx, #{parts.join(', ')})",
                "return false unless record",
                assign(:resultVar, "record"),
                assign(:createdVar, "created"),
                "record"
              ]
            end
          end

          private

          def match_source
            mapping_source(value(:matchFields)) || "{}"
          end

          def attributes_source
            pairs = mapping_source(value(:assignments))
            if value(:valuesFrom) == "params"
              pairs ? "(ctx[:params] || {}).to_h.merge(#{pairs})" : "(ctx[:params] || {}).to_h"
            else
              pairs || "{}"
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
