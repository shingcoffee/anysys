# frozen_string_literal: true

module SmsAudienceDomainHelpers
  def save_contact(attributes = {}, contact: nil, customer: self.customer, actor: self.actor, **fields)
    Sms::Contacts::Save.call(customer: customer, actor: actor, contact: contact,
      attributes: { phone: "+8613800138000", country_code: "CN", name: "Alice" }.merge(attributes).merge(fields))
  end

  def consent(contact, action: "granted", event_key: "consent-key", occurred_at: 1.hour.ago, **fields)
    Sms::Contacts::RecordConsent.call(customer: customer, actor: actor, contact: contact,
      attributes: { action: action, event_key: event_key, occurred_at: occurred_at,
        reference: "paper-form-42", statement: "I agree to receive SMS marketing." }.merge(fields))
  end

  def condition(field, value = nil, operator: "equals")
    { "field" => field, "operator" => operator, "value" => value }
  end

  def group(*conditions, joins: nil)
    { "type" => "group", "conditions" => conditions, "joins" => joins || Array.new([conditions.size - 1, 0].max, "AND") }
  end
end
