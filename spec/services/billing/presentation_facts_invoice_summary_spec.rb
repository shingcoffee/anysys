# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PresentationFacts, ".invoice_summary" do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:subscription) { create(:billing_subscription, customer: customer, currency: "USD", amount_cents: 2900) }

  def summary
    described_class.invoice_summary(invoices: Billing::Invoice.where(customer_id: customer.id))
  end

  it "totals unpaid invoices per currency and ignores draft, void and paid rows" do
    create(:billing_invoice, :open, customer: customer, subscription: subscription, total_cents: 2900)
    create(:billing_invoice, :open, customer: customer, subscription: subscription, total_cents: 100, status: "uncollectible")
    create(:billing_invoice, :open, customer: customer, subscription: subscription, total_cents: 19900, currency: "CNY")
    create(:billing_invoice, customer: customer, subscription: subscription, total_cents: 5000)
    create(:billing_invoice, :void, customer: customer, subscription: subscription, total_cents: 7000)

    result = summary
    expect(result[:outstanding]).to eq([
      { currency: "CNY", total_cents: 19900, count: 1 },
      { currency: "USD", total_cents: 3000, count: 2 }
    ])
    expect(result[:unpaid_count]).to eq(3)
  end

  it "never counts another tenant's invoices" do
    foreign = create(:billing_subscription, customer: other)
    create(:billing_invoice, :open, customer: other, subscription: foreign, total_cents: 9900)
    create(:billing_invoice, :open, :paid, customer: other, subscription: foreign, paid_at: 1.minute.ago)

    expect(summary).to include(outstanding: [], unpaid_count: 0, last_paid: nil)
  end

  it "returns the most recently paid invoice" do
    create(:billing_invoice, :open, :paid, customer: customer, subscription: subscription, paid_at: 2.months.ago)
    latest = create(:billing_invoice, :open, :paid, customer: customer, subscription: subscription, paid_at: 3.days.ago)
    expect(summary[:last_paid]).to eq(latest)
  end

  it "returns only invoice figures" do
    expect(summary.keys).to contain_exactly(:outstanding, :unpaid_count, :last_paid)
  end
end

RSpec.describe Billing::PresentationFacts, ".tab_counts" do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }

  it "counts open and uncollectible invoices and ignores draft, paid, and void" do
    subscription = create(:billing_subscription, customer: customer)
    create(:billing_invoice, :open, customer: customer, subscription: subscription)
    create(:billing_invoice, :open, customer: customer, subscription: subscription, status: "uncollectible")
    create(:billing_invoice, customer: customer, subscription: subscription)
    create(:billing_invoice, :open, :paid, customer: customer, subscription: subscription)
    create(:billing_invoice, :void, customer: customer, subscription: subscription)

    expect(described_class.tab_counts(customer: customer)).to include(invoices: 2)
  end

  it "counts pending and failed payment methods and ignores active and removed" do
    create(:billing_payment_method, customer: customer)
    create(:billing_payment_method, :failed, customer: customer)
    create(:billing_payment_method, :active, customer: customer)
    create(:billing_payment_method, :removed, customer: customer)

    expect(described_class.tab_counts(customer: customer)).to include(payment_methods: 2)
  end

  it "isolates counts to the given customer" do
    subscription = create(:billing_subscription, customer: customer)
    create(:billing_invoice, :open, customer: customer, subscription: subscription)
    create(:billing_payment_method, customer: customer)

    foreign = create(:billing_subscription, customer: other)
    create(:billing_invoice, :open, customer: other, subscription: foreign)
    create(:billing_invoice, :open, customer: other, subscription: foreign, status: "uncollectible")
    create(:billing_payment_method, customer: other)
    create(:billing_payment_method, :failed, customer: other)

    expect(described_class.tab_counts(customer: customer)).to eq(payment_methods: 1, invoices: 1)
  end

  it "returns zeros when customer is nil or has no attention items" do
    expect(described_class.tab_counts(customer: nil)).to eq(payment_methods: 0, invoices: 0)
    expect(described_class.tab_counts(customer: customer)).to eq(payment_methods: 0, invoices: 0)
  end
end
