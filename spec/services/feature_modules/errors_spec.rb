# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules do
  describe "error hierarchy" do
    it "defines a base Error class" do
      expect(FeatureModules::Error.ancestors).to include(StandardError)
    end

    it "defines ModuleNotEnabled inheriting from Error" do
      expect(FeatureModules::ModuleNotEnabled.ancestors).to include(FeatureModules::Error)
    end

    it "defines InputContractViolation inheriting from Error" do
      expect(FeatureModules::InputContractViolation.ancestors).to include(FeatureModules::Error)
    end

    it "defines OutputContractViolation inheriting from Error" do
      expect(FeatureModules::OutputContractViolation.ancestors).to include(FeatureModules::Error)
    end

    it "defines CrossTenantViolation inheriting from Error" do
      expect(FeatureModules::CrossTenantViolation.ancestors).to include(FeatureModules::Error)
    end

    it "defines RegistrationError inheriting from Error" do
      expect(FeatureModules::RegistrationError.ancestors).to include(FeatureModules::Error)
    end
  end

  describe "locale strings" do
    %w[
      feature_modules.errors.module_not_enabled
      feature_modules.errors.input_contract_violation
      feature_modules.errors.output_contract_violation
      feature_modules.errors.cross_tenant_violation
      feature_modules.errors.unresolvable_exit_target
    ].each do |key|
      it "defines #{key}" do
        expect(I18n.t(key, raise: true)).to be_a(String)
      end
    end
  end

  describe FeatureModules::InputContractViolation do
    it "accepts contract_errors as a keyword argument" do
      error = described_class.new("Invalid input", contract_errors: { email: ["is invalid"] })
      expect(error.message).to eq("Invalid input")
      expect(error.contract_errors).to eq(email: ["is invalid"])
    end

    it "defaults contract_errors to an empty hash" do
      error = described_class.new("Invalid input")
      expect(error.contract_errors).to eq({})
    end
  end

  describe FeatureModules::OutputContractViolation do
    it "accepts contract_errors as a keyword argument" do
      error = described_class.new("Invalid output", contract_errors: { amount: ["must be present"] })
      expect(error.message).to eq("Invalid output")
      expect(error.contract_errors).to eq(amount: ["must be present"])
    end

    it "defaults contract_errors to an empty hash" do
      error = described_class.new("Invalid output")
      expect(error.contract_errors).to eq({})
    end
  end
end
