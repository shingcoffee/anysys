# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Activities::UpdateUrlThrottle do
  it "persists a named preset and busts the registry cache" do
    result = described_class.call(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      preset: Captcha::ThrottlePresets::PRESET_5_PER_1MIN,
      surface_key: "authentication/sessions"
    )

    expect(result.success?).to eq(true)
    row = Captcha::UrlThrottle.find_by!(url_pattern: "/auth/sign_in")
    expect(row.limit_count).to eq(5)
    expect(row.period_seconds).to eq(60)
    expect(row.every_hit).to eq(false)
    expect(row.skipped).to eq(false)
  end

  it "rejects custom values outside bounds" do
    result = described_class.call(
      match_kind: "exact",
      url_pattern: "/1/page/x",
      preset: Captcha::ThrottlePresets::PRESET_CUSTOM,
      limit_count: 0,
      period_minutes: 1
    )
    expect(result.success?).to eq(false)
  end

  it "skips a URL, keeps the last rate, and does not challenge after cache bust" do
    described_class.call(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      preset: Captcha::ThrottlePresets::PRESET_5_PER_1MIN,
      surface_key: "authentication/sessions"
    )

    result = described_class.call(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      preset: Captcha::ThrottlePresets::PRESET_5_PER_1MIN,
      surface_key: "authentication/sessions",
      skipped: true
    )

    expect(result.success?).to eq(true)
    row = Captcha::UrlThrottle.find_by!(url_pattern: "/auth/sign_in")
    expect(row.skipped).to eq(true)
    expect(row.limit_count).to eq(5)
    expect(row.period_seconds).to eq(60)
    expect(Captcha::UrlMatcher.match("/auth/sign_in").skipped).to eq(true)
  end

  it "creates a skipped row at the default rate when the identity has no throttle yet" do
    result = described_class.call(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      preset: Captcha::ThrottlePresets::PRESET_100_PER_5MIN,
      surface_key: "authentication/sessions",
      skipped: true
    )

    expect(result.success?).to eq(true)
    row = Captcha::UrlThrottle.find_by!(url_pattern: "/auth/sign_in")
    expect(row.skipped).to eq(true)
    expect(row.limit_count).to eq(100)
    expect(row.period_seconds).to eq(300)
  end

  it "moves a skipped URL back to protected and restores the stored rate" do
    described_class.call(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      preset: Captcha::ThrottlePresets::PRESET_20_PER_1MIN,
      surface_key: "authentication/sessions",
      skipped: true
    )

    result = described_class.call(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      preset: Captcha::ThrottlePresets::PRESET_20_PER_1MIN,
      surface_key: "authentication/sessions",
      skipped: false
    )

    expect(result.success?).to eq(true)
    row = Captcha::UrlThrottle.find_by!(url_pattern: "/auth/sign_in")
    expect(row.skipped).to eq(false)
    expect(row.limit_count).to eq(20)
    expect(row.period_seconds).to eq(60)
  end

  it "recovers when a concurrent first-save hits the unique index" do
    described_class.call(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      preset: Captcha::ThrottlePresets::PRESET_5_PER_1MIN,
      surface_key: "authentication/sessions"
    )
    allow(Captcha::UrlThrottle).to receive(:find_or_initialize_by).and_return(
      Captcha::UrlThrottle.new(match_kind: "template", url_pattern: "/auth/sign_in")
    )

    result = described_class.call(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      preset: Captcha::ThrottlePresets::PRESET_20_PER_1MIN,
      surface_key: "authentication/sessions"
    )

    expect(result.success?).to eq(true)
    expect(Captcha::UrlThrottle.where(url_pattern: "/auth/sign_in").count).to eq(1)
    expect(Captcha::UrlThrottle.find_by!(url_pattern: "/auth/sign_in").limit_count).to eq(20)
  end
end
