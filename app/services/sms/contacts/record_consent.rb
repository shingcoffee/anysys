# frozen_string_literal: true

module Sms
  module Contacts
    class RecordConsent
      def self.call(customer:, actor:, contact:, attributes:)
        return DomainAccess.failure(:forbidden) unless DomainAccess.actor_allowed?(customer, actor)
        return DomainAccess.failure(:not_found) unless DomainAccess.scoped?(customer, contact)
        attrs = DomainAccess.attributes(attributes, Contracts::ConsentEvent::FIELDS)
        return DomainAccess.failure(:invalid_input) unless attrs

        form = Contracts::ConsentEvent.new(Contracts::ConsentEvent::Input.new)
        return DomainAccess.failure(:invalid_input, errors: form.errors.messages) unless form.validate(attrs)

        # Phone is resolved after locking, never accepted from the consent form.
        EvidenceWriter.call(customer: customer, contact: contact, phone_e164: nil, action: form.action,
          source: "admin", actor_user_id: actor.id, occurred_at: form.parsed_occurred_at,
          evidence: form.evidence, event_key: form.event_key)
      end
    end
  end
end
