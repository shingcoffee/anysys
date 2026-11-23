# frozen_string_literal: true

require "rails_helper"
require "support/generator_conformance"
require "support/generator_branch_variants"

# One enum at a time, including visibleWhen anchors; not a Cartesian product.
# Explicit validation rejections are excluded, exceptions always fail the example.
RSpec.describe "generated activity branch emission" do
  CodeGenerators::GeneratorRegistry.step_action_generators.each do |action_key, generator_class|
    it "emits compilable source without raising on every enumerated branch of #{action_key}" do
      variants = GeneratorBranchVariants.variants(generator_class, action_key)
      expect(variants).not_to be_empty
      expect(GeneratorBranchVariants.truncated?(generator_class, action_key)).to be(false)
      expect(GeneratorConformance.validation_errors(generator_class, generator_class.sample_input)).to be_empty

      accepted = 0
      variants.each do |variant|
        next if GeneratorConformance.validation_errors(generator_class, variant.config).any?

        accepted += 1
        begin
          GeneratorConformance.compiled_result(generator_class, variant.config)
        rescue StandardError, SyntaxError => e
          raise GeneratorConformance::Error,
            "#{action_key} [#{variant.label}]: #{e.class}: #{e.message}"
        end
      end
      expect(accepted).to be_positive
    end
  end
end
