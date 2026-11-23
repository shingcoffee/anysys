# frozen_string_literal: true

module Admin
  module Maintenance
    module Entities
      # Segmented links across the entities area: the domain workspace
      # (entities and journeys per domain) and the flat table.
      class ViewSwitchComponent < ApplicationComponent
        VIEWS = %i[domains table].freeze

        def initialize(current:, customer_id:)
          @current = current.to_sym
          @customer_id = customer_id
        end

        def views
          VIEWS.map { |view| { label: t("maint_core.entity_domains.views.#{view}"), path: path(view), active: view == @current } }
        end

        private

        def path(view)
          view == :table ? helpers.admin_maintenance_entities_path(@customer_id, view: "table") : helpers.admin_maintenance_entities_path(@customer_id)
        end
      end
    end
  end
end
