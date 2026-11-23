# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Logical billing lifecycle queries" do
  it "keeps valid pending and paused intents current without granting purchased entitlements" do
    %w[pending paused].each do |status|
      subscription = create(:billing_subscription, status: status)
      current = Billing::Entitlements.current_subscription(customer: subscription.customer)
      expect(current).to eq(subscription)
      expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:free)
    end
  end

  it "uses the actual trial deadline independently of stored live status or a later period end" do
    subscription = create(:billing_subscription, :trialing, current_period_start: 20.days.ago,
      trial_end: 8.days.ago, current_period_end: 1.day.from_now)
    subscription.update!(plan_snapshot: subscription.plan_snapshot.merge("grace_period_days" => 7))
    stored = subscription.attributes
    expect(Billing::Entitlements.current_subscription(customer: subscription.customer)).to be_nil
    expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:free)
    expect(subscription.reload.attributes).to eq(stored)
    expired = Billing::Activities::ExpireOverdueSubscription.call(subscription: subscription, at: Time.current)
    expect(expired.status).to eq(:expired)
    expect(subscription.reload.ended_at).to eq(subscription.trial_end + 7.days)
  end

  it "does not terminate an ordinary zero-grace renewal before its exact due boundary can issue" do
    freeze_time do
      subscription = create(:billing_subscription, current_period_start: 1.month.ago, current_period_end: Time.current)
      subscription.update!(plan_snapshot: subscription.plan_snapshot.merge("grace_period_days" => 0))
      result = Billing::Renewal.prepare(subscription: subscription, at: Time.current)
      expect(result.status).to eq(:invoice_ready)
      expect(result.invoice.period_start).to eq(Time.current)
      expect(subscription.reload.status).to eq("active")
      expect(subscription.current_period_end).to eq(Time.current)
    end
  end

  it "prepares a zero-grace renewal after a delayed scheduler without advancing or granting unpaid access" do
    freeze_time do
      Billing::Settings.current.update!(collection_mode: "manual", grace_period_days: 0)
      boundary = 2.hours.ago
      subscription = create(:billing_subscription, current_period_start: boundary - 1.month, current_period_end: boundary)
      expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:free)
      result = Billing::Renewal.prepare(subscription: subscription, at: Time.current)
      expect(result.status).to eq(:invoice_ready)
      invoice = result.invoice
      expect(invoice.period_start).to eq(boundary)
      expect(invoice.due_at).to eq(boundary)
      expect(invoice.terms_snapshot["grace_period_days"]).to eq(0)
      expect(Billing::PlanChangePolicy.grace_deadline(invoice)).to eq(boundary)
      expect(Billing::PlanChangePolicy.request_deadline(invoice)).to eq(invoice.period_end)
      expect(subscription.reload.current_period_end).to eq(boundary)
      Billing::Activities::FinalizeInvoice.call(invoice: invoice)
      Billing::Activities::RecordInvoiceDebt.call(invoice: invoice, at: Time.current)
      expect(subscription.reload.status).to eq("past_due")
      expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:free)
      settled = Billing::Activities::MarkInvoicePaid.call(invoice: invoice, source: :manual,
        actor: find_or_create_platform_owner, reference: "zero-grace-recovery", paid_at: Time.current)
      expect(settled.status).to eq(:paid)
      expect(subscription.reload.current_period_start).to eq(boundary)
      expect(subscription.current_period_end).to eq(invoice.period_end)
      expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:purchased)
    end
  end

  it "settles a delayed free initial invoice with zero grace without requiring timestamp equality" do
    freeze_time do
      allow(Billing::Onboarding).to receive(:call)
      Billing::Settings.current.update!(grace_period_days: 0)
      customer = create(:customer)
      result = Billing::Activities::Subscribe.call(customer: customer, plan: create(:billing_plan, :free), request_key: SecureRandom.uuid)
      travel 10.minutes
      Billing::Activities::FinalizeInvoice.call(invoice: result.invoice)
      expect(result.invoice.reload.status).to eq("paid")
      expect(result.invoice.settlement_source).to eq("zero")
      expect(result.subscription.reload.status).to eq("active")
      expect(result.subscription.current_period_start).to eq(result.invoice.period_start)
    end
  end

  it "uses issued renewal grace instead of changed settings or current catalog limits" do
    subscription = create(:billing_subscription, current_period_start: 1.month.ago, current_period_end: 2.days.ago)
    terms = Billing::PlanChangePolicy.invoice_terms(subscription.plan_snapshot, due_at: subscription.current_period_end)
      .merge("grace_period_days" => 3, "billing_anchor_day" => subscription.billing_anchor_day,
        "billing_anchor_month" => subscription.billing_anchor_month)
    invoice = Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: :renewal,
      idempotency_key: "renewal:logical-grace:#{subscription.id}", period_start: subscription.current_period_end,
      period_end: subscription.current_period_end + 1.month, terms_snapshot: terms)
    Billing::Activities::FinalizeInvoice.call(invoice: invoice)
    Billing::Settings.current.update!(grace_period_days: 99)
    expect(Billing::Entitlements.current_subscription(customer: subscription.customer)).to eq(subscription)
    expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:grace)
    expect(Billing::Entitlements.current_subscription(customer: subscription.customer, at: invoice.collection_deadline + 1.second)).to be_nil
  end

  it "treats an explicitly voided unpaid initial intent as ended without a GET-side mutation" do
    subscription = create(:billing_subscription, status: "pending")
    invoice = Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: :initial,
      idempotency_key: "initial:#{subscription.id}", period_start: subscription.current_period_start,
      period_end: subscription.current_period_end,
      terms_snapshot: Billing::PlanChangePolicy.invoice_terms(subscription.plan_snapshot, due_at: Time.current))
    Billing::Activities::FinalizeInvoice.call(invoice: invoice)
    expect(Billing::Activities::VoidInvoice.call(invoice: invoice).status).to eq(:voided)
    expect(Billing::Entitlements.current_subscription(customer: subscription.customer)).to be_nil
    expect(subscription.reload.status).to eq("pending")
    expect(Billing::Activities::ExpireOverdueSubscription.call(subscription: subscription, at: Time.current).status).to eq(:expired)
    expect(subscription.reload.ended_at).to eq(invoice.reload.updated_at)
  end
end
