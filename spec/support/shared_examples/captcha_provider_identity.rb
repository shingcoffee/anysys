# frozen_string_literal: true

# Class-level identity shared by every captcha vendor spec.
# Host keeps vendor-specific `.configured?` / `#verify` / `.widget` coverage.
#
#   it_behaves_like "a captcha provider identity",
#     key: "aliyun", display_name: "Aliyun Captcha", score_based: false
RSpec.shared_examples "a captcha provider identity" do |key:, display_name:, score_based: false|
  it "declares the stable key" do
    expect(described_class.key).to eq(key)
  end

  it "declares the English fallback display name" do
    expect(described_class.default_display_name).to eq(display_name)
  end

  it "declares score_based?" do
    expect(described_class.score_based?).to eq(score_based)
  end
end
