# frozen_string_literal: true

module CodeGenerators
  # Connection fields for the property editor. Label and notes only — priority
  # is not a stored or generated setting.
  class ConnectionSchema
    class << self
      def schema
        @schema ||= ConfigSchema.new(action_name: "connection", i18n_prefix: "flowchart_elements").tap do |instance|
          instance.literal :label,
            description: "Text shown on the arrow. On a Decision branch it names the outcome (Yes, No, Approved)."
          instance.literal :description, multiline: true,
            description: "Optional notes for people reading the flowchart; never affects the run."
        end
      end
    end
  end
end
