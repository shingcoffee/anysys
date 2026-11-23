# frozen_string_literal: true

module Sms
  module Campaigns
    class RefreshStats
      def self.call(customer:, campaign:, at: Time.current)
        return Support.failure(:not_found) unless Support.scoped?(customer, campaign)
        Quota.synchronize(customer) do
          campaign.lock!
          report = Report.derive(customer: customer, campaign: campaign, at: at)
          campaign.update!(stats: report.transform_values { |value| value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) ? Support.iso(value) : value },
                           stats_refreshed_at: at)
          Support.success(report)
        end
      end
    end
  end
end
