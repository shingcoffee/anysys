# frozen_string_literal: true

module Sms
  class Campaign < ApplicationRecord
    include TenantScoped
    self.table_name = "sms_campaigns"

    STATUSES = %w[draft scheduled running completed cancelled failed].freeze
    SEND_TIMINGS = %w[immediate scheduled].freeze
    TERMINAL_STATUSES = %w[completed cancelled failed].freeze

    belongs_to :template, class_name: "Sms::Template", optional: true
    belongs_to :segment, class_name: "Sms::Audience::Segment", optional: true
    belongs_to :created_by, class_name: "Authentication::User"
    belongs_to :launched_by, class_name: "Authentication::User", optional: true
    has_many :recipients, class_name: "Sms::CampaignRecipient", dependent: :restrict_with_exception
    has_many :messages, class_name: "Sms::Message", dependent: :restrict_with_exception

    validates :customer_id, :name, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :send_timing, inclusion: { in: SEND_TIMINGS }
    validates_with Sms::TenantReferences, attributes: %i[segment created_by launched_by], actors: %i[created_by launched_by]
    before_destroy :retain_launched_campaign, prepend: true

    scope :draft, -> { where(status: "draft") }
    def draft? = status == "draft"

    private

    def retain_launched_campaign
      return if draft? && launched_at.nil?

      errors.add(:base, I18n.t("sms_audience.errors.campaign_retained"))
      throw :abort
    end
  end
end
