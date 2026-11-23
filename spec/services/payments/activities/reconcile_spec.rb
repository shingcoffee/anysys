require "rails_helper"

RSpec.describe Payments::Activities::Reconcile do
  let_it_be(:customer) { create(:customer) }
  let(:order_one) { create(:payment_order, external_ref: "rc-1", amount: 1.00, subject: "s") }
  let(:order_two) { create(:payment_order, external_ref: "rc-2", amount: 2.00, subject: "s") }

  # Must precede the let! payment blocks: those build orders that require
  # Current.customer, and let!/before hooks run in definition order.
  before { Current.customer = customer }

  let!(:payment_one) do
    create(:payment, payment_order: order_one, provider: "alipay", flow: "qr",
           out_trade_no: "OT-1", amount: 1.00, status: "succeeded")
  end
  let!(:payment_two) do
    create(:payment, payment_order: order_two, provider: "alipay", flow: "qr",
           out_trade_no: "OT-2", amount: 2.00, status: "succeeded")
  end

  it "reconciles a CSV where all rows match successful payments" do
    csv = "trade_no,out_trade_no,amount\nT1,OT-1,1.00\nT2,OT-2,2.00\n"
    allow(Payments::Gateway).to receive(:download_bill)
      .and_return(csv: csv, raw_summary: { "total" => 2 })

    bill = described_class.call(customer: customer, provider: "alipay",
                                bill_date: Date.today, bill_type: "all")

    expect(bill.status).to eq("reconciled")
    expect(bill.total_count).to eq(2)
    expect(bill.total_amount).to eq(3.00)
    expect(bill.discrepancy_count).to eq(0)
    expect(bill.bill_file).to be_attached
  end

  it "flags the bill as discrepant when CSV rows do not match local payments" do
    csv = "trade_no,out_trade_no,amount\nT1,OT-1,1.00\nTX,GHOST,9.99\n"
    allow(Payments::Gateway).to receive(:download_bill)
      .and_return(csv: csv, raw_summary: {})

    bill = described_class.call(customer: customer, provider: "alipay",
                                bill_date: Date.today, bill_type: "all")

    expect(bill.status).to eq("discrepant")
    expect(bill.discrepancy_count).to eq(1)
  end

  it "flags a row whose amount disagrees with the local payment (H5: amount-aware)" do
    # OT-1 is a 1.00 payment locally, but the PSP bill reports 5.00.
    csv = "trade_no,out_trade_no,amount\nT1,OT-1,5.00\nT2,OT-2,2.00\n"
    allow(Payments::Gateway).to receive(:download_bill).and_return(csv: csv, raw_summary: {})

    bill = described_class.call(customer: customer, provider: "alipay",
                                bill_date: Date.today, bill_type: "all")

    expect(bill.status).to eq("discrepant")
    expect(bill.discrepancy_count).to eq(1)
  end

  it "flags a local success that is absent from the PSP bill (H5: reverse direction)" do
    # A settled payment the PSP bill never lists.
    order = create(:payment_order, external_ref: "rc-3", amount: 3.00, subject: "s")
    create(:payment, payment_order: order, provider: "alipay", flow: "qr",
           out_trade_no: "OT-3", amount: 3.00, status: "succeeded",
           paid_at: Time.current)
    csv = "trade_no,out_trade_no,amount\nT1,OT-1,1.00\nT2,OT-2,2.00\n"
    allow(Payments::Gateway).to receive(:download_bill).and_return(csv: csv, raw_summary: {})

    bill = described_class.call(customer: customer, provider: "alipay",
                                bill_date: Date.today, bill_type: "all")

    expect(bill.status).to eq("discrepant")
    expect(bill.discrepancy_count).to eq(1)
  end

  it "marks the bill failed and re-raises when gateway errors" do
    allow(Payments::Gateway).to receive(:download_bill)
      .and_raise(Payments::Errors::TransportError.new("network down"))

    expect {
      described_class.call(customer: customer, provider: "alipay",
                           bill_date: Date.today, bill_type: "all")
    }.to raise_error(Payments::Errors::TransportError)

    bill = Payments::ReconciliationBill.find_by(provider: "alipay", bill_date: Date.today,
                                             bill_type: "all")
    expect(bill.status).to eq("failed")
  end

  it "normalizes WeChat localized headers, backticks and the summary footer" do
    payment_one.update!(provider: "wechat_pay", paid_at: Time.current)
    csv = "\uFEFF交易时间,商户订单号,交易状态,订单金额（元）,货币种类\r\n" \
          "`2026-10-11 00:01:00,`OT-1,`SUCCESS,`1.00,`CNY\r\n" \
          "总交易单数,订单总金额,退款总金额\r\n`1,`1.00,`0.00\r\n"
    allow(Payments::Gateway).to receive(:download_bill).and_return(csv: csv, raw_summary: {})

    bill = described_class.call(customer: customer, provider: "wechat_pay", bill_date: Date.current)

    expect(bill.status).to eq("reconciled")
    expect(bill.total_count).to eq(1)
    expect(bill.total_amount).to eq(1.00)
    expect(bill.discrepancy_count).to eq(0)
  end

  it "uses gateway-normalized rows while retaining the original attachment" do
    allow(Payments::Gateway).to receive(:download_bill).and_return(
      csv: "native provider bill", rows: [{ out_trade_no: "OT-1", amount: "1.00" }], raw_summary: {}
    )

    bill = described_class.call(customer: customer, provider: "alipay", bill_date: Date.current)

    expect(bill.status).to eq("reconciled")
    expect(bill.total_count).to eq(1)
    expect(bill.bill_file.download).to eq("native provider bill")
  end

  it "does not reconcile a payment captured by a different provider" do
    allow(Payments::Gateway).to receive(:download_bill).and_return(
      csv: "out_trade_no,amount\nOT-1,1.00\n", raw_summary: {}
    )

    bill = described_class.call(customer: customer, provider: "wechat_pay", bill_date: Date.current)

    expect(bill.status).to eq("discrepant")
    expect(bill.discrepancy_count).to eq(1)
  end

  it "flags a malformed asserted amount instead of treating it as an absent assertion" do
    allow(Payments::Gateway).to receive(:download_bill).and_return(
      csv: "out_trade_no,amount\nOT-1,not-a-number\n", raw_summary: {}
    )

    bill = described_class.call(customer: customer, provider: "alipay", bill_date: Date.current)

    expect(bill.status).to eq("discrepant")
    expect(bill.discrepancy_count).to eq(1)
  end

  it "reconciles canonical WeChat refund rows against their own amount rather than the gross capture" do
    payment_one.update!(provider: "wechat_pay", paid_at: Time.current)
    refund = create(:payment_refund, payment: payment_one, amount: 0.50, status: "succeeded", psp_refund_id: "wx_refund")
    allow(Payments::Gateway).to receive(:download_bill).and_return(csv: "original native bill", raw_summary: {}, rows: [
      { "kind" => "payment", "out_trade_no" => payment_one.out_trade_no, "amount" => "1.00", "currency" => "CNY" },
      { "kind" => "refund", "out_trade_no" => payment_one.out_trade_no, "out_refund_no" => refund.out_refund_no,
        "psp_refund_id" => "wx_refund", "amount" => "0.50", "currency" => "CNY", "status" => "processing" }
    ])

    bill = described_class.call(customer: customer, provider: "wechat_pay", bill_date: Date.current)

    expect(bill.status).to eq("reconciled")
    expect(bill.discrepancy_count).to eq(0)
    expect(refund.reload.status).to eq("succeeded")
  end
end
