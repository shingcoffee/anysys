# frozen_string_literal: true

# Fixture: violates rule 2 — emits ctx.foo dotted access instead of ctx[:foo].

module AuditFixtures
  class DottedCtxGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Dotted ctx fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      <<~RUBY.chomp
        ctx.model.save
        true
      RUBY
    end

    def validate_config(_cfg)
      []
    end
  end
end
