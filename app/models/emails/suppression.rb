# frozen_string_literal: true

module Emails
  # Email suppression (bounce/complaint) ledger. Keyed on the lower-cased email
  # so case variations can't slip past suppression. NOT TenantScoped: rows are
  # written from provider webhooks without a tenant context. customer_id NULL =
  # global (all tenants on the shared sending domain); set = one tenant.
  class Suppression < ApplicationRecord
    self.table_name = "email_suppressions"

    REASONS = %w[hard_bounce complaint unsubscribe manual].freeze

    validates :email, presence: true

    scope :for_customer, ->(cid) { where(customer_id: cid) }

    def self.normalize(email) = email.to_s.strip.downcase

    def self.suppressed?(customer_id:, email:)
      where(email: normalize(email)).where(customer_id: [nil, customer_id]).exists?
    end

    def self.record_global!(email:, reason:, provider: nil)
      upsert_row(customer_id: nil, email: normalize(email), reason: reason, provider: provider)
    end

    def self.record_for_customer!(customer_id:, email:, reason:, provider: nil)
      upsert_row(customer_id: customer_id, email: normalize(email), reason: reason, provider: provider)
    end

    def self.upsert_row(customer_id:, email:, reason:, provider:)
      find_or_create_by!(customer_id: customer_id, email: email) do |s|
        s.reason   = reason
        s.provider = provider
      end
    rescue ActiveRecord::RecordNotUnique
      find_by(customer_id: customer_id, email: email)
    end
  end
end
