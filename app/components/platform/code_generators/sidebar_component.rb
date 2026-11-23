# frozen_string_literal: true

module Platform
  module CodeGenerators
    class SidebarComponent < ApplicationComponent
      # Display order: primary flowchart elements first, then secondary
      PRIMARY_ORDER = %w[start decision loop end].freeze

      # Only the five registered element types are ever rendered
      # (GeneratorRegistry::SUPPORTED_ELEMENT_TYPES). Unsupported structural
      # types were dropped here together with their unreachable generators.
      # Unknown keys fall back to a neutral dot in #element_type_dot.
      ELEMENT_TYPE_DOTS = {
        "start" => "bg-green-500", "end" => "bg-red-500", "decision" => "bg-amber-500",
        "loop" => "bg-cyan-500",
        "subflow" => "bg-purple-500"
      }.freeze

      STEP_ACTION_ICONS = {
        "model_operations" => "M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7",
        "validation" => "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z",
        "data_operations" => "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15",
        "communication" => "M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z",
        "security" => "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z",
        "background" => "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
        "file_operations" => "M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z",
        "realtime" => "M13 10V3L4 14h7v7l9-11h-7z",
        "response" => "M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6",
        "concurrency" => "M8 7h12m-12 5h12m-12 5h12M4 7h.01M4 12h.01M4 17h.01",
        "service_invocation" => "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4",
        "caching" => "M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8",
        "resilience" => "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
        "scheduling_time" => "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
        "workflow" => "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4",
        "finance" => "M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z",
        "utility" => "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
      }.freeze

      def initialize(sidebar_data:, customer_id:, search_index: [], active_category: nil, active_element_type: nil, total_count: 0)
        @sidebar_data = sidebar_data
        @customer_id = customer_id
        @search_index = search_index
        @active_category = active_category
        @active_element_type = active_element_type
        @total_count = total_count
      end

      def search_index_json
        @search_index.to_json
      end

      def element_types
        @sidebar_data.select { |item| item[:kind] == "element_type" }
      end

      # Primary element types in display order: start, decision, loop, end
      def primary_element_types
        PRIMARY_ORDER.filter_map { |key| element_types.find { |item| item[:key] == key } }
      end

      # Secondary element types: everything not in PRIMARY_ORDER
      def secondary_element_types
        element_types.reject { |item| PRIMARY_ORDER.include?(item[:key]) }.sort_by { |item| item[:label] }
      end

      def step_action_categories
        @sidebar_data.select { |item| item[:kind] == "step_action" }
      end

      def step_action_total_count
        step_action_categories.sum { |item| item[:count] }
      end

      def process_active?
        @active_category.present?
      end

      def secondary_active?
        secondary_element_types.any? { |item| active?(item) }
      end

      def active?(item)
        if item[:kind] == "element_type"
          @active_element_type == item[:key]
        else
          @active_category == item[:key]
        end
      end

      def item_url(item)
        if item[:kind] == "element_type"
          helpers.admin_maintenance_platform_code_generators_path(@customer_id, element_type: item[:key])
        else
          helpers.admin_maintenance_platform_code_generators_path(@customer_id, category: item[:key], kind: "step_action")
        end
      end

      def dot_color(key)
        ELEMENT_TYPE_DOTS[key] || "bg-gray-400"
      end

      def step_action_icon(key)
        STEP_ACTION_ICONS[key] || "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
      end

      def render_element_type_link(item)
        is_active = active?(item)
        link_classes = "flex items-center gap-2.5 px-3 py-1.5 rounded-md text-sm transition-colors " +
          (is_active ? "bg-indigo-50 text-indigo-700 font-medium" : "text-gray-600 hover:bg-gray-50 hover:text-gray-900")
        count_classes = "ml-auto text-[10px] flex-shrink-0 " +
          (is_active ? "text-indigo-500 bg-indigo-100 px-1.5 rounded-full" : "text-gray-400")

        content_tag(:a, href: item_url(item),
                    data: { generator_nav_target: "link", action: "click->generator-nav#activate" },
                    class: link_classes) do
          safe_join([
            content_tag(:span, "", class: "w-1.5 h-1.5 rounded-full flex-shrink-0 #{dot_color(item[:key])}"),
            content_tag(:span, item[:label], class: "truncate"),
            content_tag(:span, item[:count], class: count_classes)
          ])
        end
      end
    end
  end
end
