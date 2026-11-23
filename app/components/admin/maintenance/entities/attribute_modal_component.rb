# frozen_string_literal: true

module Admin
  module Maintenance
    module Entities
      # Full "Add Attribute" modal for the entity form. Self-contained — every
      # interactive element is wired to the surrounding `entity-form` Stimulus
      # controller via `data-entity-form-target` / `data-action` attributes.
      # The only external dependency is `HtmlTypeOptions.grouped_html_types`,
      # called directly on the class module (no instance state required).
      class AttributeModalComponent < ApplicationComponent
        AUDIENCE_KEYS = %w[admin member public].freeze

        def initialize(entity: nil, person_entity_ids: nil)
          @entity = entity
          @person_entity_ids = person_entity_ids
        end

        def audience_rows
          AUDIENCE_KEYS.map do |key|
            {
              key: key,
              visibility_target: "modalVisibility#{key.camelize}",
              editable_target: "modalEditable#{key.camelize}",
              apply_target: "modalValidatorApply#{key.camelize}",
              label: I18n.t("comp_admin.attribute_modal.#{key}")
            }
          end
        end

        # Hidden on the entity being edited when it is a person or a bridge.
        # The switch itself still only appears after JS sees a
        # person-entity target in the reference picker.
        def show_owner_toggle?
          @entity.nil? || (!@entity.bridge_entity? && !@entity.person?)
        end

        def person_entity_ids
          return Array(@person_entity_ids) unless @person_entity_ids.nil?

          self.class.person_entity_ids_for(lookup_customer_id)
        end

        def person_entity_ids_json
          person_entity_ids.to_json
        end

        def self.person_entity_ids_for(customer_id)
          return [] if customer_id.blank?

          Entity.with_deleted
                .where(customer_id: [ customer_id, nil ].uniq)
                .where(extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)
                .where.not(category: :bridge)
                .pluck(:id)
        end

        private

        def lookup_customer_id
          @entity&.customer_id.presence || Current.customer_id
        end
      end
    end
  end
end
