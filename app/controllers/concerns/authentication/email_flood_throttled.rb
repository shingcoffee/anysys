# frozen_string_literal: true

module Authentication
  # EmailFloodThrottled
  #
  # Dual-bucket rate limiter for unauthenticated endpoints that dispatch email
  # (password reset, confirmation resend, MFA-recovery link, sign-in link). Without it an
  # attacker can flood a victim's inbox and burn the tenant's sender reputation
  # / mail quota by POSTing the same address repeatedly.
  #
  # Two independent buckets — both must pass:
  #   * per (flow, tenant, IP)    — caps a single origin
  #   * per (flow, tenant, email) — caps a fixed recipient across rotating IPs
  #
  # The tenant segment is `current_customer_id`, which is nil on the unscoped
  # /auth/* endpoints (they carry no :customer_id and run before sign-in), so
  # those buckets collapse to the shared "global" tenant. That is deliberate,
  # not an oversight: pre-auth we cannot resolve a tenant without first
  # revealing whether the address exists, and a shared bucket is the stricter
  # of the two options. Only the tenant-scoped flows (e.g. MFA recovery under
  # /:cid/) actually isolate per customer.
  #
  # The counter is incremented on every attempt, before the work runs and
  # regardless of whether it found anything to do — counting successes would
  # give an attacker unlimited attempts against addresses that don't exist,
  # which is exactly the traffic this limiter is here to cap.
  #
  # Enumeration-safe: the throttle response is identical whether the limit was
  # hit by IP or email and whether the address is registered — it only reveals
  # that the endpoint is rate-limited, never which account exists. The email is
  # SHA-256'd so plaintext PII never lands in the shared cache key.
  #
  # Usage (in a `before_action`, halts the chain by redirecting on breach):
  #   throttle_email_flood!(flow: "confirmation",
  #                         email: params.dig(:user, :email),
  #                         redirect_path: new_user_session_path,
  #                         alert: t("auth.flash.confirmation.throttled"))
  module EmailFloodThrottled
    extend ActiveSupport::Concern

    DEFAULT_LIMIT  = 5
    DEFAULT_PERIOD = 15.minutes

    # The per-recipient bucket, shared with callers outside a controller (the
    # register_member step) so every path that mails one address counts once.
    def self.email_throttle(flow, email, tenant_key:, limit: DEFAULT_LIMIT, period: DEFAULT_PERIOD)
      normalized = email.to_s.strip.downcase
      return nil if normalized.blank?

      Authentication::Throttle.new(
        key: "flood:#{flow}_email:#{tenant_key}:#{Digest::SHA256.hexdigest(normalized)}",
        limit: limit, period: period
      )
    end

    private

    def throttle_email_flood!(flow:, email:, redirect_path:, alert:,
                              limit: DEFAULT_LIMIT, period: DEFAULT_PERIOD)
      ip_throttle    = build_flood_throttle("#{flow}:#{flood_tenant_key}:#{request.remote_ip}", limit, period)
      email_throttle = flood_email_throttle(flow, email, limit, period)

      # Register the attempt against both buckets with #hit!, which increments
      # and compares atomically. Reading first and incrementing afterwards let
      # concurrent requests all observe the same under-limit count and all
      # pass, so the effective cap scaled with the attacker's concurrency.
      # Assign both before testing — `||` would short-circuit and stop
      # counting the email bucket once the IP bucket trips.
      ip_exceeded    = ip_throttle.hit!
      email_exceeded = email_throttle&.hit!

      return true unless ip_exceeded || email_exceeded

      record_flood_throttled(flow, email)
      redirect_to redirect_path, alert: alert
      false
    end

    # Attribute the event to the *recipient's* tenant when the address resolves,
    # falling back to the URL's tenant. The /auth/* flows carry no :customer_id,
    # so `current_customer_id` alone parked every pre-auth throttle on a nil
    # tenant where the affected customer's admins could never see it — and an
    # inbox flood aimed at one tenant's user is precisely what that tenant needs
    # in its audit log. Safe for enumeration: the response is byte-identical
    # either way, so nothing about the lookup reaches the requester.
    def record_flood_throttled(flow, email)
      user = Authentication::User.find_by_normalized_email(email)

      Authentication::AuditLog.record(
        event:       :throttled,
        user:        user,
        customer_id: user&.customer_id || current_customer_id,
        request:     request,
        flow:        flow
      )
    end

    def build_flood_throttle(key, limit, period)
      Authentication::Throttle.new(key: "flood:#{key}", limit: limit, period: period)
    end

    def flood_tenant_key
      current_customer_id.presence || "global"
    end

    def flood_email_throttle(flow, email, limit, period)
      EmailFloodThrottled.email_throttle(flow, email, tenant_key: flood_tenant_key, limit: limit, period: period)
    end
  end
end
