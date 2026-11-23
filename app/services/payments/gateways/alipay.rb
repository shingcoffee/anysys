# frozen_string_literal: true

require "openssl"
require "base64"
require "cgi"

module Payments
  module Gateways
    # Alipay (China) — RSA2 signing.
    #
    # The RSA2 request signing / notification verification below is
    # intentionally hand-rolled on stdlib OpenSSL: the `alipay` gem is
    # effectively unmaintained, targets an older API generation, and its
    # process-global configuration cannot express this app's per-tenant
    # MerchantAccount PEM keys. Transport goes through OutboundHttp (Faraday).
    class Alipay < Base
      GATEWAY = "https://openapi.alipay.com/gateway.do"
      BILLING_SANDBOX_GATEWAY = "https://openapi-sandbox.dl.alipaydev.com/gateway.do"

      # Alipay validates the `timestamp` request param against Beijing time —
      # signing with the server's local zone drifts up to a day near midnight.
      TIMEZONE = "Asia/Shanghai"
      NONEXECUTION_CODES = %w[20001 40001 40002 40003 40006].freeze
      NONEXECUTION_SUB_CODES = %w[ACQ.INVALID_PARAMETER ACQ.TRADE_NOT_EXIST ACQ.BUYER_BALANCE_NOT_ENOUGH].freeze

      class << self
        def key          = "alipay"
        def display_name = "Alipay (China)"

        def credential_fields
          [
            { name: :private_key_pem,         label: "Merchant private key (PEM)",   type: :text, encrypted: true },
            { name: :platform_public_key_pem, label: "Alipay platform public key",   type: :text, encrypted: true }
          ]
        end

        def supported_flows = %i[qr h5 jsapi]

        # Alipay implements one-time charge, agreement (CYCLE_PAY) recurring,
        # refunds, downloadable settlement bills, and async notifications.
        def capabilities = %i[one_time recurring billing_agreements refunds reconciliation webhooks]

        def jsapi_user_agent_pattern = /AlipayClient/i

        def extract_merchant_id(_headers, body)
          CGI.parse(body.to_s).fetch("app_id", [""]).first
        end

        def event_id(payload)   = payload["notify_id"].presence
        def event_type(payload) = payload["trade_status"].presence || "notify"
      end

      def charge(order:, payment:, flow:, openid: nil)
        method = flow_method(flow)
        biz = {
          out_trade_no: payment.out_trade_no,
          total_amount: Payments::Money.new(order.amount, "cny").decimal_string,
          subject: order.subject
        }
        # alipay.trade.wap.pay is a page API — the browser opens a locally
        # signed gateway URL; there is no server-side call to make.
        return { prepay_payload: { h5_url: build_wap_url(biz, payment) } } if flow == :h5

        biz[:buyer_id] = openid if flow == :jsapi && openid
        data = call_api(method, biz)
        prepay =
          case flow
          when :qr then { qr_code: data["qr_code"] }
          else          { trade_no: data["trade_no"] } # :jsapi (flow already validated by flow_method)
          end
        { prepay_payload: prepay }
      end

      def query(payment:, gateway: GATEWAY)
        data = call_api("alipay.trade.query", { out_trade_no: payment.out_trade_no }, gateway: gateway)
        currency = reported_currency(data["trans_currency"].presence || "CNY")
        { status: map_status(data["trade_status"]), psp_transaction_id: data["trade_no"], raw: data,
          currency: currency, amount: reported_amount(data["total_amount"], currency: currency),
          settled_at: reported_time(data["send_pay_date"], zone: Time.find_zone(TIMEZONE)) }
      end

      def refund(payment:, refund:, gateway: GATEWAY)
        data = call_api("alipay.trade.refund", {
          out_trade_no: payment.out_trade_no,
          out_request_no: refund.out_refund_no,
          refund_amount: Payments::Money.new(refund.amount, "cny").decimal_string,
          refund_reason: refund.reason
        }, gateway: gateway)
        { psp_refund_id: data["trade_no"], status: :succeeded, raw: data }
      end

      def close(payment:, gateway: GATEWAY)
        call_api("alipay.trade.close", { out_trade_no: payment.out_trade_no }, gateway: gateway)
        { status: :closed }
      end

      def subscribe(subscription:)
        biz = {
          product_code: "CYCLE_PAY_AUTH",
          agreement_no: subscription.external_ref,
          period_type: subscription.cycle.upcase,
          execute_time: Date.today.strftime("%Y-%m-%d"),
          single_amount: Payments::Money.new(subscription.amount, "cny").decimal_string
        }
        data = call_api("alipay.user.agreement.page.sign", biz)
        { sign_url_or_params: data["sign_str"] }
      end

      def cancel_subscription(subscription:)
        mode = subscription.metadata.fetch("billing_authorization_context", {}).fetch("mode", account.mode) if subscription.billing_owned?
        target = subscription.billing_owned? ? billing_gateway(mode: mode) : GATEWAY
        call_api("alipay.user.agreement.unsign", { agreement_no: subscription.psp_agreement_id }, gateway: target)
        { status: :cancelled }
      end

      # Page-sign is a browser API, not a JSON server invocation. Reuse the
      # existing per-account RSA2 signer and transport; do not reimplement the
      # protocol in Billing. Only the supported monthly product is offered.
      def billing_authorization(subscription:, return_url:)
        unless subscription.currency == "cny" && subscription.cycle == "monthly"
          raise Payments::Errors::ApiError.new("unsupported billing agreement cadence/currency", code: "reauthorization_required")
        end
        biz = { product_code: "GENERAL_WITHHOLDING_P", personal_product_code: "CYCLE_PAY_AUTH", sign_scene: "INDUSTRY",
          external_agreement_no: subscription.external_ref,
          period_rule_params: { period_type: "MONTH", period: 1,
            execute_time: subscription.created_at.in_time_zone(TIMEZONE).strftime("%Y-%m-%d"),
            single_amount: Payments::Money.new(subscription.amount, "CNY").decimal_string } }
        fields = signed_params("alipay.user.agreement.page.sign", biz, extra: { return_url: return_url })
        { action: { kind: :provider_form, action_url: billing_gateway, method: "post", fields: fields } }
      end

      def query_agreement(subscription:)
        biz = { personal_product_code: "CYCLE_PAY_AUTH" }
        if subscription.psp_agreement_id.present?
          biz[:agreement_no] = subscription.psp_agreement_id
        else
          biz[:external_agreement_no] = subscription.external_ref
        end
        mode = subscription.metadata.fetch("billing_authorization_context", {}).fetch("mode", account.mode)
        call_api("alipay.user.agreement.query", biz, gateway: billing_gateway(mode: mode))
      end

      def billing_query(payment:)
        query(payment: payment, gateway: billing_gateway(mode: payment.attempt_context.fetch("mode")))
      end

      def billing_refund(payment:, refund:)
        refund(payment: payment, refund: refund, gateway: billing_gateway(mode: payment.attempt_context.fetch("mode")))
      end

      def billing_close(payment:)
        close(payment: payment, gateway: billing_gateway(mode: payment.attempt_context.fetch("mode")))
      end

      def charge_subscription(subscription:, payment:)
        biz = {
          out_trade_no: payment.out_trade_no,
          total_amount: Payments::Money.new(payment.amount, "cny").decimal_string,
          subject: subscription.plan_name,
          agreement_params: { agreement_no: subscription.psp_agreement_id }
        }
        data = call_api("alipay.trade.pay", biz, gateway: subscription.billing_owned? ? billing_gateway : GATEWAY)
        { psp_transaction_id: data["trade_no"], raw: data }
      end

      def download_bill(bill_date:, bill_type:)
        data = call_api("alipay.data.dataservice.bill.downloadurl.query",
                        { bill_type: bill_type.upcase, bill_date: bill_date.strftime("%Y-%m-%d") })
        dl   = http_get(data["bill_download_url"])
        { csv: dl.body, raw_summary: data }
      end

      # Replay/freshness window. Alipay stamps notify_time in Beijing local time.
      # Alipay's own redelivery schedule for a notification that hasn't been
      # acked is roughly 10m/1h/2h/6h/15h — a window shorter than ~15h would
      # reject Alipay's OWN legitimate redeliveries after any outage longer than
      # the window, permanently losing that notification (Alipay never retries
      # past its schedule). A day-scale window comfortably covers that schedule;
      # the replay-attack protection this window provides is secondary to
      # signature verification + the dispatcher's notify_id dedup ledger, so the
      # wider window trades a little replay-window tightness for not losing
      # legitimate redeliveries during a transient outage.
      NOTIFICATION_FRESHNESS_WINDOW = 25.hours

      def verify_notification(headers:, body:)
        params = CGI.parse(body).transform_values(&:first)
        sign   = params.delete("sign")
        params.delete("sign_type")
        to_sign = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
        public_key = rsa_key(account.credential(:platform_public_key_pem))
        verify_rsa_signature!(key: public_key, signature: Base64.decode64(sign.to_s), message: to_sign)
        reject_stale_notification!(params["notify_time"])
        params
      end

      register!

      private

      # Enforced only when notify_time is present & parseable (real Alipay
      # notifications always carry it); absent/garbage times fall through so the
      # signature + dedup ledger remain the primary guards.
      def reject_stale_notification!(notify_time)
        return if notify_time.blank?

        parsed = Time.find_zone(TIMEZONE).parse(notify_time.to_s) rescue nil
        return if parsed.nil?

        if (Time.now - parsed).abs > NOTIFICATION_FRESHNESS_WINDOW
          raise Payments::Errors::SignatureInvalid, "alipay notification timestamp out of window"
        end
      end

      def flow_method(flow)
        case flow
        when :qr    then "alipay.trade.precreate"
        when :h5    then "alipay.trade.wap.pay"
        when :jsapi then "alipay.trade.create"
        else raise ArgumentError, "unsupported Alipay flow: #{flow.inspect}"
        end
      end

      def billing_gateway(mode: account.mode)
        mode == "sandbox" ? BILLING_SANDBOX_GATEWAY : GATEWAY
      end

      def call_api(method, biz_content, gateway: GATEWAY)
        response = post_json(gateway,
                             body: URI.encode_www_form(signed_params(method, biz_content)),
                             headers: { "Content-Type" => "application/x-www-form-urlencoded" })
        data = response["#{method.tr('.', '_')}_response"] || response["error_response"]
        unless data.is_a?(Hash) && data["code"].present?
          raise Payments::Errors::TransportError, "missing Alipay business response/code"
        end
        return data if data["code"] == "10000"

        # 20000 is Service Currently Unavailable; 10003 is a trade.pay
        # processing result. Neither establishes non-execution of a write.
        # https://opendocs.alipay.com/open/common/105806
        if %w[20000 10003].include?(data["code"]) || data["sub_code"].to_s.start_with?("isp.")
          raise Payments::Errors::TransportError, "uncertain Alipay operation (#{data['code']})"
        end

        raise Payments::Errors::ApiError.new(data["sub_msg"].presence || data["msg"].presence || "Alipay business error",
                                            code: data["code"], payload: data,
                                            definitive: NONEXECUTION_CODES.include?(data["code"]) ||
                                              (data["code"] == "40004" && NONEXECUTION_SUB_CODES.include?(data["sub_code"])))
      end

      # Full RSA2-signed public-parameter set for an OpenAPI method — shared
      # by server-side calls (call_api) and page APIs (build_wap_url).
      def signed_params(method, biz_content, extra: {})
        params = {
          app_id: account.merchant_id,
          method: method,
          format: "JSON",
          charset: "utf-8",
          sign_type: "RSA2",
          timestamp: Time.now.in_time_zone(TIMEZONE).strftime("%Y-%m-%d %H:%M:%S"),
          version: "1.0",
          notify_url: notify_url,
          biz_content: biz_content.to_json
        }.merge(extra.compact)
        to_sign = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
        params.merge(sign: Base64.strict_encode64(rsa_sign(to_sign)))
      end

      # Signed alipay.trade.wap.pay page URL: the user's browser GETs the
      # gateway with the full signed parameter set and lands on the cashier.
      def build_wap_url(biz, payment)
        params = signed_params(
          "alipay.trade.wap.pay",
          biz.merge(product_code: "QUICK_WAP_WAY"),
          extra: { return_url: result_url(payment) }
        )
        "#{GATEWAY}?#{URI.encode_www_form(params)}"
      end

      def map_status(s)
        case s
        when "TRADE_SUCCESS", "TRADE_FINISHED" then :succeeded
        when "WAIT_BUYER_PAY"                  then :pending
        when "TRADE_CLOSED"                    then :closed
        else
          raise Payments::Errors::TransportError, "unknown Alipay trade status"
        end
      end
    end
  end
end
