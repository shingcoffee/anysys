# frozen_string_literal: true

module Admin
  class MaintenancesController < ApplicationController
    dashboard_menu_item :maintenance

    def show
      request.cookies.delete("sidebar_state_maintenance")
      cookies.delete("sidebar_state_maintenance", path: "/")
    end
  end
end
