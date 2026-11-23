# frozen_string_literal: true
require "rails_helper"
require "concurrent"

RSpec.describe "Concurrent billing intents" do
  self.use_transactional_tests = false

  before do
    raise "Committed fixtures required" if ApplicationRecord.connection.transaction_open?
    @existing_settings = Billing::Settings.find_by(singleton_guard: 0)
    @settings = @existing_settings || Billing::Settings.current
    @original_mode = @settings.collection_mode
    @original_grace = @settings.grace_period_days
    @settings.update!(collection_mode: "manual", grace_period_days: 7)
    allow(Billing::Onboarding).to receive(:call)
    @existing_default = Billing::Plan.default_plan
    @fallback_plan = @existing_default || create(:billing_plan, :default_plan)
    # No provider operation: all generated invoices remain manual. Load the
    # interfaces before contending threads so autoload is not the concurrency gate.
    @plan = create(:billing_plan)
    @customer = create(:customer)
    @subscription = Billing::Subscription.unscoped_by_tenant.where(customer_id: @customer.id).live.first
    @subscription&.update!(status: "cancelled", ended_at: Time.current)
    Billing::Activities::Subscribe
    Billing::Activities::ChangePlan
    Billing::Activities::ApplyCoupon
    Billing::CouponRedemption
    Billing::Activities::GenerateInvoice
    Billing::Activities::FinalizeInvoice
  end

  after do
    Current.reset
    # Remove only this example's committed billing records in FK order.
    [@customer, @other_customer].compact.each do |customer|
      Billing::Notice.where(customer_id: customer.id).delete_all
      Billing::CollectionAttempt.where(customer_id: customer.id).delete_all
      Billing::InvoiceLineItem.where(customer_id: customer.id).delete_all
      Billing::Invoice.where(customer_id: customer.id).delete_all
      Billing::PlanChange.where(customer_id: customer.id).delete_all
      Billing::CouponRedemption.where(customer_id: customer.id).delete_all
      Billing::Subscription.where(customer_id: customer.id).delete_all
      Billing::InvoiceSequence.where(customer_id: customer.id).delete_all
      customer.destroy!
    end
    @coupon&.destroy!
    @target&.destroy!
    @plan.destroy!
    @fallback_plan.destroy! unless @existing_default
    @existing_settings ? @settings.update!(collection_mode: @original_mode, grace_period_days: @original_grace) : @settings.destroy!
  end

  def compete(&command)
    barrier = Concurrent::CyclicBarrier.new(3)
    workers = 2.times.map do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          raise "Writers not ready" unless barrier.wait(10)
          command.call
        ensure
          Current.reset
        end
      end.tap { |thread| thread.report_on_exception = false }
    end
    raise "Writers not ready" unless barrier.wait(10)
    workers.map do |thread|
      raise "Writer timed out" unless thread.join(15)
      thread.value
    end
  ensure
    workers&.each { |thread| thread.kill if thread.alive?; thread.join }
  end

  it "returns one permanent enrollment/invoice across simultaneous request replay" do
    key = SecureRandom.uuid
    results = compete do
      Billing::Activities::Subscribe.call(customer: Customer.find(@customer.id), plan: Billing::Plan.find(@plan.id), request_key: key)
    end
    expect(results.map { |result| result.subscription.id }.uniq.size).to eq(1)
    expect(Billing::Subscription.where(customer_id: @customer.id).live.count).to eq(1)
    expect(Billing::Invoice.where(customer_id: @customer.id, purpose: "initial").count).to eq(1)
  end

  it "shares one awaiting-payment change and never grants an unpaid upgrade" do
    subscription = create(:billing_subscription, customer: @customer, plan: @plan)
    @target = create(:billing_plan, amount_usd: 199)
    key = SecureRandom.uuid
    results = compete do
      Billing::Activities::ChangePlan.call(subscription: Billing::Subscription.find(subscription.id), new_plan: Billing::Plan.find(@target.id), request_key: key)
    end
    expect(results.map { |result| result.plan_change.id }.uniq.size).to eq(1)
    expect(subscription.reload.billing_plan_id).to eq(@plan.id)
    expect(subscription.invoices.count).to eq(1)
    expect(subscription.pending_plan_change.status).to eq("awaiting_payment")
  end

  it "reserves the last coupon inventory atomically across two purchasing tenants" do
    @other_customer = create(:customer)
    Billing::Subscription.where(customer_id: @other_customer.id).live.update_all(status: "cancelled", ended_at: Time.current)
    subscriptions = [@customer, @other_customer].map { |customer| create(:billing_subscription, customer: customer, plan: @plan) }
    @coupon = create(:billing_coupon, max_redemptions: 1)
    ids = Queue.new
    subscriptions.each { |subscription| ids << subscription.id }
    results = compete do
      Billing::Activities::ApplyCoupon.call(subscription: Billing::Subscription.find(ids.pop), coupon: Billing::Coupon.find(@coupon.id))
    end
    expect(results.map(&:status)).to contain_exactly(:applied, :invalid)
    expect(@coupon.reload.times_redeemed).to eq(1)
    expect(Billing::CouponRedemption.where(billing_coupon_id: @coupon.id).count).to eq(1)
  end

  it "serializes two distinct reenrollment requests after the same expired initial intent" do
    start = (Time.current - (@settings.grace_period_days + 3).days).change(usec: 0)
    old = create(:billing_subscription, customer: @customer, plan: @plan, status: "pending",
      current_period_start: start, current_period_end: start + 1.month)
    invoice = Billing::Activities::GenerateInvoice.call(subscription: old, purpose: :initial,
      idempotency_key: "initial:#{old.id}", period_start: start, period_end: old.current_period_end,
      terms_snapshot: Billing::PlanChangePolicy.invoice_terms(old.plan_snapshot, due_at: start))
    Billing::Activities::FinalizeInvoice.call(invoice: invoice)
    frozen = invoice.reload.attributes.slice(*Billing::Invoice::FINANCIAL_ATTRIBUTES)
    expect(Billing::Providers).not_to receive(:charge)
    results = compete do
      Billing::Activities::Subscribe.call(customer: Customer.find(@customer.id), plan: Billing::Plan.find(@plan.id), request_key: SecureRandom.uuid)
    end
    expect(results.map { |result| result.subscription.id }.uniq.size).to eq(1)
    expect(results.map(&:status)).to contain_exactly(:awaiting_payment, :unchanged)
    expect(old.reload.status).to eq("expired")
    expect(Billing::Subscription.where(customer_id: @customer.id).live.count).to eq(1)
    expect(Billing::Invoice.where(customer_id: @customer.id, purpose: "initial").count).to eq(2)
    expect(invoice.reload.attributes.slice(*frozen.keys)).to eq(frozen)
    expect(invoice.status).to eq("open")
  end
end
