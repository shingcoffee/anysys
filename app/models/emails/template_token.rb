# frozen_string_literal: true

module Emails
  # Catalog row for an insertable email-template token.
  # Platform rows (customer_id NULL) are shared and read-only for tenants.
  # Custom rows bind to a customer entity attribute; recipient EntityEntry
  # resolution is deferred (render blank until User↔entry linkage exists).
  class TemplateToken < ApplicationRecord
    self.table_name = "email_template_tokens"

    SOURCE_PLATFORM = "platform_field"
    SOURCE_ENTITY   = "entity_attribute"
    SOURCE_TYPES    = [SOURCE_PLATFORM, SOURCE_ENTITY].freeze

    UUID_REGEXP = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    belongs_to :customer, optional: true
    belongs_to :entity, optional: true

    before_validation :assign_uuid, on: :create
    before_validation :normalize_platform_row
    before_validation :normalize_custom_row

    validates :uuid, presence: true, uniqueness: true, format: { with: UUID_REGEXP }
    validates :label, presence: true, length: { maximum: 100 }
    validates :source_type, inclusion: { in: SOURCE_TYPES }
    validate :platform_shape
    validate :custom_shape
    validate :attribute_slug_on_entity
    validate :entity_belongs_to_customer

    scope :platform, -> { where(customer_id: nil, source_type: SOURCE_PLATFORM) }
    scope :custom_for, ->(customer_id) {
      where(customer_id: customer_id, source_type: SOURCE_ENTITY)
    }
    # Return ids via two simple queries — SQLite can raise planner errors on
    # OR-combined relations against the partial unique indexes on this table.
    def self.accessible_for(customer_id)
      ids = platform.pluck(:id) + custom_for(customer_id).pluck(:id)
      where(id: ids)
    end

    def platform?
      customer_id.nil? && source_type == SOURCE_PLATFORM
    end

    def custom?
      source_type == SOURCE_ENTITY && customer_id.present?
    end

    # Source keys identify platform fields even when older rows retain legacy labels.
    def display_label
      return label unless platform?

      key = label.to_s
      source_label = "email.template_tokens.platform.#{source_key}"
      if source_key.present? && I18n.exists?(source_label)
        translated = I18n.t(source_label)
        return translated if translated.is_a?(String)
      end

      attr = key.split(".", 2).last.to_s
      common = "common.labels.#{attr}"
      if source_key.to_s.start_with?("authentication_user.", "customer.") && attr.present? && I18n.exists?(common)
        return I18n.t(common)
      end

      readable = (key.presence || source_key.to_s).tr("._-", " ").squish.titleize
      return I18n.t("email.template_tokens.unknown_label") if readable.blank?

      I18n.t("email.template_tokens.unknown_platform_label", label: readable)
    end

    private

    def assign_uuid
      self.uuid = SecureRandom.uuid if uuid.blank?
    end

    def normalize_platform_row
      return unless source_type == SOURCE_PLATFORM

      self.customer_id = nil
      self.entity_id = nil
      self.attribute_slug = nil
    end

    def normalize_custom_row
      return unless source_type == SOURCE_ENTITY

      self.source_key = nil
    end

    def platform_shape
      return unless source_type == SOURCE_PLATFORM

      errors.add(:source_key, :blank) if source_key.blank?
      errors.add(:customer_id, :present) if customer_id.present?
      errors.add(:entity_id, :present) if entity_id.present?
      errors.add(:attribute_slug, :present) if attribute_slug.present?
    end

    def custom_shape
      return unless source_type == SOURCE_ENTITY

      errors.add(:customer_id, :blank) if customer_id.blank?
      errors.add(:entity_id, :blank) if entity_id.blank?
      errors.add(:attribute_slug, :blank) if attribute_slug.blank?
      errors.add(:source_key, :present) if source_key.present?
    end

    def attribute_slug_on_entity
      return unless custom? && entity.present? && attribute_slug.present?

      slugs = Array(entity.property_schema_json).filter_map { |a| a["name_slug"].presence || a[:name_slug].presence }
      return if slugs.include?(attribute_slug)

      errors.add(:attribute_slug, I18n.t("email.template_tokens.errors.unknown_attribute"))
    end

    def entity_belongs_to_customer
      return unless custom? && customer_id.present? && entity_id.present?
      unless entity
        errors.add(:entity_id, I18n.t("email.template_tokens.errors.entity_not_accessible"))
        return
      end
      return if entity.customer_id == customer_id
      return if entity.shared?

      errors.add(:entity_id, I18n.t("email.template_tokens.errors.entity_not_accessible"))
    end
  end
end
