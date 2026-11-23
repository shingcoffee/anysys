# frozen_string_literal: true

module Sms
  module Campaigns
    class DraftInput
      ALLOWED = (Contracts::Draft::FIELDS + %i[lock_version scheduled_local]).freeze
      INTEGERS = %i[template_id segment_id quiet_hours_start quiet_hours_end frequency_window_hours
                    send_rate_per_minute deadline_hours lock_version].freeze

      def self.build(customer:, campaign:, attributes:)
        attrs = Sms::DomainAccess.attributes(attributes, ALLOWED)
        return [nil, Support.failure(:invalid_input)] unless attrs
        attrs = attrs.deep_dup
        INTEGERS.each do |field|
          next unless attrs.key?(field)
          value = attrs[field]
          if %i[template_id segment_id].include?(field) && value == ""
            attrs[field] = nil
          elsif value.is_a?(String) && value.match?(/\A\d{1,18}\z/)
            attrs[field] = value.to_i
          elsif !value.nil? && !value.is_a?(Integer)
            return [nil, Support.failure(:invalid_input, field: field)]
          end
        end
        draft = Sms::Campaign.new(campaign.attributes.slice(*Contracts::Draft::FIELDS.map(&:to_s)))
        draft.customer_id = customer.id
        draft.assign_attributes(attrs.except(:lock_version, :scheduled_local))
        if attrs.key?(:scheduled_local)
          local = attrs[:scheduled_local]
          draft.scheduled_at = Schedule.parse(local: local, timezone: draft.timezone)
          if local.present? && draft.scheduled_at.nil?
            return [nil, Support.failure(:schedule_invalid, field: :scheduled_local)]
          end
        end
        contract = Contracts::Draft.new(draft)
        contract.customer = customer
        valid = contract.validate(draft.attributes.slice(*Contracts::Draft::FIELDS.map(&:to_s)))
        [contract, valid ? nil : Support.failure(:invalid_input, errors: contract.errors.messages)]
      end
    end
  end
end
