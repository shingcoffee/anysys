# frozen_string_literal: true

module Emails
  module Analytics
    class Report
      def self.for(customer, since:, until_date:, send_activity_ids: nil)
        new(customer: customer, since: since, until_date: until_date, send_activity_ids: send_activity_ids).call
      end

      def initialize(customer:, since:, until_date:, send_activity_ids: nil)
        @customer = customer
        @since, @until_date = DateRange.clamp(since, until_date)
        @send_activity_ids = Array(send_activity_ids).presence
      end

      def call
        {
          since: @since,
          until_date: @until_date,
          totals: totals,
          daily: daily_series,
          send_activities: send_activity_breakdown
        }
      end

      private

      def message_scope
        scope = Emails::Message.where(customer_id: @customer.id, created_at: @since..@until_date)
        scope = scope.where(email_send_activity_id: @send_activity_ids) if @send_activity_ids
        scope
      end

      def event_scope
        scope = Emails::MessageEvent
                .joins(:message)
                .where(email_messages: { customer_id: @customer.id })
                .where(occurred_at: @since..@until_date)
        scope = scope.where(email_messages: { email_send_activity_id: @send_activity_ids }) if @send_activity_ids
        scope
      end

      def totals
        base = message_scope.select(
          "COUNT(CASE WHEN status IN ('sent','delivered','bounced','complained') THEN 1 END) AS sent",
          "COUNT(CASE WHEN status = 'delivered' THEN 1 END) AS delivered",
          "COUNT(CASE WHEN status = 'bounced' THEN 1 END) AS bounced",
          "COUNT(CASE WHEN status = 'complained' THEN 1 END) AS complained",
          "COUNT(CASE WHEN status = 'suppressed' THEN 1 END) AS suppressed",
          "COUNT(CASE WHEN status = 'failed' THEN 1 END) AS failed"
        ).to_a.first

        opened = event_scope.where(event_type: "open").distinct.count(:message_id)
        clicked = event_scope.where(event_type: "click").distinct.count(:message_id)

        {
          sent: base.sent || 0,
          delivered: base.delivered || 0,
          bounced: base.bounced || 0,
          complained: base.complained || 0,
          suppressed: base.suppressed || 0,
          failed: base.failed || 0,
          opened: opened,
          clicked: clicked
        }
      end

      def daily_series
        daily_messages = message_scope
                         .group("DATE(created_at)")
                         .select(
                           "DATE(created_at) AS date",
                            "COUNT(CASE WHEN status IN ('sent','delivered','bounced','complained') THEN 1 END) AS sent",
                           "COUNT(CASE WHEN status = 'delivered' THEN 1 END) AS delivered",
                            "COUNT(CASE WHEN status = 'bounced' THEN 1 END) AS bounced",
                            "COUNT(CASE WHEN status = 'failed' THEN 1 END) AS failed"
                         )
                         .to_a
                         .index_by { |r| r.date.is_a?(String) ? Date.parse(r.date) : r.date }

        daily_events = event_scope
                       .group("DATE(email_message_events.occurred_at)")
                       .select(
                         "DATE(email_message_events.occurred_at) AS date",
                         "COUNT(DISTINCT CASE WHEN event_type = 'open' THEN email_message_events.message_id END) AS opened",
                         "COUNT(DISTINCT CASE WHEN event_type = 'click' THEN email_message_events.message_id END) AS clicked"
                       )
                       .to_a
                       .index_by { |r| r.date.is_a?(String) ? Date.parse(r.date) : r.date }

        dates = (@since.to_date..@until_date.to_date).to_a
        dates.map do |date|
          dm = daily_messages[date]
          de = daily_events[date]
          {
            date: date,
            sent: dm&.sent || 0,
            delivered: dm&.delivered || 0,
            bounced: dm&.bounced || 0,
            failed: dm&.failed || 0,
            opened: de&.opened || 0,
            clicked: de&.clicked || 0
          }
        end
      end

      def send_activity_breakdown
        message_scope.where(status: %w[sent delivered bounced complained])
                     .where.not(email_send_activity_id: nil).group(:email_send_activity_id).count
      end
    end
  end
end
