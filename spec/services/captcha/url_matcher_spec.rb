# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::UrlMatcher do
  it "matches :customer_id as a single path segment" do
    expect(described_class.template_match?("/:customer_id/page/abc", "/42/page/abc")).to eq(true)
    expect(described_class.template_match?("/:customer_id/page/abc", "/42/extra/page/abc")).to eq(false)
  end

  it "does not challenge unmatched admin, member, health, or webhook paths" do
    expect(described_class.match("/81721200/admin/pages")).to be_nil
    expect(described_class.match("/81721200/member/home")).to be_nil
    expect(described_class.match("/up")).to be_nil
    expect(described_class.match("/payments/webhooks/alipay")).to be_nil
  end

  it "hard-skips only the challenge path so the interstitial cannot loop" do
    expect(described_class.skip?("/captcha/challenge")).to eq(true)
    expect(described_class.skip?("/captcha/challenge/extra")).to eq(true)
    expect(described_class.skip?("/up")).to eq(false)
    expect(described_class.skip?("/81721200/admin/pages")).to eq(false)
    expect(described_class.skip?("/payments/webhooks/alipay")).to eq(false)
    expect(described_class.match("/captcha/challenge")).to be_nil
  end

  it "returns the default 100/5min rule for sign-in" do
    rule = described_class.match("/auth/sign_in")
    expect(rule).to be_present
    expect(rule.limit_count).to eq(100)
    expect(rule.period_seconds).to eq(300)
    expect(rule.fail_closed).to eq(true)
    expect(rule.skipped).to eq(false)
    expect(rule.pattern).to eq("/auth/sign_in")
  end

  %w[html json xml made_up].each do |format|
    it "applies the sign-in rule to Rails' optional .#{format} suffix" do
      rule = described_class.match("/auth/sign_in.#{format}")
      expect(rule).to have_attributes(pattern: "/auth/sign_in", fail_closed: true)
    end
  end

  it "keeps an exact auth rule fail-closed even when it has no surface key" do
    create(:captcha_url_throttle, match_kind: "exact", url_pattern: "/auth/sign_in", every_hit: true)
    Captcha::ThrottleRegistry.bust!
    expect(described_class.match("/auth/sign_in.html").fail_closed).to be(true)
  end

  it "returns a skipped rule for a stored skip so the default rate cannot apply" do
    create(:captcha_url_throttle,
           match_kind: "template",
           url_pattern: "/auth/sign_in",
           surface_key: "authentication/sessions",
           skipped: true)
    Captcha::ThrottleRegistry.bust!

    rule = described_class.match("/auth/sign_in")
    expect(rule).to be_present
    expect(rule.skipped).to eq(true)
    expect(rule.pattern).to eq("/auth/sign_in")
  end

  it "matches sign-in-link aliases to the sessions surface" do
    rule = described_class.match("/auth/sign_in_link")
    expect(rule.surface_key).to eq("authentication/sessions")
  end

  it "prefers a stored exact URL over the default" do
    create(:captcha_url_throttle,
           match_kind: "exact",
           url_pattern: "/42/page/11111111-1111-1111-1111-111111111111",
           limit_count: 5,
           period_seconds: 60)
    Captcha::ThrottleRegistry.bust!

    rule = described_class.match("/42/page/11111111-1111-1111-1111-111111111111")
    expect(rule.limit_count).to eq(5)
    expect(rule.period_seconds).to eq(60)
  end
end
