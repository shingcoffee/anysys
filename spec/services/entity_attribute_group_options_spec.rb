# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityAttributeGroupOptions do
  it "exposes a non-empty ICONS map keyed by string slug" do
    expect(described_class::ICONS).to be_a(Hash)
    expect(described_class::ICONS).not_to be_empty
    expect(described_class::ICONS.keys).to all(be_a(String))
  end

  it "exposes a non-empty COLORS array of string tokens" do
    expect(described_class::COLORS).to be_an(Array)
    expect(described_class::COLORS).not_to be_empty
    expect(described_class::COLORS).to all(be_a(String))
  end

  it "exposes string defaults that appear in the catalogs" do
    expect(described_class::ICONS).to have_key(described_class::DEFAULT_ICON)
    expect(described_class::COLORS).to include(described_class::DEFAULT_COLOR)
  end

  it "freezes all catalog constants" do
    expect(described_class::ICONS).to be_frozen
    expect(described_class::COLORS).to be_frozen
  end
end
