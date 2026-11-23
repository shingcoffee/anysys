# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  module Captcha
    class ThrottlesController < ApplicationController
      dashboard_menu_item :maintenance

      private

      def redirect_for_throttle(result)
        if result.success?
          redirect_to captcha_resources_path, notice: I18n.t("captcha.throttle.flash_updated")
        else
          redirect_to captcha_resources_path, alert: I18n.t("captcha.throttle.flash_failed")
        end
      end

      # Throttles are edited inline on the captcha Resources surface, so both
      # outcomes land back on the list the operator was looking at.
      def captcha_resources_path
        admin_maintenance_platform_module_settings_captcha_pages_path(current_customer_id)
      end

      def throttle_params
        params.permit(:preset, :limit_count, :period_minutes, :skipped)
      end
    end
  end
end
end
end
