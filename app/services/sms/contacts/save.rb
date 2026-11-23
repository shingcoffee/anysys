# frozen_string_literal: true

module Sms
  module Contacts
    class Save
      def self.call(customer:, actor:, contact: nil, attributes:)
        return DomainAccess.failure(:forbidden) unless DomainAccess.actor_allowed?(customer, actor)
        return DomainAccess.failure(:not_found) if contact && !DomainAccess.scoped?(customer, contact)
        attrs = DomainAccess.attributes(attributes, Contracts::Contact::FIELDS)
        return DomainAccess.failure(:invalid_input) unless attrs

        DomainAccess.synchronize(customer) do
          record = contact ? Sms::Contact.for_customer(customer.id).lock.find(contact.id) : Sms::Contact.new(customer: customer)
          if contact && DomainAccess.integer(attrs[:lock_version]) != record.lock_version
            next DomainAccess.failure(:stale_edit, field: :lock_version)
          end
          defaults = { phone: record.phone_e164, name: record.name, country_code: record.country_code,
            timezone: record.timezone, status: record.status, custom_attributes: record.custom_attributes }
          form = Contracts::Contact.new(Contracts::Contact::Input.new(**defaults))
          next DomainAccess.failure(:invalid_input, errors: form.errors.messages) unless form.validate(attrs)

          record.assign_attributes(defaults.keys.excluding(:phone).index_with { |key| form.public_send(key) })
          if record.phone_e164 != form.phone_e164
            record.consent_status = "unknown"
            record.consent_changed_at = nil
          end
          record.phone_e164 = form.phone_e164
          record.save!
          Result.success(record)
        end
      rescue ActiveRecord::RecordNotUnique
        DomainAccess.failure(:identity_conflict, field: :phone)
      rescue ActiveRecord::StaleObjectError
        DomainAccess.failure(:stale_edit, field: :lock_version)
      rescue ActiveRecord::RecordInvalid => error
        DomainAccess.failure(:invalid_input, errors: error.record.errors.messages)
      end
    end
  end
end
