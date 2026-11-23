# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class PendingProposal < Section
          heads "Proposal waiting for approval"
          document "pending_proposal"
          MAX_INPUT_CHARS = 8_000
          LINE_SEPARATORS = /[\u2028\u2029]/
          LONG_INPUT_NOTE = "(The input is too long to repeat here. Call get_entity and rebuild the change from the plan the admin saw.)"

          private

          def body
            proposal = context.pending_operation_proposal
            return nil unless proposal

            [document, "Tool: `#{plain(proposal["operation"])}`", input_block(proposal["input"])].join("\n\n")
          end

          # The input is model-authored. JSON escapes newlines inside strings
          # and the Unicode line separators are escaped here, so every line
          # starts with JSON punctuation and no value can close the fence or
          # open a heading of its own. (script_safe would also turn "/" into
          # "\/", which garbles formulas and URLs for the model.)
          def input_block(input)
            serialized = JSON.pretty_generate(input).gsub(LINE_SEPARATORS) { |char| format("\\u%04x", char.ord) }
            return LONG_INPUT_NOTE if serialized.length > MAX_INPUT_CHARS

            "```json\n#{serialized}\n```"
          end
        end
      end
    end
  end
end
