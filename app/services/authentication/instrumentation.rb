# frozen_string_literal: true

module Authentication
  # Persists `authentication.event` notifications into the audit ledger and emits
  # a structured log line. Decoupled from controllers; a persist failure is
  # swallowed (logging must never break authentication).
  class Instrumentation
    WARN_EVENTS = %w[login_failed locked_out mfa_failed throttled].freeze

    def self.subscribe!
      ActiveSupport::Notifications.subscribe("authentication.event") do |*args|
        new.handle(ActiveSupport::Notifications::Event.new(*args))
      end
    end

    def handle(event)
      persist(event.payload)
      if event.payload[:defer_logging]
        ActiveRecord.after_all_transactions_commit { log(event.payload) }
      else
        log(event.payload)
      end
    end

    def persist(p)
      Authentication::Event.create!(
        event:       p[:event],
        user_id:     p[:user_id],
        customer_id: p[:customer_id],
        ip:          p[:ip],
        user_agent:  p[:user_agent],
        metadata:    p[:metadata] || {}
      )
    rescue StandardError => e
      # Audit logging must NEVER break an auth flow — swallow any persistence
      # error (AR, serialization, etc.), not just ActiveRecordError.
      Rails.logger.warn("[auth.audit] persist failed for #{p[:event]}: #{e.class}: #{e.message}")
    end

    def log(p)
      message = "[auth] #{p[:event]} user=#{p[:user_id] || '-'} customer=#{p[:customer_id] || '-'} ip=#{p[:ip] || '-'}"
      WARN_EVENTS.include?(p[:event].to_s) ? Rails.logger.warn(message) : Rails.logger.info(message)
    rescue StandardError
      # Emitting the structured log line must NEVER break an auth flow.
      # ActiveSupport::Notifications reraises subscriber exceptions synchronously,
      # so a logger IO error here would otherwise bubble up into login/MFA/
      # password flows. There is nowhere reliable left to report it (the logger
      # itself is the failing component), so swallow rather than re-enter it.
      nil
    end
  end
end
