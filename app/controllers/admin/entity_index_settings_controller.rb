# frozen_string_literal: true

module Admin
  class EntityIndexSettingsController < ApplicationController
    dashboard_menu_item :entities

    def update
      entity = Entity.where(customer_id: current_customer.id).or(Entity.shared).find(params[:entity_id])
      result = EntityIndexSettings::Operation::Update.call(
        customer: current_customer,
        entity: entity,
        params: params.require(:entity_index_setting).permit(visible_column_keys: [])
      )

      if result.success?
        redirect_to admin_entity_path(current_customer.id, entity),
                    notice: t("admin_misc.entities.index_setting.updated")
      else
        redirect_to admin_entity_path(current_customer.id, entity),
                    alert: result.errors[:base].presence&.to_sentence ||
                           result.errors.full_messages.to_sentence
      end
    end
  end
end
