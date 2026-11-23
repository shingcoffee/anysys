# frozen_string_literal: true

require "ruby_llm"

module AiAssistant
  module Assistant
    module Tools
      # Native ruby_llm adapter backed by the current assistant tool session.
      class ListCatalog < RubyLLM::Tool
        description "List this tenant's entities, its launched form pages (action key, audiences, entity and the processing each uses) and the form processing its pages can use, by name."

        def initialize(session:)
          @session = session
        end

        def name = "list_catalog"

        def execute
          @session.call("list_catalog", {})
        end
      end
    end
  end
end
