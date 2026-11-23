# frozen_string_literal: true

module Platform
  module CodeGenerators
    class IndexComponent < ApplicationComponent
      def initialize(sidebar_data:, filtered_generators:, customer_id:, search_index: [], category: nil, element_type: nil, kind: nil, total_count: 0)
        @sidebar_data = sidebar_data
        @filtered_generators = filtered_generators
        @customer_id = customer_id
        @search_index = search_index
        @category = category
        @element_type = element_type
        @kind = kind
        @total_count = total_count
      end

      def category_label
        if @element_type.present?
          @element_type.titleize
        elsif @category.present?
          I18n.t("comp_platform.code_generators.category.#{@category}")
        else
          @sidebar_data.first&.dig(:label) || I18n.t("comp_platform.code_generators.title")
        end
      end

      def category_icon
        if @element_type.present?
          SidebarComponent::STEP_ACTION_ICONS[@element_type] || SidebarComponent::STEP_ACTION_ICONS.values.first
        elsif @category.present?
          SidebarComponent::STEP_ACTION_ICONS[@category]
        end
      end

      def category_count
        @filtered_generators.size
      end
    end
  end
end
