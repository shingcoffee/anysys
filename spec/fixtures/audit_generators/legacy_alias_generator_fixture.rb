# frozen_string_literal: true

# Fixture: violates rule 5 — reads config["primaryKey"] || config["legacyKey"].

module AuditFixtures
  class LegacyAliasGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Legacy alias fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      strategy = config["strategy"] || config["saveStrategy"]
      "ctx[:result] = #{strategy.inspect}\ntrue"
    end

    def validate_config(_cfg)
      []
    end
  end
end
