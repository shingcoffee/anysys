# frozen_string_literal: true

module Member
  module Mfa
    # Mints/verifies stateless reset-link tokens for the member MFA
    # recovery flow. A token carries (user_id, customer_id, fingerprint),
    # is signed by Rails.application.message_verifier with a 15-minute TTL,
    # and is bound to the current value of user.otp_secret via SHA-256.
    # A successful consume nils the secret, which invalidates the
    # fingerprint of any other outstanding token.
    class ResetToken
      VERIFIER_PURPOSE = :consume
      TTL              = 15.minutes

      Result = Struct.new(:success?, :user, :reason, keyword_init: true)

      def self.generate(user)
        verifier.generate(payload_for(user), purpose: VERIFIER_PURPOSE, expires_in: TTL)
      end

      def self.verify(token)
        payload = decode(token)
        return failure(:expired_or_invalid) unless payload

        verify_user(lookup(payload), payload)
      end

      # Signature decoding may precede the lock; account identity, role and
      # fingerprint verification MUST be repeated on the locked, reloaded row.
      def self.consume(token)
        payload = decode(token)
        return failure(:expired_or_invalid) unless payload

        user = lookup(payload)
        return failure(:expired_or_invalid) unless user

        user.with_lock(requires_new: true) do
          payload = decode(token)
          next failure(:expired_or_invalid) unless payload

          result = verify_user(user, payload)
          yield user if result.success?
          result
        end
      end

      def self.verify_user(user, payload)
        return failure(:expired_or_invalid) unless user && user.id == payload[:user_id] &&
          user.customer_id == payload[:customer_id]
        return failure(:not_a_member)       unless user.member?
        return failure(:fingerprint_mismatch) unless user.otp_secret.present? &&
          fingerprint(user.otp_secret) == payload[:fingerprint]

        Result.new(success?: true, user: user, reason: nil)
      end
      private_class_method :verify_user

      def self.decode(token)
        payload = verifier.verified(token.to_s, purpose: VERIFIER_PURPOSE)
        payload.symbolize_keys if payload.is_a?(Hash)
      end
      private_class_method :decode

      def self.lookup(payload)
        ::Authentication::User.find_by(id: payload[:user_id], customer_id: payload[:customer_id])
      end
      private_class_method :lookup

      def self.fingerprint(otp_secret)
        Digest::SHA256.hexdigest(otp_secret.to_s)
      end

      def self.payload_for(user)
        {
          user_id:     user.id,
          customer_id: user.customer_id,
          fingerprint: fingerprint(user.otp_secret)
        }
      end
      private_class_method :payload_for

      def self.verifier
        Rails.application.message_verifier(:member_mfa_reset)
      end
      private_class_method :verifier

      def self.failure(reason)
        Result.new(success?: false, user: nil, reason: reason)
      end
      private_class_method :failure
    end
  end
end
