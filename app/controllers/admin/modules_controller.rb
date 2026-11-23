# frozen_string_literal: true

module Admin
  class ModulesController < ApplicationController
    dashboard_menu_item :modules

    def index
      @modules = ::Dashboard::ModuleCards.call(customer: current_customer)
    end
  end
end
