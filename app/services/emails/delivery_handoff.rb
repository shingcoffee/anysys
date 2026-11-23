# frozen_string_literal: true

module Emails
  # Enqueue is a best-effort accelerator; the queued ledger is the durable
  # outbox. Stamp before enqueue so a crash on either side is recoverable.
  class DeliveryHandoff
    RECOVERY_AFTER = 5.minutes

    def self.call(message, mode: nil, now: Time.current)
      scope = Message.where(id: message.id, status: "queued")
                     .where("delivery_enqueued_at IS NULL OR delivery_enqueued_at <= ?", now - RECOVERY_AFTER)
      return false unless scope.update_all(delivery_enqueued_at: now) == 1

      due = message.delivery_due_at || message.created_at
      job = if due && due > now
              DeliverMessageJob.set(wait_until: due).perform_later(message.id, mode)
            else
              DeliverMessageJob.perform_later(message.id, mode)
            end
      raise ActiveJob::EnqueueError, "email delivery enqueue rejected" unless job

      true
    rescue StandardError => error
      Message.where(id: message.id, status: "queued", delivery_enqueued_at: now)
             .update_all(delivery_enqueued_at: nil)
      Rails.logger.warn("[emails.handoff] message=#{message.id} #{error.class}: #{error.message}")
      false
    end
  end
end
