# frozen_string_literal: true

require "ruby_llm"

module AiAssistant
  module Assistant
    module Tools
      # Native ruby_llm adapter backed by the current assistant tool session.
      class GeneratePageTool < RubyLLM::Tool
        description "Generate and automatically launch an Admin-only form page from an existing entity in this tenant. Reuse an existing page for the same entity version without changing its launch state."
        param :entity_name, desc: "Name of the entity to generate a page for."

        def initialize(session:)
          @session = session
        end

        def name = "generate_page"

        def execute(entity_name:)
          @session.call("generate_page", "entity_name" => entity_name)
        end
      end
    end
  end
end
