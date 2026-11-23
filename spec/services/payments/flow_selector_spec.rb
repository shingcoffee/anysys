# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::FlowSelector do
  def req(ua) = instance_double(ActionDispatch::Request, user_agent: ua)

  context "card-only gateway (stripe)" do
    let(:ua) { "Mozilla/5.0 (iPhone)" }

    it "always selects :card regardless of UA" do
      expect(described_class.call(request: req(ua), provider: "stripe")).to eq(:card)
    end
  end

  context "china gateway (alipay) preserves existing heuristic" do
    let(:ua) { "Mozilla/5.0 (Macintosh)" }

    it "selects :qr on desktop" do
      expect(described_class.call(request: req(ua), provider: "alipay")).to eq(:qr)
    end
  end

  context "in-app browser" do
    let(:ua) { "MicroMessenger/8.0" }

    it "selects :jsapi for wechat_pay" do
      expect(described_class.call(request: req(ua), provider: "wechat_pay")).to eq(:jsapi)
    end
  end

  # Regression tests from original spec
  it "returns :jsapi inside WeChat browser for wechat_pay" do
    ua = "Mozilla/5.0 ... MicroMessenger/8.0"
    expect(described_class.call(request: req(ua), provider: "wechat_pay")).to eq(:jsapi)
  end

  it "returns :jsapi inside Alipay browser for alipay" do
    ua = "Mozilla/5.0 ... AlipayClient/10.2"
    expect(described_class.call(request: req(ua), provider: "alipay")).to eq(:jsapi)
  end

  it "returns :h5 on mobile browser outside PSP apps" do
    ua = "Mozilla/5.0 (iPhone; ... Mobile Safari)"
    expect(described_class.call(request: req(ua), provider: "alipay")).to eq(:h5)
    expect(described_class.call(request: req(ua), provider: "wechat_pay")).to eq(:h5)
  end

  it "returns :qr on desktop" do
    ua = "Mozilla/5.0 (Macintosh; ...) Chrome"
    expect(described_class.call(request: req(ua), provider: "wechat_pay")).to eq(:qr)
  end
end
