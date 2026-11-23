# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class MathOperationGenerator < BaseGenerator
          UNARY_OPS = FlowchartRuntime::Numbers::UNARY
          BINARY_OPS = FlowchartRuntime::Numbers::BINARY
          CLAMP_OPS = FlowchartRuntime::Numbers::CLAMP
          OPERATIONS = FlowchartRuntime::Numbers::OPERATIONS
          DIVIDE_BY_ZERO_POLICIES = FlowchartRuntime::Numbers::DIVIDE_POLICIES
          ROUNDING_MODES = FlowchartRuntime::Numbers::ROUNDING_MODES
          BOUNDS_OPS = %w[random clamp].freeze
          DIVIDE_OPS = %w[divide modulo percent].freeze

          generator_metadata do
            description "Performs decimal arithmetic with BigDecimal so money totals stay exact: add, subtract, " \
                        "multiply, divide, modulo, power, min, max, percent (source as a percentage of other), " \
                        "abs, floor, ceil, round, sqrt, clamp, and integer random. Reads sourceVariable and, for " \
                        "binary ops, otherVariable. Writes resultVar. Use format_value to display currency and " \
                        "calculate for collection totals. Fails with math_operation.failed on a non-numeric value " \
                        "or when divideByZero is raise and the divisor is zero."
            category :data_operations
            version "1.2.0"
            presentation icon: "M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z",
                         color: "emerald", single_use: false, privileged: false
          end

          config_schema do
            enum :operation, OPERATIONS, default: "add",
              description: "Math to apply. Binary ops need otherVariable. percent is source/other*100. " \
                           "clamp pins source between minValue and maxValue. random is an integer in that range. " \
                           "round uses precision and roundingMode."
            input :sourceVariable, example: "subtotal",
              description: "Context path of the first operand (e.g. params.subtotal). Unused for random."
            input :otherVariable, example: "tax",
              description: "Context path of the second operand for add, subtract, multiply, divide, modulo, " \
                           "power, min, max, and percent (e.g. params.tax)."
            output :resultVar, default: "number",
              description: "Context variable that receives the BigDecimal result (or an integer for random)."
            integer :precision, min: 0, max: 20,
              description: "Decimal places to round to (0-20). Blank keeps full precision. Example: 2 for money."
            enum :roundingMode, ROUNDING_MODES, default: "half_up", group: :advanced,
              description: "How precision rounds: half_up (default, 0.5 away from zero), half_even (banker's), " \
                           "floor (toward -inf), ceiling (toward +inf)."
            enum :divideByZero, DIVIDE_BY_ZERO_POLICIES, default: "raise", visible: { operation: DIVIDE_OPS },
              description: "When the divisor is zero: raise fails the step, nil writes nil, zero writes 0, " \
                           "infinity and nan write those IEEE values."
            integer :minValue, default: 0, visible: { operation: BOUNDS_OPS },
              description: "Inclusive lower bound for clamp and random. Example: 0."
            integer :maxValue, default: 100, visible: { operation: BOUNDS_OPS },
              description: "Inclusive upper bound for clamp and random. Example: 100. Must be >= minValue."
            requires :sourceVariable, when: { operation: UNARY_OPS + BINARY_OPS + CLAMP_OPS }
            requires :otherVariable, when: { operation: BINARY_OPS }

            validate do |_cfg, errors|
              next unless BOUNDS_OPS.include?(value(:operation).to_s)
              next if value(:minValue).to_i <= value(:maxValue).to_i

              errors.add(:maxValue, :min_greater_than_max)
            end
          end

          def generate_body
            body(
              attempt('"math_operation.failed"', FlowchartRuntime::Numbers::Error) do
                [
                  assign(:resultVar, numbers_call),
                  "true"
                ]
              end
            )
          end

          private

          def numbers_call
            "FlowchartRuntime::Numbers.apply(#{numbers_args})"
          end

          def numbers_args
            op = value(:operation).to_s
            args = [source_expr, "operation: #{read(:operation)}"]
            args << "other: #{read(:otherVariable)}" if BINARY_OPS.include?(op) && value(:otherVariable).present?
            args << "precision: #{read(:precision)}" unless value(:precision).nil?
            args << "divide_by_zero: #{read(:divideByZero)}" if DIVIDE_OPS.include?(op) && value(:divideByZero) != "raise"
            if BOUNDS_OPS.include?(op)
              args << "min_value: #{read(:minValue)}" unless value(:minValue) == 0
              args << "max_value: #{read(:maxValue)}" unless value(:maxValue) == 100
            end
            args << "rounding_mode: #{read(:roundingMode)}" unless value(:roundingMode) == "half_up"
            args.join(", ")
          end

          def source_expr
            value(:sourceVariable).present? ? read(:sourceVariable) : "nil"
          end
        end
      end
    end
  end
end
