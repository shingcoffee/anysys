# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::NavigationOrder do
  it "maps known modules to hub sections and anything else to :other" do
    expect(described_class.section_for("payment")).to eq(:communication)
    expect(described_class.section_for(:website)).to eq(:records)
    expect(described_class.section_for("future")).to eq(:other)
  end

  it "groups items by section in section order, keeping each item's order and skipping empty sections" do
    items = %w[future captcha email authentication sms]

    expect(described_class.by_section(items, &:itself)).to eq([
      [:records, %w[authentication]],
      [:communication, %w[email sms]],
      [:growth, %w[captcha]],
      [:other, %w[future]]
    ])
  end

  it "translates section labels at call time" do
    expect(described_class.section_label(:growth)).to eq("Growth & protection")
    expect(I18n.with_locale(:"zh-CN") { described_class.section_label(:growth) }).to eq("增长与安全")
  end
end
