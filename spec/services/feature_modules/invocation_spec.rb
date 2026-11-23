# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Invocation do
  let_it_be(:customer) { create(:customer) }
  let!(:fm) { create(:feature_module, :handoffable, key: "demo", name: "Demo") }
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
      entry_path { |c| "/#{c.id}/demo/start" }
      input_contract do
        property :amount, validates: { presence: true, numericality: { greater_than: 0 } }
      end
    end
  end

  before do
    allow(fm).to receive(:registration_class).and_return(registration)
    allow(FeatureModules::Module).to receive(:find_by).with(key: "demo").and_return(fm)
    Current.customer = customer
  end

  after  { Current.customer = nil }

  describe ".begin!" do
    let(:triggering_page) { create(:page, customer: customer) }

    def begin_invocation(**overrides)
      described_class.begin!(**{
        session: session, customer: customer, module_key: "demo",
        triggering_page: triggering_page, entity_entry: nil,
        input: { amount: 50 }, exit_target: nil
      }.merge(overrides))
    end

    it "stores invocation state in session and returns the entry_path" do
      url = begin_invocation(exit_target: { kind: "url", url: "https://e.test" })
      expect(url).to eq("/#{customer.id}/demo/start")
      data = session[:feature_module_invocation]
      expect(data[:module_key]).to eq("demo")
      expect(data[:customer_id]).to eq(customer.id)
      expect(data[:input]).to eq(amount: 50)
      expect(data[:exit_target]).to eq(kind: "url", url: "https://e.test")
      expect(data[:triggering_page_id]).to eq(triggering_page.id)
    end

    it "mints a per-invocation token in the session" do
      begin_invocation
      expect(session[:feature_module_invocation][:token]).to be_a(String).and be_present
    end

    it "writes a FeatureModules::Log entry tagged invocation.begin / success" do
      expect { begin_invocation }.to change(FeatureModules::Log, :count).by(1)

      log = FeatureModules::Log.order(:id).last
      expect(log.action).to eq("invocation.begin")
      expect(log.status).to eq("success")
      expect(log.feature_module_id).to eq(fm.id)
    end

    it "abandons an existing invocation before starting a new one" do
      session[:feature_module_invocation] = {
        module_key: "demo", customer_id: customer.id, started_at: 1.hour.ago.iso8601
      }
      expect { begin_invocation }
        .to change { FeatureModules::Log.where(action: "invocation.abandon").count }.by(1)
      expect(session[:feature_module_invocation][:module_key]).to eq("demo")
    end

    it "raises ModuleNotEnabled when the customer has not enabled the module" do
      cfm.update!(status: :suspended)
      expect { begin_invocation }.to raise_error(FeatureModules::ModuleNotEnabled)
      expect(session).not_to have_key(:feature_module_invocation)
    end

    it "interpolates #display_name into ModuleNotEnabled, not the stored English name" do
      allow(fm).to receive(:display_name).and_return("Localized module")
      cfm.update!(status: :suspended)

      expect { begin_invocation }.to raise_error(
        FeatureModules::ModuleNotEnabled,
        I18n.t("feature_modules.errors.module_not_enabled", module_name: "Localized module")
      )
    end

    it "raises ModuleNotEnabled when the target module is not handoff-enabled" do
      fm.update!(handoff_enabled: false)
      expect { begin_invocation }
        .to raise_error(FeatureModules::ModuleNotEnabled, /cannot be handed off/)
      expect(session).not_to have_key(:feature_module_invocation)
    end

    it "raises ModuleNotEnabled when there is no FeatureModules::Module record for the key" do
      allow(FeatureModules::Module).to receive(:find_by).with(key: "ghost").and_return(nil)
      expect { begin_invocation(module_key: "ghost", input: {}) }
        .to raise_error(FeatureModules::ModuleNotEnabled)
    end

    it "raises InputContractViolation when input fails the contract" do
      expect { begin_invocation(input: { amount: -1 }) }
        .to raise_error(FeatureModules::InputContractViolation)
      expect(session).not_to have_key(:feature_module_invocation)
    end

    it "does not await end-user input when the module declares no user_fillable fields" do
      begin_invocation
      expect(session[:feature_module_invocation][:awaiting_input]).to be(false)
    end

    context "when the module declares user_fillable inputs" do
      let(:registration) do
        Class.new(FeatureModules::BaseModule) do
          def self.module_key = "demo"
          def self.module_name = "Demo"
          def self.provision!(_c) = nil
          entry_path { |c| "/#{c.id}/demo/start" }
          input_contract do
            property :amount, validates: { presence: true, numericality: { greater_than: 0 } }
            property :phone, source: :user_fillable, validates: { presence: true }
          end
        end
      end

      it "defers a blank required user_fillable input to the entry step and awaits it" do
        begin_invocation
        expect(session[:feature_module_invocation]).to include(awaiting_input: true, input: { amount: 50 })
      end

      it "rejects invalid author input, reporting only the violations that block the handoff" do
        expect { begin_invocation(input: { amount: -1 }) }
          .to raise_error(FeatureModules::InputContractViolation) { |error|
            expect(error.message).to include("Amount must be greater than 0")
            expect(error.message).not_to include("Phone")
          }
        expect(session).not_to have_key(:feature_module_invocation)
      end
    end

    it "coerces resolved input to the field's type before validating and storing" do
      begin_invocation(input: { amount: "50" }) # string from a form field
      stored = session[:feature_module_invocation][:input]
      expect(stored[:amount]).to eq(50.0) # numericality field -> coerced to Float
    end

    it "raises RegistrationError when module has no entry_path" do
      no_entry = Class.new(FeatureModules::BaseModule) do
        def self.module_key  = "demo"
        def self.module_name = "Demo"
        def self.provision!(_c) = nil
      end
      allow(fm).to receive(:registration_class).and_return(no_entry)

      expect { begin_invocation(input: {}) }
        .to raise_error(FeatureModules::RegistrationError, /entry_path/)
    end
  end

  describe ".current" do
    it "returns the hash when customer_id matches Current.customer.id" do
      session[:feature_module_invocation] = { module_key: "demo", customer_id: customer.id }
      expect(described_class.current(session)).to include(module_key: "demo")
    end

    it "raises CrossTenantViolation when customer_id mismatches" do
      session[:feature_module_invocation] = { module_key: "demo", customer_id: -999 }
      expect { described_class.current(session) }.to raise_error(FeatureModules::CrossTenantViolation)
    end

    it "returns nil when no invocation is present" do
      expect(described_class.current(session)).to be_nil
    end

    # After the JSON cookie serializer round-trips the session, the stashed
    # hash comes back with string keys. current must still read it correctly
    # (and expose symbol access to callers) rather than mis-firing the
    # cross-tenant guard on a nil customer_id.
    it "normalizes a string-keyed session (JSON round-trip) to indifferent access" do
      session[:feature_module_invocation] = {
        "module_key" => "demo", "customer_id" => customer.id,
        "input" => { "amount" => 50 }, "exit_target" => { "kind" => "url", "url" => "https://e.test" }
      }
      data = described_class.current(session)
      expect(data[:module_key]).to eq("demo")
      expect(data[:input][:amount]).to eq(50)
      expect(data.dig(:exit_target, :url)).to eq("https://e.test")
    end
  end

  describe ".clear!" do
    it "removes the session key" do
      session[:feature_module_invocation] = { module_key: "demo", customer_id: customer.id }
      described_class.clear!(session)
      expect(session).not_to have_key(:feature_module_invocation)
    end
  end

  describe ".abandon!" do
    it "clears the session key and writes an abandon log" do
      session[:feature_module_invocation] = { module_key: "demo", customer_id: customer.id }
      expect {
        described_class.abandon!(session: session, reason: "superseded")
      }.to change { FeatureModules::Log.where(action: "invocation.abandon").count }.by(1)
      expect(session).not_to have_key(:feature_module_invocation)
      log = FeatureModules::Log.order(:id).last
      expect(log.action).to eq("invocation.abandon")
      expect(log.status).to eq("success")
    end

    it "is a no-op when no invocation is present" do
      expect {
        described_class.abandon!(session: session, reason: "n/a")
      }.not_to change(FeatureModules::Log, :count)
    end
  end

  describe ".update_input!" do
    let(:customer) { create(:customer) }

    before { Current.customer = customer }

    def seeded_session(input)
      { FeatureModules::Invocation::SESSION_KEY =>
          { module_key: "payment", customer_id: customer.id, input: input } }
    end

    it "overwrites the invocation input for the live invocation" do
      session = seeded_session(amount_cents: 100)
      described_class.update_input!(session: session, input: { amount_cents: 100, body: "hi" })
      stored = session[FeatureModules::Invocation::SESSION_KEY]
      expect(stored[:input] || stored["input"]).to include("body" => "hi").or include(body: "hi")
    end

    it "marks the end-user input as supplied" do
      session = seeded_session(amount_cents: 100)
      session[FeatureModules::Invocation::SESSION_KEY][:awaiting_input] = true
      described_class.update_input!(session: session, input: { amount_cents: 100 })
      expect(session[FeatureModules::Invocation::SESSION_KEY][:awaiting_input]).to be(false)
    end

    it "no-ops when no invocation is present" do
      session = {}
      expect(described_class.update_input!(session: session, input: { a: 1 })).to be_nil
      expect(session).to be_empty
    end

    it "raises CrossTenantViolation when the session belongs to another tenant" do
      session = seeded_session(amount_cents: 100)
      session[FeatureModules::Invocation::SESSION_KEY][:customer_id] = customer.id + 999
      expect {
        described_class.update_input!(session: session, input: { amount_cents: 1 })
      }.to raise_error(FeatureModules::CrossTenantViolation)
    end
  end
end
