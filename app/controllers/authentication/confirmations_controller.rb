# frozen_string_literal: true

module Authentication
  class ConfirmationsController < Devise::ConfirmationsController
    include TenantContext
    include Authentication::EmailFloodThrottled
    include Authentication::PermitsUserParams
    include Authentication::TrustedDeviceCookieable
    include Authentication::FinishesSignIn
    include Authentication::NoStore

    layout "auth"

    before_action :throttle_confirmation_requests!, only: :create
    # #show is addressed by the confirmation token — same reasoning as
    # SignInLinksController#show.
    before_action :no_store!, only: :show
    # Consuming someone else's confirmation link would otherwise silently swap
    # an authenticated session to that account, letting an attacker who mails
    # their own link get a victim to work inside the attacker's tenant. The
    # sign-in-link and customer-signup confirm actions already guard this;
    # confirmation did not. With reconfirmable off, email confirmation only
    # ever happens at sign-up, so nobody legitimately needs it while signed in.
    before_action :redirect_signed_in_user, only: :show

    # Devise's stock confirmation/new template calls new_user_registration_path,
    # which requires a tenant :customer_id this public /auth/confirmation URL
    # does not have. Resend lives on the sign-in unconfirmed banner instead.
    def new
      redirect_to new_user_session_path
    end

    # GET /auth/confirmation?confirmation_token=…
    #
    # HEAD is answered without consuming the token. Mail clients and link
    # scanners probe confirmation URLs the same way they probe sign-in links.
    def show
      return head(:ok) if request.head?

      self.resource = resource_class.confirm_by_token(params[:confirmation_token])
      if resource.errors.empty?
        set_flash_message!(:notice, :confirmed)
        result = SignInFlow.complete(user: resource, trusted_device_token: trusted_device_token)
        if result.success?
          finish_sign_in(result, remember_me: false)
        else
          redirect_to after_confirmation_path_for(resource_name, resource)
        end
      else
        redirect_to new_user_session_path, alert: t("auth.flash.confirmation.invalid")
      end
    end

    protected

    def after_confirmation_path_for(_resource_name, _resource)
      new_user_session_path
    end

    def after_resending_confirmation_instructions_path_for(_resource_name)
      if session[:customer_signup_email].present?
        customer_registration_check_email_path
      else
        new_user_session_path
      end
    end

    # Tolerates a missing :user key rather than raising ParameterMissing (a
    # 400 on a malformed POST is a different, informative response for an
    # unauthenticated endpoint that is otherwise deliberately uniform). A
    # blank email then takes the same no-match path as an unknown address.
    def resource_params
      permitted_user_params(:email)
    end

    private

    def redirect_signed_in_user
      return unless user_signed_in?

      redirect_to default_signed_in_path_for(current_user)
    end

    def throttle_confirmation_requests!
      throttle_email_flood!(
        flow:          "confirmation",
        email:         resource_params[:email],
        redirect_path: after_resending_confirmation_instructions_path_for(resource_name),
        alert:         t("auth.flash.confirmation.throttled")
      )
    end
  end
end
