# frozen_string_literal: true

require "time"

module Email
  module Cron
    # Recovers overdue orphan queues through the shared enqueue guard, and
    # dead-letters exhausted delivery attempts. Due/claim timestamps, rather than
    # creation alone, start the grace window. Runs cross-tenant (credentials are platform-global
    # and the message row carries everything needed; Emails::Message has no
    # default tenant scope). Delivery/bounce/complaint transitions for webhook
    # providers arrive via Emails::WebhooksController, not here.
    class ReconcileMessages
      DEAD_LETTER_AFTER = 1.hour

      def self.call(now: Time.current)
        Emails::Message.where(status: "queued")
                       .where(created_at: ..(now - DEAD_LETTER_AFTER))
                       .find_each do |message|
          next unless FeatureModules::Module.enabled?(key: "email", customer_id: message.customer_id)

          message.with_lock do
            next unless message.status == "queued"
            next if message.delivery_claim_token.present? && message.delivery_claimed_at &&
                    message.delivery_claimed_at > now - Emails::DeliveryDispatch::CLAIM_TTL

            metadata = message.metadata || {}
            due_at = message.delivery_due_at || timestamp(metadata["scheduled_at"])
            next if message.delivery_due_at.nil? && metadata["scheduled_at"].present? && due_at.nil?
            next if due_at && due_at > now

            dispatched_at = message.delivery_claimed_at || timestamp(metadata["dispatched_at"])
            next if [message.created_at, due_at, dispatched_at].compact.max > now - DEAD_LETTER_AFTER

            if Emails::DeliveryDispatch.blocked?(message)
              message.mark_suppressed!
            elsif message.delivery_attempts >= Emails::DeliveryDispatch::MAX_ATTEMPTS
              message.mark_failed!(code: "UNDELIVERED", message: I18n.t("admin_modules.emails.send_activities.dead_letter.stuck_reason"))
            else
              Emails::DeliveryHandoff.call(message, mode: metadata["credential_mode"] || metadata["mode"], now: now)
            end
          end
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.warn("[email] dead-letter failed message=#{message.id}: #{e.message}")
        end
      end

      def self.timestamp(value)
        Time.iso8601(value) if value.is_a?(String) && value.present?
      rescue ArgumentError
        nil
      end
      private_class_method :timestamp
    end
  end
end
