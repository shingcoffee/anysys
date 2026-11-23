# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      class IndustryTemplateDefaultSeedsController < ApplicationController
        dashboard_menu_item :maintenance

        def create
          count = IndustryTemplateMappingSeeder.seed_defaults!
          redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id),
                      notice: t("maint_platform.flash.industry_templates.defaults_seeded", count: count)
        end

        def destroy
          IndustryTemplateMappingSeeder.seed_all!
          redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id),
                      notice: t("maint_platform.flash.industry_templates.reset_to_defaults")
        end
      end
    end
  end
end
