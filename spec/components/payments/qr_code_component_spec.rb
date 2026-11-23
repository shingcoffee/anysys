# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::QrCodeComponent, type: :component do
  let(:payment) do
    instance_double(Payments::Payment,
                    id: 99, out_trade_no: "ots-abc-99", provider: "wechat_pay",
                    prepay_payload: { "code_url" => "weixin://wxpay/bizpayurl?pr=abc" })
  end

  before do
    stub_helpers = double("helpers", params: { customer_id: "12345678" })
    # Echo the identifier arg back so the specs can assert both poll and
    # result URLs key on out_trade_no (not the sequential primary key).
    allow(stub_helpers).to receive(:payment_status_path) { |**kw| "/12345678/payments/#{kw[:id]}/status" }
    allow(stub_helpers).to receive(:payment_result_path) { |**kw| "/12345678/payments/result/#{kw[:payment_id]}" }
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  it "wires Stimulus QR poll attributes and renders an inline QR svg" do
    render_inline(described_class.new(payment: payment))

    section = page.find("section")
    expect(section["data-controller"]).to eq("payments--qr-poll")
    # Status poll must key on out_trade_no — CheckoutsController#status 404s an
    # integer primary-key lookup for anonymous shoppers.
    expect(section["data-payments--qr-poll-status-url-value"]).to eq("/12345678/payments/ots-abc-99/status")
    # The result route keys on out_trade_no (same as status) so sequential
    # integer PKs cannot be enumerated on this public page.
    expect(section["data-payments--qr-poll-result-url-value"]).to eq("/12345678/payments/result/ots-abc-99")
    expect(page).to have_css("svg")
    expect(page).to have_css("[data-payments--qr-poll-target='status']", text: "Waiting for payment")
  end

  it "labels the QR instruction with the gateway display name" do
    render_inline(described_class.new(payment: payment))
    expect(page).to have_text("Use WeChat Pay (China) to scan the code below")
  end

  it "does not label a non-WeChat QR as Alipay" do
    stripe_payment = instance_double(Payments::Payment, id: 101, out_trade_no: "ots-stripe",
                                      provider: "stripe",
                                      prepay_payload: { "code_url" => "https://stripe.example/qr" })
    render_inline(described_class.new(payment: stripe_payment))
    expect(page).to have_text("Use Credit / Debit Card (Stripe) to scan the code below")
    expect(page).not_to have_text("Alipay")
  end

  it "renders the code_url into the inline svg (no third-party image service)" do
    render_inline(described_class.new(payment: payment))
    html = page.native.to_html
    expect(html).not_to include("api.qrserver.com")
    expect(html).to include("<svg")
  end

  it "falls back to qr_code when code_url is not provided" do
    fallback_payment = instance_double(Payments::Payment, id: 100, out_trade_no: "ots-fallback",
                                                provider: "alipay",
                                                prepay_payload: { "qr_code" => "QR_PAYLOAD" })
    render_inline(described_class.new(payment: fallback_payment))

    expect(page).to have_css("svg")
  end
end
