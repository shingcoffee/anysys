# frozen_string_literal: true

module Admin
  module Maintenance
    class EntityRestorationsController < BaseRestorationsController
      restorable finder: -> { deleted_definition_scope(Entity).find(params[:entity_id]) },
                 redirect: -> { admin_maintenance_entities_url(current_customer_id) },
                 flash_key: "maint_core.flash.entity_restorations.restored"

      private

      # Forms taken offline when the entity was trashed stay offline.
      def restored_notice(record)
        names = Page.accessible.for_entity(record.id).where(launched: false).by_name.pluck(:name)
        return super if names.empty?

        "#{super} #{t('maint_core.flash.entity_restorations.offline_forms', names: names.to_sentence)}"
      end
    end
  end
end
