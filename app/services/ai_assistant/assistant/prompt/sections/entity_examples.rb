# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class EntityExamples < Section
          heads "Worked examples"
          document "entity_examples"

          private

          def body = document
        end
      end
    end
  end
end
