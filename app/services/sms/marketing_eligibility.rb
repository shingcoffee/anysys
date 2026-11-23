# frozen_string_literal: true

module Sms
  # Permission is tied to the exact current tenant/contact/phone identity.
  class MarketingEligibility
    def self.call(customer:, contact:, phone_e164: nil)
      Contacts::Eligibility.call(customer: customer, contact: contact, phone_e164: phone_e164)
    end

    def self.require!(customer:, contact:, phone_e164:)
      decision = call(customer: customer, contact: contact, phone_e164: phone_e164)
      return contact if decision[:eligible]

      raise Errors::MarketingIneligible.new(reason: decision[:reason])
    end
  end
end
