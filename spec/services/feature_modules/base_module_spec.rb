# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::BaseModule do
  let(:customer) { instance_double(Customer, id: 42) }

  # Builds an anonymous BaseModule subclass with the mandatory identity/provision
  # boilerplate; the block (evaluated in class context) declares the DSL under test.
  def build_module(key, name = key.titleize, &body)
    Class.new(described_class) do
      define_singleton_method(:module_key)  { key }
      define_singleton_method(:module_name) { name }
      def self.provision!(_c) = nil
    end.tap { |klass| klass.class_eval(&body) if body }
  end

  def build_registration(key, mandatory:)
    build_module(key) { mandatory! if mandatory }
  end

  describe ".register!" do
    it "preserves configured false, nil and string defaults while refreshing schema metadata" do
      reg = build_module("defaults_audit")
      schema = {
        "enabled" => { "type" => "boolean", "default" => true },
        "choice" => { "type" => "string", "default" => "initial" },
        "optional" => { "type" => "string", "default" => "initial" }
      }
      allow(reg).to receive(:configuration_schema).and_return(schema)
      reg.register!
      fm = FeatureModules::Module.find_by!(key: "defaults_audit")
      configured = fm.configuration_schema_json
      configured["enabled"]["default"] = false
      configured["choice"]["default"] = "configured"
      configured["optional"]["default"] = nil
      configured["retired"] = { "default" => "old" }
      fm.update!(configuration_schema: configured.to_json)
      schema["choice"]["type"] = "select"
      schema["new"] = { "type" => "string", "default" => "new default" }

      reg.register!
      result = fm.reload.configuration_schema_json
      expect(result["enabled"]["default"]).to be(false)
      expect(result["choice"]).to eq("type" => "select", "default" => "configured")
      expect(result["optional"]["default"]).to be_nil
      expect(result["new"]["default"]).to eq("new default")
      expect(result).not_to have_key("retired")
    end

    it "seeds a brand-new non-mandatory module as inactive + optional" do
      reg = build_registration("seed_demo", mandatory: false)
      reg.register!
      fm = FeatureModules::Module.find_by!(key: "seed_demo")
      expect(fm.status).to eq("inactive")
      expect(fm.required).to be(false)
    end

    it "forces a mandatory module active + required" do
      reg = build_registration("seed_auth", mandatory: true)
      reg.register!
      fm = FeatureModules::Module.find_by!(key: "seed_auth")
      expect(fm.status).to eq("active")
      expect(fm.required).to be(true)
    end

    it "preserves owner-set status/required on an existing non-mandatory module" do
      reg = build_registration("seed_keep", mandatory: false)
      reg.register!
      FeatureModules::Module.find_by!(key: "seed_keep").update!(status: :active, required: true)
      reg.register! # boot again
      fm = FeatureModules::Module.find_by!(key: "seed_keep")
      expect(fm.status).to eq("active")
      expect(fm.required).to be(true)
    end
  end

  describe ".entry_path" do
    it "stores a block and exposes it via .entry_path_for(customer)" do
      klass = build_module("demo") { entry_path { |c| "/#{c.id}/demo/start" } }
      expect(klass.entry_path_for(customer)).to eq("/42/demo/start")
    end

    it "defaults to nil when not declared" do
      klass = build_module("noentry", "No Entry")
      expect(klass.entry_path_for(customer)).to be_nil
    end
  end

  describe ".handoff_entry_i18n" do
    it "stores an explicit i18n scope for the framework entry step" do
      klass = build_module("demo") { handoff_entry_i18n "comp_payments.handoff_entry" }
      expect(klass.handoff_entry_i18n_scope).to eq("comp_payments.handoff_entry")
    end

    it "defaults to feature_modules.<key>.handoff_entry when not declared" do
      klass = build_module("demo")
      expect(klass.handoff_entry_i18n_scope).to eq("feature_modules.demo.handoff_entry")
    end
  end

  describe ".default_exit" do
    it "stores and exposes a default_exit hash" do
      klass = build_module("d2") { default_exit kind: "url", url: "https://example.com" }
      expect(klass.default_exit_config).to eq(kind: "url", url: "https://example.com")
    end

    it "returns nil when not declared" do
      klass = build_module("d3")
      expect(klass.default_exit_config).to be_nil
    end

    it "raises RegistrationError at class-load time for an unknown kind" do
      expect {
        build_module("dbad") { default_exit kind: "lolwat" }
      }.to raise_error(FeatureModules::RegistrationError, /unknown kind/i)
    end
  end

  describe ".input_contract and .output_contract" do
    let(:klass) do
      build_module("ioo") do
        input_contract do
          property :amount, validates: { presence: true, numericality: { greater_than: 0 } }
        end

        output_contract do
          property :reference, validates: { presence: true }
        end
      end
    end

    it "builds a Reform::Form subclass for inputs" do
      contract_class = klass.input_contract_class
      expect(contract_class.ancestors).to include(Reform::Form)

      form = contract_class.new(OpenStruct.new(amount: nil))
      expect(form.validate(amount: nil)).to be false
      expect(form.errors[:amount]).not_to be_empty
    end

    it "builds a Reform::Form subclass for outputs" do
      contract_class = klass.output_contract_class
      form = contract_class.new(OpenStruct.new(reference: nil))
      expect(form.validate(reference: "abc")).to be true
    end

    it "returns an empty-but-valid contract when not declared" do
      form = build_module("empty").input_contract_class.new(OpenStruct.new)
      expect(form.validate({})).to be true
    end
  end

  describe ".input_contract_fields / .output_contract_fields" do
    let(:klass) do
      build_module("fielded") do
        input_contract do
          property :amount_cents, validates: { presence: true, numericality: { greater_than: 0, only_integer: true } }
          property :currency,     validates: { presence: true, inclusion: { in: %w[CNY] } }
          property :note
        end

        output_contract do
          property :status, validates: { inclusion: { in: %w[succeeded failed] } }
        end
      end
    end

    it "exposes rich descriptors derived from the validations" do
      amount = klass.input_contract_fields.find { |f| f.name == "amount_cents" }
      expect(amount.required?).to be(true)
      expect(amount.type).to eq("integer")
      expect(amount.constraint).to include("> 0")

      currency = klass.input_contract_fields.find { |f| f.name == "currency" }
      expect(currency.type).to eq("enum")
      expect(currency.constraint).to include("CNY")

      note = klass.input_contract_fields.find { |f| f.name == "note" }
      expect(note.required?).to be(false)
      expect(note.type).to eq("string")
    end

    it "derives input_contract_properties (names) from the fields" do
      expect(klass.input_contract_properties).to eq(%w[amount_cents currency note])
    end

    it "prefers a declared type: over the inferred one" do
      typed = build_module("typed") do
        input_contract do
          property :count,   type: :integer                 # no validators to infer from
          property :toggle,  type: :boolean
          property :note,    type: :string, validates: { presence: true }
        end
      end
      expect(typed.input_contract_fields.map { |f| [f.name, f.type] }).to eq(
        [%w[count integer], %w[toggle boolean], %w[note string]]
      )
    end

    it "exposes output_contract_fields" do
      status = klass.output_contract_fields.find { |f| f.name == "status" }
      expect(status.type).to eq("enum")
      expect(status.required?).to be(false)
    end

    it "returns empty arrays when no contract is declared" do
      empty = build_module("unfielded")
      expect(empty.input_contract_fields).to eq([])
      expect(empty.output_contract_fields).to eq([])
      expect(empty.input_contract_properties).to eq([])
    end
  end

  describe "input_contract source: policy" do
    let(:mod) do
      Class.new(FeatureModules::BaseModule) do
        input_contract do
          property :amount, type: :integer, validates: { presence: true }
          property :note,   type: :string, source: :user_fillable
        end
      end
    end

    it "defaults an undeclared source to author_only" do
      amount = mod.input_contract_fields.find { |f| f.name == "amount" }
      expect(amount.author_only?).to be(true)
      expect(amount.user_fillable?).to be(false)
      expect(amount.source).to eq("author_only")
    end

    it "honors an explicit source: :user_fillable" do
      note = mod.input_contract_fields.find { |f| f.name == "note" }
      expect(note.user_fillable?).to be(true)
      expect(note.author_only?).to be(false)
    end

    it "exposes source in to_h" do
      note = mod.input_contract_fields.find { |f| f.name == "note" }
      expect(note.to_h).to include(source: "user_fillable")
    end
  end

  describe "generic host-integration hooks" do
    let(:dummy_module) { build_module("dummy_hooks", "Dummy") }

    describe ".before_request" do
      it "is a no-op by default and returns nil" do
        fake_controller = double("controller")
        expect(dummy_module.before_request(fake_controller)).to be_nil
      end
    end

    describe ".sidebar_contributions" do
      it "returns a default empty contribution set" do
        fake_controller = double("controller")
        expect(dummy_module.sidebar_contributions(fake_controller))
          .to eq(entries: [], settings: [])
      end
    end

    describe ".entries_for" do
      it "raises NotImplementedError by default" do
        expect { dummy_module.entries_for(entry_key: "x", params: {}) }
          .to raise_error(NotImplementedError)
      end
    end
  end
end
