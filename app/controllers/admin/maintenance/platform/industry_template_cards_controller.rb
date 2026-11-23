# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      class IndustryTemplateCardsController < ApplicationController
        dashboard_menu_item :maintenance
        before_action :set_industry

        def show
          @templates = PageLayoutTemplates.all
          @mapped_keys = IndustryTemplateMapping.template_keys_for(@industry)
          @category_counts = PageLayoutTemplates.category_counts
          @base_url = admin_maintenance_platform_industry_templates_path(current_customer_id)
          @total_templates = PageLayoutTemplates.keys.size

          render "admin/maintenance/platform/industry_templates/template_cards", layout: false
        end

        private

        def set_industry
          @industry = params[:industry_template_id].to_s
          return if Customer.industries.key?(@industry)

          redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id),
                      alert: t("maint_platform.flash.industry_templates.invalid_industry", industry: @industry)
        end
      end
    end
  end
end
