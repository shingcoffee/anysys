# frozen_string_literal: true

module CodeGenerators
  class GeneratorValidator
    REQUIRED_METADATA = %i[description category version].freeze

    class << self
      def validate_source(source)
        errors = []
        errors.concat(check_syntax(source))
        return errors if errors.any?

        errors.concat(check_interface(source))
        errors.concat(check_metadata(source))
        errors
      end

      private

      def check_syntax(source)
        RubyVM::InstructionSequence.compile(source)
        []
      rescue SyntaxError => e
        ["Syntax error: #{e.message}"]
      end

      def check_interface(source)
        errors = []

        unless source.match?(/<\s*(?:::)?(?:CodeGenerators::)?BaseGenerator\b/)
          errors << "Must inherit from CodeGenerators::BaseGenerator"
        end

        unless source.match?(/def\s+generate_body\b/)
          errors << "Missing required method: generate_body"
        end

        # config_schema auto-provides validate_config via GeneratorInterface.
        unless source.match?(/def\s+validate_config\b/) || source.match?(/config_schema\s+do\b/)
          errors << "Missing required config validation: define validate_config or a config_schema block"
        end

        errors
      end

      def check_metadata(source)
        errors = []

        unless source.match?(/generator_metadata/)
          errors << "Missing generator_metadata block"
          return errors
        end

        REQUIRED_METADATA.each do |field|
          unless source.match?(/^\s+#{field}\s+/)
            errors << "Missing metadata: #{field}"
          end
        end

        errors
      end
    end
  end
end
