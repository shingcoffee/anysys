require "rails_helper"

RSpec.describe Payments::Order, type: :model do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  it "requires external_ref, amount, subject, and a supported currency" do
    o = described_class.new
    expect(o).not_to be_valid
    expect(o.errors.attribute_names).to include(:external_ref, :amount, :subject)
  end

  it "accepts any currency supported by a registered gateway (vendor-agnostic)" do
    # CNY valid via Alipay/WeChat; USD valid via PayPal/Stripe
    %w[CNY USD].each do |code|
      o = described_class.new(external_ref: "r", amount: 1.00, subject: "s", currency: code)
      o.valid?
      expect(o.errors[:currency]).to be_empty, "expected #{code} to be valid but got: #{o.errors[:currency]}"
    end
  end

  it "rejects a currency not supported by any gateway" do
    o = described_class.new(external_ref: "r", amount: 1.00, subject: "s", currency: "XXX")
    expect(o).not_to be_valid
    expect(o.errors[:currency]).to be_present
  end

  it "rounds amounts to two decimal places" do
    order = described_class.new(external_ref: "precision", amount: "31.095",
                                subject: "s", currency: "USD")

    expect(order).to be_valid
    expect(order.amount).to eq(31.10)
  end

  it "rounds zero-decimal currency amounts to whole units" do
    order = described_class.new(external_ref: "jpy-fraction", amount: "1000.50",
                                subject: "s", currency: "JPY")

    expect(order).to be_valid
    expect(order.amount).to eq(1001.00)
  end

  it "allows one external_ref per customer" do
    described_class.create!(external_ref: "r1", amount: 1.00, subject: "s")
    dup = described_class.new(external_ref: "r1", amount: 1.00, subject: "s")
    expect(dup).not_to be_valid
  end

  it "transitions to paid on mark_paid!" do
    o = described_class.create!(external_ref: "r2", amount: 1.00, subject: "s")
    o.mark_paid!(Time.zone.now)
    expect(o.reload.status).to eq("paid")
  end

  it "reports from mark_paid! whether this call settled the order" do
    o = described_class.create!(external_ref: "r-settle", amount: 1.00, subject: "s")
    expect(o.mark_paid!(Time.zone.now)).to be_truthy
    expect(o.mark_paid!(Time.zone.now)).to be(false)
  end

  describe "guarded transitions (C5: a settled order is never regressed)" do
    it "does NOT flip a paid order to failed" do
      o = described_class.create!(external_ref: "g1", amount: 1.00, subject: "s")
      o.mark_paid!(Time.zone.now)
      o.mark_failed!
      expect(o.reload.status).to eq("paid")
    end

    it "does NOT flip a paid order to closed" do
      o = described_class.create!(external_ref: "g2", amount: 1.00, subject: "s")
      o.mark_paid!(Time.zone.now)
      o.mark_closed!
      expect(o.reload.status).to eq("paid")
    end

    it "does NOT regress a refunded order back to paid" do
      o = described_class.create!(external_ref: "g3", amount: 1.00, subject: "s")
      o.update!(status: "refunded")
      o.mark_paid!(Time.zone.now)
      expect(o.reload.status).to eq("refunded")
    end

    it "still allows pending -> failed" do
      o = described_class.create!(external_ref: "g4", amount: 1.00, subject: "s")
      o.mark_failed!
      expect(o.reload.status).to eq("failed")
    end
  end
end
