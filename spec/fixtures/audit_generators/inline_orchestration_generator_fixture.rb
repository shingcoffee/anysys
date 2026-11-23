# frozen_string_literal: true

# Fixture: violates rule 4 — emits TWO ActivitySteps:: calls in one body.

module AuditFixtures
  class InlineOrchestrationGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Inline orchestration fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      <<~RUBY.chomp
        ActivitySteps::DetectAndRouteParams.call(ctx)
        ActivitySteps::PopulatePrimary.call(ctx, model: ctx[:model])
        true
      RUBY
    end

    def validate_config(_cfg)
      []
    end
  end
end
