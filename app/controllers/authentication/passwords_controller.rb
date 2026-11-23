# frozen_string_literal: true

module Authentication
  class PasswordsController < Devise::PasswordsController
    include TenantContext
    include Authentication::PermitsUserParams
    include Authentication::EmailFloodThrottled

    layout "auth"

    before_action :throttle_password_reset!, only: :create
    before_action :ensure_password_reset_available!, only: %i[edit update]

    protected

    # Devise hook. A successful reset must not also establish a session: the
    # person holding the emailed token has proved control of the mailbox, not
    # possession of the second factor, so they sign in again through the
    # normal gate (which re-applies MFA).
    def sign_in_after_reset_password?
      false
    end

    def after_resetting_password_path_for(resource)
      Authentication::AuditLog.record(event: :password_reset_completed, user: resource, request: request)
      new_user_session_path
    end

    def after_sending_reset_password_instructions_path_for(_resource_name)
      Authentication::AuditLog.record(event: :password_reset_requested,
                                      customer_id: resource&.customer_id, request: request)
      new_user_session_path
    end

    def resource_params
      permitted_user_params(:email, :password, :password_confirmation, :reset_password_token)
    end

    private

    # Rate-limit reset REQUESTS so the endpoint can't be used to email-bomb a
    # known address or probed for enumeration. Delegates to the shared dual
    # bucket (per-IP and per-recipient, identical response on either breach)
    # rather than the hand-rolled copy that used to live here — which had
    # drifted into a second SHA-256 email-bucket implementation and a direct
    # `find_by("LOWER(email) = ?")` that bypassed the canonical lookup.
    def throttle_password_reset!
      throttle_email_flood!(
        flow:          "password_reset",
        email:         permitted_user_params(:email)[:email],
        redirect_path: new_user_password_path,
        alert:         t("auth.flash.password.throttled")
      )
    end

    # Devise's inherited #edit and #update had no tenant gate at all: only the
    # request side consulted the toggles, so a token minted while password
    # reset was enabled stayed redeemable for its whole 6-hour window after an
    # admin disabled password reset — or disabled the authentication module
    # outright. Disabling was therefore not an incident-response control.
    #
    # Resolving the tenant from the token (not from user input) means an
    # unknown or forged token reveals nothing: it falls through to Devise's
    # standard invalid-token handling.
    def ensure_password_reset_available!
      user = reset_password_token_owner
      return if user.nil?
      return if user.password_reset_available?

      render :disabled, status: :forbidden
    end

    def reset_password_token_owner
      # Check exactly the token Devise consumes: #edit reads the query param,
      # while #update reads the permitted user payload. A conflicting query
      # token must never select a different tenant for the availability gate.
      token = action_name == "edit" ? params[:reset_password_token] : resource_params[:reset_password_token]
      return nil if token.blank?

      resource_class.with_reset_password_token(token.to_s)
    end
  end
end
