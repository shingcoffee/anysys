# frozen_string_literal: true

module Sms
  module Campaigns
    class Report
      COUNTS = %i[matched eligible_at_start pending admitted attempted api_accepted delivered failed unknown queued
                  suppressed expired skipped cancelled].freeze

      def self.call(customer:, campaign:, refresh: false)
        return Support.failure(:not_found) unless Support.scoped?(customer, campaign)
        return RefreshStats.call(customer: customer, campaign: campaign) if refresh
        Support.success(derive(customer: customer, campaign: campaign, at: Time.current))
      end

      def self.derive(customer:, campaign:, at: nil)
        report = COUNTS.to_h { |key| ["#{key}_count".to_sym, 0] }.merge(
          skip_counts: Hash.new(0), deferred_counts: Hash.new(0), provider_segments_total: 0,
          provider_segments_missing_count: 0, delivery_rate: nil, snapshot_at: campaign.started_at,
          refreshed_at: at || campaign.stats_refreshed_at)
        Sms::CampaignRecipient.where(customer_id: customer.id, campaign_id: campaign.id).includes(:message)
          .find_in_batches(batch_size: Support::BATCH_SIZE) do |recipients|
          recipients.each do |recipient|
            report[:matched_count] += 1
            report[:eligible_at_start_count] += 1 if recipient.contact_snapshot.dig("eligibility_at_start", "eligible") == true
            report["#{recipient.status}_count".to_sym] += 1 if %w[pending skipped cancelled].include?(recipient.status)
            report[:skip_counts][recipient.skip_reason] += 1 if recipient.skip_reason
            message = recipient.message
            if recipient.deferral_reason && (recipient.status == "pending" || (message && message.dispatch_started_at.nil? && message.status == "queued"))
              report[:deferred_counts][recipient.deferral_reason] += 1
            end
            next unless message && message.customer_id == customer.id && message.campaign_id == campaign.id
            report[:admitted_count] += 1
            report[:attempted_count] += 1 if message.dispatch_started_at
            report[:api_accepted_count] += 1 if message.sent_at
            report["#{message.status}_count".to_sym] += 1 if %w[delivered failed unknown queued suppressed expired].include?(message.status)
            segments = message.metadata["provider_segments"]
            if segments.is_a?(Integer) && segments.positive?
              report[:provider_segments_total] += segments
            else
              report[:provider_segments_missing_count] += 1
            end
          end
        end
        report[:delivery_rate] = report[:delivered_count].fdiv(report[:attempted_count]) if report[:attempted_count].positive?
        report
      end
    end
  end
end
