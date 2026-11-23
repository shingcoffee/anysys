# frozen_string_literal: true

module Authentication
  class MfaSessionsController < ApplicationController
    include Authentication::FinishesSignIn
    include Authentication::RequiresSignIn

    layout "auth"
    before_action :require_mfa_configured!

    def show
      redirect_to mfa_landing_path if mfa_session_verified?
    end

    def create
      return render_mfa_throttled if mfa_throttle.exceeded?

      if current_user.verify_otp(params[:otp_code])
        mfa_throttle.clear
        mark_mfa_verified!
        remember_trusted_device! if params[:trust_device].present?
        Authentication::AuditLog.record(event: :mfa_verified, user: current_user, request: request)
        redirect_to signed_in_destination(current_user),
                    notice: t("auth.flash.mfa.verified")
      else
        mfa_throttle.record_failure
        Authentication::AuditLog.record(event: :mfa_failed, user: current_user, request: request)
        flash.now[:alert] = t("auth.flash.mfa.invalid_code")
        render :show, status: :unprocessable_entity
      end
    end

    private

    # Throttle TOTP verification per user so a valid post-password session
    # cannot brute-force the 6-digit second factor. Shared-store backed.
    def mfa_throttle
      @mfa_throttle ||= Authentication::Throttle.mfa(current_user)
    end

    def render_mfa_throttled
      Authentication::AuditLog.record(event: :throttled, user: current_user, request: request, flow: "mfa")
      flash.now[:alert] = t("auth.flash.mfa.throttled")
      render :show, status: :too_many_requests
    end

    # /:cid/auth/mfa/session is only meaningful when the user has actually
    # set up TOTP. If MFA is not configured, route them to their home; if it
    # was disabled mid-session, fall back to the same destination.
    def require_mfa_configured!
      return if current_user.mfa_configured?

      redirect_to mfa_landing_path
    end

    def mfa_landing_path
      Authentication::LandingPath.for(current_user, customer_id: current_customer_id)
    end

    # Persist a trusted-device record and drop a signed cookie so the next
    # sign-in from this browser can skip the TOTP prompt for 30 days.
    # The cookie value is the raw opaque token; the server-side row stores
    # only its SHA-256 digest so a leaked DB row cannot forge a valid cookie.
    def remember_trusted_device!
      _record, raw = Authentication::TrustedDevice.issue!(
        user: current_user, ip: request.remote_ip, user_agent: request.user_agent
      )
      cookies.signed[:trusted_device] = {
        value:     raw,
        expires:   Authentication::TrustedDevice::DEFAULT_TTL.from_now,
        httponly:  true,
        secure:    request.ssl?,
        same_site: :lax
      }
    end
  end
end
