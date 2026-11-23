# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class MapValueGenerator < BaseGenerator
          MATCH_MODES = %w[exact regex range].freeze
          FALLBACK_STRATEGIES = %w[default pass_through raise].freeze

          generator_metadata do
            description "Looks up a value in a table and writes the mapped result (status code to a label, score band to a grade). exact matches a key, regex matches a pattern, range matches min..max. Use assign_value for a constant, type_cast to convert types, and hash_manipulate.pick to extract one field first. Reads sourceVariable; writes resultVar. fallbackStrategy default uses defaultValue, pass_through returns the input, raise fails with map_value.failed when nothing matches."
            category :data_operations
            version "3.0.0"
            presentation icon: "M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7",
                          color: "purple", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "status",
                  description: "Ctx path of the value to look up. Example: status or score."
            output :resultVar, default: "mapped_value",
                   description: "Ctx variable later steps read. Example: status_label."
            enum :matchMode, MATCH_MODES, default: "exact",
                 description: "How input values match rows. exact compares keys; regex matches a pattern such as ^paid; range matches 0..50. Default exact."
            mapping :mappings, key: :literal, value: :literal,
                    example: [{ "key" => "active", "value" => "Active" }, { "key" => "inactive", "value" => "Inactive" }],
                    visible: { matchMode: "exact" },
                    description: "Input value mapped to the output value for exact mode. Example: paid -> Paid, void -> Cancelled."
            mapping :rules, key: :literal, value: :literal,
                    example: [{ "key" => "^a", "value" => "starts-a" }],
                    visible: { matchMode: %w[regex range] },
                    description: "Pattern (regex) or range (1..10 or 1...10) mapped to the output value. First match wins."
            literal :defaultValue, example: "Unknown",
                    description: "Value used when nothing matches and fallbackStrategy is default. Example: Unknown."
            enum :fallbackStrategy, FALLBACK_STRATEGIES, default: "default",
                 description: "When nothing matches: default writes defaultValue; pass_through writes the input; raise fails the step with map_value.failed."
            flag :caseSensitive, default: true, group: :advanced,
                 description: "Match letter case for exact and regex. Default true. Set false so PAID matches paid."
            requires :mappings, when: { matchMode: "exact" }
            requires :rules, when: { matchMode: %w[regex range] }
          end

          def generate_body
            body(
              attempt('"map_value.failed"', FlowchartRuntime::ValueMap::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::ValueMap.apply(#{apply_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def apply_args
            args = [read(:sourceVariable), "match_mode: #{read(:matchMode)}"]
            args << "mappings: #{read(:mappings)}" if value(:mappings).present?
            args << "rules: #{rules_literal}" if rules_literal
            args << "fallback: #{read(:fallbackStrategy)}" unless value(:fallbackStrategy) == "default"
            args << "default: #{read(:defaultValue)}" unless value(:defaultValue).to_s.strip.empty?
            args << "case_sensitive: false" unless value(:caseSensitive)
            args.join(", ")
          end

          def rules_literal
            rows = Array(value(:rules)).filter_map do |row|
              next unless row.is_a?(Hash)

              pattern = row["key"] || row[:key] || row["pattern"] || row[:pattern]
              next if pattern.to_s.empty?

              mapped = row.key?("value") || row.key?(:value) ? (row["value"] || row[:value]) : nil
              { "pattern" => pattern.to_s, "value" => mapped.to_s }
            end
            return if rows.empty?

            literal(rows)
          end
        end
      end
    end
  end
end
