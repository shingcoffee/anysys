# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Contracts::ProviderSettings do
  # Ensure aliyun provider is registered in the Captcha::Providers registry.
  # In autoloaded environments the constant isn't resolved until first reference.
  subject(:form) do
    described_class.new(
      OpenStruct.new(
        provider: "aliyun", access_key_id: "AKID-test",
        access_key_secret: "SECRET-test", enabled: true, fail_policy: "open",
        config: valid_config
      )
    )
  end

  before { Captcha::Providers::Aliyun }


  let(:valid_config) do
    { scene_id: "abc", prefix: "identity-1", endpoint: "captcha.cn-shanghai.aliyuncs.com", region: "cn-shanghai" }.to_json
  end

  let(:valid_params) do
    {
      provider:          "aliyun",
      access_key_id:     "AKID",
      access_key_secret: "SECRET",
      enabled:           true,
      fail_policy:       "open",
      config:            valid_config
    }
  end

  def validate_with(params)
    form.validate(params)
    form
  end

  describe "access_key_id validation" do
    it "is valid with a non-blank access_key_id and valid config" do
      expect(validate_with(valid_params).errors[:base]).to be_empty
    end

    it "adds a base error (localized) when access_key_id is blank" do
      f = validate_with(valid_params.merge(access_key_id: ""))
      expect(f.errors[:base]).to include(I18n.t("captcha.platform_settings.errors.access_key_id_blank"))
    end

    it "treats a whitespace-only access_key_id as blank" do
      f = validate_with(valid_params.merge(access_key_id: "   "))
      expect(f.errors[:base]).to include(I18n.t("captcha.platform_settings.errors.access_key_id_blank"))
    end
  end

  describe "fail_policy validation" do
    it "adds a base error (localized) for an invalid fail_policy" do
      f = validate_with(valid_params.merge(fail_policy: "sideways"))
      expect(f.errors[:base]).to include(I18n.t("captcha.platform_settings.errors.fail_policy_invalid"))
    end

    Captcha::ProviderSettings::FAIL_POLICIES.each do |policy|
      it "accepts the declared fail_policy '#{policy}'" do
        f = validate_with(valid_params.merge(fail_policy: policy))
        expect(f.errors[:base]).to be_empty
      end
    end
  end

  describe "provider validation (required config fields)" do
    it "adds the unknown-provider base error when the provider is unregistered" do
      f = validate_with(valid_params.merge(provider: "unknown_vendor_xyz", config: "{}"))
      expect(f.errors[:base]).to include(I18n.t("captcha.platform_settings.errors.unknown_provider"))
    end
  end

  describe "required config fields" do
    it "adds a localized base error per missing required field" do
      # Scene id and identity prefix are required; endpoint and region default.
      f = validate_with(valid_params.merge(config: {}.to_json))
      expect(f.errors[:base]).not_to be_empty
      expect(f.errors[:base].join(" ")).to match(/scene id|endpoint|region/i)
    end

    it "is valid when all required config fields are present" do
      expect(validate_with(valid_params).errors[:base]).to be_empty
    end

    it "accepts a JSON-string config (as submitted from ProviderSettings#config)" do
      f = validate_with(valid_params.merge(config: valid_config))
      expect(f.errors[:base]).to be_empty
    end

    it "treats malformed JSON config as an empty hash rather than raising" do
      f = validate_with(valid_params.merge(config: "{not json"))
      expect(f.errors[:base]).not_to be_empty
    end

    it "accepts a string-keyed Hash config (the shape JSON.parse produces)" do
      f = validate_with(valid_params.merge(config: JSON.parse(valid_config)))
      expect(f.errors[:base]).to be_empty
    end

    it "normalizes symbol-keyed Hash configuration" do
      f = validate_with(valid_params.merge(config: JSON.parse(valid_config).symbolize_keys))
      expect(f.errors[:base]).to be_empty
    end

    it "rejects an endpoint/region mismatch with a localized configuration error" do
      config = JSON.parse(valid_config).merge("region" => "ap-southeast-1")
      f = validate_with(valid_params.merge(config: config))
      expect(f.errors[:base]).to include(I18n.t("captcha.platform_settings.errors.configuration_invalid"))
    end

    it "requires the V2 identity credential" do
      f = validate_with(valid_params.merge(config: { scene_id: "abc" }.to_json))
      expect(f.errors[:base]).to include(I18n.t("captcha.platform_settings.errors.field_blank", field: I18n.t("captcha.providers.aliyun.fields.prefix")))
    end

    ["null", "[]", "true"].each do |config|
      it "reports non-object JSON #{config} as invalid configuration" do
        expect(validate_with(valid_params.merge(config: config)).errors[:base]).not_to be_empty
      end
    end
  end
end
