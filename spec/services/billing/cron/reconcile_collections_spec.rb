# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Cron::ReconcileCollections do
  include BillingPartitionBHelpers

  it "recovers a committed accepted draft once with its original number, lines and coupon reservation" do
    aggregate = billing_aggregate(mode: "manual", finalize: false)
    invoice = aggregate.fetch(:invoice)
    subscription = aggregate.fetch(:subscription)
    Billing::Activities::ApplyCoupon.call(subscription: subscription, coupon: create(:billing_coupon, percent_off: 20, duration: "once"))
    original_lines = invoice.line_items.pluck(:id, :amount_cents)
    expect(invoice.reload.status).to eq("draft")
    expect(Payments::Gateway).not_to receive(:charge_subscription)
    described_class.perform
    issued = invoice.reload.attributes.slice(*Billing::Invoice::FINANCIAL_ATTRIBUTES)
    described_class.perform
    expect(invoice.reload.attributes.slice(*Billing::Invoice::FINANCIAL_ATTRIBUTES)).to eq(issued)
    expect(invoice.status).to eq("open")
    expect(invoice.line_items.where(kind: "subscription").pluck(:id, :amount_cents)).to eq(original_lines)
    expect(invoice.discount_cents).to eq(2000)
    expect(subscription.reload.coupon_redemption.cycles_used).to eq(1)
    expect(Billing::InvoiceSequence.find_by!(customer_id: invoice.customer_id).last_value).to eq(1)
    expect(Billing::Notice.where(event_key: "invoice_issued:#{invoice.id}").count).to eq(1)
    expect(enqueued_jobs.count { |job| job[:job] == Billing::FinalizeInvoiceJob && job[:args] == [invoice.id] }).to eq(1)
  end

  it "does not finalize a terminal subscription's stale draft" do
    aggregate = billing_aggregate(mode: "manual", finalize: false)
    aggregate.fetch(:subscription).update!(status: "expired", ended_at: Time.current)
    described_class.perform
    expect(aggregate.fetch(:invoice).reload.status).to eq("draft")
    expect(aggregate.fetch(:invoice).number).to be_nil
    expect(Billing::InvoiceSequence.where(customer_id: aggregate.fetch(:tenant).id)).to be_empty
  end

  it "does not finalize a draft for a different renewal boundary" do
    aggregate = billing_aggregate(mode: "manual")
    subscription = aggregate.fetch(:subscription)
    subscription.update!(status: "active")
    draft = Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: :renewal,
      idempotency_key: "stale-renewal", period_start: subscription.current_period_start,
      period_end: subscription.current_period_end, terms_snapshot: aggregate.fetch(:invoice).terms_snapshot)
    described_class.perform
    expect(draft.reload.status).to eq("draft")
    expect(draft.number).to be_nil
  end
end
