# frozen_string_literal: true
require "rails_helper"
require_relative "partition_b_helpers"

RSpec.describe "Billing settlement and renewal integrity" do
  include BillingPartitionBHelpers
  let(:subscription) { create(:billing_subscription, current_period_start: 1.month.ago, current_period_end: Time.current.change(usec: 0)) }
  let(:owner) { find_or_create_platform_owner }

  before do
    allow(Billing::Onboarding).to receive(:call)
    Billing::Settings.current.update!(collection_mode: "manual", grace_period_days: 7)
    create(:billing_plan, :default_plan)
  end

  def finalize(invoice)
    Billing::Activities::FinalizeInvoice.call(invoice: invoice)
  end

  def settle(invoice, at: Time.current)
    Billing::Activities::MarkInvoicePaid.call(invoice: invoice, source: :manual, actor: owner, reference: "wire-#{invoice.id}", paid_at: at)
  end

  it "recovers valid uncollectible renewal debt, advances once and preserves issued policy" do
    boundary = subscription.current_period_end
    invoice = Billing::Renewal.prepare(subscription: subscription).invoice
    finalize(invoice)
    Billing::Activities::RecordInvoiceDebt.call(invoice: invoice, at: boundary + 1.day)
    invoice.update!(status: "uncollectible", collection_state: "exhausted")
    Billing::Settings.current.update!(grace_period_days: 0)
    expect(Billing::Entitlements.for(customer: subscription.customer, at: boundary + 2.days).source).to eq(:grace)
    expect(settle(invoice, at: boundary + 2.days).status).to eq(:paid)
    expect(subscription.reload.current_period_start).to eq(boundary)
    expect(subscription.status).to eq("active")
    expect(subscription.past_due_at).to be_nil
    finish = subscription.current_period_end
    expect(settle(invoice).status).to eq(:unchanged)
    expect(subscription.reload.current_period_end).to eq(finish)
  end

  it "records late payment after expiry without resurrecting access" do
    invoice = Billing::Renewal.prepare(subscription: subscription).invoice
    finalize(invoice)
    deadline = Billing::PlanChangePolicy.grace_deadline(invoice)
    Billing::Activities::ExpireOverdueSubscription.call(subscription: subscription, at: deadline)
    expect(settle(invoice, at: deadline + 1.second).status).to eq(:review_required)
    expect(invoice.reload.status).to eq("paid")
    expect(invoice.settlement_review_code).to eq("subscription_ended")
    expect(subscription.reload.status).to eq("expired")
    expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:free)
  end

  it "does not extend pending initial service dates on a late-but-valid payment" do
    customer = create(:customer)
    accepted = Billing::Activities::Subscribe.call(customer: customer, plan: create(:billing_plan), request_key: SecureRandom.uuid)
    original = accepted.subscription.current_period_end
    finalize(accepted.invoice)
    settle(accepted.invoice, at: accepted.invoice.due_at + 2.days)
    expect(accepted.subscription.reload.current_period_end).to eq(original)
    expect(accepted.subscription.status).to eq("active")
  end

  it "expires a late-settled initial request even when expiry cron has not run" do
    customer = create(:customer)
    accepted = Billing::Activities::Subscribe.call(customer: customer, plan: create(:billing_plan), request_key: SecureRandom.uuid)
    finalize(accepted.invoice)
    deadline = Billing::PlanChangePolicy.grace_deadline(accepted.invoice)
    result = settle(accepted.invoice, at: deadline + 1.second)
    expect(result.status).to eq(:review_required)
    expect(accepted.subscription.reload.status).to eq("expired")
    expect(accepted.subscription.ended_at).to eq(deadline)
    expect(Billing::Subscription.where(customer_id: customer.id).live.count).to eq(0)
  end

  it "uses accepted downgrade/cadence snapshots even after catalog archival" do
    subscription.update!(current_period_end: 1.day.from_now)
    target = create(:billing_plan, :yearly, amount_usd: 49)
    change = Billing::Activities::ChangePlan.call(subscription: subscription, new_plan: target, request_key: SecureRandom.uuid).plan_change
    Billing::Catalog::ArchivePlan.call(plan: target)
    boundary = subscription.current_period_end
    invoice = Billing::Renewal.prepare(subscription: subscription, at: boundary).invoice
    finalize(invoice)
    expect(subscription.reload.interval).to eq("monthly")
    settle(invoice, at: boundary)
    expect(subscription.reload.interval).to eq("yearly")
    expect(subscription.amount_cents).to eq(4900)
    expect(subscription.current_period_end).to eq(boundary + 1.year)
    expect(change.reload.status).to eq("applied")
  end

  it "reuses an unpaid renewal rather than minting successive periods" do
    invoice = Billing::Renewal.prepare(subscription: subscription).invoice
    finalize(invoice)
    Billing::Activities::RecordInvoiceDebt.call(invoice: invoice, at: Time.current)
    3.times do
      expect(Billing::Renewal.prepare(subscription: subscription, at: 2.days.from_now).invoice.id).to eq(invoice.id)
    end
    expect(subscription.invoices.count).to eq(1)
    expect(subscription.reload.current_period_end).to eq(invoice.period_start)
  end

  it "safely cancels a frozen scheduled renewal and reuses the boundary revision for the old plan" do
    subscription.update!(current_period_end: 1.day.from_now)
    target = create(:billing_plan, amount_usd: 29)
    change = Billing::Activities::ChangePlan.call(subscription: subscription, new_plan: target, request_key: SecureRandom.uuid).plan_change
    boundary = subscription.current_period_end
    first = Billing::Renewal.prepare(subscription: subscription, at: boundary).invoice
    finalize(first)
    expect(Billing::Activities::CancelPlanChange.call(subscription: subscription, plan_change: change).status).to eq(:cancelled)
    expect(first.reload.status).to eq("void")
    replacement = Billing::Renewal.prepare(subscription: subscription, at: boundary).invoice
    expect(replacement.terms_snapshot["amount_cents"]).to eq(9900)
    expect(replacement.idempotency_key).to eq("#{first.idempotency_key}:revision:1")
    expect(Billing::Renewal.prepare(subscription: subscription, at: boundary).invoice.id).to eq(replacement.id)
    expect(first.terms_snapshot["amount_cents"]).to eq(2900)
  end

  it "cancels a safely unpaid upgrade at the boundary and renews the purchased terms" do
    subscription.update!(current_period_end: 1.day.from_now)
    result = Billing::Activities::ChangePlan.call(subscription: subscription, new_plan: create(:billing_plan, amount_usd: 199), request_key: SecureRandom.uuid)
    finalize(result.invoice)
    renewed = Billing::Renewal.prepare(subscription: subscription, at: subscription.current_period_end)
    expect(result.invoice.reload.status).to eq("void")
    expect(result.plan_change.reload.status).to eq("expired")
    expect(renewed.invoice.terms_snapshot["amount_cents"]).to eq(9900)
    expect(subscription.reload.status).to eq("active")
  end

  it "does not mark a purchased subscription past_due for proration failure" do
    subscription.update!(current_period_end: 1.day.from_now)
    result = Billing::Activities::ChangePlan.call(subscription: subscription, new_plan: create(:billing_plan, amount_usd: 199), request_key: SecureRandom.uuid)
    finalize(result.invoice)
    Billing::Activities::RecordInvoiceDebt.call(invoice: result.invoice, at: 2.days.from_now)
    expect(subscription.reload.status).to eq("active")
    expect(subscription.past_due_at).to be_nil
  end

  it "keeps source period correlation while holding an ambiguous upgrade, then uses its original boundary" do
    subscription.update!(current_period_end: 1.day.from_now)
    change = Billing::Activities::ChangePlan.call(subscription: subscription, new_plan: create(:billing_plan, amount_usd: 199), request_key: SecureRandom.uuid)
    finalize(change.invoice)
    # Actual durable attempt populations, rather than a mocked pending result.
    account = create(:payment_merchant_account, customer: owner.customer, provider: "stripe")
    method = Billing::PaymentMethod.create!(customer: subscription.customer, provider: "stripe", status: "pending",
      request_key: SecureRandom.uuid, merchant_account: account)
    attempt = Billing::CollectionAttempt.create!(customer: subscription.customer, invoice: change.invoice,
      payment_method: method, merchant_account: account, ordinal: 1, request_key: SecureRandom.uuid, state: "unknown")
    boundary = subscription.current_period_end
    expect(Billing::Renewal.prepare(subscription: subscription, at: boundary).status).to eq(:blocked)
    expect(Billing::Activities::CancelPlanChange.call(subscription: subscription, plan_change: change.plan_change).status).to eq(:conflict)
    expect(subscription.invoices.count).to eq(1)
    attempt.update!(state: "failed", completed_at: boundary)
    expect(settle(change.invoice, at: boundary + 1.day).status).to eq(:paid)
    renewal = Billing::Renewal.prepare(subscription: subscription, at: boundary + 1.day)
    expect(renewal.invoice.period_start).to eq(boundary)
    expect(renewal.invoice.terms_snapshot["amount_cents"]).to eq(19900)
  end

  it "projects a recorded on-time renewal capture before an overdue reenrollment decision" do
    aggregate = billing_aggregate(mode: "manual", purpose: "renewal")
    old = aggregate.fetch(:subscription)
    invoice = aggregate.fetch(:invoice)
    old.update!(current_period_start: invoice.period_start - 1.month, current_period_end: invoice.period_start)
    payment = billing_payment(aggregate, paid_at: invoice.due_at + 1.day)
    expect(invoice.reload.status).to eq("open")
    travel_to(invoice.collection_deadline + 1.second) do
      result = Billing::Activities::Subscribe.call(customer: aggregate.fetch(:tenant), plan: aggregate.fetch(:plan), request_key: SecureRandom.uuid)
      expect(result.status).to eq(:unchanged)
      expect(result.subscription.id).to eq(old.id)
      expect(old.reload.status).to eq("active")
      expect(old.current_period_end).to eq(invoice.period_end)
      expect(invoice.reload.payment_id).to eq(payment.id)
      expect(invoice.entitlements_applied_at).to eq(payment.paid_at)
      expect(old.invoices.count).to eq(1)
    end
  end

  it "lets renewal preparation recover recorded settlement without prematurely ending its base" do
    aggregate = billing_aggregate(mode: "manual", purpose: "renewal")
    old = aggregate.fetch(:subscription)
    invoice = aggregate.fetch(:invoice)
    old.update!(current_period_start: invoice.period_start - 1.month, current_period_end: invoice.period_start)
    billing_payment(aggregate, paid_at: invoice.due_at + 1.day)
    result = Billing::Renewal.prepare(subscription: old, at: invoice.collection_deadline + 1.second)
    expect(result.status).to eq(:not_due)
    expect(old.reload.status).to eq("active")
    expect(old.current_period_end).to eq(invoice.period_end)
    expect(invoice.reload.status).to eq("paid")
  end

  it "ends an overdue intent but blocks reenrollment while its real provider attempt is unknown" do
    aggregate = billing_aggregate(mode: "manual")
    invoice = aggregate.fetch(:invoice)
    old = aggregate.fetch(:subscription)
    payment = billing_payment(aggregate, state: "unknown")
    payment.update!(status: "pending")
    expect(Billing::Providers).not_to receive(:charge)
    travel_to(invoice.collection_deadline + 1.second) do
      2.times do
        result = Billing::Activities::Subscribe.call(customer: aggregate.fetch(:tenant), plan: aggregate.fetch(:plan), request_key: SecureRandom.uuid)
        expect(result.status).to eq(:conflict)
        expect(result.reason).to eq(:collection_in_flight)
      end
      expect(old.reload.status).to eq("expired")
      expect(old.invoices.count).to eq(1)
      expect(invoice.reload.status).to eq("open")
      expect(invoice.collection_attempts.first.state).to eq("unknown")
      expect(payment.reload.status).to eq("pending")

      # A verified capture ends ambiguity. B records real late money and review;
      # only then can this explicit request create a separate paid enrollment.
      payment.mark_succeeded!(psp_id: "pi_late_reenrollment", at: Time.current, notify: {})
      result = Billing::Activities::Subscribe.call(customer: aggregate.fetch(:tenant), plan: aggregate.fetch(:plan), request_key: SecureRandom.uuid)
      expect(result.status).to eq(:awaiting_payment)
      expect(result.subscription.id).not_to eq(old.id)
      expect(invoice.reload.status).to eq("paid")
      expect(invoice.settlement_review_code).to eq("subscription_ended")
      expect(invoice.payment_id).to eq(payment.id)
      expect(invoice.collection_attempts.first.reload.state).to eq("succeeded")
      expect(old.reload.status).to eq("expired")
      expect(Billing::Subscription.where(customer_id: old.customer_id).live.count).to eq(1)
    end
  end
end
