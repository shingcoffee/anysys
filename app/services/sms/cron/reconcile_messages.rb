# frozen_string_literal: true

module Sms
  module Cron
    # Reconcile receipts, then bounded query fallback for both poll and webhook
    # vendors. Lack of confirmation is not proof of failure. Never resend an
    # attempted message or convert an undispatched queued row to a dead letter;
    # RecoverMessages owns crashed dispatch attempts. Late receipts still repair
    # unknown messages after the polling window closes.
    class ReconcileMessages
      GRACE = 2.minutes
      MAX_AGE = 3.days
      RECONCILABLE_STATUSES = %w[pending sent unknown].freeze
      # Async admission can precede the attempt by days. The settlement window
      # starts at dispatch; historical rows fall back to acceptance/admission.
      DELIVERY_CLOCK_SQL = "COALESCE(dispatch_started_at, sent_at, created_at)"

      def self.call(now: Time.current)
        Sms::ReceiptInbox.reconcile
        reconcile_pollable(now)
        mark_unresolved_unknown(now)
      end

      def self.reconcile_pollable(now)
        Sms::Message.where(status: RECONCILABLE_STATUSES)
                    .where("#{DELIVERY_CLOCK_SQL} >= ? AND #{DELIVERY_CLOCK_SQL} <= ?", now - MAX_AGE, now - GRACE)
                    .where.not(vendor_message_id: [nil, ""])
                    .find_each { |message| reconcile_one(message) }
      end

      def self.reconcile_one(message)
        # Disabling new sends never discards outstanding delivery receipts.
        return unless Sms::Adapters.for(message.provider).query_supported?

        Sms::Gateway.query(message: message)
      rescue StandardError => error
        Rails.logger.warn("[sms] reconcile failed message=#{message.id}: #{error.class}: #{error.message}")
      end

      def self.mark_unresolved_unknown(now)
        Sms::Message.where(status: %w[pending sent])
                    .where("#{DELIVERY_CLOCK_SQL} < ?", now - MAX_AGE)
                    .find_each do |message|
          message.mark_unknown!(raw: message.raw_response || {})
        rescue ActiveRecord::RecordInvalid => error
          Rails.logger.warn("[sms] unconfirmed message=#{message.id}: #{error.message}")
        end
      end
    end
  end
end
