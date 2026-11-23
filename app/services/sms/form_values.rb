# frozen_string_literal: true

module Sms
  class FormValues
    def self.for(record, kind:)
      RequestAttributes::INPUTS.fetch(kind).to_h do |field|
        value = if (mapping = RequestAttributes::JSON_FIELDS[field])
          JSON.pretty_generate(record.public_send(mapping.first) || {})
        elsif field == :phone
          record.phone_e164
        elsif field == :scheduled_local
          record.scheduled_at&.in_time_zone(record.timezone)&.strftime("%Y-%m-%dT%H:%M")
        else
          record.public_send(field)
        end
        [field, value]
      end
    end

    def self.consent
      { action: "granted", occurred_at: Time.current.iso8601, reference: "", statement: "", notes: "", event_key: SecureRandom.uuid }
    end

    def self.entity_sync
      { country_code: "CN", timezone: "Asia/Shanghai", attribute_map_json: "{}", after_entry_id: 0 }
    end
  end
end
