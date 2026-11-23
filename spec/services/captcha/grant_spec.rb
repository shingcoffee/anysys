# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Grant do
  let(:rule) do
    Captcha::ThrottleRegistry::Rule.new(
      pattern: "/auth/sign_in",
      match_kind: "template",
      limit_count: 100,
      period_seconds: 300,
      every_hit: false,
      skipped: false,
      fail_closed: true,
      surface_key: "authentication/sessions",
      page_id: nil
    )
  end

  it "grants the remaining window, not a fresh full period" do
    described_class.mark_window(ip: "1.2.3.4", pattern: rule.pattern, period: 300)
    described_class.cache.write(
      "captcha:window:1.2.3.4:#{rule.pattern}",
      90.seconds.from_now.to_i,
      expires_in: 90
    )

    ttl = described_class.ttl_for(rule, ip: "1.2.3.4")
    expect(ttl).to be_within(2.seconds).of(90.seconds)
  end

  it "uses the 5-minute every-hit grant" do
    every = rule.with(every_hit: true, period_seconds: nil, limit_count: nil)
    expect(described_class.ttl_for(every, ip: "1.2.3.4")).to eq(Captcha::ThrottlePresets::EVERY_HIT_GRANT)
  end
end
