# frozen_string_literal: true

module Emails
  module Audience
    class ListMembership < ApplicationRecord
      self.table_name = "email_list_memberships"

      belongs_to :email_list, class_name: "Emails::Audience::List"
      belongs_to :user, class_name: "Authentication::User"

      validates :user_id, uniqueness: { scope: :email_list_id }
    end
  end
end
