# frozen_string_literal: true

module Authentication
  # Single source of truth for "which surface does this user belong on?".
  #
  # The answer is needed in six unrelated places — after sign-in, after MFA
  # verification, after MFA setup, after MFA disable, after an account update,
  # and when an authorization check denies a request — and it was previously
  # copy-pasted into each of them. Two of those copies had already drifted:
  # one hard-coded "/#{cid}/member" instead of the named route, and the
  # authorization-denied path pointed at "/#{cid}", which has no route at all
  # and therefore rendered a routing error instead of a usable page.
  #
  # Per AGENTS.md there are exactly two authenticated surfaces: `/:cid/member`
  # for members and `/:cid/admin` for admin/owner. Anonymous callers get the
  # sign-in form.
  class LandingPath
    include Rails.application.routes.url_helpers

    # @param user [Authentication::User, nil]
    # @param customer_id [Integer, String, nil] the tenant whose surface to
    #   land on. Defaults to the user's own tenant; callers pass the URL tenant
    #   so a platform owner acting inside another customer stays there.
    # @return [String] a path, never nil
    def self.for(user, customer_id: nil)
      new(user, customer_id: customer_id).call
    end

    def initialize(user, customer_id: nil)
      @user = user
      @customer_id = customer_id
    end

    def call
      return new_user_session_path unless user
      return new_user_session_path if customer_id.blank?

      member_surface? ? member_dashboard_path(customer_id) : admin_assistant_path(customer_id)
    end

    private

    attr_reader :user

    def customer_id
      @customer_id.presence || user&.customer_id
    end

    # Defer to the model's own precedence rule rather than re-deriving it. It
    # resolves owner > admin > member, so a user holding both `admin` and
    # `member` lands on the admin surface (the superset), and — importantly —
    # it falls back to "member" for a user carrying no role row at all. Sending
    # a role-less user to the admin surface would only get them denied again.
    def member_surface?
      user.respond_to?(:primary_role_key) && user.primary_role_key == "member"
    end
  end
end
