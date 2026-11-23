# frozen_string_literal: true

module Emails
  class DashboardStats
    def self.for(customer, since: 30.days.ago, until_date: Time.current)
      since, until_date = Emails::Analytics::DateRange.clamp(since, until_date)

      # Gather totals for messages
      message_totals = Emails::Message
                       .where(customer_id: customer.id)
                       .where(created_at: since..until_date)
                       .select(
                          "COUNT(CASE WHEN status IN ('sent', 'delivered', 'bounced', 'complained') THEN 1 END) AS total_sent",
                         "COUNT(CASE WHEN status = 'delivered' THEN 1 END) AS total_delivered",
                         "COUNT(CASE WHEN status = 'bounced' THEN 1 END) AS total_bounced",
                         "COUNT(CASE WHEN status = 'complained' THEN 1 END) AS total_complained",
                          "COUNT(CASE WHEN status = 'suppressed' THEN 1 END) AS total_suppressed",
                          "COUNT(CASE WHEN status = 'failed' THEN 1 END) AS total_failed"
                       )
                       .to_a.first

      # Gather totals for events
      event_totals = Emails::MessageEvent
                     .joins(:message)
                     .where(email_messages: { customer_id: customer.id })
                     .where(email_message_events: { occurred_at: since..until_date })
                     .group(:event_type)
                     .select("event_type", "COUNT(DISTINCT email_message_events.message_id) AS count")
                     .to_a
                     .to_h { |e| [e.event_type, e.count] }

      # Gather totals for suppressions
      unsubscribed = Emails::Suppression
                     .for_customer(customer.id)
                     .where(reason: "unsubscribe")
                     .where(created_at: since..until_date)
                     .count

      totals = {
        sent: message_totals.total_sent || 0,
        delivered: message_totals.total_delivered || 0,
        bounced: message_totals.total_bounced || 0,
        complained: message_totals.total_complained || 0,
        suppressed: message_totals.total_suppressed || 0,
        failed: message_totals.total_failed || 0,
        opened: event_totals["open"] || 0,
        clicked: event_totals["click"] || 0,
        unsubscribed: unsubscribed
      }

      # Gather daily series for messages
      daily_messages = Emails::Message
                       .where(customer_id: customer.id)
                       .where(created_at: since..until_date)
                       .group("DATE(created_at)")
                       .select(
                         "DATE(created_at) AS date",
                          "COUNT(CASE WHEN status IN ('sent', 'delivered', 'bounced', 'complained') THEN 1 END) AS total_sent",
                         "COUNT(CASE WHEN status = 'delivered' THEN 1 END) AS total_delivered",
                          "COUNT(CASE WHEN status = 'bounced' THEN 1 END) AS total_bounced",
                          "COUNT(CASE WHEN status = 'failed' THEN 1 END) AS total_failed"
                       )
                       .to_a
                       .index_by { |r| r.date.is_a?(String) ? Date.parse(r.date) : r.date }

      # Gather daily series for events
      daily_events = Emails::MessageEvent
                     .joins(:message)
                     .where(email_messages: { customer_id: customer.id })
                     .where(email_message_events: { occurred_at: since..until_date })
                     .group("DATE(email_message_events.occurred_at)")
                     .select(
                       "DATE(email_message_events.occurred_at) AS date",
                       "COUNT(DISTINCT CASE WHEN event_type = 'open' THEN email_message_events.message_id END) AS total_opened",
                       "COUNT(DISTINCT CASE WHEN event_type = 'click' THEN email_message_events.message_id END) AS total_clicked"
                     )
                     .to_a
                     .index_by { |r| r.date.is_a?(String) ? Date.parse(r.date) : r.date }

      dates = (since.to_date..until_date.to_date).to_a
      daily = dates.map do |date|
        dm = daily_messages[date]
        de = daily_events[date]
        {
          date: date,
          sent: dm&.total_sent || 0,
          delivered: dm&.total_delivered || 0,
          bounced: dm&.total_bounced || 0,
          failed: dm&.total_failed || 0,
          opened: de&.total_opened || 0,
          clicked: de&.total_clicked || 0
        }
      end

      {
        totals: totals,
        daily: daily
      }
    end
  end
end
