# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::FinalizeInvoiceJob do
  # These checks exercise a real committed boundary; the production guard is
  # deliberately not stubbed to accommodate RSpec's nonjoinable fixture root.
  self.use_transactional_tests = false

  before do
    clear_enqueued_jobs
    allow(Billing::Onboarding).to receive(:call)
    @prior_settings = Billing::Settings.find_by(singleton_guard: 0)
    @settings = @prior_settings || Billing::Settings.current
    @prior_policy = @settings.attributes.slice("collection_mode", "grace_period_days")
    @settings.update!(collection_mode: "manual", grace_period_days: 7)
    @customer = create(:customer)
    @plan = create(:billing_plan)
  end

  after do
    Current.reset
    Billing::Notice.where(customer_id: @customer.id).delete_all
    Billing::CollectionAttempt.where(customer_id: @customer.id).delete_all
    Billing::InvoiceLineItem.where(customer_id: @customer.id).delete_all
    Billing::Invoice.where(customer_id: @customer.id).delete_all
    Billing::PlanChange.where(customer_id: @customer.id).delete_all
    Billing::CouponRedemption.where(customer_id: @customer.id).delete_all
    Billing::Subscription.where(customer_id: @customer.id).delete_all
    Billing::InvoiceSequence.where(customer_id: @customer.id).delete_all
    @customer.destroy!
    # The upgrade example may create the pinned owner outside fixture
    # transactions. Remove only records it owns; leave an existing owner intact.
    @created_platform_owner&.destroy! unless @created_platform_customer
    @created_platform_customer&.destroy!
    @target&.destroy!
    @plan.destroy!
    @prior_settings ? @settings.update!(@prior_policy) : @settings.destroy!
    clear_enqueued_jobs
  end

  def accept
    Billing::Activities::Subscribe.call(customer: @customer, plan: @plan, request_key: SecureRandom.uuid)
  end

  def committed_platform_owner
    platform = Customer.find_by(id: Authentication::User::PLATFORM_CUSTOMER_ID) ||
      (@created_platform_customer = create(:customer, id: Authentication::User::PLATFORM_CUSTOMER_ID))
    Authentication::User.find_by(customer: platform, email: Authentication::User::PLATFORM_OWNER_EMAIL) ||
      (@created_platform_owner = create(:user, :platform_owner, customer: platform))
  end

  it "only queues after the real outer transaction commits, then processes once outside it" do
    result = nil
    ApplicationRecord.transaction do
      result = accept
      expect(result.status).to eq(:awaiting_payment)
      expect(result.invoice.status).to eq("draft")
      expect(enqueued_jobs.select { |job| job[:job] == described_class }).to be_empty
    end
    expect(enqueued_jobs.select { |job| job[:job] == described_class }.size).to eq(1)
    expect(Billing::Activities::CollectInvoice).to receive(:call).and_wrap_original do |method, **arguments|
      expect(Billing::Invoice.connection.transaction_open?).to be(false)
      method.call(**arguments)
    end
    described_class.perform_now(result.invoice.id)
    expect(result.invoice.reload.status).to eq("open")
    expect(result.subscription.reload.status).to eq("pending")
  end

  it "refuses to process inside a real domain transaction without removing the collector's guard" do
    result = accept
    expect(Billing::Activities::FinalizeInvoice).not_to receive(:call)
    ApplicationRecord.transaction do
      expect { described_class.perform_now(result.invoice.id) }.to raise_error(ArgumentError, "invoice processing must run after domain commit")
    end
    expect(result.invoice.reload.status).to eq("draft")
    expect(result.invoice.number).to be_nil
  end

  it "recovers a committed initial draft after the acceptance callback is lost and replays the same identity" do
    allow(Billing::Result).to receive(:collect_after_commit)
    result = accept
    key = result.subscription.request_key
    expect(result.invoice.reload.status).to eq("draft")
    expect(Billing::Invoice.connection.transaction_open?).to be(false)
    allow(Billing::Result).to receive(:collect_after_commit).and_call_original
    replay = Billing::Activities::Subscribe.call(customer: @customer, plan: @plan, request_key: key)
    expect(replay.status).to eq(:unchanged)
    expect(replay.invoice.id).to eq(result.invoice.id)
    Billing::Cron::FinalizeDraftInvoices.perform
    number = result.invoice.reload.number
    lines = result.invoice.line_items.pluck(:id)
    described_class.perform_now(result.invoice.id)
    Billing::Cron::FinalizeDraftInvoices.perform
    described_class.perform_now(result.invoice.id)
    expect(result.invoice.reload.number).to eq(number)
    expect(result.invoice.line_items.pluck(:id)).to eq(lines)
    expect(result.subscription.reload.status).to eq("pending")
    expect(result.subscription.invoices.count).to eq(1)
    expect(result.invoice.collection_attempts.count).to eq(0)
  end

  it "recovers an upgrade draft before period end without granting its unpaid target or generating another invoice" do
    initial = accept
    described_class.perform_now(initial.invoice.id)
    Billing::Activities::MarkInvoicePaid.call(invoice: initial.invoice, source: :manual,
      actor: committed_platform_owner, reference: "paid-base")
    @target = create(:billing_plan, amount_usd: 199)
    allow(Billing::Result).to receive(:collect_after_commit)
    changed = Billing::Activities::ChangePlan.call(subscription: initial.subscription.reload, new_plan: @target, request_key: SecureRandom.uuid)
    expect(changed.invoice.reload.status).to eq("draft")
    expect(initial.subscription.current_period_end).to be > Time.current
    allow(Billing::Result).to receive(:collect_after_commit).and_call_original
    Billing::Cron::RenewSubscriptions.perform
    expect(changed.invoice.reload.status).to eq("open")
    expect(initial.subscription.reload.billing_plan_id).to eq(@plan.id)
    replay = Billing::Activities::ChangePlan.call(subscription: initial.subscription, new_plan: @target, request_key: changed.plan_change.request_key)
    expect(replay.invoice.id).to eq(changed.invoice.id)
    described_class.perform_now(replay.invoice.id)
    expect(changed.plan_change.reload.status).to eq("awaiting_payment")
    expect(initial.subscription.invoices.where(purpose: "proration").count).to eq(1)
  end

  it "does not finalize a draft that no longer matches its accepted period" do
    result = accept
    result.subscription.update!(current_period_start: result.subscription.current_period_start + 1.day,
      current_period_end: result.subscription.current_period_end + 1.day)
    expect(Billing::Activities::CollectInvoice).not_to receive(:call)
    Billing::Cron::FinalizeDraftInvoices.perform
    described_class.perform_now(result.invoice.id)
    expect(result.invoice.reload.status).to eq("draft")
    expect(result.invoice.number).to be_nil
    expect(result.invoice.collection_attempts.count).to eq(0)
  end
end
