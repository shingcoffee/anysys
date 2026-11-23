# frozen_string_literal: true

module Payments
  module Cron
    # Recovery pass for the async webhook pipeline (WebhookDispatcher +
    # ProcessWebhookEventJob). WeChat/Alipay/etc. never redeliver a
    # notification once it has been acked with HTTP success, so once an
    # event is handed to the queue, PSP redelivery can no longer be relied on
    # to recover it if something goes wrong — this reaper is the actual
    # recovery path for the two ways an event can be stranded:
    #
    #   - "received" but stuck past ProcessWebhookEventJob's own retry window
    #     (RECEIVED_GRACE) — the job was never enqueued/picked up, or its
    #     worker died mid-attempt.
    #   - "failed" (dead-lettered after exhausting retries) — re-driven on a
    #     throttled cadence (FAILED_REDRIVE_INTERVAL) and abandoned past
    #     FAILED_MAX_AGE so a permanently-broken event does not retry
    #     forever. No attempts-counter column is needed: the age cap plus the
    #     updated_at throttle already bound the total number of re-drives a
    #     failing event can receive.
    class RedriveWebhookEvents
      RECEIVED_GRACE          = 15.minutes
      FAILED_MAX_AGE          = 7.days
      FAILED_REDRIVE_INTERVAL = 6.hours

      def self.perform(now: Time.current)
        stuck_received(now).find_each { |event| redrive(event) }
        redrivable_failed(now).find_each { |event| redrive(event) }
      end

      def self.stuck_received(now)
        Payments::WebhookEvent.where(status: "received").where(updated_at: ..(now - RECEIVED_GRACE))
      end

      def self.redrivable_failed(now)
        Payments::WebhookEvent.where(status: "failed")
                              .where(created_at: (now - FAILED_MAX_AGE)..)
                              .where(updated_at: ..(now - FAILED_REDRIVE_INTERVAL))
      end
      private_class_method :stuck_received, :redrivable_failed

      def self.redrive(event)
        event.with_lock do
          next if event.status == "processed" || event.processing?

          event.update!(status: "received")
          Payments::ProcessWebhookEventJob.perform_later(event.id, event.signing_merchant_id, event.signing_account_id)
        end
      rescue StandardError => e
        Rails.logger.error("[payments.cron] RedriveWebhookEvents event=#{event.id} failed: #{e.class}: #{e.message}")
      end
      private_class_method :redrive
    end
  end
end
