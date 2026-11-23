# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class PageProcessing < Section
          heads "What happens when a form is submitted"
          document "page_processing"

          private

          def body = document
        end
      end
    end
  end
end
