# frozen_string_literal: true

module Admin
  module Maintenance
    class PageModuleDataController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance

      def show
        @page          = definition_scope(Page).find(params[:page_id])
        module_id      = params[:module_id]
        modules_config = @page.configuration_json["modules"] || []
        unless modules_config.is_a?(Array)
          return render json: { error: t("maint_core.errors.page_modules.invalid") }, status: :unprocessable_entity
        end

        mod_config = modules_config.find { |m| m.is_a?(Hash) && m["id"] == module_id }
        return render json: { error: t("maint_core.errors.page_modules.not_found") }, status: :not_found unless mod_config

        renderer = CompositePageRenderer.new([mod_config], customer_id: current_customer_id, params: {
          page:      params[:page],
          sort:      params[:sort],
          direction: params[:direction]
        })
        result = renderer.render_modules.first
        unless result && result[:module_type] == "list"
          return render json: { error: t("maint_core.errors.page_modules.not_a_list") }, status: :unprocessable_entity
        end

        render json: {
          records:    Array(result[:records]).map { |r| r.as_json.merge(r.data_json) },
          pagination: result[:pagination],
          columns:    result[:columns]
        }
      end
    end
  end
end
