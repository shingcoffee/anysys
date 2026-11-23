# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Complete do
  let_it_be(:customer) { create(:customer) }
  let!(:fm) { create(:feature_module, key: "demo", name: "Demo") }
  let!(:cfm) do
    create(:customer_feature_module,
           customer: customer, feature_module: fm,
           status: :active, configuration: {}.to_json)
  end
  let(:session) { {} }
  let(:registration) do
    Class.new(FeatureModules::BaseModule) do
      def self.module_key = "demo"
      def self.module_name = "Demo"
      def self.provision!(_c) = nil
      default_exit kind: "url", url: "https://fallback.test"
      output_contract do
        property :reference, validates: { presence: true }
      end
    end
  end

  before do
    allow(fm).to receive(:registration_class).and_return(registration)
    allow(FeatureModules::Module).to receive(:find_by).with(key: "demo").and_return(fm)
    Current.customer = customer
  end

  after  { Current.customer = nil }

  def stash_invocation(**overrides)
    session[:feature_module_invocation] = {
      module_key: "demo", customer_id: customer.id,
      exit_target: nil, started_at: Time.current.iso8601
    }.merge(overrides)
  end

  def complete(output:)
    described_class.call(session: session, customer: customer, module_key: "demo", output: output)
  end

  def last_complete_log
    FeatureModules::Log.where(action: "invocation.complete").order(:id).last
  end

  describe ".call (happy path)" do
    it "validates output, resolves exit, clears session, writes success log, returns redirect + flash" do
      stash_invocation(exit_target: { kind: "url", url: "https://ok.test" })

      result = complete(output: { reference: "abc" })

      expect(result[:redirect_to]).to eq("https://ok.test")
      expect(result[:flash]).to eq(feature_module_result: { module_key: "demo", output: { reference: "abc" } })
      expect(session).not_to have_key(:feature_module_invocation)
      expect(last_complete_log.status).to eq("success")
    end
  end

  describe ".call (invalid output)" do
    it "raises OutputContractViolation and writes failure log" do
      stash_invocation
      expect { complete(output: { reference: nil }) }
        .to raise_error(FeatureModules::OutputContractViolation)

      expect(last_complete_log.status).to eq("failure")
    end
  end

  describe ".call (stale / no live invocation)" do
    it "proceeds via fallback chain and marks the log with stale: true" do
      result = complete(output: { reference: "x" })

      expect(result[:redirect_to]).to eq("https://fallback.test")

      log = last_complete_log
      expect(log.status).to eq("success")
      parsed = JSON.parse(log.response_data)
      expect(parsed["stale"]).to eq(true)
    end
  end

  describe ".call (cross-tenant)" do
    it "clears session, raises CrossTenantViolation, and writes a failure log" do
      stash_invocation(customer_id: -999)
      expect { complete(output: { reference: "x" }) }
        .to raise_error(FeatureModules::CrossTenantViolation)

      expect(session).not_to have_key(:feature_module_invocation)
      expect(last_complete_log.status).to eq("failure")
    end
  end
end
