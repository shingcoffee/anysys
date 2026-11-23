# frozen_string_literal: true

module Sms
  module Audience
    class Segment < ApplicationRecord
      include TenantScoped
      self.table_name = "sms_segments"

      has_many :draft_campaigns, -> { where(status: "draft") }, class_name: "Sms::Campaign",
        foreign_key: :segment_id, dependent: :restrict_with_exception
      has_many :campaigns, class_name: "Sms::Campaign", dependent: :nullify
      validates :customer_id, :name, presence: true
    end
  end
end
