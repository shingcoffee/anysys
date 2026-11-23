# frozen_string_literal: true

module Member
  # Member-facing MFA controller. Operates strictly on `current_user`; never
  # accepts a target user_id parameter, which removes a class of cross-user
  # vulnerabilities at the controller layer. Authorization is delegated to
  # Member::BaseController (URL gate enforces `member?`, tenant gate
  # enforces same-customer access).
  class MfaController < BaseController
    include Authentication::MfaEnrollment

    before_action :no_store!, only: :setup
    before_action :redirect_if_mfa_already_required!, only: :setup

    def setup
      request.post? ? enable_mfa : render_enrollment
    end

    def destroy
      result = Authentication::MutationAudit.mfa(user: current_user, request: request,
                                                actor: current_user, source: "self_service") do
        Member::Mfa::Operation::Disable.call(user: current_user, code: params[:code])
      end

      if result.success?
        redirect_to security_path, notice: t("member.security.mfa.disabled")
      else
        redirect_to security_path, alert: mfa_otp_failure_alert(result)
      end
    end

    private

    def render_enrollment(status: :ok)
      return head :no_content if prefetch_request? && current_user.otp_secret.blank?

      ensure_otp_secret!
      @qr_code = enrollment_qr_code
      render :setup, status: status
    end

    def enable_mfa
      result = Authentication::MutationAudit.mfa(user: current_user, request: request,
                                                actor: current_user, source: "self_service") do
        Member::Mfa::Operation::Enable.call(user: current_user, code: params[:code])
      end

      unless result.success?
        flash.now[:alert] = mfa_otp_failure_alert(result)
        return render_enrollment(status: :unprocessable_entity)
      end

      mark_mfa_verified!
      redirect_to security_path, notice: t("member.security.mfa.enabled")
    end

    def security_path
      member_security_path(current_user.customer_id)
    end

    def redirect_if_mfa_already_required!
      return unless current_user&.mfa_required?

      redirect_to security_path, notice: t("member.security.mfa.already_enabled")
    end

    def mfa_otp_failure_alert(result)
      messages = case result.errors
      when Hash then result.errors.values.flatten
      else Array(result.errors).flatten
      end

      if messages.include?(Member::Mfa::Operation::Enable::THROTTLED)
        t("member.security.mfa.throttled")
      else
        t("member.security.mfa.invalid_code")
      end
    end
  end
end
