# frozen_string_literal: true

module Admin
  class SettingsController < ApplicationController
    dashboard_menu_item :settings

    def show
      @settings_nodes = SettingsContributor.new(settings_dashboard_context).contribute
    end

    private

    def settings_dashboard_context
      DashboardContext.new(
        current_user:      current_user,
        current_customer:  current_customer,
        current_menu_item: :settings,
        request_path:      request.path
      )
    end
  end
end
