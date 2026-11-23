# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::RunLink do
  it "adds the run token and keeps the existing query" do
    expect(described_class.append("/1/page/abc?locale=en", "tok")).to eq("/1/page/abc?locale=en&run=tok")
  end

  it "adds the exact page for the admin entry surface" do
    page = instance_double(Page, id: 42)
    expect(described_class.append("/1/admin/entities/3/entries/new", "tok", page: page))
      .to eq("/1/admin/entities/3/entries/new?page=42&run=tok")
  end

  it "leaves the path alone without a token or page" do
    expect(described_class.append("/1/page/abc", nil)).to eq("/1/page/abc")
  end
end
