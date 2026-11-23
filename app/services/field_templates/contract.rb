# frozen_string_literal: true

module FieldTemplates
  class Contract < Reform::Form
    property :name
    property :category
    property :description
    property :configuration
    property :customer_id

    validates :name, presence: true, length: { maximum: 100 }
    validates :configuration, presence: true
    validates :category, length: { maximum: 50 }, allow_blank: true
    validate :name_unique_per_customer

    private

    def name_unique_per_customer
      scope = ::FieldTemplate.where(customer_id: customer_id, name: name)
      scope = scope.where.not(id: model.id) if model.persisted?
      errors.add(:name, I18n.t("maint_core.errors.field_templates.name_taken")) if scope.exists?
    end
  end
end
