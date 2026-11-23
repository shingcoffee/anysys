# frozen_string_literal: true
require "rails_helper"
require_relative "partition_b_helpers"

RSpec.describe "Billing collection settlement integration" do
  include BillingPartitionBHelpers

  it "applies a persisted immediate target exactly once after late valid settlement" do
    aggregate = billing_aggregate
    subscription = aggregate.fetch(:subscription)
    subscription.update!(status: "active")
    target = create(:billing_plan, amount_usd: 200, amount_cny: 200)
    target_terms = Billing::PlanChangePolicy.snapshot(plan: target, currency: "USD")
    change = Billing::PlanChange.create!(customer_id: subscription.customer_id, subscription: subscription,
      from_plan: aggregate.fetch(:plan), to_plan: target, request_key: SecureRandom.uuid,
      kind: "immediate", status: "awaiting_payment", effective_at: Time.current,
      period_start: subscription.current_period_start, period_end: subscription.current_period_end,
      from_snapshot: subscription.plan_snapshot, target_snapshot: target_terms)
    invoice = Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: :proration,
      idempotency_key: "plan-change:#{change.id}", period_start: subscription.current_period_start,
      period_end: subscription.current_period_end, terms_snapshot: aggregate.fetch(:invoice).terms_snapshot.merge(target_terms), plan_change: change,
      extra_line_items: [{ description: "Proration", kind: "proration", quantity: 1, unit_amount_cents: 5000, amount_cents: 5000 }])
    Billing::Activities::FinalizeInvoice.call(invoice: invoice)
    expect(subscription.reload.billing_plan_id).to eq(aggregate.fetch(:plan).id)
    payment = billing_payment(aggregate.merge(invoice: invoice), paid_at: 1.day.from_now)
    2.times { Billing::Activities::MarkInvoicePaid.call(invoice: invoice, payment: payment, source: :gateway, paid_at: payment.paid_at) }
    expect(subscription.reload.billing_plan_id).to eq(target.id)
    expect(subscription.plan_snapshot).to eq(target_terms)
    expect(change.reload.status).to eq("applied")
    expect(invoice.reload.entitlements_applied_at).to eq(payment.paid_at)
    expect(Billing::Notice.where(kind: "payment_succeeded", billing_invoice_id: invoice.id).count).to eq(1)
  end
end
