# frozen_string_literal: true

module Authentication
  class CustomerRegistrationsController < ApplicationController
    include Authentication::EmailFloodThrottled
    include Authentication::NoStore
    include Authentication::PermitsUserParams
    include Authentication::TrustedDeviceCookieable
    include Authentication::FinishesSignIn

    layout "auth"

    before_action :redirect_signed_in_user
    before_action :throttle_customer_signup!, only: %i[create resend]
    before_action :ensure_customer_signup_enabled, only: %i[create resend confirm]
    # #confirm is addressed by the signup token, so every response it renders
    # carries the token in the URL.
    before_action :no_store!, only: :confirm

    def new
      @user = User.new
      render_disabled and return unless PlatformSettings.customer_signup_enabled?
    end

    def create
      email = CustomerSignupToken.normalize(sign_up_params[:email])
      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        @user = User.new(email: sign_up_params[:email])
        @user.errors.add(:email, :invalid)
        render :new, status: :unprocessable_entity
        return
      end

      IssueCustomerSignup.call(email: email)
      session[:customer_signup_email] = email
      redirect_to customer_registration_check_email_path
    end

    def resend
      email = session[:customer_signup_email].to_s
      redirect_to(new_customer_registration_path) and return if email.blank?

      IssueCustomerSignup.call(email: email)
      redirect_to customer_registration_check_email_path
    end

    def check_email
      @email = session[:customer_signup_email].to_s
      redirect_to(new_customer_registration_path) and return if @email.blank?
    end

    def confirm
      return head(:ok) if request.head?

      email = CustomerSignupToken.verify(params[:token])
      return render(:expired, status: :unprocessable_entity) if email.blank?

      existing = User.find_by_normalized_email(email)

      # Single use. The token is a stateless encrypted message with a 3-day
      # TTL and nothing is recorded when it is spent, so without this check a
      # replay of an already-confirmed address signs the holder straight back
      # in — making the welcome email a password-equivalent bearer credential
      # for 72 hours, with no way to revoke it. Tenant sign-ups land in shared
      # mailboxes (info@, admin@, billing@), get forwarded, and sit in proxy
      # logs. Registration is already complete here, so send them through the
      # normal sign-in gate instead.
      return redirect_as_already_registered if existing&.confirmed?

      # Each branch either yields the user to sign in or renders its own
      # response and returns nil.
      user = existing ? confirm_existing(existing) : register_new_tenant(email)
      return if user.nil?

      result = SignInFlow.complete(user: user, trusted_device_token: trusted_device_token)
      return redirect_to(new_user_session_path) unless result.success?

      finish_sign_in(result, remember_me: false)
    end

    private

    def redirect_as_already_registered
      redirect_to new_user_session_path,
                  notice: t("auth.flash.customer_signup.already_confirmed")
    end

    # Devise returns false when the confirmation period has lapsed, which would
    # otherwise leave confirmed_at nil and hand an unconfirmed user to
    # SignInFlow.
    def confirm_existing(user)
      return user if user.confirm

      render :expired, status: :unprocessable_entity
      nil
    end

    def register_new_tenant(email)
      result = CustomerSignup.call(email: email)
      return result.user if result.success?

      # A concurrent confirm of the same link may have won the race and
      # committed the account between our lookup and our insert. Registration
      # did succeed, just not in this request, so send them to sign-in rather
      # than showing a signup form for an address that now exists.
      if User.find_by_normalized_email(email)&.confirmed?
        redirect_as_already_registered
      else
        @user = result.user || User.new(email: email)
        render :new, status: :unprocessable_entity
      end

      nil
    end

    # Tolerates a missing :user key rather than raising ParameterMissing (a
    # 400 on a malformed POST is a different, informative response for an
    # unauthenticated endpoint that is otherwise deliberately uniform).
    def sign_up_params
      permitted_user_params(:email)
    end

    def throttle_customer_signup!
      email = action_name == "resend" ? session[:customer_signup_email] : sign_up_params[:email]
      throttle_email_flood!(
        flow:          "customer_signup",
        email:         email,
        redirect_path: new_customer_registration_path,
        alert:         t("auth.flash.customer_signup.throttled")
      )
    end

    def redirect_signed_in_user
      return unless user_signed_in?

      redirect_to default_signed_in_path_for(current_user)
    end

    def ensure_customer_signup_enabled
      return if PlatformSettings.customer_signup_enabled?

      @user = User.new
      render_disabled
    end

    def render_disabled
      render :disabled, status: :ok
    end
  end
end
