# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Activities::CreateSubscription do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }

  let(:payment_method) do
    create(:payment_method,
           customer:              customer,
           user:                  user,
           provider:              "stripe",
           psp_customer_id:       "cus_123",
           psp_payment_method_id: "pm_visa_1",
           status:                "active")
  end

  before do
    Current.customer = customer
    allow(Payments::Gateway).to receive(:subscribe).and_return(status: :pending_sign)
  end

  after { Current.reset }

  def call
    described_class.call(
      customer: customer, payment_method: payment_method,
      plan_name: "Gold", amount: 20.00, cycle: "monthly", currency: "usd"
    )
  end

  it "creates an active subscription bound to the payment method and its provider" do
    sub = call

    expect(sub).to be_persisted
    expect(sub.status).to eq("active")
    expect(sub.provider).to eq("stripe")
    expect(sub.payment_method_id).to eq(payment_method.id)
    expect(sub.customer_id).to eq(customer.id)
    expect(sub.amount).to eq(20.00)
    expect(sub.currency).to eq("usd")
  end

  it "anchors the first charge one cycle out so ChargeDueSubscriptions can pick it up" do
    sub = call
    expect(sub.next_charge_at).to be_present
    expect(sub.next_charge_at).to be > Time.current
  end

  it "mints a unique external_ref" do
    sub = call
    expect(sub.external_ref).to be_present
  end

  it "invokes the gateway subscribe hook" do
    call
    expect(Payments::Gateway).to have_received(:subscribe).with(customer: customer, subscription: kind_of(Payments::Subscription))
  end

  it "returns the existing live subscription instead of inserting a second" do
    first  = call
    second = call
    expect(second.id).to eq(first.id)
    expect(Payments::Subscription.where(payment_method_id: payment_method.id).count).to eq(1)
    expect(Payments::Gateway).to have_received(:subscribe).once
  end

  it "deduplicates a paused enrollment without reactivating it or creating another agreement" do
    first = call
    first.mark_paused!

    expect { expect(call.id).to eq(first.id) }.not_to change(Payments::Subscription, :count)
    expect(first.reload.status).to eq("paused")
    expect(Payments::Gateway).to have_received(:subscribe).once
  end

  it "calls the gateway outside the enrollment lock and preserves concurrent cancellation" do
    payment_method
    baseline = ActiveRecord::Base.connection.open_transactions
    allow(Payments::Gateway).to receive(:subscribe) do |customer:, subscription:|
      expect(ActiveRecord::Base.connection.open_transactions).to eq(baseline)
      Payments::Subscription.find(subscription.id).mark_cancelled!
      { status: :pending_sign }
    end

    expect(call.status).to eq("cancelled")
    expect(Payments::Subscription.where(payment_method_id: payment_method.id).sole.status).to eq("cancelled")
  end

  it "still enrolls a different plan on the same card" do
    call
    other = described_class.call(
      customer: customer, payment_method: payment_method,
      plan_name: "Silver", amount: 20.00, cycle: "monthly", currency: "usd"
    )
    expect(other.plan_name).to eq("Silver")
    expect(Payments::Subscription.where(payment_method_id: payment_method.id).count).to eq(2)
  end

  it "allows a new enroll after the matching live subscription is cancelled" do
    first = call
    first.mark_cancelled!
    second = call
    expect(second.id).not_to eq(first.id)
    expect(second.status).to eq("active")
  end

  it "activates a stranded pending_sign row instead of reporting it as done" do
    stranded = create(:payment_subscription,
      customer: customer, provider: "stripe", payment_method: payment_method,
      external_ref: "stranded-pending", plan_name: "Gold", amount: 20.00,
      cycle: "monthly", currency: "usd", status: "pending_sign")

    result = call

    expect(result.id).to eq(stranded.id)
    expect(result.status).to eq("active")
    expect(Payments::Gateway).to have_received(:subscribe).once
  end

  it "rejects a billing vault token" do
    platform = ensure_platform_customer(name: "Platform Owner")
    Current.customer = platform
    token = create(:payment_method,
      customer: platform, user_id: nil, billing_customer_id: customer.id,
      billing_authorized_by_id: user.id, provider: "stripe", status: "active")

    expect {
      described_class.call(
        customer: platform, payment_method: token,
        plan_name: "Gold", amount: 20.00, cycle: "monthly", currency: "usd"
      )
    }.to raise_error(Payments::Errors::TenantMismatch)
    expect(Payments::Subscription.where(payment_method_id: token.id)).to be_empty
  end

  it "does not leave a pending_sign row when the gateway is missing credentials" do
    allow(Payments::Gateway).to receive(:subscribe)
      .and_raise(Payments::Errors::CredentialsMissing, "none")

    expect { call }.to raise_error(Payments::Errors::CredentialsMissing)
    expect(Payments::Subscription.where(customer_id: customer.id)).to be_empty
  end
end
