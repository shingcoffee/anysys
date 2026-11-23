# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Module completion round-trip", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:fm) { create(:feature_module, key: "test_module", name: "Test Module") }
  let!(:cfm) do
    create(:customer_feature_module,
           customer: customer, feature_module: fm,
           status: :active, configuration: {}.to_json)
  end

  before do
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class)
      .and_return(FeatureModules::TestModule::Registration)
    Current.customer = customer
  end

  after { Current.customer = nil }

  it "clears session, sets flash, and returns redirect via Complete.call" do
    # A request-scope session_stub — Complete.call treats session as a plain hash.
    # Because this test just calls the activity directly, we skip wiring a real route.
    session_stub = {
      feature_module_invocation: {
        module_key:  "test_module",
        customer_id: customer.id,
        input:       { x: 1 },
        exit_target: { kind: "route", name: "customer_home" },
        started_at: Time.current.iso8601
      }
    }

    result = FeatureModules::Complete.call(
      session:    session_stub,
      customer:   customer,
      module_key: "test_module",
      output:     { ok: "yes" }
    )

    expect(result[:redirect_to]).to eq("/#{customer.id}/admin/dashboard")
    expect(result[:flash]).to include(
      feature_module_result: { module_key: "test_module", output: { ok: "yes" } }
    )
    expect(session_stub).not_to have_key(:feature_module_invocation)
  end

  it "falls through to module default_exit when no invocation in session (stale path)" do
    session_stub = {}

    result = FeatureModules::Complete.call(
      session:    session_stub,
      customer:   customer,
      module_key: "test_module",
      output:     { ok: "yes" }
    )

    expect(result[:redirect_to]).to eq("/#{customer.id}/admin/dashboard")
    log = FeatureModules::Log.where(action: "invocation.complete").order(:id).last
    expect(JSON.parse(log.response_data)["stale"]).to eq(true)
  end
end
