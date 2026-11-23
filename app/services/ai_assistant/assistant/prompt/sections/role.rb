# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class Role < Section
          heads "Role"
          document "role"

          private

          def body = document
        end
      end
    end
  end
end
