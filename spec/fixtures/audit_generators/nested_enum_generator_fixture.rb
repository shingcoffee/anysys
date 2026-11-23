# frozen_string_literal: true

module AuditFixtures
  class NestedEnumGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Nested enum fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      build_fragment(config["strategy"])
    end

    def validate_config(cfg)
      %w[ignored validation values].include?(cfg["strategy"])
      []
    end

    private

    def build_fragment(raw)
      [raw].each do
        <<~RUBY
          end
        RUBY
      end

      strategy = %w[save save!].include?(raw) ? raw : "save"
      "ctx[:model].#{strategy}\ntrue"
    end
  end
end
