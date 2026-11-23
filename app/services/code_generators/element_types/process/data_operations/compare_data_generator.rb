# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class CompareDataGenerator < BaseGenerator
          COMPARISON_TYPES = %w[diff equal].freeze

          generator_metadata do
            description "Compares two hashes (for example an order before and after an edit). comparisonType diff (default) writes added, removed, and changed fields into resultVar; equal writes a boolean. Use hash_manipulate to pick keys first, and ignoreKeys to skip timestamps such as updated_at. Reads sourceVariable and otherVariable. Fails with compare_data.failed when a side is not a hash."
            category :data_operations
            version "3.0.0"
            presentation icon: "M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4", color: "blue",
                          single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "before",
                  description: "Ctx path of the left (before) hash. Example: before or original_order."
            input :otherVariable, required: true, example: "after",
                  description: "Ctx path of the right (after) hash. Example: after or updated_order."
            output :resultVar, default: "diff",
                   description: "Ctx variable later steps read. For diff this is a hash of added/removed/changed; for equal it is true or false."
            enum :comparisonType, COMPARISON_TYPES, default: "diff",
                 description: "diff writes {added, removed, changed: {key => {from, to}}}; equal writes a boolean. Default diff."
            list :ignoreKeys, item: :literal, example: %w[updated_at],
                 description: "Keys stripped from both sides before compare. Example: updated_at, created_at."
            flag :caseInsensitive, default: false, group: :advanced,
                 description: "Downcase strings on both sides before comparing. Default false."
            decimal :numericTolerance, min: 0, default: 0, group: :advanced,
                    description: "Absolute difference allowed for numeric values (e.g. 0.01 for money). 0 requires exact equality."
          end

          def generate_body
            body(
              attempt('"compare_data.failed"', FlowchartRuntime::HashDiff::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::HashDiff.compare(#{compare_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def compare_args
            comparison = read(:comparisonType)
            ignore = read(:ignoreKeys)
            insensitive = read(:caseInsensitive)
            tolerance = read(:numericTolerance)
            args = [read(:sourceVariable), read(:otherVariable)]
            args << "comparison_type: #{comparison}" unless comparison == '"diff"'
            args << "ignore_keys: #{ignore}" unless ignore == "[]"
            args << "case_insensitive: true" if insensitive == "true"
            args << "numeric_tolerance: #{tolerance}" unless tolerance == "0" || tolerance == "0.0"
            args.join(", ")
          end
        end
      end
    end
  end
end
