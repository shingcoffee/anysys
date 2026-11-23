# frozen_string_literal: true

module Sms
  module Contacts
    # Trusted internal writer for signed unsubscribe / verified provider events.
    # Admin callers must pass through RecordConsent's actor/evidence contract.
    class EvidenceWriter
      def self.call(customer:, contact:, phone_e164:, action:, source:, occurred_at:, evidence:, event_key:, actor_user_id: nil)
        return DomainAccess.failure(:not_found) unless DomainAccess.scoped?(customer, contact)
        time = Contracts::Bounds.time(occurred_at)
        unless Sms::ConsentEvent::ACTIONS.include?(action) && Sms::ConsentEvent::SOURCES.include?(source) &&
            time && time <= Time.current && Contracts::Bounds.object?(evidence, bytes: 4096) &&
            Contracts::Bounds.text?(event_key, bytes: 128, required: true)
          return DomainAccess.failure(:invalid_evidence)
        end
        if source == "admin"
          actor = Authentication::User.find_by(id: actor_user_id)
          return DomainAccess.failure(:forbidden) unless DomainAccess.actor_allowed?(customer, actor)
          form = Contracts::ConsentEvent.new(Contracts::ConsentEvent::Input.new)
          attrs = { action: action, occurred_at: time, event_key: event_key }.merge(evidence.symbolize_keys)
          return DomainAccess.failure(:invalid_evidence) unless (evidence.keys - %w[reference statement notes]).empty? && form.validate(attrs)
        elsif action != "revoked" || actor_user_id
          return DomainAccess.failure(:invalid_evidence)
        end

        DomainAccess.synchronize(customer) do
          locked = Sms::Contact.for_customer(customer.id).lock.find(contact.id)
          phone = phone_e164 || locked.phone_e164
          next DomainAccess.failure(:invalid_phone) unless PhoneNumber.normalize(phone) == phone
          next DomainAccess.failure(:phone_changed) if source == "admin" && phone != locked.phone_e164
          facts = { contact_id: locked.id, phone_e164: phone, action: action, source: source,
            actor_user_id: actor_user_id, occurred_at: time, evidence: evidence }
          existing = Sms::ConsentEvent.for_customer(customer.id).find_by(event_key: event_key)
          if existing
            same = facts.all? { |key, value| existing.public_send(key) == value }
            next DomainAccess.failure(:event_key_conflict, field: :event_key) unless same
            next Result.success(contact: locked, event: existing, replayed: true)
          end

          event = Sms::ConsentEvent.create!(facts.merge(customer_id: customer.id, event_key: event_key))
          if phone == locked.phone_e164
            locked.update!(consent_status: action, consent_changed_at: event.created_at)
          end
          if action == "revoked"
            Sms::OptOut.record_for_customer!(customer_id: customer.id, phone_e164: phone, reason: source)
          end
          Result.success(contact: locked, event: event, replayed: false)
        end
      end
    end
  end
end
