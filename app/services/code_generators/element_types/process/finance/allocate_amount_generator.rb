# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Finance
        class AllocateAmountGenerator < BaseGenerator
          METHODS = FlowchartRuntime::Allocation::METHODS
          REMAINDER_STRATEGIES = FlowchartRuntime::Allocation::REMAINDER_STRATEGIES

          generator_metadata do
            description "Splits a money amount into parts that always sum exactly to the rounded input, using largest-remainder (Hamilton) so leftover cents are assigned and the parts add up. Use this to split an invoice across cost centres, a payment across line items, or a budget across departments. Use calculate_pricing to total an order first, or build_installment_plan for a repayment schedule. Reads amount, and weightsVariable when method is ratio or percent. Writes the decimal-string array to resultVar. Refuses allocate_amount.invalid_amount, invalid_weights, or percent_total when percent weights do not sum to 100."
            category :finance
            version "1.1.0"
            presentation icon: "M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4M4 17l4-4",
                         color: "teal", single_use: false, privileged: false
          end

          config_schema do
            input :amount, required: true, example: "total",
                  description: "Ctx path of the amount to split, such as total or invoice.grand_total. Must evaluate to a number (integer, decimal string, or BigDecimal)."
            enum :method, METHODS, default: "even",
                 description: "even splits into equal parts (set parts). ratio splits by relative weights from weightsVariable. percent is ratio but the weights must sum to 100."
            integer :parts, min: 1, max: 1000, default: 2, visible: { method: "even" },
                    description: "How many equal parts to create when method is even, from 1 to 1000. Ignored for ratio and percent, where the weights list length is the part count."
            input :weightsVariable, example: "weights", visible: { method: %w[ratio percent] },
                  description: "Ctx path of the weights array when method is ratio or percent, such as weights. Each item is a number, or a hash/record whose weight is read from weightField."
            literal :weightField, default: "", group: :advanced, visible: { method: %w[ratio percent] },
                    description: "Hash or record key to read when weights are objects, such as share. Leave blank to try weight, value, ratio, percent, then share in that order."
            integer :precision, min: 0, max: 6, default: 2,
                    description: "Decimal places for each allocated amount (0-6). Use 2 for CNY/USD. Parts are rounded to this scale then adjusted so they still sum to the input."
            enum :remainderStrategy, REMAINDER_STRATEGIES, default: "largest_remainder",
                 description: "Where leftover units go after rounding so parts still sum to the input. largest_remainder (default, Hamilton) gives extras to the largest fractional remainders; first/last give them to the first or last parts; largest_share gives them to the biggest weights."
            output :resultVar, default: "allocations",
                   description: "Ctx variable that receives the array of allocated amounts as decimal strings at the chosen precision, such as allocations. Example: [\"33.34\", \"33.33\", \"33.33\"]."
            requires :weightsVariable, when: { method: %w[ratio percent] }
          end

          def generate_body
            attempt('"allocate_amount.failed"', FlowchartRuntime::Allocation::Error) do
              [
                "allocations = FlowchartRuntime::Allocation.split(ctx, #{split_args})",
                assign(:resultVar, "allocations")
              ]
            end
          end

          private

          def split_args
            method = value(:method).to_s
            weighted = %w[ratio percent].include?(method)
            [
              "amount: #{read(:amount)}",
              "method: #{read(:method)}",
              ("parts: #{read(:parts)}" if method == "even" && value(:parts) != 2),
              ("weights: #{read(:weightsVariable)}" if weighted && value(:weightsVariable).to_s.strip.present?),
              ("weight_field: #{read(:weightField)}" if weighted && value(:weightField).to_s.strip.present?),
              ("precision: #{read(:precision)}" unless value(:precision) == 2),
              ("remainder_strategy: #{read(:remainderStrategy)}" unless value(:remainderStrategy).to_s == "largest_remainder")
            ].compact.join(", ")
          end
        end
      end
    end
  end
end
