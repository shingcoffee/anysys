# frozen_string_literal: true

module Authentication
  # Shared session establishment after a successful first factor (password).
  # Callers must invoke SignInFlow first and pass the Result. Reads the
  # trusted-device cookie before reset_session.
  module FinishesSignIn
    extend ActiveSupport::Concern
    include Authentication::SafeReturnPath

    private

    def finish_sign_in(result, remember_me:)
      # Both the flash and Devise's stored location live in the session, so
      # reset_session drops them. Carry both across the rotation: OAuth
      # authorize (and any other pre-auth return-to) needs the location, and a
      # notice set before sign-in (e.g. "your email address has been
      # confirmed") has to reach the page we are about to redirect to.
      return_to = peek_return_to
      pending_flash = flash
      reset_session
      request.flash = pending_flash
      restore_return_to(return_to)
      result.user.remember_me = remember_me
      sign_in(:user, result.user)
      mark_mfa_verified!(result.user, verified: result.mfa_verified)
      Authentication::AuditLog.record(event: :login_succeeded, user: result.user, request: request,
                                      mfa_pending: !result.mfa_verified)

      customer_id = result.user.customer_id
      case result.next_action
      when :mfa_required       then redirect_to mfa_session_path(customer_id)
      when :mfa_setup_required then redirect_to mfa_setup_path(customer_id)
      else                          redirect_to after_sign_in_path_for(result.user)
      end
    end

    # Completes a pending person claim only after the session is fully
    # established (no MFA step still pending). Consume the claim first so a
    # stored return-to cannot skip it; then prefer that stored path so a
    # continuation recorded from someone else's email cannot hijack an
    # OAuth authorize (or any other safe return).
    def signed_in_destination(user)
      continuation = People::Claim.complete!(user)
      stored = stored_location_for(:user)
      safe_return_path_for(user, stored) || continuation || default_signed_in_path_for(user)
    end

    def after_sign_in_path_for(resource)
      signed_in_destination(resource)
    end

    # Where a signed-in user belongs when there is no stored location. Also
    # used to bounce an already-signed-in visitor away from the sign-in
    # surfaces. See Authentication::LandingPath for the rule.
    def default_signed_in_path_for(user)
      Authentication::LandingPath.for(user)
    end
  end
end
