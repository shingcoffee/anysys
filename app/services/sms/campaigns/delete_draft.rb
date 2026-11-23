# frozen_string_literal: true

module Sms
  module Campaigns
    class DeleteDraft
      def self.call(customer:, actor:, campaign:)
        return Support.failure(:forbidden) unless Support.actor_allowed?(customer, actor)
        return Support.failure(:not_found) unless campaign.is_a?(Sms::Campaign) && Support.scoped?(customer, campaign)

        Sms::DomainAccess.synchronize(customer) do
          record = Sms::Campaign.for_customer(customer.id).lock.find(campaign.id)
          unless record.status == "draft" && !Sms::CampaignRecipient.for_customer(customer.id).where(campaign_id: record.id).exists?
            next retained_failure
          end
          record.destroy!
          Support.success(record)
        end
      rescue ActiveRecord::RecordNotFound
        Support.failure(:not_found)
      rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::RecordNotDestroyed
        retained_failure
      end

      def self.retained_failure
        Support.failure(:not_draft, errors: { base: [I18n.t("sms_campaign_http.errors.not_draft")] })
      end
      private_class_method :retained_failure
    end
  end
end
