# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Activities::AssignDelivery do
  let!(:aliyun_sandbox) { create(:sms_credential, provider: "aliyun", mode: "sandbox", status: "active") }
  let!(:aliyun_production) { create(:sms_credential, provider: "aliyun", mode: "production", status: "disabled") }
  let!(:twilio_sandbox) do
    create(:sms_credential, provider: "twilio", mode: "sandbox", status: "disabled",
           access_key_id: "AC_TEST", access_key_secret: "AUTH_TOKEN",
           config: { "messaging_service_sid" => "MG1" })
  end

  it "activates the chosen vendor per mode and disables the others" do
    result = described_class.call(sandbox_provider: "twilio", production_provider: "aliyun")

    expect(result.success?).to be(true)
    expect(aliyun_sandbox.reload.status).to eq("disabled")
    expect(twilio_sandbox.reload.status).to eq("active")
    expect(aliyun_production.reload.status).to eq("active")
  end

  it "clears a mode when the provider is blank" do
    result = described_class.call(sandbox_provider: "", production_provider: "aliyun")

    expect(result.success?).to be(true)
    expect(aliyun_sandbox.reload.status).to eq("disabled")
    expect(aliyun_production.reload.status).to eq("active")
  end

  it "returns an error when the vendor has no credential for that mode" do
    result = described_class.call(sandbox_provider: "twilio", production_provider: "twilio")

    expect(result.success?).to be(false)
    expect(result.errors.join).to include("twilio")
    expect(aliyun_sandbox.reload.status).to eq("active")
  end

  it "rejects an incomplete credential and rolls back sibling mode changes" do
    twilio_sandbox.update_columns(status: "disabled")
    twilio_sandbox.write_config(messaging_service_sid: "")
    twilio_sandbox.save!(validate: false)

    result = described_class.call(sandbox_provider: "twilio", production_provider: "aliyun")

    expect(result.success?).to be(false)
    expect(aliyun_sandbox.reload.status).to eq("active")
    expect(aliyun_production.reload.status).to eq("disabled")
  end

  it "uses the same assignment invariant for an existing active-card save" do
    twilio_sandbox.assign_attributes(status: "active")
    result = described_class.persist(record: twilio_sandbox)

    expect(result.success?).to be(true)
    expect(Sms::Credential.active.where(mode: "sandbox")).to contain_exactly(twilio_sandbox)
    expect(aliyun_sandbox.reload.status).to eq("disabled")
  end
end
