# frozen_string_literal: true

module Admin
  module Entities
    # An entity's Forms tab: the forms bound to the entity, beside its
    # Entries tab (EntitiesController#show).
    class PagesController < ApplicationController
      dashboard_menu_item :entities
      include PageListing

      def index
        @entity = Entity.where(customer_id: current_customer.id).or(Entity.shared).non_bridge.find(params[:entity_id])
        @entry_count = EntityEntry.where(customer_id: current_customer.id, entity_id: @entity.id).count
        scope = Admin::Pages::BrowseScope.call(customer_id: current_customer.id, entity_ids: [@entity.id])
        @form_count = scope.count
        list_pages(scope)
      end
    end
  end
end
