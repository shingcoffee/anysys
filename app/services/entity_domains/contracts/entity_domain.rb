# frozen_string_literal: true

require "reform/form"

module EntityDomains
  module Contracts
    class EntityDomain < Reform::Form
      property :name
      property :description
      property :color

      validates :name, presence: true, length: { maximum: 100 }
      validates :description, length: { maximum: 500 }
      validates :color, inclusion: { in: ::EntityDomain::COLORS }

      validate :name_uniqueness

      private

      def name_uniqueness
        return if name.blank?

        scope = ::EntityDomain.for_customer(model.customer_id).where("LOWER(name) = ?", name.downcase)
        scope = scope.where.not(id: model.id) if model.persisted?
        errors.add(:name, I18n.t("maint_core.entity_domains.errors.name_taken")) if scope.exists?
      end
    end
  end
end
