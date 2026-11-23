# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # When a reply that wrote nothing may hand the turn to the flowchart
        # pass. Only the platform owner has that pass, so the section drops for
        # everyone else.
        class FlowchartHandoff < Section
          heads "Handing a turn to the flowchart designer"
          document "flowchart_handoff"

          private

          def body
            document if context.flowchart_visible?
          end
        end
      end
    end
  end
end
