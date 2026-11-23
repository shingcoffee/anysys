# frozen_string_literal: true

require "rails_helper"
require "digest"

# Bridge between a page → module handoff and the public checkout. The Payment
# module's `entry_path` points here; #start turns the server-validated
# invocation into a Payments::Order whose external_ref is derived from the
# per-invocation token (author-supplied external_ref no longer exists), then
# forwards to the checkout. The payer's note is collected beforehand by the
# framework entry step (FeatureModules::HandoffsController).
RSpec.describe "Payments::Checkouts#start", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:payment_module) { enable_module!("payment", customer, name: "Payments") }
  let(:token)    { "tok-abc123" }
  let(:expected_ref) { "ORD-#{Digest::SHA256.hexdigest(token)[0, 12].upcase}" }
  let(:start_path) { "/#{customer.id}/payments/checkout/start" }

  before { Current.customer = customer }

  # Mirrors what FeatureModules::Invocation.current returns after the JSON
  # session round-trip: a HashWithIndifferentAccess carrying the token + input.
  def stub_invocation(input:, module_key: "payment", tok: token, awaiting_input: false)
    allow_any_instance_of(Payments::CheckoutsController)
      .to receive(:current_invocation)
      .and_return({ module_key: module_key, customer_id: customer.id, token: tok, input: input,
                    awaiting_input: awaiting_input }.with_indifferent_access)
  end

  let(:input) do
    { amount: 25.00, currency: "CNY", subject: "Donation", body: "Happy birthday", metadata: { campaign: "x" } }
  end

  it "sends the shopper back to the framework entry step while the note is still owed" do
    stub_invocation(input: input, awaiting_input: true)
    get start_path
    expect(response).to redirect_to("/#{customer.id}/handoff")
    expect(Payments::Order.count).to eq(0)
  end

  it "materializes the order from the invocation input and forwards to the checkout" do
    stub_invocation(input: input)
    expect { get start_path }.to change(Payments::Order, :count).by(1)

    order = Payments::Order.for_current_customer.find_by!(external_ref: expected_ref)
    expect(order).to have_attributes(amount: 25.00, currency: "CNY", subject: "Donation", body: "Happy birthday")
    expect(response).to redirect_to("/#{customer.id}/payments/checkout?ref=#{expected_ref}")
  end

  it "is idempotent — replaying #start with the same token reuses the order" do
    stub_invocation(input: input)
    get start_path
    expect { get start_path }.not_to change(Payments::Order, :count)
  end

  it "materializes the smallest half-up rounded positive CNY amount" do
    stub_invocation(input: input.merge(amount: 0.005))
    get start_path
    expect(Payments::Order.for_current_customer.find_by!(external_ref: expected_ref).amount).to eq(0.01)
  end

  it "bounces to the customer home when there is no active payment invocation" do
    stub_invocation(input: input, module_key: "sms")

    get start_path
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("comp_payments.flash.no_active_request"))
    expect(Payments::Order.count).to eq(0)
  end

  it "refuses a cross-tenant invocation" do
    allow_any_instance_of(Payments::CheckoutsController)
      .to receive(:current_invocation)
      .and_raise(FeatureModules::CrossTenantViolation)

    get start_path
    expect(response).to have_http_status(:forbidden)
  end
end
