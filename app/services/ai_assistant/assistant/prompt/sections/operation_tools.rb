# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class OperationTools < Section
          heads "Operation tools"
          document "operation_tools"

          private

          def body
            return document if context.native_tools?

            [document, json_convention, *operation_listings].join("\n\n")
          end

          def json_convention
            <<~TEXT
              This vendor has no native tools. Call a tool by returning only this JSON object,
              then finish with the final `{"intent","reply"}` envelope after the tool result:

              {"tool": "<name>", "arguments": { ... }}
            TEXT
          end

          def operation_listings
            ops_context = context.operations_context
            Operations.all.filter_map do |operation|
              next unless operation.is_a?(Class) && operation < Operations::Base
              next unless operation.available?(ops_context)

              definition = operation.tool_definition(ops_context)
              <<~TEXT
                ### `#{definition[:name]}`
                #{definition[:description]}

                ```json
                #{json(definition[:parameters])}
                ```
              TEXT
            end
          end
        end
      end
    end
  end
end
