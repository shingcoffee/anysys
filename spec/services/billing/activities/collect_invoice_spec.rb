# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::CollectInvoice do
  include BillingPartitionBHelpers
  before { allow_test_root_transaction }

  it "prepares stable identities before HTTP and retains the same ambiguous attempt" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    allow(Payments::Gateway).to receive(:charge_subscription) do |payment:, merchant_account:, **|
      expect(Billing::Invoice.connection.open_transactions).to eq(1)
      attempt = invoice.collection_attempts.find_by!(payment_id: payment.id)
      expect(attempt.request_key).to eq(payment.out_trade_no)
      expect(payment.merchant_account_id).to eq(merchant_account.id)
      raise Payments::Errors::TransportError, "lost response"
    end
    result = described_class.call(invoice: invoice)
    expect(result.status).to eq(:pending)
    attempt = invoice.collection_attempts.sole
    expect(attempt.state).to eq("unknown")
    expect(invoice.reload.attempt_count).to eq(0)
    expect { described_class.call(invoice: invoice, trigger: :recovery) }.not_to change(Payments::Payment, :count)
    expect(Payments::Gateway).to have_received(:charge_subscription).once
  end

  it "exhausts [1,3,7] after four definitive failures, with disjoint initial and retry populations" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    start = invoice.due_at
    allow(Payments::Gateway).to receive(:charge_subscription).and_return(status: :failed, failure_code: "card_declined")
    expect(described_class.call(invoice: invoice, at: start).status).to eq(:retry_scheduled)
    expect(invoice.reload.next_attempt_at).to eq(start + 1.day)
    expect(described_class.call(invoice: invoice, trigger: :initial, at: start + 1.day).status).to eq(:skipped)
    [1, 3, 7].each { |day| described_class.call(invoice: invoice, trigger: :retry, at: start + day.days) }
    expect(invoice.reload.attempt_count).to eq(4)
    expect(invoice.collection_state).to eq("exhausted")
    expect(invoice.status).to eq("uncollectible")
    expect(invoice.next_attempt_at).to be_nil
    expect(invoice.collection_attempts.count).to eq(4)
    expect(Billing::Notice.where(kind: "payment_failed", billing_invoice_id: invoice.id).count).to eq(4)
  end

  it "keeps a manual invoice pending after global mode changes and rejects missing methods without fake attempts" do
    aggregate = billing_aggregate(mode: "manual")
    Billing::Settings.current.update!(collection_mode: "gateway")
    expect(described_class.call(invoice: aggregate.fetch(:invoice)).status).to eq(:pending_manual)
    expect(aggregate.fetch(:invoice).collection_attempts).to be_empty
    gateway = billing_aggregate
    gateway.fetch(:method).update!(is_default: false)
    2.times { expect(described_class.call(invoice: gateway.fetch(:invoice), trigger: :recovery).status).to eq(:blocked) }
    expect(gateway.fetch(:invoice).collection_attempts).to be_empty
    expect(Billing::Notice.where(kind: "collection_blocked", billing_invoice_id: gateway.fetch(:invoice).id).count).to eq(1)
  end

  it "persists the Stripe intent and exposes SCA without retrying" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    allow(Payments::Gateway).to receive(:charge_subscription).and_return(status: :requires_action, psp_transaction_id: "pi_auth", client_secret: "secret_auth")
    expect(described_class.call(invoice: invoice).status).to eq(:requires_action)
    expect(invoice.collection_attempts.sole.payment.psp_transaction_id).to eq("pi_auth")
    expect(Billing::InvoicePaymentAction.for(invoice: invoice)).to include(kind: :stripe_sca, client_secret: "secret_auth")
    expect(described_class.call(invoice: invoice, trigger: :retry).status).to eq(:pending)
    expect(Payments::Gateway).to have_received(:charge_subscription).once
  end
end
