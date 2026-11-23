# frozen_string_literal: true

# Fixture: passes rule 4 — single ActivitySteps:: call IS the body. Thin wrapper
# is the canonical "one step = one service invocation" shape and is allowed.

module AuditFixtures
  class ThinWrapperGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Thin wrapper fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      <<~RUBY.chomp
        ActivitySteps::SaveAll.call(ctx)
        true
      RUBY
    end

    def validate_config(_cfg)
      []
    end
  end
end
