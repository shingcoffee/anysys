# frozen_string_literal: true

module FlowchartDefinitions
  # Turns an LLM flowchart definition into a canvas configuration plus identity.
  class Normalizer
    IDENTITY_KEYS = %w[id shared status uuid entity_id current_version].freeze
    ELEMENT_IDENTITY_KEYS = %w[customer_id shared status uuid entity_id current_version].freeze
    ELEMENT_LAYOUT_KEYS = %w[id type label x y width height properties steps].freeze
    ELEMENT_SIZE = { "width" => 100, "height" => 45 }.freeze
    ORIGIN_X = 400
    ORIGIN_Y = 80
    ROW_GAP = 100
    CANVAS_SIZE = { "width" => 2000, "height" => 1500 }.freeze

    Result = Struct.new(:name, :description, :configuration, :errors, keyword_init: true) do
      def ok? = errors.empty?
    end

    def self.call(definition)
      new(definition).call
    end

    def initialize(definition)
      @definition = definition
      @errors = []
    end

    def call
      unless @definition.is_a?(Hash)
        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_not_an_object")
        return Result.new(errors: @errors)
      end

      row = @definition.deep_stringify_keys.except(*IDENTITY_KEYS)
      if row.key?("customer_id")
        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_forbidden_identity")
        return Result.new(errors: @errors)
      end

      elements = Array(row["elements"]).map.with_index { |element, index| normalize_element(element, index) }
      connections = Array(row["connections"]).map.with_index { |connection, index| normalize_connection(connection, index) }
      configuration = ProcessSplitter.call(
        "elements" => elements,
        "connections" => connections,
        "metadata" => {
          "canvas" => CANVAS_SIZE,
          "created_at" => Time.current.iso8601,
          "source" => "assistant"
        }
      )

      Result.new(
        name: row["name"].to_s.strip,
        description: row["description"].to_s,
        configuration: configuration,
        errors: @errors
      )
    end

    private

    def normalize_element(element, index)
      unless element.is_a?(Hash)
        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_not_an_object")
        return {}
      end

      element = element.deep_stringify_keys.except(*ELEMENT_IDENTITY_KEYS)
      properties = element["properties"].is_a?(Hash) ? element["properties"].deep_stringify_keys : {}
      properties = properties.merge(element.except(*ELEMENT_LAYOUT_KEYS))
      properties = UiConfigSchema.defaults_for(element["type"].to_s).merge(properties)
      steps = element["steps"] || properties["steps"]
      properties["steps"] = Array(steps).map { |step| normalize_step(step) } if element["type"].to_s == "process" || steps.present?

      {
        "id" => element["id"].presence || "el_#{index + 1}",
        "type" => element["type"].to_s,
        "x" => element.key?("x") ? element["x"] : ORIGIN_X,
        "y" => element.key?("y") ? element["y"] : ORIGIN_Y + (index * ROW_GAP),
        "width" => element["width"].presence || ELEMENT_SIZE["width"],
        "height" => element["height"].presence || ELEMENT_SIZE["height"],
        "label" => element["label"].presence || default_element_label(element["type"]),
        "properties" => properties
      }
    end

    def normalize_step(step)
      unless step.is_a?(Hash)
        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_not_an_object")
        return {}
      end

      step = step.deep_stringify_keys
      raw_action = step["action"].to_s
      action = Palette.canonical_key(raw_action) || raw_action
      labels = Array(step["selectionLabels"]).presence || (action.present? ? [Palette.human_label(action)] : [])
      config = step["config"].is_a?(Hash) ? step["config"].deep_stringify_keys : {}
      {
        "action" => action,
        "config" => UiConfigSchema.defaults_for(action).merge(config),
        "selectionLabels" => labels
      }
    end

    def default_element_label(type)
      key = "flowchart_elements.#{type}.defaultLabel"
      return I18n.t(key) if I18n.exists?(key, I18n.locale, fallback: false)

      type.to_s.capitalize
    end

    def normalize_connection(connection, index)
      unless connection.is_a?(Hash)
        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_not_an_object")
        return {}
      end

      connection = connection.deep_stringify_keys
      {
        "id" => connection["id"].presence || "c_#{index + 1}",
        "from" => connection["from"].to_s,
        "to" => connection["to"].to_s,
        "fromPosition" => connection["fromPosition"].presence || "bottom",
        "toPosition" => connection["toPosition"].presence || "top",
        "label" => connection["label"],
        "matchValue" => connection["matchValue"]
      }.compact
    end
  end
end
