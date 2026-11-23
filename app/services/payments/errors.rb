# frozen_string_literal: true

module Payments
  module Errors
    class Error             < StandardError; end
    class CredentialsMissing < Error; end
    class TransportError < Error
      def definitive? = false
      def uncertain? = true
      def classification = :uncertain
    end
    class ApiError           < Error
      attr_reader :code, :payload, :classification

      # Non-execution is a vendor assertion, not a consequence of this class or
      # of receiving any 4xx. Unknown outcomes conservatively retain their key.
      # Never allow a caller to label HTTP 5xx/409/429 definitive.
      def initialize(message, code: nil, payload: {}, definitive: false)
        super(message)
        @code = code
        @payload = payload
        status = code.to_s.match?(/\A[1-5]\d{2}\z/) ? code.to_i : nil
        uncertain_status = status && (status >= 500 || [409, 429].include?(status))
        @classification = definitive == true && !uncertain_status ? :definitive_rejection : :uncertain
      end

      def definitive? = classification == :definitive_rejection
      def uncertain? = !definitive?
    end
    class SignatureInvalid   < Error; end
    class TenantNotFound     < Error; end
    class CardDeclined       < Error; end
    class TenantMismatch     < Error; end
    # Public checkout (or any Charge caller) tried to capture an order that
    # is already paid / partially refunded / refunded. A second PSP capture
    # must not be created — that would charge the shopper twice.
    class OrderSettled       < Error; end
    class OrderExpired       < Error; end
    # A dual-provider switch could not close the in-flight sibling at the PSP,
    # so starting a second capture would collect twice.
    class OrderInFlight      < Error; end
    # Off-session charge could not complete because the card issuer demands
    # interactive authentication (3DS/SCA). Non-terminal: the caller (cron)
    # must NOT advance the subscription's next_charge_at when this is raised.
    class PaymentRequiresAction < Error; end
    # A refund request violates an invariant (payment not captured, or the
    # cumulative refunded amount would exceed the captured amount). Carries a
    # machine-readable `code` (:not_captured / :non_positive / :exceeds_remainder /
    # :billing_collection)
    # plus already-formatted `details` so the admin controller can render a
    # translated flash — while `message` stays the developer-oriented English
    # string kept for logs.
    class RefundNotAllowed      < Error
      attr_reader :code, :details
      def initialize(message, code: nil, details: {})
        super(message); @code = code; @details = details
      end
    end
  end
end
