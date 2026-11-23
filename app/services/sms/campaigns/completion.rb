# frozen_string_literal: true

module Sms
  module Campaigns
    class Completion
      def self.call(customer:, campaign:, at:)
        return false unless campaign.status == "running" && campaign.started_at
        recipients = Sms::CampaignRecipient.where(customer_id: customer.id, campaign_id: campaign.id)
        return false if recipients.where(status: "pending").exists?
        return false if Sms::Message.where(customer_id: customer.id, id: recipients.where.not(message_id: nil).select(:message_id),
          dispatch_started_at: nil).where.not(status: %w[suppressed expired]).exists?
        campaign.update!(status: "completed", finished_at: at, run_token: nil, run_lease_expires_at: nil)
        true
      end
    end
  end
end
