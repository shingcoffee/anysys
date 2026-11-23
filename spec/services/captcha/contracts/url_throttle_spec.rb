# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Contracts::UrlThrottle do
  def validate_with(**attrs)
    form = described_class.new(OpenStruct.new)
    form.validate(attrs)
    form
  end

  it "accepts a named preset" do
    form = validate_with(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      preset: "100_per_5min"
    )
    expect(form.errors).to be_empty
  end

  it "rejects an unknown match kind" do
    form = validate_with(match_kind: "glob", url_pattern: "/x", preset: "every_hit")
    expect(form.errors[:match_kind]).to be_present
  end

  it "requires custom bounds" do
    form = validate_with(
      match_kind: "exact",
      url_pattern: "/1/page/x",
      preset: "custom",
      limit_count: 0,
      period_minutes: 90
    )
    expect(form.errors[:limit_count]).to be_present
    expect(form.errors[:period_minutes]).to be_present
  end
end
