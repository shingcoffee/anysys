# frozen_string_literal: true

module Sms
  module Contacts
    class SyncEntity
      BATCH_SIZE = 100

      def self.call(customer:, actor:, attributes:, preview: false)
        return DomainAccess.failure(:forbidden) unless DomainAccess.actor_allowed?(customer, actor)
        attrs = DomainAccess.attributes(attributes, Contracts::EntitySync::FIELDS)
        return DomainAccess.failure(:invalid_input) unless attrs
        source_id = DomainAccess.integer(attrs[:entity_id])
        return DomainAccess.failure(:invalid_source, field: :entity_id) unless source_id&.positive?

        sources = EntitySources.new(customer: customer)
        source = sources.find(source_id)
        form = Contracts::EntitySync.new(Contracts::EntitySync::Input.new(country_code: "CN", attribute_map: {}, after_entry_id: 0))
        form.source_fields = sources.fields(source_id)
        return DomainAccess.failure(:invalid_input, errors: form.errors.messages) unless form.validate(attrs)

        new(customer: customer, source: source, form: form, preview: preview).call
      rescue ActiveRecord::RecordNotFound
        DomainAccess.failure(:not_found, field: :entity_id)
      end

      def initialize(customer:, source:, form:, preview:)
        @customer, @source, @form, @preview = customer, source, form, preview
        @planned_phones, @planned_sources = {}, {}
      end

      def call
        scope = EntityEntry.for_customer(@customer.id).where(entity_id: @source.id)
        through = DomainAccess.integer(@form.through_entry_id) || scope.maximum(:id) || 0
        after = DomainAccess.integer(@form.after_entry_id)
        batch = scope.where(id: (after + 1)..through).order(:id).limit(BATCH_SIZE).to_a
        result = { preview: @preview, scanned: batch.size, created: 0, updated: 0, unchanged: 0,
          invalid: 0, conflicts: 0, items: [], next_after_entry_id: batch.last&.id,
          through_entry_id: through, has_more: batch.any? && scope.where(id: (batch.last.id + 1)..through).exists? }
        batch.each do |entry|
          item = process_safely(entry)
          result[item[:outcome] == :conflict ? :conflicts : item[:outcome]] += 1
          result[:items] << item
        end
        Result.success(result)
      end

      private

      def process_safely(entry)
        @preview ? process(entry) : DomainAccess.synchronize(@customer) { process(entry) }
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError
        # Rescue AFTER the per-item savepoint rolls back; PostgreSQL cannot
        # continue using a transaction after a failed uniqueness statement.
        item(entry, nil, :conflict, :identity_conflict)
      rescue ActiveRecord::RecordInvalid => error
        conflict = error.record.errors.details[:phone_e164].any? { |detail| detail[:error] == :taken }
        item(entry, error.record, conflict ? :conflict : :invalid, conflict ? :identity_conflict : :invalid_source_data)
      end

      def process(entry)
        data = entry.data_json
        return item(entry, nil, :invalid, :invalid_source_data) unless data.is_a?(Hash)
        phone = PhoneNumber.normalize(data[@form.phone_field], country: @form.country_code)
        return item(entry, nil, :invalid, :invalid_phone) unless phone

        contacts = Sms::Contact.for_customer(@customer.id)
        linked = @planned_sources[entry.id] || contacts.find_by(source_entity_id: @source.id, source_entry_id: entry.id)
        by_phone = @planned_phones[phone] || contacts.find_by(phone_e164: phone)
        if @preview && by_phone && (planned = @planned_sources[by_phone.source_entry_id]) && planned.phone_e164 != phone
          by_phone = nil
        end
        if linked && by_phone && !same_contact?(linked, by_phone)
          return item(entry, linked, :conflict, :identity_conflict)
        end
        record = linked || by_phone || Sms::Contact.new(customer: @customer)
        if !linked && (record.source_entity_id || record.source_entry_id)
          return item(entry, record, :conflict, :source_conflict)
        end

        record.lock! if record.persisted? && !@preview
        return item(entry, record, :invalid, :invalid_source_data) unless record.custom_attributes.is_a?(Hash)
        attrs = record.custom_attributes.dup
        @form.attribute_map.each { |key, field| attrs[key] = data[field] }
        name = @form.name_field.present? ? data[@form.name_field] : record.name
        return item(entry, record, :invalid, :invalid_name) unless name.nil? || Contracts::Bounds.scalar?(name)
        name = name.to_s unless name.nil?
        validator = Contracts::Contact.new(Contracts::Contact::Input.new)
        values = { phone: phone, name: name, country_code: @form.country_code, timezone: @form.timezone.presence,
          status: record.status, custom_attributes: attrs }
        return item(entry, record, :invalid, :invalid_source_data) unless validator.validate(values)

        fresh = record.new_record?
        old_phone = record.phone_e164
        changes = values.except(:phone).merge(phone_e164: phone, source_kind: "entity",
          source_entity_id: @source.id, source_entry_id: entry.id, source_mapping: @form.mapping)
        changed = changes.any? { |key, value| record.public_send(key) != value }
        record.assign_attributes(changes)
        if old_phone != phone
          record.consent_status = "unknown"
          record.consent_changed_at = nil
        end
        record.synced_at = Time.current
        if @preview
          @planned_phones.delete(old_phone) if old_phone != phone
          @planned_phones[phone] = record
          @planned_sources[entry.id] = record
        else
          record.save!
        end
        item(entry, record, fresh ? :created : (changed ? :updated : :unchanged))
      end

      def same_contact?(left, right)
        left.equal?(right) || (left.persisted? && right.persisted? && left.id == right.id)
      end

      def item(entry, contact, outcome, error_code = nil)
        { entry_id: entry.id, contact_id: contact&.id, outcome: outcome, error_code: error_code }
      end
    end
  end
end
