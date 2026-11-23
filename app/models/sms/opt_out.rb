# frozen_string_literal: true

module Sms
  # SMS opt-out (suppression) ledger. Keyed on the E.164 phone so prefix
  # variations can't slip past suppression.
  #
  # NOT TenantScoped: rows are written from provider webhooks (inbound STOP)
  # without a tenant context. Because SMS credentials are platform-global (one
  # vendor account serves every tenant), an inbound STOP creates a GLOBAL row
  # (customer_id NULL) that suppresses the number for all tenants; a tenant may
  # also hold its own row (customer_id set) for a manual suppression.
  class OptOut < ApplicationRecord
    self.table_name = "sms_opt_outs"

    validates :phone_e164, presence: true

    # Global rows (nil) apply to every tenant; tenant rows apply to that tenant.
    scope :for_customer, ->(cid) { where(customer_id: [nil, cid]) }

    # Rows a tenant admin may SEE on the opt-out list: its own manual rows, plus
    # global rows ONLY for numbers this tenant has actually messaged. Without the
    # latter restriction a tenant could enumerate the platform-wide STOP list —
    # including numbers only OTHER tenants ever texted (cross-tenant PII). This
    # narrows visibility only; suppression at send time stays global via
    # `opted_out?`, which still consults every global row.
    scope :visible_to_customer, ->(cid, messaged_phones) do
      where(customer_id: cid).or(where(customer_id: nil, phone_e164: messaged_phones))
    end

    def self.opted_out?(customer_id:, phone_e164:)
      phone = Sms::PhoneNumber.normalize(phone_e164)
      return false unless phone

      where(phone_e164: phone).where(customer_id: [nil, customer_id]).exists?
    end

    def self.record_global!(phone_e164:, provider: nil, reason: nil)
      upsert_row(customer_id: nil, phone_e164: phone_e164, provider: provider, reason: reason)
    end

    def self.record_for_customer!(customer_id:, phone_e164:, provider: nil, reason: nil)
      upsert_row(customer_id: customer_id, phone_e164: phone_e164, provider: provider, reason: reason)
    end

    def self.upsert_row(customer_id:, phone_e164:, provider:, reason:)
      phone_e164 = Sms::PhoneNumber.normalize(phone_e164)
      raise ArgumentError, I18n.t("sms_standards.errors.invalid_phone") unless phone_e164

      find_or_create_by!(customer_id: customer_id, phone_e164: phone_e164) do |o|
        o.provider = provider
        o.reason   = reason
      end
    rescue ActiveRecord::RecordNotUnique
      find_by(customer_id: customer_id, phone_e164: phone_e164)
    end
  end
end
