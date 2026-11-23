# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::FieldHeaderComponent, type: :component do
  let(:design) do
    Websites::Admin::StylePanelComponent.new(section_id: "sec_1", label: "Headline", styles: {}, theme: nil,
                                             targets: Websites::SectionStyles.targets_for("hero_split").select { |t| t[:field] == "headline" })
  end

  it "renders only the label when there is no aside or design" do
    render_inline(described_class.new) { "Kicker" }

    row = page.find("[data-field-header]")
    expect(row).to have_text("Kicker")
    expect(row[:class].split).to include("min-h-7", "justify-between")
    expect(row).not_to have_css("button")
    expect(row.all(:xpath, "./div").size).to eq(1)
  end

  it "pins the Design trigger after the aside at the right edge" do
    render_inline(described_class.new(design: design)) do |header|
      header.with_aside { "<span data-aside>7</span>".html_safe }
      "Headline"
    end

    right = page.find("[data-field-header] > div:last-child")
    expect(right).to have_css("[data-aside] + button[data-style-trigger][aria-controls='#{design.panel_id}']")
    expect(right.find("button[data-style-trigger]")[:class].split).to include("pointer-fine:opacity-0", "group-hover/design:opacity-100")
  end
end
