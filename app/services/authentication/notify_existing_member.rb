# frozen_string_literal: true

module Authentication
  # What a sign-up does for an address that already has an account, while
  # the visitor sees the same "check your email" answer as a new sign-up:
  # a confirmed active member of this tenant gets a sign-in link, counted
  # against the sign-in link page's per-address flood bucket; anyone else
  # (unconfirmed, admin, owner, another tenant) gets nothing.
  #
  # Returns true when a link was issued.
  class NotifyExistingMember
    # The sign-in link page is unscoped, so its bucket uses the "global" key.
    FLOOD_FLOW = "sign_in_link"
    FLOOD_TENANT_KEY = "global"

    def self.call(user:, customer_id:)
      return false unless member_of?(user, customer_id)
      return false if flooded?(user.email)

      IssueSignInLink.call(email: user.email)
      true
    end

    def self.member_of?(user, customer_id)
      user.present? && user.active? && user.confirmed? && user.member? &&
        user.customer_id.to_s == customer_id.to_s
    end

    def self.flooded?(email)
      EmailFloodThrottled.email_throttle(FLOOD_FLOW, email, tenant_key: FLOOD_TENANT_KEY).hit!
    end
    private_class_method :flooded?
  end
end
