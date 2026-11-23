# frozen_string_literal: true

module Sms
  # Best-effort queue accelerator; recovery always scans the committed ledger.
  class DeliveryHandoff
    RECOVERY_AFTER = 5.minutes

    def self.call(message, now: Time.current, recovery_after: RECOVERY_AFTER)
      ActiveRecord.after_all_transactions_commit { enqueue(message, now: now, recovery_after: recovery_after) }
    end

    def self.enqueue(message, now: Time.current, recovery_after: RECOVERY_AFTER)
      scope = Message.where(id: message.id, status: "queued", dispatch_started_at: nil)
                     .where("delivery_enqueued_at IS NULL OR delivery_enqueued_at <= ?", now - recovery_after)
      return false unless scope.update_all(delivery_enqueued_at: now) == 1

      due_at = Message.where(id: message.id).pick(:delivery_due_at)
      job = if due_at && due_at > now
        DeliverMessageJob.set(wait_until: due_at).perform_later(message.id)
      else
        DeliverMessageJob.perform_later(message.id)
      end
      raise ActiveJob::EnqueueError, I18n.t("sms.errors.enqueue_rejected") unless job

      true
    rescue StandardError => error
      begin
        Message.where(id: message.id, status: "queued", dispatch_started_at: nil, delivery_enqueued_at: now)
               .update_all(delivery_enqueued_at: nil)
      rescue StandardError => reset_error
        # A DB interruption while resetting the accelerator must not invalidate
        # committed acceptance; a leftover stamp ages out in recovery.
        Rails.logger.warn("[sms.handoff] stamp reset message=#{message.id} #{reset_error.class}: #{reset_error.message}")
      end
      Rails.logger.warn("[sms.handoff] message=#{message.id} #{error.class}: #{error.message}")
      false
    end
    private_class_method :enqueue
  end
end
