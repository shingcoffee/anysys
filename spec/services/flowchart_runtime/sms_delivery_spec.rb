# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::SmsDelivery do
  let(:customer) { create(:customer) }
  let!(:credential) { create(:sms_credential, provider: "aliyun", mode: "sandbox") }
  let!(:template) do
    create(:sms_template, key: "verify_code", variables: %w[code minutes],
                          provider_template_codes: { "aliyun" => "SMS_1" })
  end
  let(:vars) { { "code" => "1234", "minutes" => "5" } }
  let(:phone) { "+8613800138000" }

  before do
    enable_module!("sms", customer, name: "SMS")
    allow(Sms::DeliverMessageJob).to receive(:perform_later)
  end

  it "returns the admitted message id" do
    ctx = { errors: [] }
    id = described_class.deliver(ctx, customer: customer, to: phone, template_key: "verify_code", vars: vars)
    expect(id).to eq(Sms::Message.last.id)
    expect(ctx[:errors]).to eq([])
  end

  it "maps suppression to send_sms.suppressed" do
    Sms::OptOut.record_global!(phone_e164: phone, provider: "twilio", reason: "inbound:STOP")
    ctx = { errors: [] }
    expect(described_class.deliver(ctx, customer: customer, to: phone, template_key: "verify_code", vars: vars)).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.send_sms.suppressed"))
  end

  it "maps daily cap and rate limits to send_sms.quota" do
    described_class.deliver({ errors: [] }, customer: customer, to: phone, template_key: "verify_code", vars: vars)
    ctx = { errors: [] }
    expect(described_class.deliver(ctx, customer: customer, to: phone, template_key: "verify_code", vars: vars)).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.send_sms.quota"))
  end

  it "maps an invalid number to send_sms.invalid_number" do
    ctx = { errors: [] }
    expect(described_class.deliver(ctx, customer: customer, to: "nope", template_key: "verify_code", vars: vars)).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.send_sms.invalid_number"))
  end

  it "maps a missing template to send_sms.template_missing" do
    ctx = { errors: [] }
    expect(described_class.deliver(ctx, customer: customer, to: phone, template_key: "missing_key", vars: {})).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.send_sms.template_missing"))
  end

  it "raises when customer is missing" do
    expect {
      described_class.deliver({ errors: [] }, customer: nil, to: phone, template_key: "verify_code")
    }.to raise_error(described_class::Error, /customer/)
  end
end
