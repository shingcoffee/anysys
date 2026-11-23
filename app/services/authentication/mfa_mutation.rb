# frozen_string_literal: true

module Authentication
  # MFA mutations share the credential lock with recovery consumption. Do not
  # clear or replace a newer secret using an instance loaded before a rotation.
  class MfaMutation
    def self.call(user:, **attributes)
      CredentialLifecycle.with_current(user) do |account|
        account.update!(attributes)
        user.reload
      end
    end
  end
end
