# frozen_string_literal: true

module Authentication
  # Enumeration-safe: callers always show the same check-email page.
  # Confirmed active users get a one-time link. Unconfirmed users get a
  # confirmation resend. Everyone else is a no-op.
  #
  # Two properties this class has to hold onto:
  #
  # * The email lookup is the shared Authentication::User.find_by_normalized_email
  #   so a missing address walks the same code path as a present one.
  # * The sign-in link is enqueued, never delivered inline. Blocking the
  #   request thread on SMTP would make "registered" measurably slower than
  #   "not registered" — a timing oracle that defeats the identical
  #   check-email page — and would hand an unauthenticated endpoint the
  #   availability of the mail relay.
  class IssueSignInLink
    TOKEN_TTL = 15.minutes

    def self.call(...)
      new(...).call
    end

    def initialize(email:)
      @email = email
    end

    def call
      user = User.find_by_normalized_email(@email)
      return unless user
      return unless user.active?
      return unless FeatureModules::Module.enabled?(key: "authentication", customer_id: user.customer_id)

      user.confirmed? ? deliver_sign_in_link(user) : resend_confirmation
    end

    private

    # The class-level entry point applies the auth-module and tenant sign-up
    # resend gates; the instance method Devise ships does not. Going through
    # the class method keeps this endpoint from mailing confirmations for a
    # tenant that has sign-up switched off.
    def resend_confirmation
      User.send_confirmation_instructions(email: @email)
    end

    def deliver_sign_in_link(user)
      raw = nil
      user.with_lock do
        # The email lookup may have raced an identity change. Never mint a new
        # link for the old address after that change revoked its old links.
        next unless user.email == @email.to_s.strip.downcase && user.active? && user.confirmed?
        next unless FeatureModules::Module.enabled?(key: "authentication", customer_id: user.customer_id)

        raw, hashed = Devise.token_generator.generate(User, :sign_in_token)
        user.update_columns(sign_in_token: hashed, sign_in_token_sent_at: Time.current)
      end
      return unless raw

      SignInLinkMailer.sign_in_link(user, raw).deliver_later
    end
  end
end
