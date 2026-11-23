# frozen_string_literal: true

module Admin
  class ModuleHowtosController < ApplicationController
    dashboard_menu_item :modules

    def show
      feature_module = FeatureModules::Module.available_for_customer(current_customer.id).find_by!(key: params[:module_key])
      @module_card = ::Dashboard::ModuleCards.call(customer: current_customer).find { |card| card.key == feature_module.key }
      contributions = feature_module.registration_class.sidebar_contributions(
        ::DashboardContext.new(current_user: current_user, current_customer: current_customer,
                               current_menu_item: :modules, request_path: request.path)
      )
      @settings_links = Array(contributions[:settings]).filter_map do |item|
        next unless item.to_sidebar_node(menu_item: :settings, module_key: feature_module.key,
                                         customer_id: current_customer.id).permitted_for?(current_user)

        ::Dashboard::Link.new(
          label: item.label,
          href: item.href_for(menu_item: :settings, module_key: feature_module.key, customer_id: current_customer.id)
        )
      end
    end
  end
end
