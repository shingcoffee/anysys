# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Gateways::WechatPay::BillParser do
  # Native ALL headers and vendor-escaped values, not a normalized English CSV.
  let(:headers) do
    "交易时间,公众账号ID,商户号,特约商户号,设备号,微信订单号,商户订单号,用户标识,交易类型,交易状态,付款银行,货币种类,应结订单金额,代金券金额,微信退款单号,商户退款单号,退款金额,充值券退款金额,退款类型,退款状态,商品名称,商户数据包,手续费,费率,订单金额,申请退款金额,费率备注".split(",")
  end
  let(:payment_row) do
    {
      "交易时间" => "2026-10-10 23:30:00", "公众账号ID" => "wxappid", "商户号" => "1900000001",
      "微信订单号" => "4200000008201712143733500001", "商户订单号" => "order-1",
      "交易类型" => "NATIVE", "交易状态" => "SUCCESS", "货币种类" => "CNY",
      "应结订单金额" => "8.00", "代金券金额" => "2.00", "订单金额" => "10.00", "申请退款金额" => "0.00",
      "微信退款单号" => "0", "商户退款单号" => "0", "退款金额" => "0.00",
      "商品名称" => 'A \\"quoted\\" item', "商户数据包" => "line\\nnext", "手续费" => "0.06"
    }
  end
  let(:refund_row) do
    payment_row.merge(
      "交易状态" => "REFUND", "订单金额" => "0.00", "应结订单金额" => "0.00",
      "申请退款金额" => "4.00", "退款金额" => "3.00", "退款状态" => "PROCESSING",
      "微信退款单号" => "50401010122021000000038202001", "商户退款单号" => "refund-1"
    )
  end

  def native_bill(rows, summary: true)
    lines = [headers.join(",")]
    rows.each { |row| lines << headers.map { |header| "`#{row.fetch(header, '')}" }.join(",") }
    lines.concat(["总交易单数,应结订单总金额,退款总金额,订单总金额,申请退款总金额", "`2,`8.00,`3.00,`10.00,`4.00"]) if summary
    "\uFEFF#{lines.join("\r\n")}\r\n"
  end

  it "separates the footer and uses gross order amount rather than coupon-adjusted settlement" do
    result = described_class.call(native_bill([payment_row, refund_row]))
    expect(result.records.size).to eq(2)
    expect(result.records.first).to include(
      "kind" => "payment", "amount" => BigDecimal("10.00"), "currency" => "CNY",
      "out_trade_no" => "order-1", "psp_transaction_id" => "4200000008201712143733500001",
      "settled_at" => Time.utc(2026, 10, 10, 15, 30)
    )
    expect(result.summary).to include("总交易单数" => "2", "订单总金额" => "10.00")
  end

  it "preserves refund kind, gross requested amount and acceptance-time status without claiming settlement" do
    record = described_class.call(native_bill([refund_row], summary: false)).records.sole
    expect(record).to include("kind" => "refund", "amount" => BigDecimal("4.00"), "status" => "processing",
                             "out_refund_no" => "refund-1", "psp_refund_id" => "50401010122021000000038202001",
                             "settled_at" => nil)
  end

  it "handles literal vendor-escaped quotes and newlines without mistaking them for CSV quoting" do
    record = described_class.call(native_bill([payment_row], summary: false)).records.sole
    expect(record["raw"]["商品名称"]).to eq(payment_row["商品名称"])
    expect(record["raw"]["商户数据包"]).to eq("line\\nnext")
  end

  it "supports a SUCCESS bill that has no refund columns" do
    body = "交易时间,微信订单号,商户订单号,交易状态,货币种类,订单金额\n" \
      "`2026-10-10 23:30:00,`WX1,`order-1,`SUCCESS,`CNY,`10.00\n"
    expect(described_class.call(body).records.sole["amount"]).to eq(BigDecimal("10.00"))
  end

  it "supports the REFUND bill's explicit success-time column" do
    body = "交易时间,微信订单号,商户订单号,交易状态,货币种类,订单金额,申请退款金额,退款状态,退款成功时间,商户退款单号\n" \
      "`2026-10-09 20:00:00,`WX1,`order-1,`REFUND,`CNY,`0.00,`4.00,`SUCCESS,`2026-10-10 23:30:00,`refund-1\n"
    expect(described_class.call(body).records.sole).to include("kind" => "refund", "settled_at" => Time.utc(2026, 10, 10, 15, 30))
  end

  ["NaN", "not-money", "-1.00"].each do |amount|
    it "rejects an invalid monetary assertion: #{amount}" do
      expect { described_class.call(native_bill([payment_row.merge("订单金额" => amount)], summary: false)) }
        .to raise_error(Payments::Errors::ApiError) { |error| expect(error.code).to eq("invalid_bill") }
    end
  end

  it "rejects missing native headers rather than silently reporting a clean empty bill" do
    expect { described_class.call("date,amount\n2026-10-10,1.00\n") }.to raise_error(Payments::Errors::ApiError)
  end

  it "rejects truncated rows rather than silently dropping a transaction" do
    expect { described_class.call("#{headers.join(',')}\n`2026-10-10\n") }.to raise_error(Payments::Errors::ApiError)
  end

  it "rejects invalid UTF-8 bytes with a controlled bill error" do
    expect { described_class.call("\xFF".b) }.to raise_error(Payments::Errors::ApiError)
  end
end
