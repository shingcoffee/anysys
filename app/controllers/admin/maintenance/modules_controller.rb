# frozen_string_literal: true

module Admin
module Maintenance
  class ModulesController < ApplicationController
    dashboard_menu_item :maintenance

    def index
      @available_modules = FeatureModules::Module.available.by_name
      @enabled_module_ids = FeatureModules::CustomerAssignment
        .where(customer_id: current_customer_id)
        .enabled
        .pluck(:feature_module_id)
      @open_links = ::Dashboard::ModuleCards.call(customer: current_customer)
        .to_h { |card| [card.key, card.primary] }
        .compact
      @assignments_by_module_id = FeatureModules::CustomerAssignment
        .where(customer_id: current_customer_id, feature_module_id: @enabled_module_ids)
        .index_by(&:feature_module_id) if current_user.platform_owner?
    end
  end
end
end
