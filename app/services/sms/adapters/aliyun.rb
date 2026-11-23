# frozen_string_literal: true

# Sms::Adapters (registry) is referenced by register!/default! at load time.
require_relative "../adapters"

module Sms
  module Adapters
    # Aliyun Dysmsapi adapter (:poll delivery mechanism — status is pulled via
    # QuerySendDetails, since Aliyun pushes delivery receipts to an MNS queue
    # rather than an HTTP webhook).
    #
    # The RPC v1.0 HMAC-SHA1 signature lives in Vendor::AliyunRpc — the one
    # shared signer for every Aliyun RPC adapter in the app. It is hand-rolled
    # there (no maintained Ruby SDK covers Aliyun RPC APIs) and golden-tested.
    # Encoding gotchas vs plain CGI.escape: '+'→'%20', '*'→'%2A', '%7E'→'~';
    # HMAC key is access_key_secret with a trailing '&'.
    class Aliyun < Base
      HOST            = "https://dysmsapi.aliyuncs.com"
      VERSION         = "2017-05-25"
      DEFAULT_REGION  = "cn-hangzhou"

      class << self
        def key                  = "aliyun"
        def default_display_name = "Aliyun SMS"
        def delivery_mechanism   = :poll
        def query_supported?     = true

        def config_fields
          [
            { name: :sign_name, label: "Sign name", type: :string },
            { name: :region,    label: "Region",    type: :string, default: DEFAULT_REGION }
          ]
        end

        def configured?(credential)
          credential.access_key_id.present? &&
            credential.access_key_secret.present? &&
            credential.config_value(:sign_name).present?
        end
      end

      register!
      default!

      def send_message(to:, template:, template_params:)
        params = common_params.merge(
          "Action"        => "SendSms",
          "PhoneNumbers"  => to,
          "SignName"      => credential.config_value(:sign_name).to_s,
          "TemplateCode"  => template.provider_code("aliyun").to_s,
          "TemplateParam" => template_params.to_json
        )
        json = rpc_result(params, failure_key: Sms::Message::FAILURE_SEND)
        malformed_response!(raw: response_audit(json)) unless validated_vendor_message_id(json["BizId"])
        { vendor_message_id: json["BizId"], raw: json }
      end

      def query(message:)
        # QuerySendDetails uses the domestic 11-digit number; international
        # numbers use country code + national number, without '+'. Provider
        # calendar dates/times are China Standard Time, not the app's locale.
        # https://help.aliyun.com/zh/sms/developer-reference/api-dysmsapi-2017-05-25-querysenddetails
        # Dispatch, not admission or the response received after midnight,
        # determines the provider's SendDate. Legacy rows use sent_at/created_at.
        send_date = (message.dispatch_started_at || message.sent_at || message.created_at).in_time_zone("Asia/Shanghai").to_date
        params = common_params.merge(
          "Action"      => "QuerySendDetails",
          "PhoneNumber" => query_phone(message.to),
          "SendDate"    => send_date.strftime("%Y%m%d"),
          "PageSize"    => "1",
          "CurrentPage" => "1",
          "BizId"       => message.vendor_message_id
        )
        json = rpc_result(params, failure_key: "sms_standards.errors.query_failed")
        # QuerySendDetails' actual response names, including the Sms prefix.
        dtos = json["SmsSendDetailDTOs"]
        details = dtos.is_a?(Hash) ? dtos["SmsSendDetailDTO"] : nil
        rows = details.is_a?(Array) ? details.select { |row| row.is_a?(Hash) } : []
        detail = rows.find { |row| receipt_phone(row["PhoneNum"], expected: message.to) == message.to }
        detail ||= rows.first
        detail ||= {}
        {
          status: map_query_status(detail["SendStatus"]), raw: json,
          phone: receipt_phone(detail["PhoneNum"], expected: message.to),
          provider_status: detail["SendStatus"]&.to_s,
          failure_code: detail["SendStatus"].to_s == "2" ? detail["ErrCode"] : nil,
          occurred_at: ReceiptDetails.time(detail["ReceiveDate"], zone: "Asia/Shanghai")
        }.compact
      end

      # Binds this adapter's credential to the shared signer. The algorithm and
      # the "Signature" merge both live in Vendor::AliyunRpc; only the secret's
      # location is per-adapter.
      def sign_params(params)
        Vendor::AliyunRpc.sign(params, secret: credential.access_key_secret)
      end

      private

      def receipt_phone(value, expected:)
        # Aliyun's international PhoneNum is country-code + number, without an
        # international marker. Do not feed it to the CN-national input parser.
        return ReceiptDetails.phone(value) unless value.is_a?(String) && value.match?(/\A[0-9]+\z/)

        domestic = expected.start_with?("+86") && value.length == 11
        ReceiptDetails.phone(domestic ? value : "+#{value}")
      end

      def query_phone(phone)
        normalized = PhoneNumber.normalize(phone)
        return phone unless normalized

        normalized.start_with?("+86") ? normalized.delete_prefix("+86") : normalized.delete_prefix("+")
      end

      def rpc_result(params, failure_key:)
        response, json = http_post_form(HOST, sign_params(params))
        # A successful-looking body on HTTP failure (or malformed JSON) cannot
        # prove rejection/acceptance. A worker must never blindly resend it.
        unless response.status.to_i.between?(200, 299) && json.is_a?(Hash) && json["Code"].is_a?(String) && json["Code"].present?
          vendor_id = json["BizId"] if params["Action"] == "SendSms" && json.is_a?(Hash) && json["Code"] == "OK"
          malformed_response!(vendor_message_id: vendor_id, raw: response_audit(json))
        end
        unless json["Code"] == "OK"
          raise Sms::Errors::ApiError.new(json["Message"].presence || I18n.t(failure_key),
                                         code: json["Code"], payload: json)
        end
        json
      end

      def response_audit(json)
        json.slice("Code", "BizId", "Message", "RequestId") if json.is_a?(Hash)
      end

      def common_params
        Vendor::AliyunRpc.common_params(
          access_key_id: credential.access_key_id,
          region_id:     credential.config_value(:region, DEFAULT_REGION),
          version:       VERSION
        )
      end

      # Aliyun SendStatus: 1 = waiting, 2 = failed, 3 = succeeded.
      def map_query_status(status)
        case status.to_s
        when "3" then :delivered
        when "2" then :failed
        else        :unknown
        end
      end
    end
  end
end
