# frozen_string_literal: true

module AuditFixtures
  class InvalidBodyTypeGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Returns an invalid non-nil body type"
      category :fixtures
      version "1.0.0"
    end

    config_schema do
      enum :mode, %w[safe]
    end

    def self.sample_input
      { "mode" => "safe" }
    end

    def generate_body
      { invalid: true }
    end
  end
end
