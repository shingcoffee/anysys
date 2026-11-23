# frozen_string_literal: true

module FlowchartDefinitions
  # Semantic checks the JSON Schema cannot express: identity, registered
  # actions, graph shape.
  class GraphValidator
    Result = Struct.new(:errors, keyword_init: true) do
      def ok? = errors.empty?
    end

    def self.call(normalized:, customer:)
      new(normalized: normalized, customer: customer).call
    end

    def initialize(normalized:, customer:)
      @normalized = normalized
      @customer = customer
      @errors = []
    end

    def call
      @errors.concat(Array(@normalized.errors))
      validate_identity
      validate_elements
      validate_connections
      Result.new(errors: @errors)
    end

    private

    def validate_identity
      if @normalized.name.blank?
        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_name_blank")
      end
      reject_deleted_name
    end

    def reject_deleted_name
      return if @normalized.name.blank? || @customer.blank?

      existing = Flowchart.unscoped.where(customer_id: @customer.id, name: @normalized.name).first
      return unless existing&.deleted?

      @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_inactive", name: existing.name)
    end

    def validate_elements
      if elements.empty?
        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_elements_blank")
        return
      end

      ids = []
      types = []
      elements.each do |element|
        unless element.is_a?(Hash)
          @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_not_an_object")
          next
        end
        id = element["id"].to_s
        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_element_id_blank") if id.blank?
        ids << id
        type = element["type"].to_s
        types << type
        unless Palette::ELEMENT_TYPES.include?(type)
          @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_unknown_element_type", value: type)
        end
        validate_process_steps(element) if type == "process"
      end

      @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_duplicate_element_ids") if ids.uniq.size != ids.size
      start_count = types.count("start")
      @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_missing_start") if start_count.zero?
      @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_multiple_starts") if start_count > 1
      @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_missing_end") unless types.include?("end")
    end

    def validate_process_steps(element)
      steps = Array(element.dig("properties", "steps"))
      if steps.empty?
        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_steps_blank")
        return
      end

      steps.each do |step|
        action = step.is_a?(Hash) ? step["action"].to_s : ""
        if action.blank?
          @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_action_blank")
          next
        end
        next if Palette.known_action?(action)

        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_unknown_action", value: action)
      end
    end

    def validate_connections
      ids = elements.filter_map { |element| element["id"].to_s if element.is_a?(Hash) }.to_set
      start_ids = elements.filter_map { |element|
        element["id"].to_s if element.is_a?(Hash) && element["type"].to_s == "start"
      }.to_set

      connections.each do |connection|
        unless connection.is_a?(Hash)
          @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_not_an_object")
          next
        end
        %w[from to].each do |key|
          target = connection[key].to_s
          next if ids.include?(target)

          @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_unknown_endpoint", value: target)
        end
        next unless start_ids.include?(connection["to"].to_s)

        @errors << I18n.t("ai_assistant.assistant.apply_errors.flowchart_start_has_incoming")
      end
    end

    def elements
      @elements ||= Array(@normalized.configuration && @normalized.configuration["elements"])
    end

    def connections
      @connections ||= Array(@normalized.configuration && @normalized.configuration["connections"])
    end
  end
end
