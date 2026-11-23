# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Activities::AssignDelivery do
  let!(:smtp_sandbox) { create(:email_credential, provider: "smtp", mode: "sandbox", status: "active") }
  let!(:smtp_production) { create(:email_credential, :production, provider: "smtp", status: "disabled") }
  let!(:ses_sandbox) do
    create(:email_credential, provider: "ses", mode: "sandbox", status: "disabled",
           host: nil, username: nil, password: "secret",
           config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com", "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses" })
  end

  it "activates the chosen vendor per mode and disables the others" do
    result = described_class.call(sandbox_provider: "ses", production_provider: "smtp")

    expect(result.success?).to be(true)
    expect(smtp_sandbox.reload.status).to eq("disabled")
    expect(ses_sandbox.reload.status).to eq("active")
    expect(smtp_production.reload.status).to eq("active")
  end

  it "clears a mode when the provider is blank" do
    result = described_class.call(sandbox_provider: "", production_provider: "smtp")

    expect(result.success?).to be(true)
    expect(smtp_sandbox.reload.status).to eq("disabled")
    expect(smtp_production.reload.status).to eq("active")
  end

  it "returns an error when the vendor has no credential for that mode" do
    result = described_class.call(sandbox_provider: "aliyun", production_provider: "smtp")

    expect(result.success?).to be(false)
    expect(result.errors.join).to include("aliyun")
    expect(smtp_sandbox.reload.status).to eq("active")
  end

  it "rejects an incomplete credential and rolls back sibling mode changes" do
    ses_sandbox.update_columns(status: "disabled")
    ses_sandbox.write_config(from_email: "")
    ses_sandbox.save!(validate: false)

    result = described_class.call(sandbox_provider: "ses", production_provider: "smtp")

    expect(result.success?).to be(false)
    expect(smtp_sandbox.reload.status).to eq("active")
    expect(smtp_production.reload.status).to eq("disabled")
  end
end
