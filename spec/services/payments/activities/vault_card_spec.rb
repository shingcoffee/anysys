# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Activities::VaultCard do
  let_it_be(:customer) { create(:customer) }
  let(:gateway_result) do
    { client_secret: "seti_secret_xxx", psp_customer_id: "cus_abc123" }
  end
  let(:user)       { create(:user, customer: customer) }
  let(:return_url) { "https://example.com/return" }

  before do
    Current.customer = customer
    allow(Payments::Gateway).to receive(:vault_card).and_return(gateway_result)
  end

  def vault(**overrides)
    described_class.call(customer: customer, user: user, provider: "stripe",
                         return_url: return_url, **overrides)
  end

  it "calls the gateway with the correct arguments" do
    vault

    expect(Payments::Gateway).to have_received(:vault_card).with(
      customer:   customer,
      user:       user,
      provider:   "stripe",
      return_url: "https://example.com/return"
    )
  end

  it "persists a PaymentMethod row with status active" do
    pm = vault[:payment_method]
    expect(pm).to be_persisted
    expect(pm.status).to eq("active")
    expect(pm.provider).to eq("stripe")
    expect(pm.psp_customer_id).to eq("cus_abc123")
    expect(pm.customer_id).to eq(customer.id)
    expect(pm.user_id).to eq(user.id)
  end

  it "sets psp_payment_method_id to a pending placeholder bound to the SetupIntent" do
    allow(Payments::Gateway).to receive(:vault_card).and_return(
      gateway_result.merge(setup_intent_id: "seti_bound")
    )
    expect(vault[:payment_method].psp_payment_method_id).to eq("pending:seti_bound")
  end

  it "returns the client_secret from the gateway" do
    expect(vault[:client_secret]).to eq("seti_secret_xxx")
  end
end
