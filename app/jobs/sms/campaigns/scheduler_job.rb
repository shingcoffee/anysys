# frozen_string_literal: true

module Sms
  module Campaigns
    class SchedulerJob < ApplicationJob
      queue_as :default

      def perform
        now = Time.current
        Sms::Campaign.where(status: %w[scheduled running]).find_in_batches(batch_size: Support::BATCH_SIZE) do |campaigns|
          campaigns.each do |candidate|
            next if candidate.status == "scheduled" && candidate.scheduled_at && candidate.scheduled_at > now
            customer = Customer.find(candidate.customer_id)
            Current.set(customer: customer) do
              Quota.synchronize(customer) do
                campaign = Sms::Campaign.find_by!(customer_id: customer.id, id: candidate.id)
                campaign.lock!
                next unless %w[scheduled running].include?(campaign.status)
                next if campaign.status == "scheduled" && campaign.scheduled_at && campaign.scheduled_at > now
                if campaign.run_token.nil? || campaign.run_lease_expires_at.nil? || campaign.run_lease_expires_at <= now
                  campaign.update!(run_token: SecureRandom.uuid, run_lease_expires_at: now + Support::LEASE, heartbeat_at: now)
                end
                messages = Sms::Message.where(customer_id: customer.id, campaign_id: campaign.id, status: "queued", dispatch_started_at: nil).delivery_due(now)
                messages.limit(Support::BATCH_SIZE).each { |message| Sms::DeliveryHandoff.call(message, now: now, recovery_after: 1.minute) }
                pending_due = Sms::CampaignRecipient.where(customer_id: customer.id, campaign_id: campaign.id, status: "pending")
                  .where("delivery_due_at IS NULL OR delivery_due_at <= ?", now).exists?
                # Also close expired work and complete attempted orchestration.
                if campaign.started_at.nil? || pending_due || messages.exists? || campaign.expires_at.nil? || campaign.expires_at <= now ||
                  !Sms::CampaignRecipient.where(campaign_id: campaign.id, status: "pending").exists?
                  Support.enqueue(customer.id, campaign.id, campaign.run_token)
                end
              end
            end
          end
        end
      end
    end
  end
end
