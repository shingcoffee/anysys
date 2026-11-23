# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::ProviderSettings do
  before { Captcha::Providers::Aliyun } # force registry load in isolation

  describe ".active" do
    it "returns nil when no provider row exists" do
      expect(described_class.active).to be_nil
    end

    it "returns nil when the enabled row exists but is not configured" do
      described_class.for_provider("aliyun").activate!
      expect(described_class.active).to be_nil
    end

    it "returns nil when a fully configured row exists but is not enabled" do
      create(:captcha_provider_settings, enabled: false)
      expect(described_class.active).to be_nil
    end

    it "returns the row when it is both enabled and configured" do
      settings = create(:captcha_provider_settings, enabled: true)
      expect(described_class.active).to eq(settings)
    end
  end

  describe ".for_provider" do
    it "creates the row on first access" do
      expect { described_class.for_provider("aliyun") }.to change(described_class, :count).from(0).to(1)
    end

    it "returns the existing row on subsequent access" do
      first  = described_class.for_provider("aliyun")
      second = described_class.for_provider("aliyun")
      expect(first).to eq(second)
      expect(described_class.count).to eq(1)
    end

    it "is race-safe against a concurrent insert (RecordNotUnique retried as a find)" do
      allow(described_class).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)
      existing = create(:captcha_provider_settings, provider: "aliyun")
      expect(described_class.for_provider("aliyun")).to eq(existing)
    end
  end

  describe "validations" do
    it "rejects a second row for the same provider" do
      described_class.for_provider("aliyun")
      duplicate = described_class.new(provider: "aliyun", access_key_id: "x", access_key_secret: "y")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:provider]).to be_present
    end

    it "rejects an unknown provider" do
      bad = described_class.new(provider: "nonexistent", access_key_id: "x", access_key_secret: "y")
      expect(bad).not_to be_valid
      expect(bad.errors[:provider]).to be_present
    end

    it "rejects an invalid fail_policy" do
      s = build(:captcha_provider_settings, fail_policy: "sideways")
      expect(s).not_to be_valid
      expect(s.errors[:fail_policy]).to be_present
    end

    it "accepts open/closed fail_policy values" do
      described_class::FAIL_POLICIES.each do |policy|
        expect(build(:captcha_provider_settings, fail_policy: policy)).to be_valid
      end
    end

    it "rejects a score_threshold outside 0..1" do
      expect(build(:captcha_provider_settings, score_threshold: 1.5)).not_to be_valid
      expect(build(:captcha_provider_settings, score_threshold: -0.1)).not_to be_valid
    end

    it "allows a nil score_threshold (binary provider)" do
      expect(build(:captcha_provider_settings, score_threshold: nil)).to be_valid
    end

    it "allows a score_threshold within 0..1" do
      expect(build(:captcha_provider_settings, score_threshold: 0.5)).to be_valid
    end
  end

  describe "credential encryption" do
    it "encrypts access_key_secret at rest" do
      s = create(:captcha_provider_settings, access_key_secret: "SECRET")
      raw = ActiveRecord::Base.connection.execute(
        "SELECT access_key_secret FROM captcha_provider_settings WHERE id=#{s.id}"
      ).first
      stored = raw.is_a?(Hash) ? raw["access_key_secret"] : raw[0]
      expect(stored).not_to include("SECRET")
      expect(s.reload.access_key_secret).to eq("SECRET")
    end
  end

  describe "#configured?" do
    it "delegates to the provider class" do
      s = described_class.for_provider("aliyun")
      expect(s.configured?).to eq(false)
      s.update!(access_key_id: "AKID", access_key_secret: "S")
      s.write_config(scene_id: "scn", prefix: "identity-1")
      s.save!
      expect(s.reload.configured?).to eq(true)
    end

    it "degrades to false for a stale/unknown provider key instead of raising" do
      s = described_class.new(provider: "gone")
      s.save!(validate: false)
      expect(s.configured?).to eq(false)
    end
  end

  describe "#score_based?" do
    it "delegates to the provider class" do
      s = described_class.for_provider("aliyun")
      expect(s.score_based?).to eq(false)
    end

    it "degrades to false for a stale/unknown provider key instead of raising" do
      s = described_class.new(provider: "gone")
      s.save!(validate: false)
      expect(s.score_based?).to eq(false)
    end
  end

  describe "#fail_open? / #fail_closed?" do
    it "treats any non-'closed' value as open (including the default)" do
      s = build(:captcha_provider_settings, fail_policy: "open")
      expect(s.fail_open?).to eq(true)
      expect(s.fail_closed?).to eq(false)
    end

    it "treats 'closed' as closed" do
      s = build(:captcha_provider_settings, fail_policy: "closed")
      expect(s.fail_open?).to eq(false)
      expect(s.fail_closed?).to eq(true)
    end
  end

  describe "#config_value / #write_config" do
    it "round-trips JSON config keys" do
      s = described_class.for_provider("aliyun")
      s.write_config(scene_id: "X")
      s.save!
      expect(s.reload.config_value(:scene_id)).to eq("X")
      expect(s.config_value(:missing, "fallback")).to eq("fallback")
    end

    it "merges rather than replaces existing keys" do
      s = described_class.for_provider("aliyun")
      s.write_config(scene_id: "A", endpoint: "e1")
      s.save!
      s.write_config(scene_id: "B")
      s.save!
      expect(s.reload.config_value(:scene_id)).to eq("B")
      expect(s.config_value(:endpoint)).to eq("e1")
    end
  end

  describe "#activate! / #deactivate!" do
    it "enables this row and clears any other enabled row atomically" do
      a = create(:captcha_provider_settings, provider: "aliyun", enabled: true)
      b = described_class.for_provider("turnstile")
      b.activate!
      expect(a.reload.enabled).to eq(false)
      expect(b.reload.enabled).to eq(true)
    end

    it "leaves the row as the sole enabled row when activating it directly" do
      s = described_class.for_provider("aliyun")
      s.activate!
      expect(s.reload.enabled).to eq(true)
    end

    it "retries once on a RecordNotUnique race and succeeds" do
      s = described_class.for_provider("aliyun")
      call_count = 0
      allow(s).to receive(:update!) do
        call_count += 1
        raise ActiveRecord::RecordNotUnique, "boom" if call_count == 1

        s.update_column(:enabled, true)
      end
      expect { s.activate! }.not_to raise_error
      expect(call_count).to eq(2)
    end

    it "re-raises after a second consecutive RecordNotUnique" do
      s = described_class.for_provider("aliyun")
      allow(s).to receive(:update!).and_raise(ActiveRecord::RecordNotUnique, "boom")
      expect { s.activate! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "#deactivate! turns the row off" do
      s = create(:captcha_provider_settings, enabled: true)
      s.deactivate!
      expect(s.reload.enabled).to eq(false)
    end
  end

  describe "#provider_class" do
    it "resolves the registered provider class" do
      s = described_class.for_provider("aliyun")
      expect(s.provider_class).to eq(Captcha::Providers::Aliyun)
    end
  end
end
