# frozen_string_literal: true

module Oauth
  # Decides who may complete `/oauth/authorize`. Pure: it takes the candidate
  # user and whether the session already cleared MFA, and answers with the
  # user plus a `next_action` symbol. Turning that symbol into a URL is the
  # controller's job (Oauth::AuthorizationsController#resource_owner_redirect_path),
  # which keeps routing out of the service and the service testable without a
  # controller double.
  class AuthenticateResourceOwner
    # next_action is one of:
    #   :sign_in    — no usable session; send the visitor to Devise
    #   :mfa_verify — enrollment is enforced and this session has not verified
    #   :mfa_setup  — enrollment was started but never finished
    #   :authorized — `user` may be handed to Doorkeeper as the resource owner
    Result = Struct.new(:user, :next_action, keyword_init: true) do
      def authorized?
        next_action == :authorized
      end
    end

    def self.call(user:, mfa_verified:)
      new(user: user, mfa_verified: mfa_verified).call
    end

    def initialize(user:, mfa_verified:)
      @user = user
      @mfa_verified = mfa_verified
    end

    def call
      return sign_in_result unless @user&.active?
      return sign_in_result unless authentication_enabled?

      pending = pending_mfa_action
      return Result.new(user: @user, next_action: pending) if pending

      Result.new(user: @user, next_action: :authorized)
    end

    private

    def sign_in_result
      Result.new(user: nil, next_action: :sign_in)
    end

    def authentication_enabled?
      FeatureModules::Module.enabled?(key: "authentication", customer_id: @user.customer_id)
    end

    # /oauth/authorize is exempt from the global MFA gate (it is the surface
    # that has to stay reachable while the gate redirects), so it re-asks the
    # same question here. Both ask Authentication::MfaObligation, which is why
    # the OAuth flow cannot be used to side-step an outstanding second factor.
    def pending_mfa_action
      case Authentication::MfaObligation.for(user: @user, verified: @mfa_verified)
      when Authentication::MfaObligation::VERIFY then :mfa_verify
      when Authentication::MfaObligation::ENROLL then :mfa_setup
      end
    end
  end
end
