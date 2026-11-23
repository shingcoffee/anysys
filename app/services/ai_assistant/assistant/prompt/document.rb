# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      # Loader for the static markdown that backs prompt sections.
      #
      # Prompt prose is deliberately NOT in config/locales: it is a machine
      # contract, not user-facing copy, and translating it would hand the model
      # a different brief depending on which locale the admin happens to be
      # browsing in. The admin's language is honoured by instructing the model
      # to reply in it, not by rewriting the instructions.
      module Document
        ROOT = Pathname.new(__dir__).join("documents")
        EXTENSION = ".md"

        class Missing < StandardError; end

        class << self
          # @param name [String, Symbol] file basename without extension
          # @return [String] the document contents
          def read(name)
            cache[name.to_s] ||= load(name.to_s)
          end

          def reset!
            @cache = nil
          end

          def path_for(name)
            ROOT.join("#{name}#{EXTENSION}")
          end

          private

          def cache
            @cache ||= {}
          end

          def load(name)
            path = path_for(name)
            raise Missing, "prompt document not found: #{path}" unless path.file?

            path.read.strip.freeze
          end
        end
      end
    end
  end
end
