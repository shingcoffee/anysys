# frozen_string_literal: true

class FlowchartNotification < ApplicationRecord
  include TenantScoped

  belongs_to :user, class_name: "Authentication::User"
  belongs_to :page, optional: true

  validates :customer_id, :user_id, presence: true
end
