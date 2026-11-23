# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Finance
        class BuildInstallmentPlanGenerator < BaseGenerator
          METHODS = FlowchartRuntime::Installments::METHODS
          FREQUENCIES = FlowchartRuntime::Installments::FREQUENCIES.keys.freeze
          ROUNDING_MODES = FlowchartRuntime::Installments::ROUNDING_MODES

          generator_metadata do
            description "Builds a repayment, subscription, or instalment schedule from a principal, annual rate, period count, and frequency. Use annuity for equal payments each period (standard amortizing / equal-instalment loans) and equal_principal for equal principal with declining interest (common bank loans). Use allocate_amount to split one amount, or calculate_pricing to total an order first. Reads principal (and optional rateVariable, startDateVariable). Writes the schedule array to resultVar and payment/principal/interest totals to totalsVar. Refuses invalid_principal, invalid_periods, invalid_start_date, or down_payment_exceeds_principal."
            category :finance
            version "1.1.0"
            presentation icon: "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
                         color: "amber", single_use: false, privileged: false
          end

          config_schema do
            input :principal, required: true, example: "loan_amount",
                  description: "Ctx path of the principal to finance, such as loan_amount or order.total. Must be a number greater than zero. Down payment is subtracted first."
            decimal :annualRate, default: 0, min: 0, max: 100,
                    description: "Nominal annual interest rate as a percent, such as 12 for 12 percent. Overridden at runtime when rateVariable is set. 0 means an interest-free schedule."
            input :rateVariable, example: "interest_rate", group: :advanced,
                  description: "Optional ctx path whose numeric percent overrides annualRate at runtime, such as interest_rate from a looked-up product. Leave blank to use annualRate."
            integer :periods, min: FlowchartRuntime::Installments::PERIODS.min,
                              max: FlowchartRuntime::Installments::PERIODS.max, default: 12,
                    description: "Number of payments in the schedule, from 1 to 600. 12 with monthly frequency is one year."
            enum :frequency, FREQUENCIES, default: "monthly",
                 description: "Spacing between due dates, and the divisor that turns the annual rate into a period rate. monthly (12), quarterly (4), semiannual (2), annual (1), weekly (52), biweekly (26)."
            enum :method, METHODS, default: "annuity",
                 description: "annuity: equal payment each period (PMT / equal instalment). equal_principal: equal principal each period, interest declines. interest_only: interest each period, principal balloons on the last. flat: interest charged on the original principal every period."
            input :startDateVariable, example: "start_date",
                  description: "Optional ctx path of the schedule origin date, such as start_date. Accepts a Date, Time, or ISO8601 date string. Blank means today in the application time zone."
            integer :firstPaymentOffset, min: 0, max: 12, default: 1,
                    description: "How many frequency periods after the start date the first instalment is due. 1 (default) is next period; 0 means due on the start date."
            decimal :downPayment, default: 0, min: 0, group: :advanced,
                    description: "Amount subtracted from principal before the schedule is built, such as 2000. Must be less than principal or the step refuses."
            integer :precision, min: 0, max: 6, default: 2,
                    description: "Decimal places for every amount on the schedule (0-6). Use 2 for CNY/USD."
            enum :roundingMode, ROUNDING_MODES, default: "half_up",
                 description: "How each amount is rounded at the chosen precision. half_up is ordinary rounding; half_even is banker's rounding; floor/ceiling always go down/up."
            flag :finalPaymentAdjust, default: true,
                 description: "When on (default), the last row absorbs rounding residue so principal sums exactly to the financed amount. Turn off only when you must keep a fixed formula payment on the last row."
            output :resultVar, default: "installments",
                   description: "Ctx variable for the schedule array. Each row has number, due_date (ISO8601 YYYY-MM-DD), and payment/principal/interest/balance as decimal strings."
            output :totalsVar, default: "installment_totals", group: :advanced,
                   description: "Ctx variable for the payment, principal, and interest totals as decimal strings at the chosen precision, such as installment_totals."
          end

          def generate_body
            attempt('"build_installment_plan.failed"', FlowchartRuntime::Installments::Error) do
              [
                "plan = FlowchartRuntime::Installments.build(ctx, #{plan_args})",
                assign(:resultVar, 'plan && plan["schedule"]'),
                assign(:totalsVar, 'plan && plan["totals"]')
              ]
            end
          end

          private

          def plan_args
            [
              "principal: #{read(:principal)}",
              ("annual_rate: #{read(:annualRate)}" unless value(:annualRate).to_f.zero?),
              ("rate_override: #{read(:rateVariable)}" if value(:rateVariable).to_s.strip.present?),
              ("periods: #{read(:periods)}" unless value(:periods) == 12),
              ("frequency: #{read(:frequency)}" unless value(:frequency).to_s == "monthly"),
              ("method: #{read(:method)}" unless value(:method).to_s == "annuity"),
              ("start_date: #{read(:startDateVariable)}" if value(:startDateVariable).to_s.strip.present?),
              ("first_payment_offset: #{read(:firstPaymentOffset)}" unless value(:firstPaymentOffset) == 1),
              ("down_payment: #{read(:downPayment)}" unless value(:downPayment).to_f.zero?),
              ("precision: #{read(:precision)}" unless value(:precision) == 2),
              ("rounding_mode: #{read(:roundingMode)}" unless value(:roundingMode).to_s == "half_up"),
              ("final_payment_adjust: #{read(:finalPaymentAdjust)}" unless value(:finalPaymentAdjust))
            ].compact.join(", ")
          end
        end
      end
    end
  end
end
