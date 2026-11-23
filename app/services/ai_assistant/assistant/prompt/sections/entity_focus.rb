# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # The entity the workspace preview is pinned to. Naming it lets the
        # admin say "add a phone number" without repeating the entity name, and
        # removes a clarifying question that would otherwise be asked.
        class EntityFocus < Section
          heads "Entity currently open in the workspace"

          private

          def body
            entity = context.focused_entity
            return nil unless entity

            name = plain(entity.name)
            <<~TEXT
              The admin is looking at **#{name}**. Treat an unqualified request ("add a phone
              number", "group these", "make the email required") as a change to this entity, without
              asking which entity is meant. Read it with `get_entity` before `update_entity`, and
              pass `expected_version`.
            TEXT
          end
        end
      end
    end
  end
end
