# frozen_string_literal: true

module Member
  module Mfa
    module Operation
      class Enable
        Result = Struct.new(:success?, :user, :errors, keyword_init: true)

        THROTTLED = :throttled

        def self.call(user:, code:)
          return failure(user, base: ["must be a member"]) unless user&.member?

          user.generate_otp_secret! if user.otp_secret.blank?

          # Same `mfa:<id>` bucket as disable / session verify so enrollment
          # cannot brute-force the freshly planted TOTP secret.
          throttle = Authentication::Throttle.new(
            key: "mfa:#{user.id}", limit: 5, period: 15.minutes
          )
          return failure(user, base: [THROTTLED]) if throttle.exceeded?

          unless user.verify_otp(code)
            throttle.record_failure
            return failure(user, code: ["is invalid"])
          end

          throttle.clear
          user.enable_mfa!
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
