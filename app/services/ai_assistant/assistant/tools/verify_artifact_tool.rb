# frozen_string_literal: true

require "ruby_llm"

module AiAssistant
  module Assistant
    module Tools
      # Native ruby_llm adapter backed by the current assistant tool session.
      class VerifyArtifactTool < RubyLLM::Tool
        description "Verify an entity, page, or website page artifact in this tenant."
        param :kind, desc: "One of entity, page, or website_page."
        param :id, desc: "Database id of the artifact."

        def initialize(session:)
          @session = session
        end

        def name = "verify_artifact"

        def execute(kind:, id:)
          @session.call("verify_artifact", "kind" => kind, "id" => id)
        end
      end
    end
  end
end
