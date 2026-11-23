# frozen_string_literal: true

module Emails
  module SendActivities
    class SendActivityList < ApplicationRecord
      self.table_name = "email_send_activity_lists"

      belongs_to :send_activity, class_name: "Emails::SendActivities::SendActivity",
                                 foreign_key: :email_send_activity_id,
                                 inverse_of: :send_activity_lists
      belongs_to :email_list, class_name: "Emails::Audience::List"

      validates :email_list_id, uniqueness: { scope: :email_send_activity_id }
      validate :email_list_same_tenant
      validate :email_lists_within_limit

      private

      def email_list_same_tenant
        return if send_activity.nil? || email_list.nil?
        return if send_activity.customer_id == email_list.customer_id

        errors.add(:email_list, I18n.t("admin_modules.errors.validations.cross_tenant_association"))
      end

      def email_lists_within_limit
        return if send_activity.nil? || email_list.nil?

        # Exclude self so assigning exactly MAX lists does not fail while each
        # in-memory join is validated against a collection that already includes it.
        sibling_count = send_activity.send_activity_lists.count { |join| !join.equal?(self) }
        return if sibling_count < SendActivity::MAX_EMAIL_LISTS

        errors.add(
          :email_list,
          I18n.t("admin_modules.emails.send_activities.errors.lists_too_many", max: SendActivity::MAX_EMAIL_LISTS)
        )
      end
    end
  end
end
