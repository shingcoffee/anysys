# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::VerificationContext do
  describe "#initialize" do
    it "stringifies verify_param and blanks-to-nil the optional attributes" do
      ctx = described_class.new(verify_param: "tok", remoteip: "", user_agent: "", hostname: "", action: nil)
      expect(ctx.verify_param).to eq("tok")
      expect(ctx.remoteip).to be_nil
      expect(ctx.user_agent).to be_nil
      expect(ctx.hostname).to be_nil
      expect(ctx.action).to be_nil
    end

    it "coerces a nil verify_param to an empty string" do
      ctx = described_class.new(verify_param: nil)
      expect(ctx.verify_param).to eq("")
    end

    it "symbolizes the action" do
      ctx = described_class.new(verify_param: "tok", action: "page_submit")
      expect(ctx.action).to eq(:page_submit)
    end

    it "carries through remoteip, user_agent, and hostname when present" do
      ctx = described_class.new(verify_param: "tok", remoteip: "1.2.3.4", user_agent: "UA", hostname: "example.com")
      expect(ctx.remoteip).to eq("1.2.3.4")
      expect(ctx.user_agent).to eq("UA")
      expect(ctx.hostname).to eq("example.com")
    end
  end

  describe "#blank_token?" do
    it "is true for an empty string" do
      expect(described_class.new(verify_param: "").blank_token?).to eq(true)
    end

    it "is true for whitespace-only" do
      expect(described_class.new(verify_param: "   ").blank_token?).to eq(true)
    end

    it "is true when verify_param is nil" do
      expect(described_class.new(verify_param: nil).blank_token?).to eq(true)
    end

    it "is false for a non-blank token" do
      expect(described_class.new(verify_param: "tok").blank_token?).to eq(false)
    end
  end

  describe "#token_digest" do
    it "is the SHA256 hex digest of the raw verify_param" do
      ctx = described_class.new(verify_param: "abc")
      expect(ctx.token_digest).to eq(Digest::SHA256.hexdigest("abc"))
    end

    it "is deterministic for the same token" do
      a = described_class.new(verify_param: "same-token").token_digest
      b = described_class.new(verify_param: "same-token").token_digest
      expect(a).to eq(b)
    end

    it "differs across different tokens" do
      a = described_class.new(verify_param: "token-a").token_digest
      b = described_class.new(verify_param: "token-b").token_digest
      expect(a).not_to eq(b)
    end
  end

  describe "vendor context binding" do
    it "uses each interstitial SDK's real action convention" do
      ctx = described_class.new(verify_param: "tok", action: :access_challenge)
      expect(ctx.vendor_action(provider: "google_recaptcha_v3")).to eq("submit")
      expect(ctx.vendor_action(provider: "turnstile")).to eq("")
    end

    it "pins ordinary actions verbatim and leaves the connection probe unbound" do
      ctx = described_class.new(verify_param: "tok", action: :sign_in)
      expect(ctx.vendor_action(provider: "turnstile")).to eq("sign_in")
      probe = described_class.new(verify_param: "probe", action: :connection_test)
      expect(probe.vendor_action(provider: "google_recaptcha_v3")).to be_nil
    end

    it "requires host and action together when they are expected" do
      ctx = described_class.new(verify_param: "tok", hostname: "forms.example", action: :sign_in)
      expect(ctx.matches_vendor_context?({ "hostname" => "forms.example", "action" => "sign_in" }, provider: "turnstile")).to be(true)
      expect(ctx.matches_vendor_context?({ "hostname" => "foreign.example", "action" => "sign_in" }, provider: "turnstile")).to be(false)
      expect(ctx.matches_vendor_context?({ "hostname" => "forms.example" }, provider: "turnstile")).to be(false)
    end
  end
end
