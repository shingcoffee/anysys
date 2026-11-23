# frozen_string_literal: true

module Admin
  module Maintenance
    class EntityTemplatePreviewsController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance

      def show
        @entity = definition_scope(Entity).find(params[:entity_id])

        unless @entity.referenced_template.present?
          redirect_to admin_maintenance_entity_path(current_customer_id, @entity), alert: t("maint_core.flash.entity_template_previews.no_template")
          return
        end

        ref_data = begin
          parsed = JSON.parse(@entity.referenced_template)
          parsed.with_indifferent_access if parsed.is_a?(Hash)
        rescue JSON::ParserError, TypeError
          nil
        end

        unless valid_reference_shape?(ref_data)
          redirect_to admin_maintenance_entity_path(current_customer_id, @entity), alert: t("maint_core.flash.entity_template_previews.invalid_template")
          return
        end

        built = TemplatePreviewBuilder.call(customer: current_customer, ref_data: ref_data, entity: @entity)
        @page = built[:page]
        @content = built[:content]
        @form_action = "#"

        render template: "admin/maintenance/pages/preview", layout: "template_preview"
      end

      private

      def valid_reference_shape?(reference)
        return false unless reference && reference[:key].is_a?(String) && reference[:key].present?
        return true unless reference.key?(:preview_rows)

        rows = reference[:preview_rows]
        rows.is_a?(Array) && rows.all? { |row| row.is_a?(Array) && row.all? { |element| element.is_a?(Hash) } }
      end
    end
  end
end
