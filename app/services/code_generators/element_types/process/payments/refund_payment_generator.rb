# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Payments
        class RefundPaymentGenerator < BaseGenerator
          REFUND_MODES = %w[partial full].freeze

          generator_metadata do
            description "Refunds a captured payment of this customer through Payments::Activities::Refund, scoped to ctx[:customer_id]. Use partial with amount for a part of the remaining captured total, or full to refund everything still captured. Use request_payment to take money, not this step. Reads payment (id or Payment record) and optional amount/reason. Writes the Payments::Refund record to resultVar. Refuses refund_payment.not_found, not_captured, non_positive, exceeds_remainder, billing_collection, or failed. Never refunds another tenant's payment."
            category :payments
            version "1.2.0"
            presentation icon: "M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6",
                        color: "amber", single_use: false, privileged: false
          end

          config_schema do
            expression :payment, required: true, example: "ctx[:payment_id]",
                       description: "Ruby expression for a payment id of this customer, or a Payments::Payment record already loaded, such as ctx[:payment_id]. Looked up with Payments::Payment.for_customer; another tenant's id is not_found."
            enum :refundMode, REFUND_MODES, default: "partial",
                 description: "partial (default) refunds amount, which must be a positive decimal in major units and not more than the remaining captured total. full refunds the entire remaining captured amount and ignores amount."
            expression :amount, example: 'BigDecimal("1.00")', visible: { refundMode: "partial" },
                       description: "Ruby expression for the refund amount in major units when refundMode is partial, such as BigDecimal(\"1.00\") or ctx[:refund_amount]. Do not use a Float literal (1.00). Required for partial; omitted for full."
            expression :reason, example: '"duplicate"',
                       description: "Optional Ruby expression for the reason recorded with the refund, such as \"duplicate\" or ctx[:reason]. Stored on the refund row and sent to the gateway when it supports a reason."
            output :resultVar, default: "refund",
                   description: "Ctx variable that receives the Payments::Refund record after a successful refund, such as refund. Unset when the step refuses."
            requires :amount, when: { refundMode: "partial" }
          end

          def generate_body
            body(assign(:resultVar, "FlowchartRuntime::Payments.refund(ctx, #{refund_args})"))
          end

          private

          def refund_args
            parts = ["payment: #{read(:payment)}"]
            parts << "mode: #{read(:refundMode)}" unless value(:refundMode) == "partial"
            parts << "amount: #{read(:amount)}" if value(:refundMode) == "partial"
            parts << "reason: #{read(:reason)}" if value(:reason).to_s.strip.present?
            parts.join(", ")
          end
        end
      end
    end
  end
end
