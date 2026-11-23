# frozen_string_literal: true

module FlowchartElements
  class BaseElementComponent < ApplicationComponent
    attr_reader :element_type, :label, :element_id, :position, :properties

    def initialize(element_type:, label: nil, element_id: nil, position: {}, properties: {}, **html_attributes)
      @element_type = element_type
      @label = label || default_label
      @element_id = element_id || "element_#{SecureRandom.hex(4)}"
      @position = position
      @properties = properties
      @html_attributes = html_attributes
    end

    private

    def default_label
      element_type.to_s.humanize
    end

    def base_classes
      "flowchart-element border rounded-lg px-2 py-2.5 text-sm font-medium cursor-grab active:cursor-grabbing hover:shadow-md transition-all duration-150 select-none text-center"
    end

    def element_classes
      "#{base_classes} #{element_specific_classes}"
    end

    def element_specific_classes
      # To be overridden by specific element types
      ""
    end

    def html_attributes
      base_attrs = {
        id: element_id,
        class: element_classes,
        data: {
          element_type: element_type,
          element_id: element_id,
          label: label,
          "drag-source" => true,
          "flowchart-element" => element_type
        }
      }

      merge_html_attributes(base_attrs, @html_attributes || {})
    end

    def data_attributes
      {
        "drag-source" => true,
        "flowchart-element" => element_type
      }
    end

    def icon_classes
      "w-4 h-4 flex-shrink-0"
    end

    def label_classes
      "text-[10px] leading-tight truncate w-full text-center"
    end

    # SVG icons for different element types
    def start_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M8 5v14l11-7z"
      end
    end

    def end_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M6 6h12v12H6z"
      end
    end

    def process_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M3 5h18v14H3z"
      end
    end

    def decision_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M12 2l10 10-10 10L2 12z"
      end
    end

    def loop_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", class: icon_classes do
        safe_join([
          content_tag(:path, "", d: "M4 12a8 8 0 0 1 8-8h1", 'stroke-width': "2", 'stroke-linecap': "round"),
          content_tag(:path, "", d: "M20 12a8 8 0 0 1-8 8h-1", 'stroke-width': "2", 'stroke-linecap': "round"),
          content_tag(:path, "", d: "M17 8l-4-4 4-4", 'stroke-width': "2", 'stroke-linecap': "round", 'stroke-linejoin': "round", fill: "none"),
          content_tag(:path, "", d: "M7 16l4 4-4 4", 'stroke-width': "2", 'stroke-linecap': "round", 'stroke-linejoin': "round", fill: "none")
        ])
      end
    end

    def connector_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :circle, "", cx: "12", cy: "12", r: "8"
      end
    end

    def document_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"
      end
    end

    def database_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M12 1C8.5 1 5.8 2.1 5.8 3.5v17C5.8 21.9 8.5 23 12 23s6.2-1.1 6.2-2.5v-17C18.2 2.1 15.5 1 12 1z"
      end
    end

    def manual_process_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M3 5h18v10c0 2-2 4-4 4H7c-2 0-4-2-4-4V5z"
      end
    end

    def delay_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10S17.5 2 12 2zm5 11h-6V7h2v4h4v2z"
      end
    end

    def preparation_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M7 3l5 2 5-2v14l-5 2-5-2V3z"
      end
    end

    def display_icon
      content_tag :svg, viewBox: "0 0 24 24", fill: "currentColor", class: icon_classes do
        content_tag :path, "", d: "M3 5h14c2 0 4 2 4 4v6c0 2-2 4-4 4H3c-2 0-4-2-4-4V9c0-2 2-4 4-4z"
      end
    end

    # Render the appropriate icon for this element type
    def render_icon
      case element_type.to_s
      when "start" then start_icon
      when "end" then end_icon
      when "process" then process_icon
      when "decision" then decision_icon
      when "loop" then loop_icon
      when "connector" then connector_icon
      when "document" then document_icon
      when "database" then database_icon
      when "manual_process" then manual_process_icon
      when "delay" then delay_icon
      when "preparation" then preparation_icon
      when "display" then display_icon
      else process_icon # Default fallback
      end
    end
  end
end
