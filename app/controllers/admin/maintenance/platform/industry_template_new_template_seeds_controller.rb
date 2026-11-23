# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      class IndustryTemplateNewTemplateSeedsController < ApplicationController
        dashboard_menu_item :maintenance

        def create
          count = IndustryTemplateMappingSeeder.seed_new_templates!
          redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id),
                      notice: t("maint_platform.flash.industry_templates.new_mappings_created", count: count)
        end
      end
    end
  end
end
