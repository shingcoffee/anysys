require "rails_helper"

RSpec.describe Payments::ReconciliationBill, type: :model do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  it "enforces unique [customer_id, provider, bill_date, bill_type]" do
    described_class.create!(provider: "alipay", bill_date: Date.today, bill_type: "all")
    dup = described_class.new(provider: "alipay", bill_date: Date.today, bill_type: "all")
    expect(dup).not_to be_valid
  end

  it "validates provider, bill_type, status" do
    b = described_class.new(provider: "x", bill_type: "y", status: "z", bill_date: Date.today)
    expect(b).not_to be_valid
  end

  it "mark_parsed! updates counts and status" do
    b = described_class.create!(provider: "wechat_pay", bill_date: Date.today, bill_type: "all")
    b.mark_parsed!(total_count: 10, total_amount: 10.00, raw_summary: { "k" => "v" })
    expect(b.reload.status).to eq("parsed")
    expect(b.total_count).to eq(10)
    expect(b.total_amount).to eq(10.00)
  end

  it "mark_reconciled! flips status based on discrepancies" do
    b = described_class.create!(provider: "wechat_pay", bill_date: Date.today, bill_type: "all")
    b.mark_reconciled!(discrepancies: 0)
    expect(b.reload.status).to eq("reconciled")
    b.mark_reconciled!(discrepancies: 2)
    expect(b.reload.status).to eq("discrepant")
    expect(b.discrepancy_count).to eq(2)
  end
end
