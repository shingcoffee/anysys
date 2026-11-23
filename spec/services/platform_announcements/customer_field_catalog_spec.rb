# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAnnouncements::CustomerFieldCatalog do
  subject(:catalog) { described_class.new }

  it "exposes a whitelist of customer attributes" do
    expect(catalog.fields.map { |f| f[:field] }).to eq(
      %w[id name alias industry tier status locale contact phone address created_at updated_at]
    )
  end

  it "labels fields through i18n" do
    name = catalog.fields.find { |f| f[:field] == "name" }
    expect(name[:label]).to eq(I18n.t("maint_platform.announcements.fields.name"))
  end

  it "treats enum columns as string equals/not_equals without contains" do
    tier = catalog.fields.find { |f| f[:field] == "tier" }
    expect(tier[:type]).to eq(:string)
    expect(tier[:enum]).to be true
    expect(tier[:operators]).to eq(%w[equals not_equals is_blank is_present])
  end

  it "resolves a known field and rejects an unknown identifier" do
    expect(catalog.resolve("name")).to include(column: "name", type: :string, association: nil)
    expect(catalog.resolve("encrypted_password")).to be_nil
    expect(catalog.resolve("role")).to be_nil
  end
end
