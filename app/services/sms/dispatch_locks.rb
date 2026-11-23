# frozen_string_literal: true

module Sms
  class DispatchLocks
    # Read IDs to establish the order; re-read every mutable decision under locks.
    def self.synchronize(message)
      customer = Customer.find(message.customer_id)
      Quota.synchronize(customer) do
        campaign = message.campaign_id && Campaign.find_by!(id: message.campaign_id, customer_id: customer.id)
        campaign&.lock!
        contact = message.contact_id && Contact.find_by!(id: message.contact_id, customer_id: customer.id)
        contact&.lock!
        recipient = campaign && CampaignRecipient.find_by!(campaign_id: campaign.id, customer_id: customer.id, message_id: message.id)
        recipient&.lock!
        message.lock!
        yield customer, campaign, contact, recipient
      end
    end
  end
end
