# frozen_string_literal: true

module AuditFixtures
  class ValidationErrorVariantGenerator < CodeGenerators::BaseGenerator
    class << self
      attr_accessor :generated_modes
    end

    self.generated_modes = []

    generator_metadata do
      description "Rejects one audited configuration variant"
      category :fixtures
      version "1.0.0"
    end

    config_schema do
      enum :mode, %w[safe invalid]
    end

    def self.sample_input
      { "mode" => "safe" }
    end

    def validate_config(candidate)
      return [] unless candidate["mode"] == "invalid"

      ["mode is invalid", "required value is missing"]
    end

    def generate_body
      self.class.generated_modes << config["mode"]
      return "Marshal.load(payload)" if config["mode"] == "invalid"

      "true"
    end
  end
end
