# frozen_string_literal: true

module AuditFixtures
  class NilBodyGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Allows the generator interface to omit a body"
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
      nil
    end
  end
end
