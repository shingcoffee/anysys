# frozen_string_literal: true

module AuditFixtures
  class RaisingVariantGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Raises for one audited configuration variant"
      category :fixtures
      version "1.0.0"
    end

    config_schema do
      enum :mode, %w[safe explode]
    end

    def self.sample_input
      { "mode" => "safe" }
    end

    def generate_body
      raise ArgumentError, "intentional explode variant" if config["mode"] == "explode"

      "true"
    end
  end
end
