# frozen_string_literal: true

module Admin
  module Maintenance
    class PageFieldOptionsController < ApplicationController
      include SharedResourceMode
      dashboard_menu_item :maintenance

      def show
        @page = definition_scope(Page).find(params[:page_id])
        field = @page.input_fields.find { |item| item["id"] == params[:field_id] }
        return render json: [], status: :not_found unless field

        render json: field_options(field)
      end

      private

      # The builder previews as an admin of the URL tenant.
      def field_options(field)
        dynamic = field["dynamic_options"]
        return [] unless dynamic.is_a?(Hash)

        case dynamic["options_source"]
        when EntityDefinitions::Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE
          ::Entities::ReferenceOptions.call(entity_id: dynamic["entity_id"], label_field: dynamic["label_field"],
                                            customer_id: current_customer_id, audience: EntityAttributeAudience::ADMIN)
                                      .map { |label, value| { label: label, value: value } }
        when "query"
          PageContentGenerator::DynamicOptionsResolver.new(current_customer_id, audience: EntityAttributeAudience::ADMIN)
                                                      .resolve([field]).first.fetch("options")
        else
          []
        end
      end
    end
  end
end
