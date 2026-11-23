# frozen_string_literal: true

module FlowchartDefinitions
  # JSON Schema of the flowchart fill the assistant LLM emits, plus a
  # prompt fragment (rules, CRUD templates, few-shots). Step-action enum
  # and palette are derived from ActionCatalog.
  class StructureSchema
    SCHEMA_PATH = Pathname.new(__FILE__).sub_ext(".json")
    PROMPT_PATH = Pathname.new(__FILE__).sub_ext(".prompt.txt")

    def self.json
      @json ||= begin
        schema = JSON.parse(SCHEMA_PATH.read)
        action = schema.dig("$defs", "step", "properties", "action")
        if action.is_a?(Hash)
          action["enum"] = Palette.canonical_keys
          action["description"] = "Canonical ActionCatalog step-action key from the palette. Do not invent names."
        end
        schema
      end
    end

    def self.prompt
      format(PROMPT_PATH.read, schema: JSON.pretty_generate(json), palette: Palette.prompt)
    end

    def self.prompt_examples
      PROMPT_PATH.read.scan(/^Output:\n(\{.*\})$/).flatten.map { |raw| JSON.parse(raw) }
    end

    def self.reset!
      @json = nil
    end
  end
end
