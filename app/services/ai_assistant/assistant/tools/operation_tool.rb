# frozen_string_literal: true

require "ruby_llm"

module AiAssistant
  module Assistant
    module Tools
      # One ruby_llm adapter for any registered operation. Name, description
      # and params_schema come from the operation; execute goes through Session.
      class OperationTool < RubyLLM::Tool
        def initialize(session:, operation:)
          @session = session
          @operation = operation
        end

        def name
          @operation.key
        end

        def description
          @operation.summary
        end

        def params_schema
          @params_schema ||= @operation.tool_definition(@session.operation_context)[:parameters]
        end

        def execute(**args)
          JSON.generate(@session.call(@operation.key, args))
        end
      end
    end
  end
end
