# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::RefundDialogComponent, type: :component do
  let(:order)   { instance_double(Payments::Order, external_ref: "ORD-9", currency: "USD") }
  let(:payment) do
    instance_double(Payments::Payment, id: 77, payment_order: order, provider: "alipay",
                             amount: 25.00, status: "succeeded")
  end

  before do
    stub_helpers = double("helpers",
                         params: { customer_id: "12345678" },
                         admin_modules_payments_transaction_refunds_path: "/12345678/admin/modules/payments/transactions/77/refunds",
                         protect_against_forgery?: false)
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
    render_inline(described_class.new(payment: payment))
  end

  it "renders the refund form with prefilled amount and reason field" do
    expect(page).to have_text("ORD-9")
    expect(page).to have_text("Alipay (China)")
    expect(page).to have_text(I18n.t("comp_payments.transaction_table.statuses.succeeded"))
    expect(page).to have_field("amount", with: "25.00")
    expect(page).to have_field("reason")
    expect(page).to have_button("Issue Refund")
    expect(page).not_to have_css("h1")
  end

  it "localizes provider and status in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(payment: payment))
      expect(page).to have_text("Alipay (China)")
      expect(page).to have_text(I18n.t("comp_payments.transaction_table.statuses.succeeded"))
    end
  end

  it "caps the amount input at the payment's original amount" do
    amount_input = page.find_field("amount")
    expect(amount_input["max"]).to eq("25.00")
    expect(amount_input["min"]).to eq("0.01")
  end

  it "formats the original amount in the payment order currency" do
    expect(page).to have_text(Billing::CurrencyResolver.format(2500, "USD"))
    expect(page).not_to have_text("¥25.00")
  end

  describe "#provider_label" do
    it "falls back to the raw key for an unknown provider" do
      unknown = instance_double(Payments::Payment, provider: "not_a_gateway", status: "succeeded")
      expect(described_class.new(payment: unknown).provider_label).to eq("not_a_gateway")
    end
  end

  describe "#status_label" do
    it "falls back to the raw key for an unknown status" do
      unknown = instance_double(Payments::Payment, provider: "alipay", status: "unknown")
      expect(described_class.new(payment: unknown).status_label).to eq("unknown")
    end
  end
end
