# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Template do
  it "is valid with required attributes" do
    expect(build(:sms_template)).to be_valid
  end

  it "requires a unique snake_case key" do
    create(:sms_template, key: "verify_code")
    expect(build(:sms_template, key: "verify_code")).not_to be_valid
    expect(build(:sms_template, key: "Verify-Code")).not_to be_valid
  end

  it "requires variables to be an array of strings" do
    tpl = build(:sms_template, variables: [1, 2])
    expect(tpl).not_to be_valid
    expect(tpl.errors[:variables]).to include("must be an array of strings")
  end

  it "scopes .active to status='active'" do
    active  = create(:sms_template, key: "a", status: "active")
    retired = create(:sms_template, key: "b", status: "retired")
    expect(described_class.active).to include(active)
    expect(described_class.active).not_to include(retired)
  end

  it "exposes required_vars as an Array regardless of column value" do
    tpl = create(:sms_template, variables: %w[code])
    expect(tpl.required_vars).to eq(%w[code])
  end

  describe "#provider_codes_present validation" do
    it "is invalid with an empty provider_template_codes hash" do
      tpl = build(:sms_template, provider_template_codes: {})
      expect(tpl).not_to be_valid
      expect(tpl.errors[:provider_template_codes]).to include(
        I18n.t("maint_platform.errors.validations.sms_provider_codes_required")
      )
    end

    it "is invalid when every provider code is blank" do
      tpl = build(:sms_template, provider_template_codes: { "aliyun" => "", "twilio" => "  " })
      expect(tpl).not_to be_valid
    end

    it "is valid with at least one non-blank provider code" do
      tpl = build(:sms_template, provider_template_codes: { "aliyun" => "", "twilio" => "HX123" })
      expect(tpl).to be_valid
    end
  end

  describe "#provider_codes / #provider_code" do
    it "returns the codes hash, defaulting to {} when nil" do
      tpl = build(:sms_template, provider_template_codes: nil)
      expect(tpl.provider_codes).to eq({})
    end

    it "#provider_code returns the code for a given provider key" do
      tpl = build(:sms_template, provider_template_codes: { "aliyun" => "SMS_1", "twilio" => "HX1" })
      expect(tpl.provider_code("aliyun")).to eq("SMS_1")
      expect(tpl.provider_code(:twilio)).to eq("HX1")
    end

    it "#provider_code returns nil for a blank or missing entry" do
      tpl = build(:sms_template, provider_template_codes: { "aliyun" => "", "twilio" => "HX1" })
      expect(tpl.provider_code("aliyun")).to be_nil
      expect(tpl.provider_code("unknown")).to be_nil
    end
  end

  describe "#active?" do
    it "is true when status is active" do
      expect(build(:sms_template, status: "active")).to be_active
    end

    it "is false when retired" do
      expect(build(:sms_template, status: "retired")).not_to be_active
    end
  end
end
