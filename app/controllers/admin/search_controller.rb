# frozen_string_literal: true

module Admin
  class SearchController < ApplicationController
    def index
      q = params[:q].to_s.strip
      groups = SearchQuery.call(
        customer: current_customer, query: q, user: current_user
      )
      render json: { query: q, groups: groups }
    end

    private

    def current_dashboard_menu_item = nil
    helper_method :current_dashboard_menu_item
  end
end
