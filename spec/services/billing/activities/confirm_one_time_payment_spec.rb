# frozen_string_literal: true

require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::ConfirmOneTimePayment do
  include BillingPartitionBHelpers
  before { allow_test_root_transaction }

  def offer_providers(*keys)
    allow(Billing::OneTimeProviders).to receive(:call) do |currency:|
      keys.map do |key|
        { key: key, label_key: "comp_payments.gateways.#{key}.name",
          supported_currencies: currency.to_s.upcase == "CNY" ? %w[CNY] : %w[USD CNY] }
      end
    end
  end

  def stub_charge(payload:, psp_id: "pi_confirm")
    allow(Payments::Gateway).to receive(:charge).and_return(prepay_payload: payload, psp_transaction_id: psp_id)
  end

  def start_stripe(aggregate)
    offer_providers("stripe")
    stub_charge(payload: { "client_secret" => "secret_confirm" }, psp_id: "pi_confirm")
    Billing::Activities::StartOneTimePayment.call(invoice: aggregate.fetch(:invoice), provider: "stripe")
  end

  it "returns payment_not_found when the invoice has no one-time attempt" do
    aggregate = billing_aggregate
    result = described_class.call(invoice: aggregate.fetch(:invoice))
    expect(result.status).to eq(:invalid)
    expect(result.reason).to eq(:payment_not_found)
    expect(aggregate.fetch(:invoice).reload).to be_open
  end

  it "returns pending while the PSP capture is still outstanding" do
    aggregate = billing_aggregate
    start_stripe(aggregate)
    allow(Payments::Activities::Query).to receive(:call).and_return(status: :pending)

    result = described_class.call(invoice: aggregate.fetch(:invoice).reload)
    expect(result.status).to eq(:pending)
    expect(aggregate.fetch(:invoice).reload).to be_open
    expect(aggregate.fetch(:invoice).attempt_count).to eq(0)
  end

  it "settles a captured payment, activates the subscription, and leaves the recurring method alone" do
    aggregate = billing_aggregate
    started = start_stripe(aggregate)
    payment = started.record.payment
    method = aggregate.fetch(:method)
    allow(Payments::Activities::Query).to receive(:call) do |**|
      payment.reload.mark_succeeded!(psp_id: "pi_confirm", at: Time.current, notify: {})
      { status: :succeeded }
    end

    result = described_class.call(invoice: aggregate.fetch(:invoice).reload, out_trade_no: payment.out_trade_no)

    invoice = aggregate.fetch(:invoice).reload
    expect(result.status).to eq(:succeeded)
    expect(invoice).to be_paid
    expect(invoice.payment_id).to eq(payment.id)
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
    expect(method.reload).to be_active
    expect(method.is_default).to be(true)
    expect(invoice.attempt_count).to eq(0)
  end

  it "marks a closed PSP trade failed without a dunning penalty" do
    aggregate = billing_aggregate
    started = start_stripe(aggregate)
    payment = started.record.payment
    allow(Payments::Activities::Query).to receive(:call) do |**|
      payment.reload.mark_closed!
      { status: :closed }
    end

    result = described_class.call(invoice: aggregate.fetch(:invoice).reload)
    invoice = aggregate.fetch(:invoice).reload
    expect(result.status).to eq(:failed)
    expect(result.reason).to eq(:one_time_charge_failed)
    expect(invoice).to be_open
    expect(invoice.attempt_count).to eq(0)
    expect(invoice.collection_attempts.sole.state).to eq("failed")
    expect(Billing::Notice.where(kind: "payment_failed", billing_invoice_id: invoice.id)).to be_empty
  end

  it "returns payment_not_found for a mismatched out_trade_no" do
    aggregate = billing_aggregate
    start_stripe(aggregate)
    result = described_class.call(invoice: aggregate.fetch(:invoice).reload, out_trade_no: "bi-does-not-exist")
    expect(result.status).to eq(:invalid)
    expect(result.reason).to eq(:payment_not_found)
  end
end
