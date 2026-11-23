# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # What an entity is and everything it drives once saved. Without this
        # the model treats an entity as a bare list of columns and under-models
        # the domain.
        class EntityPlatform < Section
          heads "What an entity is in Anysys"
          document "entity_platform"

          # Exact capability bullet from entity_platform.md. A document edit that
          # moves the bullet fails the tenant-admin prompt spec instead of
          # silently leaking the word through a regex miss.
          FLOWCHART_CAPABILITY = <<~MD
            - **Flowcharts.** Every form page is bound to one flowchart that processes its submissions: it
              validates, saves the record and runs any side effects. New pages use the shared "Save page record" flowchart.
          MD

          private

          def body
            text = document
            return text if context.flowchart_visible?

            text.sub(FLOWCHART_CAPABILITY, "")
          end
        end
      end
    end
  end
end
