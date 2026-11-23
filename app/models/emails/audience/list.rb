# frozen_string_literal: true

module Emails
  module Audience
    class List < ApplicationRecord
      self.table_name = "email_lists"

      include TenantScoped

      LIST_TYPES = %w[static dynamic].freeze

      has_many :send_activity_lists, class_name: "Emails::SendActivities::SendActivityList",
                                     foreign_key: :email_list_id,
                                     dependent: :restrict_with_exception
      has_many :email_send_activities, through: :send_activity_lists,
                                       class_name: "Emails::SendActivities::SendActivity"
      has_many :list_memberships, class_name: "Emails::Audience::ListMembership",
                                  foreign_key: :email_list_id,
                                  dependent: :destroy
      has_many :users, through: :list_memberships

      validates :customer_id, presence: true
      validates :name,        presence: true
      validates :list_type,   inclusion: { in: LIST_TYPES }

      def dynamic? = list_type == "dynamic"
      def static? = list_type == "static"

      # Static lists use explicit memberships; dynamic lists evaluate segment_rules
      # against tenant users at send/count time.
      def audience
        if static?
          users
        else
          Emails::Audience::SegmentQuery.call(customer: customer, rules: segment_rules)
        end
      end

      def audience_count
        audience.count
      end
    end
  end
end
