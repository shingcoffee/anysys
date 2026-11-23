# frozen_string_literal: true

# Fixture: a clean generator that passes ALL mechanical audit rules.
# Used by spec/scripts/audit_generators_spec.rb as the positive baseline.

module AuditFixtures
  class CleanGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Clean fixture generator"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      target = fetch_with_default("resultVar", "model")
      <<~RUBY.chomp
        ctx[:#{target}] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])
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
