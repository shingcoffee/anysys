# frozen_string_literal: true

module Authentication
  # Serialize credential writes and grant consumption/issuance on the user row.
  # Dirty writes from a stale instance must not resurrect a replaced credential.
  class CredentialLifecycle
    ATTRIBUTES = %w[encrypted_password otp_secret email customer_id].freeze

    def self.around_update(user)
      return yield unless ATTRIBUTES.any? { |name| user.will_save_change_to_attribute?(name) }

      account = User.find(user.id)
      account.with_lock(requires_new: true) do
        before = snapshot(account)
        expected = ATTRIBUTES.map { |name| user.attribute_in_database(name) }
        raise ActiveRecord::StaleObjectError.new(user, "update") unless expected == before

        OwnerIdentity.validate(user)
        raise ActiveRecord::RecordInvalid.new(user) if user.errors.any?

        user.last_otp_at = nil if user.will_save_change_to_otp_secret?
        result = yield
        revoke!(user) if result && invalidated?(before, snapshot(account.reload))
        result
      end
    end

    def self.with_current(user)
      account = User.find(user.id)
      account.with_lock(requires_new: true) do
        raise ActiveRecord::StaleObjectError.new(user, "update") unless snapshot(user) == snapshot(account)

        yield account
      end
    end

    def self.snapshot(user)
      ATTRIBUTES.map { |name| user.public_send(name) }
    end

    def self.invalidated?(before, after)
      password, secret, email, customer_id = before
      password != after[0] || (secret.present? && secret != after[1]) ||
        email != after[2] || customer_id != after[3]
    end
    private_class_method :invalidated?

    def self.revoke!(user)
      user.trusted_devices.delete_all
      Oauth::AccessToken.revoke_all_for(user.id)
      Doorkeeper.config.access_grant_model.where(resource_owner_id: user.id, revoked_at: nil)
        .update_all(revoked_at: Time.current)
      user.update_columns(sign_in_token: nil, sign_in_token_sent_at: nil)
    end
    private_class_method :revoke!
  end
end
