# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::JsapiInvokerComponent, type: :component do
  let(:payment) do
    instance_double(Payments::Payment,
                    id: 42, out_trade_no: "ots-jsapi-42",
                    provider: "wechat_pay",
                    prepay_payload: { "appId" => "wxabc", "nonceStr" => "n" })
  end

  before do
    stub_helpers = double("helpers", params: { customer_id: "12345678" })
    allow(stub_helpers).to receive(:payment_result_path) { |**kw| "/12345678/payments/result/#{kw[:payment_id]}" }
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  it "wires Stimulus JSAPI invoker attributes" do
    render_inline(described_class.new(payment: payment))

    section = page.find("section")
    expect(section["data-controller"]).to eq("payments--jsapi-invoker")
    expect(section["data-payments--jsapi-invoker-provider-value"]).to eq("wechat_pay")
    expect(JSON.parse(section["data-payments--jsapi-invoker-params-value"])).to eq("appId" => "wxabc", "nonceStr" => "n")
    expect(section["data-payments--jsapi-invoker-result-url-value"]).to eq("/12345678/payments/result/ots-jsapi-42")
  end

  it "serializes a different provider's params_json" do
    alipay_payment = instance_double(Payments::Payment, id: 43, out_trade_no: "ots-jsapi-43",
                                                provider: "alipay", prepay_payload: { "trade_no" => "T1" })
    render_inline(described_class.new(payment: alipay_payment))

    section = page.find("section")
    expect(section["data-payments--jsapi-invoker-provider-value"]).to eq("alipay")
    expect(JSON.parse(section["data-payments--jsapi-invoker-params-value"])).to eq("trade_no" => "T1")
  end
end
