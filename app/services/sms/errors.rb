# frozen_string_literal: true

module Sms
  module Errors
    class Error              < StandardError; end
    class CredentialsMissing < Error; end
    class TemplateNotFound   < Error; end
    class TemplateVarsInvalid < Error; end
    class ModuleDisabled     < Error; end
    class IdempotencyConflict < Error; end

    class MarketingIneligible < TemplateVarsInvalid
      attr_reader :reason

      def initialize(reason:)
        @reason = reason
        super(I18n.t("sms_campaigns.reasons.#{reason}"))
      end
    end

    class RateLimited < Error
      attr_reader :window
      def initialize(window:, msg: nil)
        @window = window
        super(msg || I18n.t("sms.errors.rate_limited", window: window))
      end
    end

    class DailyCapExceeded < Error; end
    class Suppressed       < Error; end   # recipient has opted out (STOP)
    class ApiError         < Error
      attr_reader :code, :payload
      def initialize(msg, code: nil, payload: nil)
        @code = code
        @payload = payload
        super(msg)
      end
    end
    class TransportError < Error
      attr_reader :vendor_message_id, :payload

      def initialize(message = nil, vendor_message_id: nil, payload: nil)
        @vendor_message_id = vendor_message_id
        @payload = payload
        super(message)
      end
    end
    class SignatureInvalid < Error; end
  end
end
