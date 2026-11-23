# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::NullSurfaceSetting do
  subject(:null) { described_class.new }

  it "returns the given default from enabled_or" do
    expect(null.enabled_or(true)).to be(true)
    expect(null.enabled_or(false)).to be(false)
  end

  it "returns the given default from label_or" do
    expect(null.label_or("Default Label")).to eq("Default Label")
  end

  it "returns the given default from icon_or" do
    expect(null.icon_or(:star)).to eq(:star)
  end

  it "returns the given default from subtitle_or" do
    expect(null.subtitle_or("A subtitle")).to eq("A subtitle")
  end

  it "returns the given default from empty_headline_or" do
    expect(null.empty_headline_or("No items")).to eq("No items")
  end

  it "returns the given default from empty_body_or" do
    expect(null.empty_body_or("Try adding one")).to eq("Try adding one")
  end

  it "returns the given default from per_page_or" do
    expect(null.per_page_or(25)).to eq(25)
  end

  it "returns the given default from position_or" do
    expect(null.position_or(1)).to eq(1)
  end

  it "returns nil from visible_column_keys" do
    expect(null.visible_column_keys).to be_nil
  end

  it "returns nil from visible_detail_row_keys" do
    expect(null.visible_detail_row_keys).to be_nil
  end

  it "returns nil from visible_section_keys" do
    expect(null.visible_section_keys).to be_nil
  end

  it "returns nil from row_action_or" do
    expect(null.row_action_or("Open")).to be_nil
  end
end
