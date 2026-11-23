# frozen_string_literal: true

module Admin
  class DashboardsController < ApplicationController
    dashboard_menu_item :home

    # Admin/owner authorization is enforced by RouteAuthorization for
    # /:cid/admin/* — do not add a duplicate role before_action.
    def show
      @home = ::Dashboard::Home.call(customer: current_customer)
    end
  end
end
