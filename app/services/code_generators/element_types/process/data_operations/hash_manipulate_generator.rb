# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class HashManipulateGenerator < BaseGenerator
          OPERATIONS = %w[pick omit keys values merge rename_keys compact set_keys].freeze
          MERGE_STRATEGIES = %w[shallow deep replace append].freeze
          ARRAY_MERGE_MODES = %w[concat replace unique_union].freeze
          ON_CONFLICT = %w[first last].freeze

          generator_metadata do
            description "Reshapes one hash: pick or omit keys, merge another hash, rename keys, compact nils, set computed keys, or list keys/values. Use compare_data to diff two hashes, collection_manipulate for arrays of records, and map_value to translate a single value. Reads sourceVariable (and otherVariable for merge); writes resultVar. Fails with hash_manipulate.failed when the source is not a hash."
            category :data_operations
            version "3.0.0"
            presentation icon: "M4 6h16M4 10h16M4 14h16M4 18h16", color: "indigo",
                          single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "data",
                  description: "Ctx path of the hash this step reads. Example: payload or person."
            output :resultVar, default: "hash",
                   description: "Ctx variable later steps read. Example: public_profile."
            enum :operation, OPERATIONS, default: "pick",
                 description: "How to reshape the source. pick keeps keys; omit drops them; keys/values list them; merge combines otherVariable; rename_keys uses renameMap; compact drops nils; set_keys writes computedFields."
            list :keys, item: :literal, example: %w[name email], visible: { operation: %w[pick omit] },
                 description: "Key names to pick or omit. Dotted paths pick a nested value under the last segment. Example: name, email."
            input :otherVariable, example: "overrides", visible: { operation: "merge" },
                  description: "Ctx path of the second hash merged into the source. Example: overrides or defaults."
            mapping :renameMap, key: :literal, value: :literal,
                    example: [{ "key" => "old_name", "value" => "new_name" }],
                    visible: { operation: "rename_keys" },
                    description: "Original key mapped to the new key. Example: first_name -> given_name."
            mapping :computedFields, key: :literal, value: :expression,
                    example: [{ "key" => "total", "value" => "1 + 1" }],
                    visible: { operation: "set_keys" },
                    description: "Keys to set, each with a Ruby expression for the value. Example: total = ctx[:qty].to_i * ctx[:price].to_f."
            flag :caseInsensitive, default: false, visible: { operation: %w[pick omit] }, group: :advanced,
                 description: "Match pick/omit keys without regard to letter case. Default false."
            enum :mergeStrategy, MERGE_STRATEGIES, default: "shallow", visible: { operation: "merge" },
                 description: "How the two hashes combine. shallow overwrites top-level keys; deep merges nested hashes; replace returns the other hash; append concatenates array values."
            enum :arrayMergeMode, ARRAY_MERGE_MODES, default: "concat", visible: { operation: "merge" }, group: :advanced,
                 description: "How array values combine on a deep or append merge. concat joins them; replace uses the other hash; unique_union concatenates and uniq. Default concat."
            enum :onConflict, ON_CONFLICT, default: "last", visible: { operation: "merge" }, group: :advanced,
                 description: "Which side wins when both hashes share a key. last uses the other hash; first keeps the source. Default last."
            requires :keys, when: { operation: %w[pick omit] }
            requires :otherVariable, when: { operation: "merge" }
            requires :renameMap, when: { operation: "rename_keys" }
            requires :computedFields, when: { operation: "set_keys" }
          end

          def generate_body
            body(
              attempt('"hash_manipulate.failed"', FlowchartRuntime::HashOps::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::HashOps.apply(#{apply_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def apply_args
            other = optional_input(:otherVariable)
            keys = optional_list(:keys)
            rename = optional_mapping(:renameMap)
            insensitive = read(:caseInsensitive)
            strategy = read(:mergeStrategy)
            array_mode = read(:arrayMergeMode)
            conflict = read(:onConflict)
            computed = computed_literal
            args = [read(:operation), read(:sourceVariable)]
            args << "other: #{other}" unless other == "nil"
            args << "keys: #{keys}" unless keys == "[]"
            args << "rename_map: #{rename}" unless rename == "{}"
            args << "case_insensitive: true" if insensitive == "true"
            args << "merge_strategy: #{strategy}" unless strategy == '"shallow"'
            args << "array_merge_mode: #{array_mode}" unless array_mode == '"concat"'
            args << "on_conflict: #{conflict}" unless conflict == '"last"'
            args << "computed: #{computed}" unless computed == "{}"
            args.join(", ")
          end

          def optional_input(name)
            raw = value(name)
            raw.to_s.strip.empty? ? "nil" : read(name)
          end

          def optional_list(name)
            raw = value(name)
            raw.blank? ? "[]" : read(name)
          end

          def optional_mapping(name)
            raw = value(name)
            raw.blank? ? "{}" : read(name)
          end

          def computed_literal
            rows = Array(value(:computedFields))
            pairs = rows.filter_map do |row|
              next unless row.is_a?(Hash)

              key = (row["key"] || row[:key]).to_s
              val = (row["value"] || row[:value]).to_s.strip
              next if key.empty? || val.empty?

              if key.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)
                "#{key}: #{emit_expression(val)}"
              else
                "#{key.inspect} => #{emit_expression(val)}"
              end
            end
            pairs.empty? ? "{}" : "{#{pairs.join(", ")}}"
          end
        end
      end
    end
  end
end
