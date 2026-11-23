# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication module handoff round trip", type: :model do
  let(:customer) { create(:customer) }
  let(:session)  { {} }

  before do
    # Authentication is auto-provisioned when a customer is created; the
    # FeatureModules::Module record should exist with key "authentication".
    # If not, create it to keep the test hermetic.
    fm = enable_module!("authentication", customer, name: "User Authentication")
    fm.update!(handoff_enabled: true)
    Current.customer = customer
  end

  after { Current.customer = nil }

  it "flows through a module that declares no input/output contracts (auth)" do
    triggering_page = create(:page, customer: customer)

    entry_path = FeatureModules::Invocation.begin!(
      session:         session,
      customer:        customer,
      module_key:      "authentication",
      triggering_page: triggering_page,
      entity_entry:    nil,
      input:           {},
      exit_target:     { kind: "route", name: "customer_home" }
    )

    expect(entry_path).to eq("/auth/sign_in")

    result = FeatureModules::Complete.call(
      session:    session,
      customer:   customer,
      module_key: "authentication",
      output:     {} # auth module has no output_contract → empty payload accepted
    )

    expect(result[:redirect_to]).to eq("/#{customer.id}/admin/dashboard")
    expect(session).not_to have_key(:feature_module_invocation)
  end
end
