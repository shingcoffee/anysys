# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      # One heading-delimited block of the system prompt.
      #
      # Subclasses declare a `heading` and implement `#body`. Static wording
      # lives in a sibling markdown document (see {Document}) so prose can be
      # edited without touching Ruby; anything derived from a registry or from
      # the tenant is composed in `#body`.
      #
      # A section that returns a blank body is dropped from the prompt, which
      # is how optional context (focused entity, empty catalog) opts out.
      class Section
        class << self
          attr_reader :heading

          # @param text [String] the `##` heading rendered above the body.
          def heads(text)
            @heading = text
          end

          # Names the markdown document backing this section.
          def document(name)
            @document_name = name
          end

          attr_reader :document_name
        end

        def initialize(context)
          @context = context
        end

        def render
          content = body.to_s.strip
          return nil if content.empty?

          "## #{self.class.heading}\n\n#{content}"
        end

        private

        attr_reader :context

        def body
          raise NotImplementedError, "#{self.class.name} must implement #body"
        end

        # The markdown document declared with `document`, as a String.
        def document
          Document.read(self.class.document_name)
        end

        def json(value)
          JSON.generate(value)
        end

        # Artifact names are tenant input and sections quote them into
        # markdown. Flattening one keeps a name carrying a newline, a `##` or a
        # backtick from posing as prompt structure of its own.
        def plain(text)
          text.to_s.delete("`#").gsub(/[[:space:]]+/, " ").strip
        end
      end
    end
  end
end
