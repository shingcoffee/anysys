# frozen_string_literal: true

module Sms
  module Campaigns
    class DeliveryPolicy
      def self.call(message:, at: Time.current)
        campaign = message.campaign_id && Sms::Campaign.find_by(id: message.campaign_id, customer_id: message.customer_id)
        # These operational gates dominate permission and delay decisions.
        return decision(:suppress, :campaign_cancelled) if campaign&.status == "cancelled"
        return decision(:suppress, :campaign_failed) if campaign&.status == "failed"
        return decision(:expire, campaign ? :campaign_expired : :expired) if (message.expires_at && message.expires_at <= at) ||
          (campaign&.expires_at && campaign.expires_at <= at)
        return decision(:suppress, :module_disabled) unless FeatureModules::Module.enabled?(key: "sms", customer_id: message.customer_id)
        if message.campaign_id && (!campaign || !Snapshot.valid?(campaign))
          return decision(:suppress, :template_invalid)
        end
        marketing = campaign || message.metadata.dig("template_snapshot", "purpose") == "marketing"
        contact = marketing && Sms::Contact.find_by(id: message.contact_id, customer_id: message.customer_id)
        if marketing
          eligibility = Sms::MarketingEligibility.call(customer: Customer.find(message.customer_id), contact: contact, phone_e164: message.to)
          return decision(:suppress, eligibility[:reason]) unless eligibility[:eligible]
        elsif Sms::OptOut.opted_out?(customer_id: message.customer_id, phone_e164: message.to)
          return decision(:suppress, :opted_out)
        end
        if campaign
          settings = campaign.settings_snapshot
          if Eligibility.frequency_capped?(customer_id: message.customer_id, phone: message.to,
            hours: settings.fetch("frequency_window_hours"), at: at, message_id: message.id)
            return decision(:suppress, :frequency_capped)
          end
          zone = Schedule.valid_zone?(contact.timezone) ? contact.timezone : settings.fetch("timezone")
          due = QuietWindow.next_allowed(at: at, timezone: zone, start_hour: settings.fetch("quiet_hours_start"), end_hour: settings.fetch("quiet_hours_end"))
          return bounded_defer(message, due, :quiet_hours) if due > at
        end
        return bounded_defer(message, message.delivery_due_at, :account_rate) if message.delivery_due_at && message.delivery_due_at > at
        decision(:allow, nil)
      end

      def self.decision(action, reason, due_at = nil)
        { action: action, due_at: due_at, reason: reason }
      end

      def self.bounded_defer(message, due, reason)
        return decision(:expire, message.campaign_id ? :campaign_expired : :expired) if message.expires_at && due >= message.expires_at
        decision(:defer, reason, due)
      end
    end
  end
end
