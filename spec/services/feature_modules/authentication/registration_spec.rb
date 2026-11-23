# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Authentication::Registration do
  it_behaves_like "a feature module registration",
                  key: "authentication", name: "User Authentication"

  def configure_authentication(customer, config)
    ensure_customer_feature_module(
      customer, ::FeatureModules::Module.find_by!(key: "authentication"),
      configuration: config.to_json
    )
  end

  describe ".configuration_schema" do
    subject(:schema) { described_class.configuration_schema }

    it "includes mfa_enabled boolean setting" do
      aggregate_failures do
        expect(schema["mfa_enabled"]).to be_present
        expect(schema["mfa_enabled"]["type"]).to eq("boolean")
      end
    end

    it "includes session_timeout numeric setting" do
      expect(schema["session_timeout"]["type"]).to eq("number")
    end

    it "does not surface allow_registration or allow_password_reset (they have dedicated settings entries)" do
      aggregate_failures do
        expect(schema).not_to have_key("allow_registration")
        expect(schema).not_to have_key("allow_password_reset")
      end
    end
  end

  it "excludes toggle keys owned by dedicated controllers (.configuration_keys)" do
    expect(described_class.configuration_keys).to match_array(
      %i[mfa_enabled session_timeout max_login_attempts]
    )
  end

  # The per-tenant `mfa_enabled` key declared in configuration_schema is read
  # by Authentication::Settings#mfa_enabled? (see settings_spec) and acted on
  # by Authentication::MfaObligation. This module no longer reimplements
  # either, so there is nothing tenant-specific left to assert here.

  describe "handoff DSL" do
    let(:customer) { instance_double(Customer, id: 11) }

    it "declares entry_path" do
      expect(described_class.entry_path_for(customer)).to eq("/auth/sign_in")
    end

    it "declares a default_exit" do
      expect(described_class.default_exit_config).to eq(kind: "route", name: "customer_home")
    end

    it "has empty input/output contracts (valid against empty payload)" do
      i = described_class.input_contract_class.new(OpenStruct.new)
      o = described_class.output_contract_class.new(OpenStruct.new)
      aggregate_failures do
        expect(i.validate({})).to be true
        expect(o.validate({})).to be true
      end
    end

    it "still responds to provision! and deprovision!" do
      expect(described_class).to respond_to(:provision!)
      expect(described_class).to respond_to(:deprovision!)
    end
  end

  # This module deliberately has no per-request hook. MFA enforcement lives in
  # Authentication::EnforcesMfa (one gate, app-wide) and the decision itself in
  # Authentication::MfaObligation. A second gate used to live here and the two
  # drifted apart; this asserts the duplicate stays gone.
  describe ".before_request" do
    it "inherits the base no-op and never redirects" do
      controller = instance_double(ApplicationController)
      expect(controller).not_to receive(:redirect_to)
      expect(described_class.before_request(controller)).to be_nil
    end

    it "does not reintroduce its own MFA enforcement" do
      expect(described_class.singleton_class.instance_methods(false)).not_to include(:enforce_mfa!)
    end
  end
end
