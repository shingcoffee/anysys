# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Activities::Verify do
  let!(:settings) { create(:captcha_provider_settings) } # aliyun, enabled: true, fully configured

  around do |example|
    prior = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = prior
  end

  def context(verify_param: "{}", **opts)
    Captcha::VerificationContext.new(verify_param: verify_param, action: :page_submit, **opts)
  end

  def stub_provider(outcome:, http_status: 200, raw: {}, score: nil, hostname: nil)
    allow(Captcha::Providers::Aliyun).to receive(:verify)
      .and_return(outcome: outcome, http_status: http_status, raw: raw, score: score, hostname: hostname)
  end

  describe "no active provider (:disabled)" do
    it "returns :disabled without touching the provider when no row is enabled" do
      settings.deactivate!
      expect(Captcha::Providers::Aliyun).not_to receive(:verify)
      result = described_class.call(context: context)
      expect(result.outcome).to eq(:disabled)
      expect(result.disabled?).to eq(true)
      expect(result.passed?).to eq(false)
      expect(result.blocked_hard?).to eq(false)
    end

    it "returns :disabled when the enabled row is not fully configured" do
      settings.update!(access_key_id: nil, access_key_secret: nil)
      settings.write_config(scene_id: nil)
      settings.save!
      result = described_class.call(context: context)
      expect(result.outcome).to eq(:disabled)
    end
  end

  describe "blank token (:invalid)" do
    it "returns :invalid without calling the provider" do
      expect(Captcha::Providers::Aliyun).not_to receive(:verify)
      result = described_class.call(context: context(verify_param: ""))
      expect(result.outcome).to eq(:invalid)
      expect(result.blocked_hard?).to eq(true)
    end
  end

  describe "replay protection" do
    it "returns :replayed when the token digest was already consumed by a success within the window" do
      ctx = context(verify_param: "same-token")
      stub_provider(outcome: :success)
      described_class.call(context: ctx)

      stub_provider(outcome: :success) # would succeed again if replay weren't blocked
      result = described_class.call(context: context(verify_param: "same-token"))
      expect(result.outcome).to eq(:replayed)
      expect(result.blocked_hard?).to eq(true)
    end

    it "does not treat a merely-failed prior attempt as a consumed token" do
      ctx = context(verify_param: "retry-token")
      stub_provider(outcome: :invalid)
      described_class.call(context: ctx)

      stub_provider(outcome: :success)
      result = described_class.call(context: context(verify_param: "retry-token"))
      expect(result.outcome).to eq(:success)
    end

    it "reclassifies a concurrent duplicate success as :replayed" do
      ctx = context(verify_param: "race-token")
      stub_provider(outcome: :success)
      allow(Captcha::TokenReplay).to receive(:consumed?).and_return(false)
      allow(Captcha::TokenReplay).to receive(:consume!).and_return(false)

      result = described_class.call(context: ctx)
      expect(result.outcome).to eq(:replayed)
    end
  end

  describe "successful verification" do
    it "maps :success" do
      stub_provider(outcome: :success, http_status: 200)
      result = described_class.call(context: context)
      expect(result.outcome).to eq(:success)
      expect(result.passed?).to eq(true)
    end
  end

  %i[invalid unreachable configuration_error].each do |outcome|
    it "passes through :#{outcome} from the provider" do
      stub_provider(outcome: outcome)
      result = described_class.call(context: context)
      expect(result.outcome).to eq(outcome)
    end
  end

  describe "#fail_policy" do
    it "carries the active provider's resolved fail policy" do
      settings.update!(fail_policy: "closed")
      stub_provider(outcome: :unreachable)
      expect(described_class.call(context: context).fail_policy).to eq("closed")
    end

    it "is nil when no provider is active (:disabled)" do
      settings.deactivate!
      expect(described_class.call(context: context).fail_policy).to be_nil
    end
  end

  describe "score-threshold downgrade (score-based provider)" do
    let(:score_settings) { create(:captcha_provider_settings, provider: "turnstile", score_threshold: 0.5) }

    before do
      # Ensure only score_settings is the active/enabled row.
      settings.deactivate!
      score_settings.activate!
      allow(Captcha::ProviderSettings).to receive(:active).and_return(score_settings)
      allow(score_settings).to receive(:score_based?).and_return(true)
    end

    it "downgrades a passing outcome below the threshold to :invalid" do
      allow(Captcha::Providers::Turnstile).to receive(:verify)
        .and_return(outcome: :success, http_status: 200, raw: {}, score: 0.3)
      result = described_class.call(context: context)
      expect(result.outcome).to eq(:invalid)
    end

    it "keeps a passing outcome at/above the threshold as :success" do
      allow(Captcha::Providers::Turnstile).to receive(:verify)
        .and_return(outcome: :success, http_status: 200, raw: {}, score: 0.9)
      result = described_class.call(context: context)
      expect(result.outcome).to eq(:success)
      expect(result.score).to eq(0.9)
    end

    it "does not downgrade a non-success outcome even when score-based" do
      allow(Captcha::Providers::Turnstile).to receive(:verify)
        .and_return(outcome: :invalid, http_status: 200, raw: {}, score: 0.1)
      result = described_class.call(context: context)
      expect(result.outcome).to eq(:invalid)
    end

    it "does not downgrade when no threshold is configured" do
      allow(score_settings).to receive(:score_threshold).and_return(nil)
      allow(Captcha::Providers::Turnstile).to receive(:verify)
        .and_return(outcome: :success, http_status: 200, raw: {}, score: 0.01)
      result = described_class.call(context: context)
      expect(result.outcome).to eq(:success)
    end

    it "downgrades to :invalid when a threshold is configured but the provider result carries no score" do
      allow(Captcha::Providers::Turnstile).to receive(:verify)
        .and_return(outcome: :success, http_status: 200, raw: {}, score: nil)
      result = described_class.call(context: context)
      expect(result.outcome).to eq(:invalid)
    end
  end

  it "does not apply the score threshold for a binary (non-score-based) provider" do
    settings.update!(score_threshold: 0.9)
    stub_provider(outcome: :success, score: nil)
    result = described_class.call(context: context)
    expect(result.outcome).to eq(:success)
  end

  describe "notification emission" do
    it "emits an ActiveSupport::Notifications 'captcha.verify' event with duration, outcome, http_status, score, provider" do
      stub_provider(outcome: :success, http_status: 200, score: nil)
      events = []
      ActiveSupport::Notifications.subscribed(->(*args) { events << ActiveSupport::Notifications::Event.new(*args) },
                                              "captcha.verify") do
        described_class.call(context: context)
      end
      expect(events.size).to eq(1)
      payload = events.first.payload
      expect(payload[:outcome]).to eq(:success)
      expect(payload[:http_status]).to eq(200)
      expect(payload[:provider]).to eq("aliyun")
      expect(payload[:duration]).to be_a(Numeric)
    end

    it "does not emit a notification when short-circuited to :disabled or :invalid" do
      events = []
      subscriber = ->(*args) { events << args }
      ActiveSupport::Notifications.subscribed(subscriber, "captcha.verify") do
        described_class.call(context: context(verify_param: ""))
        settings.deactivate!
        described_class.call(context: context)
      end
      expect(events).to be_empty
    end
  end
end
