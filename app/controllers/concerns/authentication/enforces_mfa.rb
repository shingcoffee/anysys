# frozen_string_literal: true

module Authentication
  # The single MFA gate for the whole application.
  #
  # Runs last in ApplicationController's base filter chain, after
  # RouteAuthorization has authenticated and authorized the request, so
  # `current_user` is settled by the time the obligation is evaluated.
  # Authentication::MfaObligation owns the decision; this concern owns only
  # the exemptions and the redirect.
  module EnforcesMfa
    extend ActiveSupport::Concern
    include Authentication::MfaSessionVerification

    included do
      before_action :enforce_mfa!
    end

    # Reachable while a *verification* is outstanding. The verification
    # endpoint and sign-out must be here or the user is stuck in a redirect
    # loop; mfa_recoveries is the escape hatch for a lost authenticator.
    CHALLENGE_EXEMPT_CONTROLLERS = %w[
      authentication/sessions
      authentication/customer_registrations
      authentication/mfa_sessions
      authentication/mfa_recoveries
      locales
      oauth/authorizations
    ].freeze

    # Reachable while an *enrolment* is outstanding — the above plus the
    # enrolment surfaces themselves and the disable endpoint, which is how a
    # user backs out of a half-started enrolment.
    ENROLLMENT_EXEMPT_CONTROLLERS = (CHALLENGE_EXEMPT_CONTROLLERS + %w[
      authentication/mfa_setups
      authentication/mfas
      member/mfa
    ]).freeze

    private

    def enforce_mfa!
      return unless user_signed_in?

      case Authentication::MfaObligation.for(user: current_user, verified: mfa_session_verified?)
      when Authentication::MfaObligation::VERIFY
        return if CHALLENGE_EXEMPT_CONTROLLERS.include?(controller_path)

        redirect_to mfa_session_path(mfa_gate_customer_id)
      when Authentication::MfaObligation::ENROLL
        return if ENROLLMENT_EXEMPT_CONTROLLERS.include?(controller_path)

        redirect_to mfa_setup_path(mfa_gate_customer_id)
      end
    end

    # A platform owner acting inside another tenant satisfies MFA on the URL's
    # tenant; everyone else only ever sees their own.
    def mfa_gate_customer_id
      current_customer_id || current_user.customer_id
    end
  end
end
