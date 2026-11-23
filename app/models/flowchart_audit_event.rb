# frozen_string_literal: true

class FlowchartAuditEvent < ApplicationRecord
  include TenantScoped

  belongs_to :flowchart, optional: true
  belongs_to :actor_user, class_name: "Authentication::User", optional: true, foreign_key: :actor_user_id

  validates :customer_id, :event_type, presence: true
end
