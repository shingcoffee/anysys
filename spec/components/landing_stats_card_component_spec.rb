# frozen_string_literal: true

require "rails_helper"

RSpec.describe LandingStatsCardComponent, type: :component do
  it "renders a label and numeric value" do
    rendered = render_inline(described_class.new(label: "Entities", value: 7))
    expect(rendered.text).to include("Entities")
    expect(rendered.text).to include("7")
  end

  it "renders a sub-label when provided" do
    rendered = render_inline(described_class.new(label: "Pages", value: 5, sub_label: "2 published"))
    expect(rendered.text).to include("2 published")
  end

  it "renders a compact metric tile" do
    rendered = render_inline(described_class.new(label: "Users", value: 9, compact: true))
    expect(rendered.text).to include("Users")
    expect(rendered.text).to include("9")
    expect(rendered).to have_css(".text-lg")
    expect(rendered).not_to have_css(".stat-card")
  end
end
