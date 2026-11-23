# frozen_string_literal: true

module Sms
  module Campaigns
    class RefreshStatsJob < ApplicationJob
      queue_as :default

      def perform(customer_id, campaign_id)
        customer = Customer.find_by(id: customer_id)
        campaign = Sms::Campaign.find_by(customer_id: customer_id, id: campaign_id)
        return unless customer && campaign
        Current.set(customer: customer) do
          Quota.synchronize(customer) do
            campaign.lock!
            Completion.call(customer: customer, campaign: campaign, at: Time.current)
            RefreshStats.call(customer: customer, campaign: campaign)
          end
        end
      end
    end
  end
end
