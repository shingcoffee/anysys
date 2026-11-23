# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::ReconciliationTableComponent, type: :component do
  # No attached settlement file by default — the download cell is only rendered
  # when bill_file.attached? is true (covered by its own example below).
  let(:no_file) { instance_double(ActiveStorage::Attached::One, attached?: false) }

  let(:parsed_bill) do
    instance_double(Payments::ReconciliationBill, id: 1, provider: "alipay", bill_type: "all",
                                               bill_date: Date.new(2026, 4, 1),
                                               total_count: 12, total_amount: 98.76,
                                               discrepancy_count: 0, status: "parsed", bill_file: no_file)
  end
  let(:discrepant_bill) do
    instance_double(Payments::ReconciliationBill, id: 2, provider: "wechat_pay", bill_type: "success",
                                               bill_date: Date.new(2026, 4, 2),
                                               total_count: 5, total_amount: 45.00,
                                               discrepancy_count: 2, status: "discrepant", bill_file: no_file)
  end

  it "renders a row per bill with date, provider, type, rows, amount, and discrepancies" do
    render_inline(described_class.new(bills: [parsed_bill, discrepant_bill]))

    expect(page).to have_text(I18n.l(Date.new(2026, 4, 1), format: :long))
    expect(page).to have_text(I18n.l(Date.new(2026, 4, 2), format: :long))
    expect(page).to have_text("Alipay (China)")
    expect(page).to have_text("WeChat Pay (China)")
    expect(page).to have_text(I18n.t("comp_payments.reconciliation.bill_types.all"))
    expect(page).to have_text(I18n.t("comp_payments.reconciliation.bill_types.success"))
    expect(page).to have_text("12")
    expect(page).to have_text("¥98.76")
    expect(page).to have_text("¥45.00")
    expect(page).to have_text(I18n.t("comp_payments.reconciliation.statuses.parsed"))
    expect(page).to have_text(I18n.t("comp_payments.reconciliation.statuses.discrepant"))
  end

  it "localizes date, type, and status in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(bills: [parsed_bill]))
      expect(page).to have_text(I18n.l(Date.new(2026, 4, 1), format: :long))
      expect(page).to have_text(I18n.t("comp_payments.reconciliation.bill_types.all"))
      expect(page).to have_text(I18n.t("comp_payments.reconciliation.statuses.parsed"))
    end
  end

  it "renders zeros when totals are nil" do
    empty_bill = instance_double(Payments::ReconciliationBill, id: 3, provider: "alipay",
                                                            bill_type: "refund",
                                                            bill_date: Date.new(2026, 4, 3),
                                                            total_count: nil, total_amount: nil,
                                                            discrepancy_count: nil, status: "downloading", bill_file: no_file)
    render_inline(described_class.new(bills: [empty_bill]))

    expect(page).to have_text("¥0.00")
    expect(page).to have_text(I18n.t("comp_payments.reconciliation.statuses.downloading"))
  end

  describe "#status_variant" do
    subject { described_class.new(bills: []) }

    it "returns :success for reconciled" do
      expect(subject.status_variant("reconciled")).to eq(:success)
    end

    it "returns :info for parsed" do
      expect(subject.status_variant("parsed")).to eq(:info)
    end

    it "returns :warning for discrepant" do
      expect(subject.status_variant("discrepant")).to eq(:warning)
    end

    it "returns :danger for failed" do
      expect(subject.status_variant("failed")).to eq(:danger)
    end

    it "returns :default for unknown status" do
      expect(subject.status_variant("downloading")).to eq(:default)
    end
  end

  describe "#provider_label" do
    subject { described_class.new(bills: []) }

    it "falls back to the raw key for an unknown provider" do
      expect(subject.provider_label("not_a_gateway")).to eq("not_a_gateway")
    end
  end

  describe "#bill_date_label" do
    subject { described_class.new(bills: []) }

    it "returns the em dash for a blank date" do
      expect(subject.bill_date_label(nil)).to eq(I18n.t("common.labels.em_dash"))
    end
  end

  it "renders reconciled and failed status bills" do
    reconciled_bill = instance_double(Payments::ReconciliationBill, id: 10, provider: "alipay",
                                                                   bill_type: "all",
                                                                   bill_date: Date.new(2026, 5, 1),
                                                                   total_count: 3, total_amount: 15.00,
                                                                   discrepancy_count: 0, status: "reconciled", bill_file: no_file)
    failed_bill = instance_double(Payments::ReconciliationBill, id: 11, provider: "wechat_pay",
                                                               bill_type: "refund",
                                                               bill_date: Date.new(2026, 5, 2),
                                                               total_count: 0, total_amount: 0.00,
                                                               discrepancy_count: 0, status: "failed", bill_file: no_file)
    render_inline(described_class.new(bills: [reconciled_bill, failed_bill]))
    expect(page).to have_text(I18n.t("comp_payments.reconciliation.statuses.reconciled"))
    expect(page).to have_text(I18n.t("comp_payments.reconciliation.statuses.failed"))
  end

  it "renders a download link only for bills with an attached file" do
    stub_helpers = double("helpers",
                          params: { customer_id: "12345678" },
                          download_admin_modules_payments_reconciliation_path: "/12345678/admin/modules/payments/reconciliations/20/download")
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)

    attached = instance_double(ActiveStorage::Attached::One, attached?: true)
    bill = instance_double(Payments::ReconciliationBill, id: 20, provider: "alipay", bill_type: "all",
                                                         bill_date: Date.new(2026, 6, 1),
                                                         total_count: 1, total_amount: 1.00,
                                                         discrepancy_count: 0, status: "reconciled", bill_file: attached)
    render_inline(described_class.new(bills: [bill]))
    expect(page).to have_link(href: "/12345678/admin/modules/payments/reconciliations/20/download")
  end
end
