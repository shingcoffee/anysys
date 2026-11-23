# frozen_string_literal: true

module Sms
  module Audience
    class Preview
      MAX_AUDIENCE = 10_000

      def self.call(customer:, rules:, at: Time.current)
        return DomainAccess.failure(:invalid_rules, field: :segment_rules) unless SegmentQuery.valid?(customer: customer, rules: rules)
        relation = SegmentQuery.call(customer: customer, rules: rules)
        matched = relation.limit(MAX_AUDIENCE + 1).count
        return DomainAccess.failure(:audience_too_large) if matched > MAX_AUDIENCE

        eligible, excluded, samples = 0, Hash.new(0), []
        relation.find_each(batch_size: 100) do |contact|
          decision = Contacts::Eligibility.call(customer: customer, contact: contact, at: at)
          decision[:eligible] ? eligible += 1 : excluded[decision[:reason]] += 1
          if samples.size < 5
            samples << { contact_id: contact.id, name: contact.name, phone_e164: contact.phone_e164,
              consent_status: contact.consent_status, **decision }
          end
        end
        Result.success(matched_count: matched, eligible_count: eligible, excluded_counts: excluded.to_h,
          samples: samples, evaluated_at: at)
      end
    end
  end
end
