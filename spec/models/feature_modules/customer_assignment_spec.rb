# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::CustomerAssignment, type: :model do
  subject(:cfm) { build(:customer_feature_module) }

  describe "validations" do
    it { is_expected.to be_valid }

    it "requires unique feature_module per customer" do
      existing = create(:customer_feature_module)
      cfm.customer = existing.customer
      cfm.feature_module = existing.feature_module
      expect(cfm).not_to be_valid
      expect(cfm.errors[:feature_module_id]).to include("has already been taken")
    end
  end

  describe "scopes" do
    let_it_be(:customer) { create(:customer) }
    let(:feature_mod) { create(:feature_module) }
    let!(:active_cfm) { create(:customer_feature_module, customer: customer, feature_module: feature_mod, status: :active) }
    let!(:suspended_cfm) { create(:customer_feature_module, :suspended) }

    describe ".enabled" do
      it "returns only active records" do
        expect(described_class.enabled).to include(active_cfm)
        expect(described_class.enabled).not_to include(suspended_cfm)
      end
    end
  end

  describe "#configured?" do
    it "returns true when key has a value" do
      cfm.configuration = { "gateway" => "stripe" }.to_json
      expect(cfm.configured?("gateway")).to be true
    end

    it "returns false when key is missing" do
      cfm.configuration = {}.to_json
      expect(cfm.configured?("gateway")).to be false
    end
  end

  describe "#merge_configuration!" do
    it "merges keys onto the existing blob without dropping siblings" do
      cfm = create(:customer_feature_module, configuration: { "mfa_enabled" => true }.to_json)
      cfm.merge_configuration!("allow_registration" => true)
      saved = JSON.parse(cfm.reload.configuration)
      expect(saved["mfa_enabled"]).to eq(true)
      expect(saved["allow_registration"]).to eq(true)
    end
  end

  describe "delegations" do
    let(:feature_mod) { create(:feature_module, key: "delegation_test", name: "Delegation Test") }
    let(:cfm_instance) { create(:customer_feature_module, feature_module: feature_mod) }

    it "delegates key to feature_module" do
      expect(cfm_instance.feature_module_key).to eq("delegation_test")
    end

    it "delegates name to feature_module" do
      expect(cfm_instance.feature_module_name).to eq("Delegation Test")
    end
  end
end
