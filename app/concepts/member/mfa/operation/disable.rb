# frozen_string_literal: true

module Member
  module Mfa
    module Operation
      class Disable
        Result = Struct.new(:success?, :user, :errors, keyword_init: true)

        # Stable discriminator for the member MFA controller — never a
        # locale string. Controllers map this to I18n at the flash boundary.
        THROTTLED = :throttled

        def self.call(user:, code:)
          return failure(user, base: ["must be a member"]) unless user&.member?
          return failure(user, base: ["MFA is not enabled"]) unless user.mfa_required?

          # Throttle OTP attempts per user so the member disable flow cannot be
          # used to brute-force the second factor. Shares the `mfa:<id>` bucket
          # with the controller-level MFA limiters.
          throttle = Authentication::Throttle.new(
            key: "mfa:#{user.id}", limit: 5, period: 15.minutes
          )
          return failure(user, base: [THROTTLED]) if throttle.exceeded?

          unless user.verify_otp(code)
            throttle.record_failure
            return failure(user, code: ["is invalid"])
          end

          throttle.clear
          user.disable_mfa!
          Result.new(success?: true, user: user, errors: nil)
        end

        def self.failure(user, errors)
          Result.new(success?: false, user: user, errors: errors)
        end
        private_class_method :failure
      end
    end
  end
end
