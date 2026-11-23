# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::InvoiceLineItem, type: :model do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  describe "validations" do
    it "requires customer_id" do
      Current.customer = nil
      item = build(:billing_invoice_line_item, customer_id: nil)
      expect(item).not_to be_valid
      Current.customer = customer
    end

    it "requires description" do
      item = build(:billing_invoice_line_item, description: nil)
      expect(item).not_to be_valid
    end

    it "requires kind to be in KINDS" do
      expect(build(:billing_invoice_line_item, kind: "fee")).not_to be_valid
      Billing::InvoiceLineItem::KINDS.each do |valid_kind|
        expect(build(:billing_invoice_line_item, kind: valid_kind)).to be_valid
      end
    end

    it "requires quantity > 0" do
      expect(build(:billing_invoice_line_item, quantity: 0)).not_to be_valid
      expect(build(:billing_invoice_line_item, quantity: 1)).to be_valid
    end

    it "requires unit_amount_cents to be an integer (can be negative for credits)" do
      expect(build(:billing_invoice_line_item, unit_amount_cents: 1.5)).not_to be_valid
      expect(build(:billing_invoice_line_item, unit_amount_cents: -100)).to be_valid
    end
  end

  it "refuses edits, deletion and reparenting of an issued line" do
    allow(Billing::Onboarding).to receive(:call)
    invoice = create(:billing_invoice, customer: customer)
    line = create(:billing_invoice_line_item, customer: customer, invoice: invoice)
    Billing::Activities::FinalizeInvoice.call(invoice: invoice)
    expect(line.update(description: "Edited")).to be(false)
    expect(line.reload.destroy).to be(false)
    draft = create(:billing_invoice, customer: customer, subscription: invoice.subscription)
    expect(line.reload.update(invoice: draft)).to be(false)
  end
end
