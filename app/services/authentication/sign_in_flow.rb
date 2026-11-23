# frozen_string_literal: true

module Authentication
  # Centralised sign-in pipeline used by the Devise sessions controller
  # and the public root sign-in form. Email is globally unique, so tenant
  # resolution happens from the matched user row.
  #
  # Returns a Result with #success?, #user, and #next_action describing
  # where the controller should send the request:
  #   :invalid_credentials → render the form with the Devise locale error
  #   :mfa_required        → redirect to mfa_session_path
  #   :mfa_setup_required  → redirect to mfa_setup_path
  #   :authenticated       → redirect to the dashboard / stored location
  class SignInFlow
    Result = Struct.new(:success?, :user, :next_action, :mfa_verified, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    # Passwordless first factor (confirmation click or email sign-in link).
    # It replaces the password, NOT the second factor: a mailbox is one
    # factor, so an MFA-enrolled user still gets :mfa_required here exactly
    # as they would after typing their password.
    def self.complete(user:, trusted_device_token: nil)
      new(email: user&.email, password: nil, trusted_device_token: trusted_device_token)
        .complete_for(user)
    end

    def initialize(email:, password:, trusted_device_token: nil)
      @email = email
      @password = password
      @trusted_device_token = trusted_device_token
    end

    def call
      user = Authentication::User.find_for_database_authentication(email: @email)

      authenticated = user && user.password_set? && auth_enabled_for?(user) &&
        PasswordVerification.call(user: user, password: @password)

      return failure(:invalid_credentials, user: user) unless authenticated

      succeed(user)
    end

    def complete_for(user)
      return failure(:invalid_credentials, user: user) unless user
      return failure(:invalid_credentials, user: user) unless auth_enabled_for?(user)
      return failure(:invalid_credentials, user: user) if user.access_locked?
      return failure(:invalid_credentials, user: user) unless user.active?
      # This is the authorization decision for every passwordless first
      # factor, so it owns the confirmation check too. Callers' own
      # eligibility pre-flights are defence in depth, not the gate: without
      # this, an unconfirmed user reaching here was only stopped further
      # downstream by Devise's activatable Warden hook — after reset_session
      # had already run.
      return failure(:invalid_credentials, user: user) unless user.confirmed?

      succeed(user)
    end

    private

    def succeed(user)
      user.reset_failed_attempts! if user.respond_to?(:reset_failed_attempts!)

      action = post_auth_action(user)
      Result.new(success?: true, user: user, next_action: action,
                 mfa_verified: action == :authenticated)
    end

    def auth_enabled_for?(user)
      FeatureModules::Module.enabled?(key: "authentication", customer_id: user.customer_id)
    end

    def post_auth_action(user)
      if user.mfa_required?
        return :authenticated if trusted_device?(user)
        return :mfa_required
      end
      # Tenant-wide MFA for admins/owners: send them to setup *before*
      # marking the session verified. Otherwise visiting GET mfa/setup
      # plants otp_secret (mfa_configured? becomes true) while
      # session[:mfa_verified] is already true from password login, and
      # both enforce_mfa! gates treat enrollment as done.
      return :mfa_setup_required if tenant_mfa_enforced?(user)
      return :mfa_setup_required if user.mfa_configured?

      :authenticated
    end

    def tenant_mfa_enforced?(user)
      return false if user.member? && !user.admin_or_owner?

      Authentication::Settings.for(user.customer_id).mfa_enabled?
    end

    def trusted_device?(user)
      Authentication::TrustedDevice.authenticate(
        user: user, raw_token: @trusted_device_token
      ).present?
    end

    def failure(action, user: nil)
      Result.new(success?: false, user: user, next_action: action, mfa_verified: false)
    end
  end
end
