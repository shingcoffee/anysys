# frozen_string_literal: true
require "rails_helper"
require_relative "partition_b_helpers"

RSpec.describe "Billing committed collection and rejection safety" do
  include BillingPartitionBHelpers
  self.use_transactional_tests = false

  around do |example|
    connection = ApplicationRecord.connection
    baseline = connection.tables.filter_map do |table|
      key = connection.primary_key(table)
      next unless key
      [table, key, connection.select_values("SELECT #{connection.quote_column_name(key)} FROM #{connection.quote_table_name(table)}")]
    end
    platform_gateway = Payments::PlatformGateway.find_by(provider: "stripe")
    gateway_attributes = platform_gateway&.attributes
    example.run
  ensure
    # Only this example's committed rows are removed. Preserve suite seeds and
    # restore the one shared platform flag changed by the billing fixture.
    connection.disable_referential_integrity do
      baseline.each do |table, key, ids|
        clause = ids.empty? ? "" : " WHERE #{connection.quote_column_name(key)} NOT IN (#{ids.map { |id| connection.quote(id) }.join(',')})"
        connection.execute("DELETE FROM #{connection.quote_table_name(table)}#{clause}")
      end
      platform_gateway&.update_columns(gateway_attributes.except("id"))
    end
    Current.reset
  end

  def captured_outcome(payment)
    { status: :succeeded, psp_transaction_id: "pi_#{payment.id}", amount: payment.amount,
      currency: payment.payment_order.currency, settled_at: Time.current, raw: {} }
  end

  it "preserves an uncertain API error's committed identity and recovers its capture without a second charge" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    captured_keys = []
    allow(Payments::Gateway).to receive(:charge_subscription) do |payment:, **|
      expect(ApplicationRecord.connection.open_transactions).to eq(0)
      durable = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          Billing::CollectionAttempt.unscoped_by_tenant.find_by!(payment_id: payment.id).state
        end
      end.value
      expect(durable).to eq("submitting")
      captured_keys << payment.out_trade_no # PSP accepted, its response was lost.
      raise Payments::Errors::ApiError.new("uncertain prior operation", code: 400,
        payload: { "error" => { "type" => "idempotency_error" } }, definitive: false)
    end

    expect(Billing::Activities::CollectInvoice.call(invoice: invoice).status).to eq(:pending)
    attempt = invoice.collection_attempts.sole
    payment = attempt.payment
    expect(attempt.state).to eq("unknown")
    expect(payment.status).to eq("pending")
    expect(invoice.reload.attempt_count).to eq(0)
    expect(invoice.next_attempt_at).to be_nil
    expect(Billing::Activities::CollectInvoice.call(invoice: invoice, trigger: :recovery).status).to eq(:pending)
    expect(invoice.collection_attempts.sole.id).to eq(attempt.id)
    expect(Payments::Payment.where(payment_order_id: payment.payment_order_id).count).to eq(1)

    allow(Payments::Gateway).to receive(:billing_query).with(customer: aggregate.fetch(:platform), payment: payment,
      merchant_account: aggregate.fetch(:account)).and_return(captured_outcome(payment))
    expect(Billing::Activities::CollectInvoice.call(invoice: invoice, trigger: :reconcile).status).to eq(:succeeded)
    expect(invoice.reload.payment_id).to eq(payment.id)
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
    expect(Billing::Activities::CollectInvoice.call(invoice: invoice, trigger: :recovery).status).to eq(:skipped)
    expect(captured_keys).to eq([attempt.request_key])
    expect(Payments::Gateway).to have_received(:charge_subscription).once
  end

  it "releases a definitive decline, then permits exactly one new recovery capture" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    submitted_keys = []
    captured_keys = []
    allow(Payments::Gateway).to receive(:charge_subscription) do |payment:, **|
      expect(ApplicationRecord.connection.open_transactions).to eq(0)
      submitted_keys << payment.out_trade_no
      if submitted_keys.length == 1
        raise Payments::Errors::ApiError.new("issuer declined", code: 402,
          payload: { "error" => { "code" => "card_declined", "decline_code" => "insufficient_funds" } }, definitive: true)
      end
      captured_keys << payment.out_trade_no
      { status: :succeeded, psp_transaction_id: "pi_#{payment.id}" }
    end
    allow(Payments::Gateway).to receive(:billing_query) { |payment:, **| captured_outcome(payment) }

    expect(Billing::Activities::CollectInvoice.call(invoice: invoice).status).to eq(:retry_scheduled)
    first = invoice.collection_attempts.sole
    expect(first.state).to eq("failed")
    expect(first.payment.status).to eq("failed")
    expect(invoice.reload.attempt_count).to eq(1)
    expect(Billing::Activities::CollectInvoice.call(invoice: invoice, trigger: :recovery).status).to eq(:succeeded)
    second = invoice.collection_attempts.order(:ordinal).last
    expect(second.id).not_to eq(first.id)
    expect(second.request_key).not_to eq(first.request_key)
    expect(second.payment.status).to eq("succeeded")
    expect(invoice.reload.payment_id).to eq(second.payment_id)
    expect(captured_keys).to eq([second.request_key])
    expect(submitted_keys).to eq([first.request_key, second.request_key])
    expect(Billing::Activities::CollectInvoice.call(invoice: invoice, trigger: :recovery).status).to eq(:skipped)
    expect(Payments::Gateway).to have_received(:charge_subscription).twice
  end

  it "rejects gateway HTTP inside a caller transaction but permits unpaid local manual collection" do
    gateway = billing_aggregate
    manual = billing_aggregate(mode: "manual")
    expect(Payments::Gateway).not_to receive(:charge_subscription)
    expect do
      Billing::Invoice.transaction { Billing::Activities::CollectInvoice.call(invoice: gateway.fetch(:invoice)) }
    end.to raise_error(ArgumentError, "collection must run after domain commit")
    expect(gateway.fetch(:invoice).collection_attempts).to be_empty
    Billing::Invoice.transaction do
      expect(Billing::Activities::CollectInvoice.call(invoice: manual.fetch(:invoice)).status).to eq(:pending_manual)
    end
    expect(manual.fetch(:invoice).reload.status).to eq("open")
    expect(manual.fetch(:subscription).reload.status).to eq("pending")
  end

  def successful_gateway
    allow(Payments::Gateway).to receive(:charge_subscription) do |payment:, **|
      expect(ApplicationRecord.connection.open_transactions).to eq(0)
      { status: :succeeded, psp_transaction_id: "pi_#{payment.id}" }
    end
    allow(Payments::Gateway).to receive(:billing_query) { |payment:, **| captured_outcome(payment) }
  end

  def collection_jobs(invoice)
    enqueued_jobs.select { |job| job[:job] == Billing::FinalizeInvoiceJob && job[:args] == [invoice.id] }
  end

  it "recovers zero-grace initial collection after a small elapsed interval and applies the accepted purchase once" do
    aggregate = billing_aggregate(grace: 0, finalize: false)
    invoice = aggregate.fetch(:invoice)
    subscription = aggregate.fetch(:subscription)
    accepted_end = subscription.current_period_end
    successful_gateway
    clear_enqueued_jobs
    expect(invoice.collection_deadline).to eq(accepted_end)
    expect(Billing::PlanChangePolicy.grace_deadline(invoice)).to eq(invoice.due_at)

    travel_to(invoice.due_at + 2.seconds) do
      expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:free)
      2.times { Billing::Cron::ReconcileCollections.perform }
      expect(collection_jobs(invoice).size).to eq(1)
      expect(invoice.reload.status).to eq("open")
      expect(invoice.collection_attempts).to be_empty
      expect(Payments::Gateway).not_to have_received(:charge_subscription)

      2.times { Billing::FinalizeInvoiceJob.perform_now(invoice.id) }
      Billing::DailyBillingJob.perform_now
      expect(invoice.reload.status).to eq("paid")
      expect(invoice.settlement_review_code).to be_nil
      expect(subscription.reload.status).to eq("active")
      expect(subscription.current_period_end).to eq(accepted_end)
      expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:purchased)
      expect(invoice.entitlements_applied_at).to eq(Time.current)
      expect(invoice.collection_attempts.count).to eq(1)
      expect(collection_jobs(invoice).size).to eq(1)
      expect(Payments::Gateway).to have_received(:charge_subscription).once
    end
  end

  it "does not double initial collection when the daily batch wins before the queued disposition job" do
    aggregate = billing_aggregate(grace: 0, finalize: false)
    invoice = aggregate.fetch(:invoice)
    successful_gateway
    clear_enqueued_jobs
    travel_to(invoice.due_at + 2.seconds) do
      Billing::Cron::ReconcileCollections.perform
      expect(collection_jobs(invoice).size).to eq(1)
      Billing::DailyBillingJob.perform_now
      2.times { Billing::FinalizeInvoiceJob.perform_now(invoice.id) }
      Billing::Cron::ReconcileCollections.perform
      expect(invoice.reload.status).to eq("paid")
      expect(invoice.collection_attempts.count).to eq(1)
      expect(Billing::Collector.platform_payments(invoice).count).to eq(1)
      expect(collection_jobs(invoice).size).to eq(1)
      expect(Payments::Gateway).to have_received(:charge_subscription).once
    end
  end

  it "expires an overdue zero-grace job without creating a payment or another initial invoice" do
    aggregate = billing_aggregate(grace: 0, finalize: false)
    invoice = aggregate.fetch(:invoice)
    subscription = aggregate.fetch(:subscription)
    deadline = invoice.period_end
    clear_enqueued_jobs
    Billing::Result.collect_after_commit(invoice)
    expect(collection_jobs(invoice).size).to eq(1)
    expect(Payments::Gateway).not_to receive(:charge_subscription)
    travel_to(deadline + 1.second) do
      Billing::FinalizeInvoiceJob.perform_now(invoice.id)
      Billing::Cron::ReconcileCollections.perform
      Billing::DailyBillingJob.perform_now
      expect(subscription.reload.status).to eq("expired")
      expect(subscription.ended_at).to eq(deadline)
      expect(subscription.invoices.count).to eq(1)
      expect(invoice.reload.status).to eq("open")
      expect(invoice.collection_state).to eq("stopped")
      expect(invoice.collection_attempts).to be_empty
      expect(Billing::Collector.platform_payments(invoice)).to be_empty
      expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:free)
    end
  end

  it "queues recovered collection only after finalization commits and not after rollback" do
    aggregate = billing_aggregate(finalize: false)
    invoice = aggregate.fetch(:invoice)
    clear_enqueued_jobs
    expect(Payments::Gateway).not_to receive(:charge_subscription)
    ApplicationRecord.transaction do
      Billing::Cron::ReconcileCollections.perform
      expect(invoice.reload.status).to eq("open")
      expect(collection_jobs(invoice)).to be_empty
      raise ActiveRecord::Rollback
    end
    expect(invoice.reload.status).to eq("draft")
    expect(invoice.number).to be_nil
    expect(collection_jobs(invoice)).to be_empty
    Billing::Cron::ReconcileCollections.perform
    expect(invoice.reload.status).to eq("open")
    expect(collection_jobs(invoice).size).to eq(1)
    expect(Billing::InvoiceSequence.find_by!(customer_id: invoice.customer_id).last_value).to eq(1)
  end
end
