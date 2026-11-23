# frozen_string_literal: true

module Authentication
  # Handles disabling MFA for the current user. Setup and verification flows
  # live in MfaSetupsController and MfaSessionsController respectively.
  class MfasController < ApplicationController
    include Authentication::RequiresSignIn

    layout "auth"

    # Disabling 2FA is a security-sensitive action. Require the user to
    # re-prove possession of the second factor (or their current password)
    # for this single request — without re-auth, anyone holding a
    # captured/fixed session cookie could permanently downgrade the
    # account in one click.
    def destroy
      return render_mfa_throttled if mfa_throttle.exceeded?

      unless reauthenticated?
        mfa_throttle.record_failure
        redirect_to mfa_landing_path, alert: t("auth.flash.mfa.reauth_required")
        return
      end

      mfa_throttle.clear
      Authentication::MutationAudit.mfa(user: current_user, request: request,
                                        actor: current_user, source: "self_service") { current_user.disable_mfa! }
      clear_mfa_verification!
      redirect_to mfa_landing_path, notice: t("auth.flash.mfa.disabled")
    end

    private

    # Throttle re-auth attempts per user so the disable endpoint cannot be
    # brute-forced for the OTP/password. Shares the per-user MFA bucket with
    # the verify and enrol surfaces, so attempts cannot be spread across
    # endpoints to multiply the budget.
    def mfa_throttle
      @mfa_throttle ||= Authentication::Throttle.mfa(current_user)
    end

    def render_mfa_throttled
      Authentication::AuditLog.record(event: :throttled, user: current_user, request: request, flow: "mfa")
      redirect_to mfa_landing_path, alert: t("auth.flash.mfa.throttled")
    end

    def mfa_landing_path
      Authentication::LandingPath.for(current_user, customer_id: current_customer_id)
    end

    # Password re-auth goes through PasswordVerification, not
    # `valid_password?`. The bare digest check bypasses Devise's
    # `valid_for_authentication?` hook, which is what owns Lockable's
    # persisted counters — so password guesses here incremented nothing, the
    # account never locked, and an already-locked account's password still
    # worked to permanently strip its second factor. The local MFA throttle
    # capped the rate but left the endpoint a lockout-free password oracle.
    def reauthenticated?
      return false unless reauth_factor_verified?

      # A successful re-auth breaks the failed-password streak, exactly as a
      # successful sign-in does. Without this the counter only ever climbed:
      # someone who mistyped their password once and then re-authenticated
      # carried that attempt forward for the life of the record, so unrelated
      # later mistakes accumulated toward a lockout they had already cleared.
      current_user.reset_failed_attempts!
      true
    end

    # Either factor is sufficient on its own — the point is to prove the
    # request came from the account holder and not merely from a captured
    # session cookie. A locked account never reaches here: Devise's activatable
    # hook chains through Lockable's `active_for_authentication?` and bounces it
    # to sign-in before the action runs.
    def reauth_factor_verified?
      otp      = params[:otp_code].to_s.strip
      password = params[:current_password].to_s

      return true if otp.present? && current_user.verify_otp(otp)

      password.present? &&
        Authentication::PasswordVerification.call(user: current_user, password: password)
    end
  end
end
