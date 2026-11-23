# frozen_string_literal: true

module Sms
  module Campaigns
    class Cancel
      def self.call(customer:, actor:, campaign:, at: Time.current)
        return Support.failure(:forbidden) unless Support.actor_allowed?(customer, actor)
        return Support.failure(:not_found) unless Support.scoped?(customer, campaign)
        Quota.synchronize(customer) do
          campaign.lock!
          next Support.success(campaign) if campaign.status == "cancelled"
          next Support.failure(:cannot_cancel) unless %w[scheduled running].include?(campaign.status)
          campaign.update!(status: "cancelled", cancelled_at: at, finished_at: at, run_token: nil, run_lease_expires_at: nil)
          CloseRemaining.call(customer: customer, campaign: campaign, reason: :campaign_cancelled, at: at)
          RefreshStats.call(customer: customer, campaign: campaign, at: at)
          Support.success(campaign)
        end
      end
    end
  end
end
