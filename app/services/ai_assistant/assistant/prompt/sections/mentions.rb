# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # Artifacts the admin named with `@` in this turn. Naming one is the
        # strongest signal of intent available — stronger than the workspace
        # pin and stronger than a name guessed out of the prose — so the model
        # is told to act on it without asking which artifact was meant.
        class Mentions < Section
          heads "Artifacts the admin pointed at"

          private

          def body
            mentions = context.mentions
            return nil if mentions.empty?

            [ listing(mentions), instruction ].join("\n\n")
          end

          def listing(mentions)
            mentions.map { |mention| "- `#{plain(mention.name)}` (existing #{mention.kind})" }.join("\n")
          end

          # The `@` is composer syntax, not part of the name, so it must not
          # travel into a definition the server will match on.
          def instruction
            <<~TEXT
              The admin wrote these with `@` to point at them. Treat them as the subject of this turn
              and update the existing artifact — never create a second one under a similar name, and
              never ask which one was meant. Their current definitions are in the catalog above.
              Strip the `@` when you use a name in a definition or in `reply`.
            TEXT
          end
        end
      end
    end
  end
end
