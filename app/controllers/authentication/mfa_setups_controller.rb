# frozen_string_literal: true

module Authentication
  class MfaSetupsController < ApplicationController
    include Authentication::FinishesSignIn
    include Authentication::MfaEnrollment
    include Authentication::RequiresSignIn

    layout "auth"
    # Once 2FA is enforced the provisioning secret must not be shown again.
    # The user menu still links here; a stolen post-MFA session would
    # otherwise dump the TOTP key in HTML (QR + manual-entry string).
    before_action :redirect_if_mfa_already_required!
    before_action :no_store!

    def show
      return head :no_content if prefetch_request? && current_user.otp_secret.blank?

      ensure_otp_secret!
      @qr_code = enrollment_qr_code
    end

    def create
      return render_mfa_throttled if mfa_throttle.exceeded?

      if current_user.verify_otp(params[:otp_code])
        mfa_throttle.clear
        Authentication::MutationAudit.mfa(user: current_user, request: request,
                                          actor: current_user, source: "self_service") { current_user.enable_mfa! }
        mark_mfa_verified!
        redirect_to signed_in_destination(current_user),
                    notice: t("auth.flash.mfa.enabled")
      else
        mfa_throttle.record_failure
        @qr_code = enrollment_qr_code
        flash.now[:alert] = t("auth.flash.mfa.invalid_code")
        render :show, status: :unprocessable_entity
      end
    end

    private

    def mfa_landing_path
      Authentication::LandingPath.for(current_user, customer_id: current_customer_id)
    end

    def mfa_throttle
      @mfa_throttle ||= Authentication::Throttle.mfa(current_user)
    end

    def render_mfa_throttled
      Authentication::AuditLog.record(event: :throttled, user: current_user, request: request, flow: "mfa")
      @qr_code = enrollment_qr_code
      flash.now[:alert] = t("auth.flash.mfa.throttled")
      render :show, status: :too_many_requests
    end

    def redirect_if_mfa_already_required!
      return unless current_user&.mfa_required?

      redirect_to mfa_landing_path, notice: t("auth.flash.mfa.already_enabled")
    end
  end
end
