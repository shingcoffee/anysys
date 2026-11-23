# frozen_string_literal: true

module Emails
  # The persisted message is the quota reservation. All email entry points use
  # this transaction, including campaign and raw sends. Reserving individual
  # recipients prevents competing batches from spending the same allowance.
  class Quota
    CAMPAIGN_PER_MINUTE = 60
    Throttled = Class.new(StandardError)

    class << self
      def synchronize(customer)
        customer.with_lock do
          # SQLite has no SELECT FOR UPDATE. Acquire its write lock before any
          # quota/idempotency reads; PostgreSQL also serializes this tenant row.
          Customer.where(id: customer.id).update_all("id = id")
          yield
        end
      end

      def reserve(attrs, campaign_limit: CAMPAIGN_PER_MINUTE)
        customer = attrs.fetch(:customer)
        synchronize(customer) do
          existing = PersistMessage.existing(customer_id: customer.id, idempotency_key: attrs[:idempotency_key])
          next [existing, false] if existing

          unless attrs[:status] == "suppressed"
            check_daily!(customer)
            if attrs[:message_type] == "campaign"
              raise Throttled if campaign_window(customer).count >= campaign_limit
            end
          end
          PersistMessage.call(attrs)
        end
      end

      def remaining_daily(customer)
        Activities::Send.daily_cap_for(customer) - daily_messages(customer).count
      end

      def campaign_allowance(customer, limit: CAMPAIGN_PER_MINUTE)
        [remaining_daily(customer), limit - campaign_window(customer).count].min.clamp(0, limit)
      end

      def check_daily!(customer)
        return if remaining_daily(customer).positive?

        raise Email::Errors::DailyCapExceeded, I18n.t("admin_modules.flash.templates.daily_cap_exceeded")
      end

      def daily_messages(customer)
        Message.where(customer_id: customer.id).where.not(status: %w[suppressed failed])
               .where(created_at: Time.current.beginning_of_day..)
      end

      def campaign_window(customer)
        Message.where(customer_id: customer.id, message_type: "campaign")
               .where.not(status: "suppressed").where(created_at: 1.minute.ago..)
      end
    end
  end
end
