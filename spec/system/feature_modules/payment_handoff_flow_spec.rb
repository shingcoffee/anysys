# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payment module handoff round trip", type: :model do
  let(:customer) { create(:customer) }
  let!(:fm) do
    enable_module!("payment", customer, name: "Payments", configuration: {}.to_json).tap do |m|
      m.update!(handoff_enabled: true)
    end
  end
  let(:landing_page) { create(:page, customer: customer, launched: true) }
  let(:triggering_page) { create(:page, customer: customer) }
  let(:session) { {} }

  before do
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class).and_return(FeatureModules::Payment::Registration)
    Current.customer = customer
  end

  after { Current.customer = nil }

  it "flows from Invocation.begin! through Complete.call to the exit landing page" do
    # 1) Trigger page submits → handoff begins
    entry_path = FeatureModules::Invocation.begin!(
      session:         session,
      customer:        customer,
      module_key:      "payment",
      triggering_page: triggering_page,
      entity_entry:    nil,
      input:           { amount: 100.00, currency: "CNY", subject: "Test order" },
      exit_target:     { kind: "page", page_id: landing_page.id }
    )

    expect(entry_path).to eq("/#{customer.id}/payments/checkout/start")
    expect(session[:feature_module_invocation][:module_key]).to eq("payment")

    # 2) Module runs its own pages (simulated) and then calls Complete
    result = FeatureModules::Complete.call(
      session:    session,
      customer:   customer,
      module_key: "payment",
      output: {
        payment_reference: "pi_test_123",
        status:            "succeeded",
        paid_at:           Time.current.iso8601
      }
    )

    # 3) User lands on the configured exit landing page and sees payment ref via flash
    expect(result[:redirect_to]).to eq("/#{customer.id}/page/#{landing_page.public_uuid}")
    expect(result[:flash]).to include(feature_module_result: { module_key: "payment",
                                                                output: hash_including(payment_reference: "pi_test_123") })
    expect(session).not_to have_key(:feature_module_invocation)

    # Audit trail has both begin and complete entries
    actions = FeatureModules::Log.where(feature_module_id: fm.id).pluck(:action)
    expect(actions).to include("invocation.begin", "invocation.complete")
  end

  it "rejects handoff with invalid input and never stashes a session" do
    expect {
      FeatureModules::Invocation.begin!(
        session:         session,
        customer:        customer,
        module_key:      "payment",
        triggering_page: triggering_page,
        entity_entry:    nil,
        input:           { amount: -0.01, currency: "CNY", subject: "" },
        exit_target:     nil
      )
    }.to raise_error(FeatureModules::InputContractViolation)

    expect(session).not_to have_key(:feature_module_invocation)
  end
end
