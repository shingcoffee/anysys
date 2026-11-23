# frozen_string_literal: true

module Authentication
  class SessionsController < Devise::SessionsController
    include TenantContext
    include Authentication::TrustedDeviceCookieable
    include Authentication::FinishesSignIn
    include Authentication::IssuesSignInLink
    include Authentication::PermitsUserParams

    layout "auth"

    # SignInFlow owns credential checks. Devise's params-auth flag would
    # also run Warden on POST /auth/sign_in and double-count lockable
    # failures / steal the unconfirmed-user response.
    skip_before_action :allow_params_authentication!, only: :create

    # Cap stuffing at 20 per 5 minutes per IP on the shared throttle store
    # (Rails.cache / solid_cache), not a per-process MemoryStore. Set above
    # Devise.maximum_attempts so per-account lockout is hit first; this is
    # the secondary defence against IP-level stuffing across many accounts.
    RATE_LIMIT_CAP    = 20
    RATE_LIMIT_WINDOW = 5.minutes

    before_action :throttle_sign_in!, only: :create

    # GET /auth/sign_in — always rendered. Auth-module enablement is checked
    # after email lookup in SignInFlow so a disabled tenant is indistinguishable
    # from bad credentials.
    def new
      self.resource = resource_class.new
      @unconfirmed_email = session.delete(:unconfirmed_email)
    end

    # POST /auth/sign_in
    def create
      return issue_sign_in_link(sign_in_params[:email]) if params[:intent] == "sign_in_link"

      # Read the trusted-device cookie BEFORE reset_session so the value is
      # available even after the session rotation clears the old session.
      token = trusted_device_token

      result = Authentication::SignInFlow.call(
        email: sign_in_params[:email],
        password: sign_in_params[:password],
        trusted_device_token: token
      )

      unless result.success?
        event = result.user&.access_locked? ? :locked_out : :login_failed
        Authentication::AuditLog.record(event: event, user: result.user,
                                        customer_id: result.user&.customer_id, request: request)
        return render_failure
      end

      if result.user && !result.user.confirmed?
        session[:unconfirmed_email] = result.user.email
        return redirect_to new_user_session_path
      end

      # Mitigate session fixation: rotate the session id across the
      # privilege boundary so any pre-auth session contents are dropped.
      finish_sign_in(result, remember_me: remember_me?)
    end

    # DELETE /auth/sign_out
    def destroy
      user = current_user
      signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
      clear_mfa_verification!
      Authentication::AuditLog.record(event: :logout, user: user, request: request) if user

      set_flash_message!(:notice, :signed_out) if signed_out

      redirect_to new_user_session_path
    end

    protected

    def sign_in_params
      permitted_user_params(:email, :password, :remember_me)
    end

    def remember_me?
      ActiveModel::Type::Boolean.new.cast(sign_in_params[:remember_me])
    end

    private

    # Counts every attempt, not just failures, and registers it with #hit! so
    # the increment and the limit comparison are one atomic step. Checking
    # first and incrementing afterwards let N concurrent requests all read the
    # same under-limit count and all pass, so the effective cap scaled with
    # the attacker's concurrency.
    def throttle_sign_in!
      throttle = Authentication::Throttle.new(
        key:    "signin:#{request.remote_ip}",
        limit:  RATE_LIMIT_CAP,
        period: RATE_LIMIT_WINDOW
      )
      return unless throttle.hit!

      Authentication::AuditLog.record(event: :throttled, request: request, flow: "sign_in")
      head :too_many_requests
    end

    def render_failure
      self.resource = resource_class.new
      flash.now[:alert] = I18n.t("devise.failure.invalid", authentication_keys: "email")
      render :new, status: :unprocessable_entity
    end
  end
end
