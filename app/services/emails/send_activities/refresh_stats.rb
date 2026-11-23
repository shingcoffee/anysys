# frozen_string_literal: true

module Emails
  module SendActivities
    class RefreshStats
      def self.call(campaign)
        campaign.with_lock do
          counts = Message.where(customer_id: campaign.customer_id, email_send_activity_id: campaign.id).group(:status).count
          campaign.update_columns(stats: campaign.stats.merge(
            "sent_count" => %w[sent delivered bounced complained].sum { |status| counts.fetch(status, 0) },
            "materialized_count" => counts.values.sum,
            "pending_count" => counts.fetch("pending", 0),
            "queued_count" => counts.fetch("queued", 0),
            "failed_count" => counts.fetch("failed", 0),
            "suppressed_count" => counts.fetch("suppressed", 0)
          ))
        end
      end
    end
  end
end
