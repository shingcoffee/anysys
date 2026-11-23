# frozen_string_literal: true

module Authentication
  # The Devise verification hook owns Lockable's persisted counters and unlocks.
  # Calling valid_password? alone checks only the digest and bypasses that hook.
  class PasswordVerification
    def self.call(user:, password:, on_comparison: nil)
      user.valid_for_authentication? do
        matches = user.valid_password?(password)
        on_comparison&.call(matches)
        matches
      end
    end

    def self.authenticate(user:, password:, &observer)
      complete(user: user, verified: call(user: user, password: password, on_comparison: observer))
    end

    def self.complete(user:, verified:)
      return unless verified && user.active_for_authentication?

      user.reset_failed_attempts!
      user
    end
  end
end
