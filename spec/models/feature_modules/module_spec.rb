# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Module, type: :model do
  subject(:feature_module) { build(:feature_module) }

  describe "status default" do
    it "defaults a new module to inactive" do
      fm = described_class.new(key: "demo", name: "Demo")
      expect(fm.status).to eq("inactive")
    end
  end

  describe "handoff_enabled default" do
    it "defaults a new module to not being a handoff target (fail-safe)" do
      fm = create(:feature_module, key: "demo", name: "Demo")
      expect(fm.handoff_enabled).to be(false)
    end
  end

  describe "#display_name" do
    it "returns the request-localized name for a known module key" do
      fm = described_class.new(key: "payment", name: "Payments")
      expect(fm.display_name).to eq(I18n.t("feature_modules.payment.name"))
      I18n.with_locale(:"zh-CN") do
        expect(fm.display_name).to eq(I18n.t("feature_modules.payment.name"))
      end
    end

    it "falls back to the stored name when no translation key exists" do
      fm = described_class.new(key: "no_such_module", name: "Fallback Name")
      expect(fm.display_name).to eq("Fallback Name")
    end
  end

  describe "validations" do
    it { is_expected.to be_valid }

    it "requires a key" do
      feature_module.key = nil
      expect(feature_module).not_to be_valid
      expect(feature_module.errors[:key]).to include("can't be blank")
    end

    it "requires a unique key" do
      create(:feature_module, key: "unique_test_key")
      feature_module.key = "unique_test_key"
      expect(feature_module).not_to be_valid
      expect(feature_module.errors[:key]).to include("has already been taken")
    end

    it "requires a name" do
      feature_module.name = nil
      expect(feature_module).not_to be_valid
      expect(feature_module.errors[:name]).to include("can't be blank")
    end
  end

  describe "inactive hard-gate" do
    let_it_be(:customer) { create(:customer) }

    it "treats an inactive module as not enabled even with an active assignment" do
      fm = described_class.create!(key: "gate", name: "Gate", status: :active)
      FeatureModules::CustomerAssignment.create!(
        customer: customer, feature_module: fm, status: :active,
        configuration: {}.to_json, enabled_at: Time.current
      )
      expect(described_class.enabled?(key: "gate", customer_id: customer.id)).to be(true)

      fm.update!(status: :inactive)
      expect(described_class.enabled?(key: "gate", customer_id: customer.id)).to be(false)
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(described_class.statuses).to eq("active" => 0, "inactive" => 1)
    end
  end

  # The controller guards required-implies-active at the request layer
  # (apply_required! returns early when the module is inactive). This block
  # verifies the invariant is ALSO enforced by a model validation, so a module
  # cannot be required while inactive even via a direct ActiveRecord write.
  describe "required-implies-active invariant" do
    it "does not allow required:true to be set when status is inactive" do
      fm = create(:feature_module, :inactive, required: false)
      fm.required = true
      expect(fm).not_to be_valid
    end

    it "allows required:true only when status is active" do
      fm = create(:feature_module, status: :active, required: false)
      fm.required = true
      expect(fm).to be_valid
    end

    it "allows required:false regardless of status" do
      inactive_fm = create(:feature_module, :inactive, required: false)
      expect(inactive_fm).to be_valid

      active_fm = create(:feature_module, status: :active, required: false)
      expect(active_fm).to be_valid
    end
  end

  # An inactive module can never be a live handoff target — pinned at the data
  # layer so the runtime handoff_enabled? gate transitively guarantees active.
  describe "handoff_enabled-implies-active invariant" do
    it "does not allow handoff_enabled:true to be set when status is inactive" do
      fm = create(:feature_module, :inactive)
      fm.handoff_enabled = true
      expect(fm).not_to be_valid
    end

    it "allows handoff_enabled:true only when status is active" do
      fm = create(:feature_module, status: :active)
      fm.handoff_enabled = true
      expect(fm).to be_valid
    end
  end

  describe "scopes" do
    let!(:active_module) { create(:feature_module, status: :active) }
    let!(:inactive_module) { create(:feature_module, :inactive) }

    describe ".available" do
      it "returns only active modules" do
        expect(described_class.available).to include(active_module)
        expect(described_class.available).not_to include(inactive_module)
      end
    end

    describe ".handoff_enabled" do
      let!(:handoffable_module) { create(:feature_module, :handoffable, status: :active) }

      it "returns only modules opted into being a handoff target" do
        expect(described_class.handoff_enabled).to include(handoffable_module)
        expect(described_class.handoff_enabled).not_to include(active_module)
      end
    end
  end

  describe "JSON attributes" do
    it "parses configuration_schema_json" do
      schema = { "gateway" => { "type" => "select" } }
      feature_module.configuration_schema = schema.to_json
      expect(feature_module.configuration_schema_json).to eq(schema)
    end
  end

  describe "#registration_class" do
    it "resolves the registration class" do
      feature_module.key = "authentication"
      expect(feature_module.registration_class).to eq(FeatureModules::Authentication::Registration)
    end
  end

  describe ".enabled?" do
    let(:customer) { create(:customer) }
    let(:module_record) { described_class.find_by!(key: "authentication") }

    it "returns true when an active FeatureModules::CustomerAssignment row exists" do
      expect(described_class.enabled?(key: "authentication", customer_id: customer.id)).to be true
    end

    it "returns false when the module is suspended for the customer" do
      cfm = FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: module_record)
      cfm.update!(status: :suspended)
      expect(described_class.enabled?(key: "authentication", customer_id: customer.id)).to be false
    end

    it "returns false when the module has no FeatureModules::CustomerAssignment row for the customer" do
      FeatureModules::CustomerAssignment.where(customer: customer, feature_module: module_record).destroy_all
      expect(described_class.enabled?(key: "authentication", customer_id: customer.id)).to be false
    end

    it "returns false when the module key does not exist" do
      expect(described_class.enabled?(key: "nonexistent_module", customer_id: customer.id)).to be false
    end

    it "returns false when customer_id is blank" do
      expect(described_class.enabled?(key: "authentication", customer_id: nil)).to be false
    end
  end

  describe ".enabled_for_customer scope" do
    let(:customer) { create(:customer) }

    it "returns modules with an active FeatureModules::CustomerAssignment row for the given customer" do
      keys = described_class.enabled_for_customer(customer.id).pluck(:key)
      expect(keys).to include("authentication")
    end

    it "excludes modules with suspended FeatureModules::CustomerAssignment rows" do
      auth_module = described_class.find_by!(key: "authentication")
      FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: auth_module)
        .update!(status: :suspended)
      keys = described_class.enabled_for_customer(customer.id).pluck(:key)
      expect(keys).not_to include("authentication")
    end

    it "returns an empty relation when customer_id is blank" do
      expect(described_class.enabled_for_customer(nil).to_a).to eq([])
    end
  end

  describe ".available_for_customer scope" do
    let(:customer) { create(:customer) }

    before do
      described_class.update_all(required: false)
    end

    def enable_for_customer(mod)
      FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: mod) do |cfm|
        cfm.status = :active
        cfm.configuration = {}.to_json
        cfm.enabled_at = Time.current
      end
    end

    it "returns enabled modules for the customer" do
      auth_module = described_class.find_by!(key: "authentication")
      enable_for_customer(auth_module)
      keys = described_class.available_for_customer(customer.id).pluck(:key)
      expect(keys).to include("authentication")
    end

    it "returns required modules even if not explicitly enabled" do
      required_module = create(:feature_module, key: "required_test", name: "Required Test", required: true, status: :active)
      keys = described_class.available_for_customer(customer.id).pluck(:key)
      expect(keys).to include("required_test")
    end

    it "does not duplicate modules that are both enabled and required" do
      auth_module = described_class.find_by!(key: "authentication")
      auth_module.update!(required: true)
      enable_for_customer(auth_module)
      keys = described_class.available_for_customer(customer.id).pluck(:key)
      expect(keys.count("authentication")).to eq(1)
    end

    it "returns only required modules when customer_id is blank" do
      required_module = create(:feature_module, key: "required_blank_test", name: "Required Blank", required: true, status: :active)
      keys = described_class.available_for_customer(nil).pluck(:key)
      expect(keys).to include("required_blank_test")
      expect(keys).not_to include("authentication")
    end
  end

  describe "extendable models" do
    let(:mod) { described_class.create!(key: "demo", name: "Demo") }

    it "defaults to no extendable models" do
      expect(mod.extendable_models_json).to eq([])
      expect(mod.extendable_model?("Some::Model")).to be(false)
    end

    it "adds and removes a model class idempotently" do
      mod.set_extendable_model!("Payments::Order", true)
      mod.set_extendable_model!("Payments::Order", true)
      expect(mod.reload.extendable_models_json).to eq(["Payments::Order"])
      expect(mod.extendable_model?("Payments::Order")).to be(true)

      mod.set_extendable_model!("Payments::Order", false)
      expect(mod.reload.extendable_models_json).to eq([])
      expect(mod.extendable_model?("Payments::Order")).to be(false)
    end

    it "records an explicit attribute selection and clears it when the model is no longer extendable" do
      mod.set_extendable_model!("Payments::Order", true)
      expect(mod.extendable_attribute_allowed?("Payments::Order", "amount")).to be(false)

      mod.set_extendable_attribute!("Payments::Order", "amount", true, candidates: %w[amount currency])
      expect(mod.reload.extendable_attributes_for("Payments::Order")).to eq(["amount"])
      expect(mod.extendable_attribute_allowed?("Payments::Order", "amount")).to be(true)

      mod.set_extendable_model!("Payments::Order", false)
      expect(mod.reload.extendable_attributes_configured?("Payments::Order")).to be(false)
    end
  end
end

RSpec.describe FeatureModules::Module::NullRegistration do
  it "responds to entry_path_for with nil" do
    expect(described_class.entry_path_for(double("customer"))).to be_nil
  end

  it "responds to default_exit_config with nil" do
    expect(described_class.default_exit_config).to be_nil
  end

  it "responds to input_contract_class with an empty Reform::Form subclass that validates empty payloads" do
    contract = described_class.input_contract_class.new(OpenStruct.new)
    expect(contract.validate({})).to be true
  end

  it "responds to output_contract_class with an empty Reform::Form subclass that validates empty payloads" do
    contract = described_class.output_contract_class.new(OpenStruct.new)
    expect(contract.validate({})).to be true
  end

  it "preserves existing provision! / deprovision! no-ops" do
    expect(described_class.provision!(double("customer"))).to be_nil
    expect(described_class.deprovision!(double("customer"))).to be_nil
  end
end
