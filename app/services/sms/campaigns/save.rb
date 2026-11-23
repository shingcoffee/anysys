# frozen_string_literal: true

module Sms
  module Campaigns
    class Save
      def self.call(customer:, actor:, campaign: nil, attributes:)
        return Support.failure(:forbidden) unless Support.actor_allowed?(customer, actor)
        return Support.failure(:not_found) if campaign && !Support.scoped?(customer, campaign)
        return Support.failure(:module_disabled) unless Support.enabled?(customer)
        attrs = Sms::DomainAccess.attributes(attributes, DraftInput::ALLOWED)
        return Support.failure(:invalid_input) unless attrs

        Quota.synchronize(customer) do
          campaign&.lock!
          next Support.failure(:not_draft) if campaign && campaign.status != "draft"
          if campaign && Sms::DomainAccess.integer(attrs[:lock_version]) != campaign.lock_version
            next Support.failure(:stale_edit)
          end
          record = campaign || Sms::Campaign.new(customer: customer, created_by_id: actor.id)
          contract, failure = DraftInput.build(customer: customer, campaign: record, attributes: attrs)
          next failure if failure

          record.assign_attributes(contract.model.attributes.slice(*Contracts::Draft::FIELDS.map(&:to_s)))
          record.save!
          Support.success(record)
        end
      rescue ActiveRecord::StaleObjectError
        Support.failure(:stale_edit)
      rescue ActiveRecord::RecordInvalid => error
        Support.failure(:invalid_input, errors: error.record.errors.messages)
      end
    end
  end
end
