# frozen_string_literal: true

module Email
  module Errors
    class Error < StandardError; end
    class CredentialsMissing < Error; end
    class TemplateNotFound < Error; end
    class TemplateVarsInvalid < Error; end
    class DailyCapExceeded < Error; end
    class InvalidRecipient < Error; end
    class Suppressed       < Error; end   # recipient is on the suppression list
    class TransportError   < Error; end   # network/timeout to an API provider
    class SignatureInvalid < Error; end   # webhook signature verification failed

    class ApiError < Error
      attr_reader :code, :payload
      def initialize(msg, code: nil, payload: nil)
        @code = code
        @payload = payload
        super(msg)
      end
    end

    # Deterministic capability rejection, shared by admission and dispatch.
    class UnsupportedMessage < ApiError; end
  end
end
