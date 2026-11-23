# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class Clarifying < Section
          heads "Asking questions and stating assumptions"
          document "clarifying"

          private

          def body = document
        end
      end
    end
  end
end
