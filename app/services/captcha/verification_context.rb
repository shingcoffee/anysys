# frozen_string_literal: true

require "digest"

module Captcha
  # Immutable request context passed into verification. Carries everything a
  # provider might need beyond the raw token: the submitter's IP (server-side
  # remoteip validation), user agent, the request hostname (hostname pinning for
  # score-based vendors), and the logical action being protected (e.g.
  # :page_submit, :sign_up) which drives the per-action fail policy.
  #
  # Score-based providers (reCAPTCHA v3, etc.) read remoteip/hostname/action;
  # Aliyun does not echo hostname/action; siteverify providers must bind them.
  class VerificationContext
    attr_reader :verify_param, :remoteip, :user_agent, :hostname, :action

    def initialize(verify_param:, remoteip: nil, user_agent: nil, hostname: nil, action: nil)
      @verify_param = verify_param.to_s
      @remoteip     = remoteip.presence
      @user_agent   = user_agent.presence
      @hostname     = hostname.presence
      @action       = action&.to_sym
    end

    def blank_token?
      verify_param.strip.empty?
    end

    # The only embedded widgets are on the interstitial. Match their actual
    # SDK conventions: Google executes "submit", Turnstile omits action.
    # Other flows use the logical action verbatim.
    def vendor_action(provider:)
      return nil if action.nil? || action == :connection_test
      return action.to_s unless action == :access_challenge

      provider == "google_recaptcha_v3" ? "submit" : ""
    end

    def matches_vendor_context?(response, provider:)
      return false if hostname.present? && response["hostname"] != hostname

      expected = vendor_action(provider: provider)
      return true if expected.nil?
      return response["action"].nil? || response["action"] == "" if expected.empty?

      response["action"] == expected
    end

    # Stable digest for the single-use ledger. Never store the raw token.
    def token_digest
      Digest::SHA256.hexdigest(verify_param)
    end
  end
end
