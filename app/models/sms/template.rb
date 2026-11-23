# frozen_string_literal: true

module Sms
  # A vendor-agnostic SMS template. `provider_template_codes` maps each vendor to
  # its approved template identifier (Aliyun TemplateCode, Twilio Content SID),
  # so one logical template can be sent through any configured vendor.
  class Template < ApplicationRecord
    self.table_name = "sms_templates"

    STATUSES = %w[active retired].freeze
    PURPOSES = %w[transactional marketing].freeze

    has_many :sms_messages, dependent: :restrict_with_exception,
                            class_name: "Sms::Message",
                            foreign_key: :sms_template_id

    validates :key, presence: true, uniqueness: true,
                    format: { with: /\A[a-z0-9_]+\z/ }
    validates :status, inclusion: { in: STATUSES }
    validate  :variables_is_array_of_strings
    validate  :provider_codes_present
    validate  :preview_contract

    scope :active, -> { where(status: "active") }
    scope :marketing, -> { where(purpose: "marketing") }

    def required_vars = Array(variables)

    def active? = status == "active"
    def marketing? = purpose == "marketing"

    def provider_codes = provider_template_codes || {}

    # The vendor-specific template identifier for a given provider key.
    def provider_code(provider)
      provider_codes[provider.to_s].presence
    end

    private

    def preview_contract
      form = Sms::Contracts::TemplatePreview.new(self)
      return if form.validate(purpose: purpose, body_template: body_template, variables: variables)

      form.errors.messages.each { |field, messages| messages.each { |message| errors.add(field, message) } }
    end

    def variables_is_array_of_strings
      list = variables
      return if list.is_a?(Array) && list.all? { |v| v.is_a?(String) }

      errors.add(:variables, I18n.t("maint_platform.errors.validations.variables_must_be_array_of_strings"))
    end

    def provider_codes_present
      return if provider_codes.is_a?(Hash) && provider_codes.values.any? { |v| v.to_s.present? }

      errors.add(:provider_template_codes, I18n.t("maint_platform.errors.validations.sms_provider_codes_required"))
    end
  end
end
