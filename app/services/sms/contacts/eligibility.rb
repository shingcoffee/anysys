# frozen_string_literal: true

module Sms
  module Contacts
    class Eligibility
      def self.call(customer:, contact:, phone_e164: nil, at: Time.current)
        reason = if !DomainAccess.scoped?(customer, contact)
          :consent_missing
        elsif contact.status != "active"
          :contact_archived
        elsif phone_e164 && contact.phone_e164 != phone_e164
          :phone_changed
        elsif contact.consent_status != "granted"
          :consent_missing
        elsif Sms::OptOut.opted_out?(customer_id: customer.id, phone_e164: contact.phone_e164)
          :opted_out
        end
        { eligible: reason.nil?, reason: reason }
      end
    end
  end
end
