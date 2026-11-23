# frozen_string_literal: true

module PageBuilder
  class ToolbarComponent < ApplicationComponent
    def initialize(page:, customer_id:, selected_entity: nil)
      @page = page
      @customer_id = customer_id
      @selected_entity = selected_entity
    end

    private

    attr_reader :page, :customer_id, :selected_entity

    def back_path
      helpers.admin_maintenance_pages_path(customer_id)
    end

    def entity_path
      return nil unless selected_entity
      helpers.admin_maintenance_entity_path(customer_id, selected_entity)
    end

    def preview_path
      helpers.admin_maintenance_page_preview_path(customer_id, page)
    end
  end
end
