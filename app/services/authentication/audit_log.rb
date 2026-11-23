# frozen_string_literal: true

module Authentication
  # Thin, decoupled writer for auth audit events. Callers emit an event; the
  # `authentication.event` notification is persisted + logged by
  # Authentication::Instrumentation, so controllers never touch the ledger
  # directly and a logging failure never breaks an auth flow.
  class AuditLog
    def self.record(event:, user: nil, customer_id: nil, request: nil, defer_logging: false, **metadata)
      options = defer_logging ? { defer_logging: true } : {}
      ActiveSupport::Notifications.instrument(
        "authentication.event",
        event:       event.to_s,
        user_id:     user&.id,
        customer_id: customer_id || user&.customer_id,
        ip:          request&.remote_ip,
        user_agent:  request&.user_agent&.to_s&.slice(0, 500),
        metadata:    metadata,
        **options
      )
    end
  end
end
