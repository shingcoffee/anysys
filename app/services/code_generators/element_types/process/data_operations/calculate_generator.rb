# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class CalculateGenerator < BaseGenerator
          OPERATIONS = %w[sum count avg min max product concat].freeze
          EMPTY_BEHAVIORS = %w[zero nil].freeze
          ROUNDING_MODES = %w[half_up half_even floor ceiling].freeze
          FIELD_OPS = %w[sum avg min max product concat].freeze

          generator_metadata do
            description "Aggregates a list of hashes or EntityEntry records: sum, count, avg, min, max, product, or concat of a field such as line-item amount. Use filter_collection to pick which rows, collection_manipulate to sort or group first, and assign_value for a single expression. Reads sourceVariable; writes resultVar. Empty lists return 0 or nil per emptyCollectionBehavior. Nil item values are skipped when ignoreNils is true. Does not fail at runtime for an empty list."
            category :data_operations
            version "3.0.0"
            presentation icon: "M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z",
                         color: "teal", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "items",
                  description: "Ctx path of the list to aggregate. Example: line_items or items."
            enum :operation, OPERATIONS, default: "count",
                 description: "Aggregation to apply. count is the list size; sum/avg/min/max/product/concat read fieldName on each item (e.g. amount). product multiplies numeric values; concat joins them."
            literal :fieldName, default: "", visible: { operation: FIELD_OPS },
                    description: "Item field aggregated for sum, avg, min, max, product, or concat. Dotted paths allowed. Example: amount or item.price. Leave blank to use the item itself."
            literal :separator, default: "", visible: { operation: "concat" },
                    description: "String inserted between concatenated values. Example: ', ' for a name list. Default is no separator."
            output :resultVar, default: "total",
                   description: "Ctx variable later steps read. Example: order_total."
            enum :emptyCollectionBehavior, EMPTY_BEHAVIORS, default: "zero", group: :advanced,
                 description: "Value when the list (or field values) is empty. zero writes 0; nil writes nil. Default zero."
            flag :ignoreNils, default: true, group: :advanced,
                 description: "Drop nil items and nil field values before aggregating. Default true so a missing amount does not spoil a sum."
            integer :precision, min: 0, max: 12, default: 0, group: :advanced,
                    description: "Decimal places to round sum/avg/min/max/product. 0 means no rounding. Example: 2 for money."
            enum :roundingMode, ROUNDING_MODES, default: "half_up", group: :advanced,
                 description: "How to round when precision is set. half_up is school rounding; half_even is banker's; floor goes down; ceiling goes up."
          end

          def generate_body
            body(
              assign("resultVar", aggregate_call),
              "true"
            )
          end

          private

          def aggregate_call
            field = read("fieldName")
            ignore = read("ignoreNils")
            behavior = read("emptyCollectionBehavior")
            precision = read("precision")
            rounding = read("roundingMode")
            separator = read("separator")
            args = ["Array(#{read("sourceVariable")})", "operation: #{read("operation")}"]
            args << "field: #{field}" unless field == '""'
            args << "ignore_nils: false" unless ignore == "true"
            args << "empty_behavior: #{behavior}" unless behavior == '"zero"'
            args << "precision: #{precision}" unless precision == "0"
            args << "rounding_mode: #{rounding}" unless rounding == '"half_up"'
            args << "separator: #{separator}" unless separator == '""'
            "FlowchartRuntime::Collections.aggregate(#{args.join(", ")})"
          end
        end
      end
    end
  end
end
