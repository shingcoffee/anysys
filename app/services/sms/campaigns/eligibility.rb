# frozen_string_literal: true

module Sms
  module Campaigns
    class Eligibility
      def self.call(customer:, contact:, phone_e164:, vars:, settings:, at:, message_id: nil)
        permission = MarketingEligibility.call(customer: customer, contact: contact, phone_e164: phone_e164)
        return permission unless permission[:eligible]
        return { eligible: false, reason: :personalization_missing } unless vars
        if frequency_capped?(customer_id: customer.id, phone: phone_e164, hours: settings.fetch("frequency_window_hours"), at: at, message_id: message_id)
          return { eligible: false, reason: :frequency_capped }
        end
        { eligible: true, reason: nil }
      end

      def self.frequency_capped?(customer_id:, phone:, hours:, at:, message_id: nil)
        scope = Sms::Message.where(customer_id: customer_id, to: phone).where.not(campaign_id: nil)
                           .where(dispatch_started_at: (at - hours.hours)..at)
        scope = scope.where.not(id: message_id) if message_id
        scope.exists?
      end
    end
  end
end
