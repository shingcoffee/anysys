# frozen_string_literal: true

module Sms
  module Audience
    class DeleteSegment
      def self.call(customer:, actor:, segment:)
        return DomainAccess.failure(:forbidden) unless DomainAccess.actor_allowed?(customer, actor)
        return DomainAccess.failure(:not_found) unless segment.is_a?(Segment) && DomainAccess.scoped?(customer, segment)

        DomainAccess.synchronize(customer) do
          record = Segment.for_customer(customer.id).lock.find(segment.id)
          if Sms::Campaign.for_customer(customer.id).where(segment_id: record.id, status: "draft").exists?
            next dependency_failure
          end
          record.destroy!
          Result.success(record)
        end
      rescue ActiveRecord::RecordNotFound
        DomainAccess.failure(:not_found)
      rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::RecordNotDestroyed
        dependency_failure
      end

      def self.dependency_failure
        Result.failure(:segment_in_use, errors: { base: [I18n.t("sms_campaign_http.errors.segment_in_use")] })
      end
      private_class_method :dependency_failure
    end
  end
end
