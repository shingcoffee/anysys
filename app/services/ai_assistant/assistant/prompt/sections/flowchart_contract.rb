# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class FlowchartContract < Section
          heads "Flowchart output contract"

          private

          def body
            FlowchartDefinitions::StructureSchema.prompt
          end
        end
      end
    end
  end
end
