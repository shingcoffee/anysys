# frozen_string_literal: true

require "openssl"
require "base64"
require "securerandom"
require "json"
require "digest"

module Payments
  module Gateways
    # WeChat Pay v3 (China) — RSA2048 signing.
    # WeChat Pay (China) — APIv3, RSA-SHA256 request signing.
    #
    # The APIv3 envelope (Authorization token, notification verification,
    # JSAPI re-signing) is intentionally hand-rolled on stdlib OpenSSL:
    # `wx_pay` targets the retired APIv2 (XML + MD5), and the community v3
    # gems are low-maintenance single-maintainer projects with no multi-tenant
    # credential support. Transport goes through OutboundHttp (Faraday).
    class WechatPay < Base
      HOST = "https://api.mch.weixin.qq.com"
      NONEXECUTION_CODES = %w[PARAM_ERROR SIGN_ERROR MCH_NOT_EXISTS RESOURCE_NOT_EXISTS ORDER_NOT_EXIST NOT_ENOUGH].freeze

      class << self
        def key          = "wechat_pay"
        def display_name = "WeChat Pay (China)"

        def credential_fields
          [
            { name: :appid,                   label: "App ID (official account / mini program)", type: :string,   encrypted: false },
            { name: :api_key_v3,              label: "APIv3 key",                       type: :password, encrypted: true },
            { name: :private_key_pem,         label: "Merchant private key (PEM)",      type: :text, encrypted: true },
            { name: :platform_public_key_pem, label: "WeChat Pay platform public key",  type: :text, encrypted: true },
            { name: :wechat_cert_serial,      label: "Merchant cert serial",            type: :string,   encrypted: false }
          ]
        end

        def supported_flows = %i[qr h5 jsapi]

        # WeChat implements one-time charge, refunds, downloadable settlement
        # bills, and async notifications. Contract-pay (recurring) is not wired
        # yet, so :recurring is intentionally absent.
        def capabilities = %i[one_time refunds reconciliation webhooks]

        def jsapi_user_agent_pattern = /MicroMessenger/i

        def extract_merchant_id(_headers, body)
          payload = notification_payload(body)
          resource = notification_hash(payload["resource"])
          mchid = notification_id(resource["mchid"]) || notification_id(payload["mchid"])
          return mchid if mchid.present?

          merchant_id_from_encrypted_resource(payload["resource"])
        end

        def notification_payload(body)
          payload = parse_notification(body)
          resource = notification_hash(payload["resource"])
          notification_hash(resource["amount"])
          payload
        end

        # WeChat v3 encrypts `resource`; plaintext mchid is not on the envelope.
        # Try each known merchant's APIv3 key until AEAD succeeds, then confirm
        # decrypted mchid matches that row. Signature verification still runs
        # after routing. Wrong keys raise CipherError and are skipped.
        def merchant_id_from_encrypted_resource(resource)
          return "" unless resource.is_a?(Hash) && resource["ciphertext"].present?

          Payments::MerchantAccount.unscoped_by_tenant.where(provider: key).find_each do |acc|
            key_bytes = acc.credential(:api_key_v3).to_s
            next unless key_bytes.bytesize == 32

            decrypted = new(account: acc).send(:gcm_decrypt, resource, key_bytes)
            mchid = notification_id(parse_notification(decrypted)["mchid"])
            return mchid if mchid.present? && mchid == acc.merchant_id.to_s
          rescue Payments::Errors::SignatureInvalid, JSON::ParserError, ArgumentError
            next
          end
          ""
        end

        def event_id(payload)   = payload["id"].presence
        def event_type(payload) = payload["event_type"].presence
      end

      def charge(order:, payment:, flow:, openid: nil, client_ip: nil)
        path, body = build_charge(order, payment, flow, openid, client_ip)
        json = post_json(HOST + path, body: body, headers: auth_headers("POST", path, body.to_json))
        prepay =
          case flow
          when :qr then { code_url: json["code_url"] }
          when :h5 then { h5_url: json["h5_url"] }
          else          jsapi_params(json["prepay_id"]) # :jsapi (flow already validated by build_charge)
          end
        { prepay_payload: prepay }
      end

      def query(payment:)
        path = "/v3/pay/transactions/out-trade-no/#{payment.out_trade_no}?mchid=#{account.merchant_id}"
        json = get_json(HOST + path, headers: auth_headers("GET", path, ""))
        amount = json["amount"] || {}
        raise Payments::Errors::TransportError, "malformed WeChat amount assertion" unless amount.is_a?(Hash)

        currency = reported_currency(amount["currency"])
        {
          status: map_status(json["trade_state"]),
          psp_transaction_id: json["transaction_id"],
          raw: json,
          currency: currency,
          amount: reported_amount(amount["total"], currency: currency, minor_units: true),
          settled_at: reported_time(json["success_time"])
        }
      end

      def refund(payment:, refund:)
        path = "/v3/refund/domestic/refunds"
        body = {
          out_trade_no: payment.out_trade_no,
          out_refund_no: refund.out_refund_no,
          amount: {
            refund: Payments::Money.new(refund.amount, "CNY").smallest_unit,
            total:  Payments::Money.new(payment.amount, "CNY").smallest_unit,
            currency: "CNY"
          },
          reason: refund.reason
        }
        json = post_json(HOST + path, body: body, headers: auth_headers("POST", path, body.to_json))
        { psp_refund_id: json["refund_id"], status: map_refund_status(json["status"]), raw: json }
      end

      def close(payment:)
        path = "/v3/pay/transactions/out-trade-no/#{payment.out_trade_no}/close"
        body = { mchid: account.merchant_id }
        http_post(HOST + path, body: body, headers: auth_headers("POST", path, body.to_json))
        { status: :closed }
      end

      def subscribe(subscription:)
        raise NotImplementedError, "WeChat contract-pay stub — requires merchant permissions"
      end

      def cancel_subscription(subscription:)
        raise NotImplementedError, "WeChat contract-pay stub"
      end

      def charge_subscription(subscription:, payment:)
        raise NotImplementedError, "WeChat contract-pay stub"
      end

      def download_bill(bill_date:, bill_type:)
        path = "/v3/bill/tradebill?bill_date=#{bill_date.strftime('%Y-%m-%d')}&bill_type=#{bill_type.upcase}"
        json = get_json(HOST + path, headers: auth_headers("GET", path, ""))
        uri = bill_download_uri(json["download_url"])
        # The token in download_url is not a substitute for APIv3 authorization.
        # Sign the exact escaped path + query returned by the bill application.
        # https://pay.weixin.qq.com/doc/v3/merchant/4012791868
        dl = http_get(uri.to_s, headers: auth_headers("GET", uri.request_uri, ""))
        verify_bill_hash!(dl.body, json)
        parsed = BillParser.call(dl.body)
        { csv: dl.body, rows: parsed.records,
          raw_summary: json.merge("bill_summary" => parsed.summary) }
      end

      # WeChat docs require notifications to be rejected if older than ~5
      # minutes; without freshness, an attacker who once captured a
      # validly-signed body can replay it indefinitely.
      NOTIFICATION_FRESHNESS_WINDOW = 5.minutes

      def verify_notification(headers:, body:)
        payload = self.class.notification_payload(body)
        sig_b64 = headers["Wechatpay-Signature"] || headers["wechatpay-signature"]
        ts      = headers["Wechatpay-Timestamp"] || headers["wechatpay-timestamp"]
        nonce   = headers["Wechatpay-Nonce"]     || headers["wechatpay-nonce"]
        raise Payments::Errors::SignatureInvalid, "missing signature headers" unless sig_b64 && ts && nonce

        ts_int = Integer(ts.to_s, 10) rescue nil
        if ts_int.nil? || (Time.now.to_i - ts_int).abs > NOTIFICATION_FRESHNESS_WINDOW.to_i
          raise Payments::Errors::SignatureInvalid, "notification timestamp out of window"
        end

        serial     = headers["Wechatpay-Serial"] || headers["wechatpay-serial"]
        message    = "#{ts}\n#{nonce}\n#{body}\n"
        public_key = resolve_platform_key(serial)
        signature = Base64.decode64(sig_b64.to_s)
        verify_rsa_signature!(key: public_key, signature: signature, message: message)
        decrypt_resource(payload)
      end

      register!

      private

      def definitive_api_rejection?(status:, payload:)
        [400, 401, 403, 404].include?(status) && payload.is_a?(Hash) && NONEXECUTION_CODES.include?(payload["code"])
      end

      def bill_download_uri(value)
        uri = URI.parse(value.to_s)
        unless uri.scheme == "https" && %w[api.mch.weixin.qq.com api2.mch.weixin.qq.com].include?(uri.host) &&
               uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil? && uri.path == "/v3/billdownload/file"
          raise URI::InvalidURIError
        end
        uri
      rescue URI::InvalidURIError
        raise Payments::Errors::ApiError.new("invalid WeChat bill download URL", code: "invalid_bill")
      end

      def verify_bill_hash!(body, metadata)
        return if metadata["hash_value"].blank?

        unless metadata["hash_type"] == "SHA1" && Digest::SHA1.hexdigest(body) == metadata["hash_value"].to_s.downcase
          raise Payments::Errors::TransportError, "WeChat bill checksum mismatch"
        end
      end

      # Platform-certificate rotation. WeChat signs each notification with one of
      # its platform certs and names it in the Wechatpay-Serial header; those certs
      # rotate. Rather than break verification until an admin re-uploads a key, we
      # resolve the cert for the header's serial from WeChat's own /v3/certificates
      # endpoint (auto-fetched, cached), and fall back to the admin-stored
      # platform_public_key_pem for bootstrap / when the fetch is unavailable.
      def resolve_platform_key(serial)
        if serial.present?
          pem = platform_certs[serial] || refreshed_platform_certs[serial]
          return public_key_from(pem) if pem.present?
        end

        stored = account.credential(:platform_public_key_pem)
        return public_key_from(stored) if stored.present?

        raise Payments::Errors::SignatureInvalid, "no platform certificate for serial #{serial.inspect}"
      end

      REFRESH_COOLDOWN = 5.minutes

      # Unknown serials force a re-download, but at most once per cooldown window
      # per merchant — an unauthenticated caller spraying bogus serials must not
      # be able to make us hammer WeChat's /v3/certificates endpoint.
      def refreshed_platform_certs
        cooldown_key = "#{platform_certs_cache_key}/refresh_cooldown"
        return {} if Rails.cache.exist?(cooldown_key)

        Rails.cache.write(cooldown_key, true, expires_in: REFRESH_COOLDOWN)
        platform_certs(refresh: true)
      end

      # { serial_no => certificate PEM }. Cached per merchant (12h); refresh: true
      # forces a re-download (used when a notification names a serial we have not
      # seen yet — i.e. WeChat just rotated).
      def platform_certs(refresh: false)
        if refresh
          @platform_certs = download_platform_certs
          Rails.cache.write(platform_certs_cache_key, @platform_certs, expires_in: 12.hours)
          return @platform_certs
        end
        @platform_certs ||=
          Rails.cache.fetch(platform_certs_cache_key, expires_in: 12.hours) { download_platform_certs }
      end

      def platform_certs_cache_key = "payments/wechat/platform_certs/#{account.merchant_id}"

      # GET /v3/certificates returns each current platform cert AEAD-encrypted under
      # the merchant's APIv3 key (same envelope as a notification resource), so we
      # decrypt with gcm_decrypt. Trust is anchored on TLS + APIv3-key possession
      # for the bootstrap fetch (WeChat's documented approach). Returns {} on any
      # gateway error so the caller can fall back to the stored key.
      def download_platform_certs
        json = get_json(HOST + "/v3/certificates", headers: auth_headers("GET", "/v3/certificates", ""))
        entries = json["data"]
        return {} unless entries.is_a?(Array)

        entries.each_with_object({}) do |entry, acc|
          next unless entry.is_a?(Hash)

          serial = entry["serial_no"]
          enc    = entry["encrypt_certificate"]
          next if serial.blank? || !enc.is_a?(Hash)

          acc[serial] = gcm_decrypt(enc, account.credential(:api_key_v3).to_s)
        end
      rescue Payments::Errors::Error
        {}
      end

      # Accept both a full X.509 certificate PEM (from /v3/certificates) and a bare
      # public-key PEM (the admin-stored fallback).
      def public_key_from(pem)
        s = pem.to_s
        key = s.include?("BEGIN CERTIFICATE") ? OpenSSL::X509::Certificate.new(s).public_key : rsa_key(s)
        raise Payments::Errors::CredentialsMissing, "WeChat platform key must be RSA" unless key.is_a?(OpenSSL::PKey::RSA)

        key
      rescue OpenSSL::OpenSSLError, ArgumentError
        raise Payments::Errors::CredentialsMissing, "invalid WeChat platform key configuration"
      end

      # APIv3 delivers the actual event object (out_trade_no, transaction_id,
      # trade_state, …) AES-256-GCM-encrypted inside resource.ciphertext,
      # keyed by the merchant's APIv3 key. Decrypt it (tag = last 16 bytes of
      # the base64 ciphertext, IV = resource.nonce, AAD = associated_data)
      # and merge the fields into "resource" so consumers read them uniformly.
      # Plaintext resources (sandbox/test bodies) pass through untouched.
      #
      # The decrypted mchid must match this account — the AEAD tag proves the
      # content was encrypted under THIS merchant's key, so a mismatch means
      # a mis-routed or forged notification.
      GCM_TAG_LENGTH = 16

      def decrypt_resource(payload)
        resource = payload["resource"]
        return payload unless resource.is_a?(Hash) && resource["ciphertext"].present?

        algorithm = resource["algorithm"].presence || "AEAD_AES_256_GCM"
        unless algorithm == "AEAD_AES_256_GCM"
          raise Payments::Errors::SignatureInvalid, "unsupported resource algorithm #{algorithm}"
        end

        api_key = account.credential(:api_key_v3).to_s
        raise Payments::Errors::CredentialsMissing, "APIv3 key not configured" if api_key.empty?

        decrypted = self.class.parse_notification(gcm_decrypt(resource, api_key))
        self.class.notification_hash(decrypted["amount"])
        mchid = self.class.notification_id(decrypted["mchid"])
        if mchid.present? && mchid != account.merchant_id.to_s
          raise Payments::Errors::SignatureInvalid, "decrypted resource mchid does not match account"
        end

        payload.merge("resource" => resource.merge(decrypted))
      end

      def gcm_decrypt(resource, api_key)
        unless api_key.bytesize == 32
          raise Payments::Errors::CredentialsMissing, "WeChat APIv3 key must contain 32 bytes"
        end
        raw = Base64.strict_decode64(resource["ciphertext"].to_s)
        ciphertext = raw[0...-GCM_TAG_LENGTH].to_s
        auth_tag   = raw[-GCM_TAG_LENGTH..].to_s

        cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
        cipher.key       = api_key
        cipher.iv        = resource["nonce"].to_s
        cipher.auth_tag  = auth_tag
        cipher.auth_data = resource["associated_data"].to_s
        cipher.update(ciphertext) + cipher.final
      rescue OpenSSL::Cipher::CipherError, ArgumentError => e
        raise Payments::Errors::SignatureInvalid, "resource decryption failed (#{e.class})"
      end

      def build_charge(order, payment, flow, openid, client_ip = nil)
        path =
          case flow
          when :qr    then "/v3/pay/transactions/native"
          when :h5    then "/v3/pay/transactions/h5"
          when :jsapi then "/v3/pay/transactions/jsapi"
          else raise ArgumentError, "unsupported WeChat Pay flow: #{flow.inspect}"
          end
        body = {
          appid: account.credential(:appid),
          mchid: account.merchant_id,
          description: order.subject,
          out_trade_no: payment.out_trade_no,
          notify_url: notify_url,
          amount: {
            total: Payments::Money.new(order.amount, "CNY").smallest_unit,
            currency: "CNY"
          }
        }
        body[:payer] = { openid: openid } if flow == :jsapi && openid
        if flow == :h5
          body[:scene_info] = {
            payer_client_ip: client_ip.to_s.presence || "127.0.0.1",
            h5_info: { type: "Wap" }
          }
        end
        [path, body]
      end

      def auth_headers(method, path, body)
        ts    = Time.now.to_i.to_s
        nonce = SecureRandom.hex(16)
        signing_string = "#{method}\n#{path}\n#{ts}\n#{nonce}\n#{body}\n"
        signature = Base64.strict_encode64(rsa_sign(signing_string))
        token = %Q(mchid="#{account.merchant_id}",serial_no="#{account.credential(:wechat_cert_serial)}",nonce_str="#{nonce}",timestamp="#{ts}",signature="#{signature}")
        {
          "Authorization" => "WECHATPAY2-SHA256-RSA2048 #{token}",
          "Content-Type"  => "application/json",
          "Accept"        => "application/json"
        }
      end

      def jsapi_params(prepay_id)
        appid = account.credential(:appid)
        ts    = Time.now.to_i.to_s
        nonce = SecureRandom.hex(16)
        package = "prepay_id=#{prepay_id}"
        signing = "#{appid}\n#{ts}\n#{nonce}\n#{package}\n"
        sig = Base64.strict_encode64(rsa_sign(signing))
        { appId: appid, timeStamp: ts, nonceStr: nonce, package: package, signType: "RSA", paySign: sig }
      end

      def map_status(state)
        case state
        when "SUCCESS" then :succeeded
        when "NOTPAY", "USERPAYING" then :pending
        when "CLOSED", "REVOKED"    then :closed
        else :failed
        end
      end

      def map_refund_status(s)
        case s
        when "SUCCESS"               then :succeeded
        when "PROCESSING"            then :processing
        when "CLOSED", "ABNORMAL"    then :failed
        else :processing
        end
      end
    end
  end
end
