# frozen_string_literal: true

module Admin
module Settings
module Modules
  module Captcha
    class PagesController < ApplicationController
      dashboard_menu_item :settings

      def update
        page = ::Page.for_current_customer.find(params[:id])
        raise ActiveRecord::RecordNotFound unless page.visible_to?("public")

        result = ::Captcha::Activities::UpdateUrlThrottle.call(
          match_kind: "exact",
          url_pattern: "/#{current_customer_id}/page/#{page.public_uuid}",
          preset: params[:preset],
          limit_count: params[:limit_count],
          period_minutes: params[:period_minutes],
          customer_id: current_customer_id,
          page: page
        )
        if result.success?
          redirect_to admin_settings_modules_captcha_path(current_customer_id),
                      notice: I18n.t("captcha.throttle.flash_updated")
        else
          redirect_to admin_settings_modules_captcha_path(current_customer_id),
                      alert: I18n.t("captcha.throttle.flash_failed")
        end
      end
    end
  end
end
end
end
