# frozen_string_literal: true

require "uri"

module Billing
  module OneTimePaymentAction
    def self.for(invoice:)
      attempt = invoice.collection_attempts.inflight.where(billing_payment_method_id: nil).order(:ordinal).last
      return unless attempt && !invoice.paid? && !invoice.void?
      payment = attempt.payment
      return unless payment && payment.status == "pending" && attempt.customer_id == invoice.customer_id &&
                    payment.merchant_account_id == attempt.merchant_account_id

      payload = payment.prepay_payload.is_a?(Hash) ? payment.prepay_payload : {}
      case payment.flow.to_sym
      when :card
        card_action(invoice: invoice, attempt: attempt, payment: payment, payload: payload)
      when :qr
        code = payload["code_url"].presence || payload["qr_code"].presence
        return unless code.present?
        { kind: :qr, flow: :qr, provider: payment.provider, out_trade_no: payment.out_trade_no, code_url: code }
      when :h5
        url = payload["h5_url"].to_s
        uri = URI.parse(url)
        return unless uri.scheme == "https" && uri.host.present?
        { kind: :h5, flow: :h5, provider: payment.provider, out_trade_no: payment.out_trade_no, url: url }
      when :jsapi
        params = payload.except(Payments::Payment::ATTEMPT_CONTEXT_KEY)
        { kind: :jsapi, flow: :jsapi, provider: payment.provider, out_trade_no: payment.out_trade_no, jsapi_params: params }
      end
    rescue URI::InvalidURIError
      nil
    end

    def self.card_action(invoice:, attempt:, payment:, payload:)
      case payment.provider
      when "stripe"
        pub = attempt.merchant_account.credential(:publishable_key)
        sec = payload["client_secret"]
        return unless pub.present? && sec.present?
        { kind: :stripe_card, flow: :card, provider: "stripe", out_trade_no: payment.out_trade_no,
          publishable_key: pub, client_secret: sec }
      when "paypal"
        cid = attempt.merchant_account.credential(:client_id)
        oid = payload["paypal_order_id"]
        return unless cid.present? && oid.present?
        { kind: :paypal_buttons, flow: :card, provider: "paypal", out_trade_no: payment.out_trade_no,
          client_id: cid, paypal_order_id: oid, currency: invoice.currency }
      end
    end
    private_class_method :card_action
  end
end
