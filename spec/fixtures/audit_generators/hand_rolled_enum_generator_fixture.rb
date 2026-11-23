# frozen_string_literal: true

# Fixture: violates rule 7 — uses %w[...].include?(...) inside generate_body
# instead of fetch_enum.

module AuditFixtures
  class HandRolledEnumGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Hand-rolled enum fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      raw = config["strategy"]
      strategy = %w[save save!].include?(raw) ? raw : "save"
      "ctx[:model].#{strategy}\ntrue"
    end

    def validate_config(_cfg)
      []
    end
  end
end
