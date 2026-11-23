# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Activities::ChargeToken do
  let_it_be(:customer) { create(:customer) }
  let(:order) do
    create(:payment_order, external_ref: "ct-order-1", amount: 50.00,
           subject: "Monthly plan", currency: "CNY")
  end
  let(:payment_method) do
    create(:payment_method,
           customer:              customer,
           user:                  user,
           provider:              "stripe",
           psp_customer_id:       "cus_abc",
           psp_payment_method_id: "pm_visa_4242",
           brand:                 "visa",
           last4:                 "4242",
           exp_month:             12,
           exp_year:              2027,
           status:                "active")
  end
  let(:user)     { create(:user, customer: customer) }

  before do
    Current.customer = customer
    create(:payment_merchant_account, customer: customer, provider: "stripe")
  end

  def charge_token(**overrides)
    described_class.call(customer: customer, order: order, payment_method: payment_method, **overrides)
  end

  context "when the charge succeeds" do
    before do
      allow(Payments::Gateway).to receive(:charge_token).and_return(
        psp_transaction_id: "pi_success_1", status: :succeeded, raw: { "id" => "pi_success_1" }
      )
    end

    it "creates a Payment row with status succeeded" do
      result = charge_token

      expect(result).to be_a(Payments::Payment)
      expect(result.status).to eq("succeeded")
      expect(result.provider).to eq("stripe")
      expect(result.psp_transaction_id).to eq("pi_success_1")
      expect(result.user_id).to eq(user.id)
    end

    it "delegates to Gateway.charge_token with correct args" do
      charge_token

      expect(Payments::Gateway).to have_received(:charge_token).with(
        customer:       customer,
        order:          order,
        payment:        instance_of(Payments::Payment),
        payment_method: payment_method
      )
    end

    it "uses flow 'card' on the Payment row" do
      expect(charge_token.flow).to eq("card")
    end
  end

  context "when the charge fails (card declined)" do
    before do
      allow(Payments::Gateway).to receive(:charge_token).and_return(
        psp_transaction_id: nil, status: :failed, raw: { "error" => "card_declined" }
      )
    end

    it "raises CardDeclined so the cron does not advance next_charge_at" do
      expect { charge_token }.to raise_error(Payments::Errors::CardDeclined)
    end

    it "still persists the Payment row with status failed before raising" do
      charge_token rescue Payments::Errors::CardDeclined

      payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).last
      expect(payment).to be_present
      expect(payment.status).to eq("failed")
    end
  end

  context "when the charge requires interactive authentication (SCA)" do
    before do
      allow(Payments::Gateway).to receive(:charge_token).and_return(
        psp_transaction_id: "pi_ra_1", status: :requires_action,
        client_secret: "pi_ra_1_secret", raw: { "id" => "pi_ra_1" }
      )
    end

    it "raises PaymentRequiresAction so the cron pauses instead of advancing" do
      expect { charge_token }.to raise_error(Payments::Errors::PaymentRequiresAction)
    end

    it "stashes the client_secret on the pending payment for on-session recovery" do
      charge_token rescue Payments::Errors::PaymentRequiresAction

      payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).last
      expect(payment.status).to eq("pending")
      expect(payment.requires_action?).to be(true)
      expect(payment.recovery_client_secret).to eq("pi_ra_1_secret")
    end
  end

  context "when called with a PaymentMethod from a different customer" do
    let(:other_customer) { create(:customer) }

    it "raises TenantMismatch without creating a Payment" do
      expect {
        charge_token(customer: other_customer)
      }.to raise_error(Payments::Errors::TenantMismatch)

      expect(Payments::Payment.unscoped_by_tenant.where(customer_id: other_customer.id).count).to eq(0)
    end
  end

  context "when the gateway raises Payments::Errors::ApiError (C2)" do
    before do
      allow(Payments::Gateway).to receive(:charge_token)
        .and_raise(Payments::Errors::ApiError.new("card network unreachable", code: "x", payload: {}))
    end

    it "preserves an unclassified API outcome and re-raises without allowing a fresh attempt" do
      expect { charge_token }.to raise_error(Payments::Errors::ApiError)

      payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).last
      expect(payment.status).to eq("created")
      expect(payment.failure_reason).to be_blank
    end
  end

  context "when the gateway raises Payments::Errors::TransportError (ambiguous)" do
    before do
      allow(Payments::Gateway).to receive(:charge_token)
        .and_raise(Payments::Errors::TransportError, "timeout")
    end

    it "leaves the payment row as created (not failed) so a retry can reuse it" do
      expect { charge_token }.to raise_error(Payments::Errors::TransportError)

      payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).last
      expect(payment.status).to eq("created")
    end
  end

  it "reuses an uncertain API-error attempt without allocating another payment" do
    error = Payments::Errors::ApiError.new("provider outcome unknown")
    error.define_singleton_method(:uncertain?) { true }
    allow(Payments::Gateway).to receive(:charge_token).and_raise(error)

    expect { charge_token }.to raise_error(Payments::Errors::ApiError)
    original = order.payments.sole
    expect(original.status).to eq("created")

    allow(Payments::Gateway).to receive(:charge_token)
      .and_return(status: :succeeded, psp_transaction_id: "pi_same", raw: {})
    result = charge_token

    expect(result.id).to eq(original.id)
    expect(result.out_trade_no).to eq(original.out_trade_no)
    expect(order.payments.count).to eq(1)
  end

  it "does not enter dunning after an SCA response loses a race with a verified capture" do
    allow(Payments::Gateway).to receive(:charge_token) do |**kwargs|
      Payments::Payment.find(kwargs[:payment].id).mark_succeeded!(psp_id: "pi_captured", at: Time.current, notify: {})
      { status: :requires_action, psp_transaction_id: "pi_captured", client_secret: "stale" }
    end

    expect(charge_token.status).to eq("succeeded")
    expect(order.reload.status).to eq("paid")
  end

  it "refuses to treat an unknown PSP status as a completed period" do
    allow(Payments::Gateway).to receive(:charge_token).and_return(status: :unknown, raw: {})

    expect { charge_token }.to raise_error(Payments::Errors::TransportError)
    expect(order.payments.sole.status).to eq("created")
    expect(order.reload.status).to eq("pending")
  end

  context "when called with an existing payment: row (stalled-attempt retry)" do
    let!(:stalled) do
      create(:payment,
             payment_order: order, provider: "stripe", flow: "card",
             out_trade_no: "ct-stalled-1", amount: order.amount, status: "created")
    end

    before do
      allow(Payments::Gateway).to receive(:charge_token).and_return(
        psp_transaction_id: "pi_reuse_1", status: :succeeded, raw: {}
      )
    end

    it "reuses the given payment row instead of creating a new one" do
      expect {
        charge_token(payment: stalled)
      }.not_to change(Payments::Payment, :count)

      expect(stalled.reload.status).to eq("succeeded")
      expect(stalled.psp_transaction_id).to eq("pi_reuse_1")
    end

    it "passes the reused payment row to Gateway.charge_token" do
      charge_token(payment: stalled)

      expect(Payments::Gateway).to have_received(:charge_token).with(
        customer:       customer,
        order:          order,
        payment:        stalled,
        payment_method: payment_method
      )
    end
  end
end
