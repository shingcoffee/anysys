# frozen_string_literal: true

require "reform/form"

module Journeys
  module Contracts
    class Journey < Reform::Form
      property :name
      property :key
      property :description
      property :entity_domain_id
      property :definition
      property :visible_audiences, virtual: true

      validates :name, presence: true, length: { maximum: 120 }
      validates :key, format: { with: PageVisibility::ACTION_KEY }

      validate :key_uniqueness
      validate :domain_accessible
      validate :audiences_present
      validate :definition_valid

      private

      def key_uniqueness
        return if key.blank?

        scope = ::Journey.for_customer(model.customer_id).where(key: key)
        scope = scope.where.not(id: model.id) if model.persisted?
        errors.add(:key, I18n.t("errors.messages.taken")) if scope.exists?
      end

      def domain_accessible
        if entity_domain_id.blank?
          errors.add(:base, I18n.t("maint_core.entity_domains.errors.domain_required"))
        elsif !::EntityDomain.for_customer(model.customer_id).exists?(id: entity_domain_id)
          errors.add(:base, I18n.t("maint_core.entity_domains.errors.domain_unavailable"))
        end
      end

      def audiences_present
        errors.add(:base, I18n.t("journeys.launch.errors.audiences_blank")) if Array(visible_audiences).empty?
      end

      def definition_valid
        Journeys::Definition.new(definition).errors.each { |message| errors.add(:base, message) }
      end
    end
  end
end
