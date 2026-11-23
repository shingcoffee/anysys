# frozen_string_literal: true

module Sms
  class CampaignRecipient < ApplicationRecord
    include TenantScoped
    self.table_name = "sms_campaign_recipients"

    STATUSES = %w[pending admitted skipped cancelled].freeze
    SKIP_REASONS = %w[contact_archived phone_changed consent_missing opted_out personalization_missing
      frequency_capped campaign_cancelled campaign_failed campaign_expired module_disabled template_invalid
      credentials_missing daily_cap_exceeded rate_limited].freeze
    DEFERRAL_REASONS = %w[quiet_hours campaign_rate account_rate daily_cap phone_window].freeze

    belongs_to :campaign, class_name: "Sms::Campaign"
    belongs_to :contact, class_name: "Sms::Contact"
    belongs_to :message, class_name: "Sms::Message", optional: true
    validates :customer_id, :phone_e164, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :skip_reason, inclusion: { in: SKIP_REASONS }, allow_nil: true
    validates :deferral_reason, inclusion: { in: DEFERRAL_REASONS }, allow_nil: true
    validates_with Sms::TenantReferences, attributes: %i[campaign contact message]
  end
end
