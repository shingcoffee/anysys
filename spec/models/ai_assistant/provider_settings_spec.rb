# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ProviderSettings do
  before { AiAssistant::Providers::OpenaiWhisper }

  describe "JOBS" do
    it "names the two exclusive platform jobs" do
      expect(described_class::JOBS).to eq([ :transcribe, :generation ])
    end
  end

  describe ".active_for" do
    it "returns nil when no provider row exists" do
      expect(described_class.active_for(:transcribe)).to be_nil
      expect(described_class.active_for(:generation)).to be_nil
    end

    it "returns nil when the transcribe_active row exists but is not configured" do
      described_class.for_provider("openai_whisper").activate_for!(:transcribe)
      expect(described_class.active_for(:transcribe)).to be_nil
    end

    it "returns nil when a fully configured row exists but that job is not active" do
      create(:ai_assistant_provider_settings, transcribe_active: false, generation_active: false)
      expect(described_class.active_for(:transcribe)).to be_nil
      expect(described_class.active_for(:generation)).to be_nil
    end

    it "returns the row when it is both transcribe_active and configured" do
      settings = create(:ai_assistant_provider_settings, transcribe_active: true, generation_active: false)
      expect(described_class.active_for(:transcribe)).to eq(settings)
      expect(described_class.active_for(:generation)).to be_nil
    end

    it "returns the generation row independently of transcribe" do
      settings = create(:ai_assistant_provider_settings, transcribe_active: false, generation_active: true)
      expect(described_class.active_for(:generation)).to eq(settings)
      expect(described_class.active_for(:transcribe)).to be_nil
    end

    it "fails closed when the active row names a stale/unknown provider" do
      stale = described_class.new(provider: "gone", api_key: "x", transcribe_active: true)
      stale.save!(validate: false)
      expect(described_class.active_for(:transcribe)).to be_nil
    end

    it "raises ArgumentError for an unknown job" do
      expect { described_class.active_for(:translate) }.to raise_error(ArgumentError)
    end
  end

  describe "the at-most-one-assignee invariant" do
    it "clears every other transcribe_active row when activating transcribe" do
      whisper = create(:ai_assistant_provider_settings, provider: "openai_whisper",
                       transcribe_active: true, generation_active: false)
      aliyun = described_class.for_provider("aliyun")

      aliyun.activate_for!(:transcribe)

      expect(described_class.where(transcribe_active: true).pluck(:provider)).to eq([ "aliyun" ])
      expect(whisper.reload.transcribe_active).to eq(false)
    end

    it "does not clear a different job when activating generation" do
      whisper = create(:ai_assistant_provider_settings, provider: "openai_whisper",
                       transcribe_active: true, generation_active: false)
      aliyun = described_class.for_provider("aliyun")
      aliyun.update!(generation_active: false)

      whisper.activate_for!(:generation)

      expect(whisper.reload).to have_attributes(transcribe_active: true, generation_active: true)
      expect(aliyun.reload.generation_active).to eq(false)
    end

    it "is enforced by the transcribe partial unique index, not just by activate_for!" do
      create(:ai_assistant_provider_settings, provider: "openai_whisper",
             transcribe_active: true, generation_active: false)
      second = described_class.new(provider: "aliyun", api_key: "x", transcribe_active: true)

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "is enforced by the generation partial unique index" do
      create(:ai_assistant_provider_settings, provider: "openai_whisper",
             transcribe_active: false, generation_active: true)
      second = described_class.new(provider: "aliyun", api_key: "x", generation_active: true)

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe ".for_provider" do
    it "creates the row on first access" do
      expect { described_class.for_provider("openai_whisper") }.to change(described_class, :count).from(0).to(1)
    end

    it "returns the existing row on subsequent access" do
      first  = described_class.for_provider("openai_whisper")
      second = described_class.for_provider("openai_whisper")
      expect(first).to eq(second)
      expect(described_class.count).to eq(1)
    end

    it "is race-safe against a concurrent insert (RecordNotUnique retried as a find)" do
      allow(described_class).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)
      existing = create(:ai_assistant_provider_settings, provider: "openai_whisper")
      expect(described_class.for_provider("openai_whisper")).to eq(existing)
    end
  end

  describe "validations" do
    it "rejects a second row for the same provider" do
      described_class.for_provider("openai_whisper")
      duplicate = described_class.new(provider: "openai_whisper", api_key: "x")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:provider]).to be_present
    end

    it "rejects an unknown provider" do
      bad = described_class.new(provider: "nonexistent", api_key: "x")
      expect(bad).not_to be_valid
      expect(bad.errors[:provider]).to be_present
    end
  end

  describe "credential encryption" do
    it "encrypts api_key at rest" do
      s = create(:ai_assistant_provider_settings, api_key: "SECRET")
      raw = ActiveRecord::Base.connection.execute(
        "SELECT api_key FROM ai_assistant_provider_settings WHERE id=#{s.id}"
      ).first
      stored = raw.is_a?(Hash) ? raw["api_key"] : raw[0]
      expect(stored).not_to include("SECRET")
      expect(s.reload.api_key).to eq("SECRET")
    end
  end

  describe "#configured?" do
    it "delegates to the provider class" do
      s = described_class.for_provider("openai_whisper")
      expect(s.configured?).to eq(false)
      s.update!(api_key: "sk-live")
      expect(s.reload.configured?).to eq(true)
    end

    it "degrades to false for a stale/unknown provider key instead of raising" do
      s = described_class.new(provider: "gone")
      s.save!(validate: false)
      expect(s.configured?).to eq(false)
    end
  end

  describe "#config_value / #write_config" do
    it "round-trips JSON config keys" do
      s = described_class.for_provider("openai_whisper")
      s.write_config(model: "whisper-1")
      s.save!
      expect(s.reload.config_value(:model)).to eq("whisper-1")
      expect(s.config_value(:missing, "fallback")).to eq("fallback")
    end

    it "merges rather than replaces existing keys" do
      s = described_class.for_provider("openai_whisper")
      s.write_config(model: "whisper-1", organization: "org-1")
      s.save!
      s.write_config(model: "whisper-1")
      s.save!
      expect(s.reload.config_value(:model)).to eq("whisper-1")
      expect(s.config_value(:organization)).to eq("org-1")
    end
  end

  describe "#activate_for! / #deactivate_for!" do
    it "leaves the row as the sole transcribe_active row when activating it directly" do
      s = described_class.for_provider("openai_whisper")
      s.activate_for!(:transcribe)
      expect(s.reload.transcribe_active).to eq(true)
    end

    it "retries once on a RecordNotUnique race and succeeds" do
      s = described_class.for_provider("openai_whisper")
      call_count = 0
      allow(s).to receive(:update!) do
        call_count += 1
        raise ActiveRecord::RecordNotUnique, "boom" if call_count == 1

        s.update_column(:transcribe_active, true)
      end
      expect { s.activate_for!(:transcribe) }.not_to raise_error
      expect(call_count).to eq(2)
    end

    it "re-raises after a second consecutive RecordNotUnique" do
      s = described_class.for_provider("openai_whisper")
      allow(s).to receive(:update!).and_raise(ActiveRecord::RecordNotUnique, "boom")
      expect { s.activate_for!(:transcribe) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "#deactivate_for! turns that job off" do
      s = create(:ai_assistant_provider_settings, transcribe_active: true, generation_active: true)
      s.deactivate_for!(:transcribe)
      expect(s.reload.transcribe_active).to eq(false)
      expect(s.generation_active).to eq(true)
    end

    it "raises ArgumentError for an unknown job" do
      s = described_class.for_provider("openai_whisper")
      expect { s.activate_for!(:translate) }.to raise_error(ArgumentError)
      expect { s.deactivate_for!(:translate) }.to raise_error(ArgumentError)
    end
  end

  describe "#provider_class" do
    it "resolves the registered provider class" do
      s = described_class.for_provider("openai_whisper")
      expect(s.provider_class).to eq(AiAssistant::Providers::OpenaiWhisper)
    end
  end
end
