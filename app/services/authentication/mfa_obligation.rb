# frozen_string_literal: true

module Authentication
  # What, if anything, does this session still owe before it may reach a
  # protected surface? Pure decision logic — no session, no request, no
  # routing — so the rule can be unit-tested and, more importantly, so there
  # is exactly one copy of it.
  #
  # It previously existed three times: ApplicationController#enforce_mfa!,
  # FeatureModules::Authentication::Registration.enforce_mfa!, and
  # Oauth::AuthenticateResourceOwner#pending_mfa_action. The three had already
  # drifted apart in both their exemption sets and their handling of the
  # session flag, which is the failure mode this collapses.
  class MfaObligation
    # Nothing outstanding — the request may proceed.
    NONE = :none
    # Enrolled and enforced, but this session has not presented a code yet.
    VERIFY = :verify
    # Enrolment must be started or finished before anything else.
    ENROLL = :enroll

    # @param user [Authentication::User, nil]
    # @param verified [Boolean] whether this session has already cleared the
    #   second factor *for the user's current secret*. Callers must bind the
    #   flag to the secret (see Authentication::MfaSessionVerification);
    #   a bare "true" from an older session is exactly the bypass below.
    # @return [Symbol] NONE, VERIFY, or ENROLL
    def self.for(user:, verified:)
      new(user: user, verified: verified).call
    end

    def initialize(user:, verified:)
      @user = user
      @verified = verified
    end

    def call
      return NONE unless user.respond_to?(:mfa_required?)

      return verified ? NONE : VERIFY if user.mfa_required?

      # An enrolment obligation is NOT satisfiable by a session flag — only by
      # actually enrolling. Honouring `verified` here was a real bypass: a
      # session established before the tenant switched MFA on (or before an
      # admin reset the user's secret) carried `verified = true` for its whole
      # life, and the gate short-circuited on it, so the mandate never applied
      # to anyone already signed in.
      return ENROLL if user.mfa_configured?
      return ENROLL if tenant_enforced?

      NONE
    end

    private

    attr_reader :user, :verified

    # Tenant-wide MFA binds admins and owners. Members are always opt-in and
    # manage their own second factor under /:cid/member/security/mfa.
    def tenant_enforced?
      return false if user.member? && !user.admin_or_owner?

      Authentication::Settings.for(user.customer_id).mfa_enabled?
    end
  end
end
