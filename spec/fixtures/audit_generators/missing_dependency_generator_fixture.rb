# frozen_string_literal: true

# Fixture: violates rule 8 — body reads ctx[:contract] but dependencies is empty.

module AuditFixtures
  class MissingDependencyGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Missing dependency fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      <<~RUBY.chomp
        ctx[:contract].save
        true
      RUBY
    end

    def validate_config(_cfg)
      []
    end

    def dependencies
      []
    end
  end
end
