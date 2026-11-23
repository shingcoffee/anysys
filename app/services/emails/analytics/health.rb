# frozen_string_literal: true

module Emails
  module Analytics
    class Health
      def self.for(customer, since:, until_date:, reason: nil)
        new(customer: customer, since: since, until_date: until_date, reason: reason).call
      end

      def initialize(customer:, since:, until_date:, reason:)
        @customer = customer
        @since, @until_date = DateRange.clamp(since, until_date)
        @reason = reason
      end

      def call
        {
          totals: deliverability_totals,
          failure_breakdown: failure_breakdown,
          suppressions: suppressions,
          top_links: top_clicked_links,
          opens_by_hour: opens_by_hour,
          opens_by_day: opens_by_day,
          devices: device_breakdown
        }
      end

      private

      def message_scope
        Emails::Message.where(customer_id: @customer.id, created_at: @since..@until_date)
      end

      def event_scope
        Emails::MessageEvent
          .joins(:message)
          .where(email_messages: { customer_id: @customer.id })
          .where(occurred_at: @since..@until_date)
      end

      def deliverability_totals
        base = message_scope.select(
          "COUNT(CASE WHEN status = 'bounced' THEN 1 END) AS bounced",
          "COUNT(CASE WHEN status = 'complained' THEN 1 END) AS complained",
          "COUNT(CASE WHEN status = 'suppressed' THEN 1 END) AS suppressed",
          "COUNT(CASE WHEN status = 'failed' THEN 1 END) AS failed"
        ).to_a.first

        %i[bounced complained suppressed failed].index_with { |status| base.public_send(status) || 0 }
      end

      def failure_breakdown
        message_scope.where(status: %w[bounced failed]).where.not(failure_code: [nil, ""])
                     .group(:failure_code).count.sort_by { |_, count| -count }.to_h
      end

      def suppressions
        scope = Emails::Suppression.for_customer(@customer.id)
        reason = scalar_reason
        scope = scope.where(reason: reason) if reason
        scope.where(created_at: @since..@until_date).order(created_at: :desc).limit(100)
      end

      def top_clicked_links
        event_scope.where(event_type: "click").where.not(url: nil).group(:url).order(Arel.sql("COUNT(*) DESC")).limit(10).count
      end

      def opens_by_hour
        event_scope.where(event_type: "open").group(Arel.sql("CAST(strftime('%H', occurred_at) AS INTEGER)")).count.transform_keys(&:to_i)
      end

      def opens_by_day
        event_scope.where(event_type: "open").group(Arel.sql("DATE(occurred_at)")).count.transform_keys { |date| date.is_a?(String) ? Date.parse(date) : date }
      end

      def device_breakdown
        event_scope.where(event_type: "open").where.not(user_agent: nil)
                   .group(Arel.sql(device_category_sql)).count
      end

      def device_category_sql
        ua = "email_message_events.user_agent"
        <<~SQL.squish
          CASE
            WHEN LOWER(#{ua}) LIKE '%ipad%' OR LOWER(#{ua}) LIKE '%tablet%'
              OR LOWER(#{ua}) LIKE '%kindle%' OR LOWER(#{ua}) LIKE '%playbook%' THEN 'tablet'
            WHEN LOWER(#{ua}) LIKE '%mobile%' OR LOWER(#{ua}) LIKE '%iphone%'
              OR LOWER(#{ua}) LIKE '%ipod%' OR LOWER(#{ua}) LIKE '%android%mobile%'
              OR LOWER(#{ua}) LIKE '%blackberry%' OR LOWER(#{ua}) LIKE '%iemobile%' THEN 'mobile'
            ELSE 'desktop'
          END
        SQL
      end

      def scalar_reason
        Array.wrap(@reason).find { |v| v.is_a?(String) || v.is_a?(Symbol) }&.to_s.presence
      end
    end
  end
end
