# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Payment::MemberSurface do
  def vendor_value
    described_class.build.index.columns.find { |col| col[:key] == :vendor }.fetch(:value)
  end

  def primary_row_value(key)
    rows = described_class.build.detail.sections.find { |s| s[:key] == :primary }.fetch(:rows)
    rows.find { |row| row[:key] == key }.fetch(:value)
  end

  def detail_vendor_value = primary_row_value(:vendor)
  def detail_flow_value   = primary_row_value(:flow)

  it "shows the gateway display_name on the index, not a titleized provider key" do
    payment = instance_double(Payments::Payment, provider: "wechat_pay")

    expect(vendor_value.call(payment)).to eq(Payments::Gateways::WechatPay.display_name)
    expect(vendor_value.call(payment)).not_to eq("wechat_pay".titleize)
  end

  it "uses the same vendor label on the payment detail" do
    payment = instance_double(Payments::Payment, provider: "alipay")

    expect(detail_vendor_value.call(payment)).to eq(Payments::Gateways::Alipay.display_name)
  end

  it "falls back to the raw provider key when the gateway is unknown" do
    payment = instance_double(Payments::Payment, provider: "unknown_gw")

    expect(vendor_value.call(payment)).to eq("unknown_gw")
  end

  it "localizes the detail header status instead of dumping the raw key" do
    payment = instance_double(Payments::Payment, status: "succeeded")
    meta = described_class.build.detail.meta.call(payment)

    expect(meta[:label]).to eq(I18n.t("common.status.succeeded"))
    expect(meta[:tone]).to eq(:success)
  end

  it "localizes the detail header status in zh-CN" do
    payment = instance_double(Payments::Payment, status: "succeeded")
    I18n.with_locale(:"zh-CN") do
      meta = described_class.build.detail.meta.call(payment)
      expect(meta[:label]).to eq(I18n.t("common.status.succeeded"))
    end
  end

  it "does not translate an unknown payment status through a colliding common.status key" do
    payment = instance_double(Payments::Payment, status: "draft")
    meta = described_class.build.detail.meta.call(payment)

    expect(meta[:label]).to eq("draft")
    expect(meta[:label]).not_to eq(I18n.t("common.status.draft"))
  end

  it "shows the gateway flow label on the payment detail, not an upcased key" do
    payment = instance_double(Payments::Payment, flow: "qr")

    expect(detail_flow_value.call(payment)).to eq(I18n.t("comp_payments.gateway_card.flows.qr"))
    expect(detail_flow_value.call(payment)).not_to eq("QR")
  end

  it "localizes the payment flow in zh-CN" do
    payment = instance_double(Payments::Payment, flow: "card")
    I18n.with_locale(:"zh-CN") do
      expect(detail_flow_value.call(payment)).to eq(I18n.t("comp_payments.gateway_card.flows.card"))
    end
  end

  it "falls back to the raw flow key when the flow is unknown" do
    payment = instance_double(Payments::Payment, flow: "unknown_flow")

    expect(detail_flow_value.call(payment)).to eq("unknown_flow")
  end

  it "passes the order currency with the amount so JPY is not shown as USD" do
    order = double(currency: "JPY")
    payment = instance_double(Payments::Payment, amount: 1000, payment_order: order)
    amount_value = described_class.build.index.columns.find { |col| col[:key] == :amount }.fetch(:value)

    expect(amount_value.call(payment)).to eq(amount: 1000, currency: "JPY")
    expect(Member::Formatters.format(amount_value.call(payment), :money_major)).to eq("¥1000")
  end
end
