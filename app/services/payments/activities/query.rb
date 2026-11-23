# frozen_string_literal: true

module Payments
  module Activities
    class Query
      def self.call(customer:, payment:)
        unless payment.customer_id == customer.id
          raise Payments::Errors::TenantMismatch, "payment query customer does not match the captured record"
        end
        # Recover a missing projection without depending on another PSP read
        # once the capture itself has already committed.
        if payment.reload.status == "succeeded"
          HandleWebhook.settle_billing_invoice!(payment)
          return { status: :succeeded, psp_transaction_id: payment.psp_transaction_id,
                   amount: payment.amount, currency: payment.payment_order.currency,
                   settled_at: payment.paid_at, raw: payment.raw_notify }
        end
        result = query_remote(customer, payment)
        case result[:status]
        when :succeeded
          # Same amount-mismatch guard as HandleWebhook: a PSP success for a
          # smaller capture must not mark the recorded amount paid. Query is
          # the public status-poll path, so skipping the guard here would let
          # an underpayment that the webhook already refused still settle.
          amount = result[:amount] || notified_amount(payment, result[:raw])
          payload = result[:raw].is_a?(Hash) ? result[:raw] : {}
          if payment.provider.to_s == "paypal" && amount.nil?
            # PayPal Order JSON without a capture amount used to count as
            # "not asserted" and settle underpayments. Refuse until an amount
            # is present.
            HandleWebhook.reject_amount_mismatch(payment, nil)
          else
            HandleWebhook.finalize_success!(
              payment,
              notified_amount: amount,
              notified_currency: result[:currency] || notified_currency(payment, payload),
              psp_id: result[:psp_transaction_id],
              at: result[:settled_at] || result[:paid_at] || settlement_time(payment, payload),
              notify: result[:raw]
            )
          end
        when :failed
          payment.mark_failed!(reason: result[:raw].to_s)
        when :closed
          payment.mark_closed!
        end
        result
      end

      def self.query_remote(customer, payment)
        if payment.provider == "stripe" && payment.psp_transaction_id.blank? &&
           payment.prepay_payload["psp_payment_intent_id"].blank?
          account = Payments::CredentialResolver.for_payment(customer: customer, payment: payment)
          # Stripe's existing metadata-search API recovers a lost create response
          # without submitting a charge. The ordinary query requires a remote ID.
          Payments::Gateway.gateway_for_merchant(provider: payment.provider, merchant_id: account.merchant_id)
            .billing_query(payment: payment)
        else
          Payments::Gateway.query(customer: customer, payment: payment)
        end
      end
      private_class_method :query_remote

      def self.notified_amount(payment, raw)
        payload = raw.is_a?(Hash) ? raw : {}
        case payment.provider.to_s
        when "wechat_pay" then HandleWebhook.wechat_amount(payload)
        when "alipay"     then HandleWebhook.alipay_amount(payload)
        when "stripe"     then HandleWebhook.stripe_amount(payload, payload["currency"].presence || payment.payment_order.currency)
        when "paypal"     then HandleWebhook.paypal_amount(payload)
        end
      end
      private_class_method :notified_amount

      def self.notified_currency(payment, payload)
        case payment.provider
        when "stripe" then payload["currency"]
        when "paypal" then HandleWebhook.paypal_currency(payload)
        end
      end
      private_class_method :notified_currency

      def self.settlement_time(payment, payload)
        case payment.provider
        when "stripe" then HandleWebhook.stripe_capture_time(payload)
        when "wechat_pay" then HandleWebhook.psp_time(payload["success_time"] || payload.dig("resource", "success_time"))
        when "alipay"
          HandleWebhook.psp_time(payload["send_pay_date"] || payload["gmt_payment"],
                                 zone: Time.find_zone(HandleWebhook::ALIPAY_TIMEZONE))
        when "paypal"
          capture = payload.dig("purchase_units", 0, "payments", "captures", 0) || payload
          HandleWebhook.psp_time(capture["create_time"])
        else Time.zone.now
        end
      end
      private_class_method :settlement_time
    end
  end
end
