# frozen_string_literal: true

module Sms
  module Audience
    class SaveSegment
      def self.call(customer:, actor:, segment: nil, attributes:)
        return DomainAccess.failure(:forbidden) unless DomainAccess.actor_allowed?(customer, actor)
        return DomainAccess.failure(:not_found) if segment && !DomainAccess.scoped?(customer, segment)
        attrs = DomainAccess.attributes(attributes, Contracts::Segment::FIELDS)
        return DomainAccess.failure(:invalid_input) unless attrs

        DomainAccess.synchronize(customer) do
          record = segment ? Segment.for_customer(customer.id).lock.find(segment.id) : Segment.new(customer: customer)
          if segment && DomainAccess.integer(attrs[:lock_version]) != record.lock_version
            next DomainAccess.failure(:stale_edit, field: :lock_version)
          end
          form = Contracts::Segment.new(record)
          form.customer = customer
          next DomainAccess.failure(:invalid_input, errors: form.errors.messages) unless form.validate(attrs)
          record.assign_attributes(name: form.name, description: form.description, segment_rules: form.segment_rules)
          record.save!
          Result.success(record)
        end
      rescue ActiveRecord::StaleObjectError
        DomainAccess.failure(:stale_edit, field: :lock_version)
      rescue ActiveRecord::RecordInvalid => error
        DomainAccess.failure(:invalid_input, errors: error.record.errors.messages)
      end
    end
  end
end
