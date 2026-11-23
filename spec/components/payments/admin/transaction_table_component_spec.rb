# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::TransactionTableComponent, type: :component do
  let(:order) { instance_double(Payments::Order, external_ref: "ORD-1", currency: "CNY") }
  let(:usd_order) { instance_double(Payments::Order, external_ref: "ORD-2", currency: "USD") }
  let(:jpy_order) { instance_double(Payments::Order, external_ref: "ORD-3", currency: "JPY") }
  let(:succeeded_payment) do
    instance_double(Payments::Payment, id: 1, payment_order: order, provider: "alipay",
                             amount: 12.34, status: "succeeded", payment_disputes: [])
  end
  let(:pending_payment) do
    instance_double(Payments::Payment, id: 2, payment_order: order, provider: "wechat_pay",
                             amount: 5.00, status: "pending", payment_disputes: [])
  end
  let(:usd_payment) do
    instance_double(Payments::Payment, id: 4, payment_order: usd_order, provider: "stripe",
                             amount: 12.34, status: "succeeded", payment_disputes: [])
  end
  let(:jpy_payment) do
    # Storage is always a major-unit decimal with two digits; for zero-decimal
    # currencies like JPY the fractional digits are still present (e.g. ¥100).
    instance_double(Payments::Payment, id: 5, payment_order: jpy_order, provider: "stripe",
                             amount: 100.00, status: "succeeded", payment_disputes: [])
  end

  def dispute(status)
    instance_double(Payments::Dispute, status: status)
  end

  before do
    stub_helpers = double("helpers",
                         params: { customer_id: "12345678" },
                         admin_modules_payments_transaction_path: "/12345678/admin/modules/payments/transactions/1",
                         protect_against_forgery?: false)
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  it "renders a row per payment with order ref, provider, and amount" do
    render_inline(described_class.new(payments: [succeeded_payment, pending_payment]))

    expect(page).to have_text("ORD-1")
    expect(page).to have_text("Alipay (China)")
    expect(page).to have_text("WeChat Pay (China)")
    expect(page).to have_text("¥12.34")
    expect(page).to have_text("¥5.00")
    expect(page).to have_text(I18n.t("comp_payments.transaction_table.statuses.succeeded"))
    expect(page).to have_text(I18n.t("comp_payments.transaction_table.statuses.pending"))
  end

  it "localizes provider and status in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(payments: [succeeded_payment]))
      expect(page).to have_text("Alipay (China)")
      expect(page).to have_text(I18n.t("comp_payments.transaction_table.statuses.succeeded"))
    end
  end

  it "formats the amount in the payment's own currency, not a hard-coded CNY symbol" do
    render_inline(described_class.new(payments: [usd_payment]))

    expect(page).to have_text("$12.34")
    expect(page).to have_no_text("¥12.34")
  end

  it "formats a zero-decimal (JPY) amount without the 100x canonical-cents inflation" do
    render_inline(described_class.new(payments: [jpy_payment]))

    expect(page).to have_text(Billing::CurrencyResolver.format(100, "JPY"))
    expect(page).to have_no_text(Billing::CurrencyResolver.format(10_000, "JPY"))
  end

  it "only shows a refund link for succeeded payments" do
    render_inline(described_class.new(payments: [succeeded_payment, pending_payment]))

    expect(page).to have_link("Refund", count: 1)
    expect(page).to have_link(I18n.t("common.actions.view"), count: 1)
  end

  it "renders an empty table body when no payments are provided" do
    render_inline(described_class.new(payments: []))

    expect(page).to have_css("table")
    expect(page).to have_no_link("Refund")
  end

  describe "#status_variant" do
    subject { described_class.new(payments: []) }

    it "returns :success for succeeded" do
      expect(subject.status_variant("succeeded")).to eq(:success)
    end

    it "returns :danger for failed" do
      expect(subject.status_variant("failed")).to eq(:danger)
    end

    it "returns :warning for pending" do
      expect(subject.status_variant("pending")).to eq(:warning)
    end

    it "returns :default for closed and other statuses" do
      expect(subject.status_variant("closed")).to eq(:default)
      expect(subject.status_variant("unknown")).to eq(:default)
    end
  end

  it "renders failed payments in the table" do
    failed_payment = instance_double(Payments::Payment, id: 3, payment_order: order,
                                      provider: "alipay", amount: 7.50, status: "failed",
                                      payment_disputes: [])
    render_inline(described_class.new(payments: [failed_payment]))
    expect(page).to have_text(I18n.t("comp_payments.transaction_table.statuses.failed"))
    expect(page).to have_no_link("Refund")
  end

  describe "#provider_label" do
    subject { described_class.new(payments: []) }

    it "falls back to the raw key for an unknown provider" do
      expect(subject.provider_label("not_a_gateway")).to eq("not_a_gateway")
    end
  end

  describe "#status_label" do
    subject { described_class.new(payments: []) }

    it "falls back to the raw key for an unknown status" do
      expect(subject.status_label("unknown")).to eq("unknown")
    end
  end

  describe "dispute flag" do
    def payment_with_disputes(disputes)
      instance_double(Payments::Payment, id: 9, payment_order: order, provider: "stripe",
                      amount: 5.00, status: "succeeded", payment_disputes: disputes)
    end

    it "shows a Chargeback badge when a dispute is lost" do
      render_inline(described_class.new(payments: [payment_with_disputes([dispute("lost")])]))
      expect(page).to have_text("Chargeback")
    end

    it "shows a Disputed badge for an open dispute" do
      render_inline(described_class.new(payments: [payment_with_disputes([dispute("under_review")])]))
      expect(page).to have_text("Disputed")
    end

    it "shows no dispute badge when all disputes are won" do
      render_inline(described_class.new(payments: [payment_with_disputes([dispute("won")])]))
      expect(page).not_to have_text("Disputed")
      expect(page).not_to have_text("Chargeback")
    end

    describe "#dispute_flag" do
      subject { described_class.new(payments: []) }

      it "prioritizes a lost dispute (chargeback) over an open one" do
        p = payment_with_disputes([dispute("under_review"), dispute("lost")])
        expect(subject.dispute_flag(p)).to eq({ variant: :danger, key: "chargeback" })
      end

      it "returns nil when there are no disputes" do
        expect(subject.dispute_flag(payment_with_disputes([]))).to be_nil
      end
    end
  end
end
