# frozen_string_literal: true

module Sms
  class Contact < ApplicationRecord
    include TenantScoped
    self.table_name = "sms_contacts"

    STATUSES = %w[active archived].freeze
    CONSENT_STATUSES = %w[unknown granted revoked].freeze
    SOURCE_KINDS = %w[manual entity].freeze

    belongs_to :source_entity, class_name: "Entity", optional: true
    belongs_to :source_entry, class_name: "EntityEntry", optional: true
    has_many :consent_events, class_name: "Sms::ConsentEvent", dependent: :restrict_with_exception
    has_many :campaign_recipients, class_name: "Sms::CampaignRecipient", dependent: :restrict_with_exception
    has_many :messages, class_name: "Sms::Message", dependent: :restrict_with_exception

    validates :customer_id, :phone_e164, presence: true
    validates :phone_e164, uniqueness: { scope: :customer_id }
    validates :status, inclusion: { in: STATUSES }
    validates :consent_status, inclusion: { in: CONSENT_STATUSES }
    validates :source_kind, inclusion: { in: SOURCE_KINDS }
    validates_with Sms::TenantReferences, attributes: %i[source_entity source_entry], shared: %i[source_entity], source_pair: true

    scope :active, -> { where(status: "active") }
    def active? = status == "active"
    def archived? = status == "archived"
  end
end
