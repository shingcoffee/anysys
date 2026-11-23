# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Modules::Authentication::UserCardHeaderComponent, type: :component do
  let(:icon) { "M4 6h16" }

  def render_header(**options)
    render_inline(described_class.new(heading_id: "user-42-devices-heading", title: "Trusted Devices",
                                      icon_path: icon, tile_class: "bg-violet-500 text-white", **options))
  end

  it "renders a decorative tinted tile and an h2 heading by default" do
    render_header

    expect(page).to have_css("header span.bg-violet-500.text-white[aria-hidden='true'] path[d='#{icon}']")
    expect(page).to have_css("h2#user-42-devices-heading", text: "Trusted Devices")
    expect(page).not_to have_css("p, header > span.tabular-nums")
    expect(page.find("header")[:class]).to include("border-b")
    expect(page).not_to have_css("summary, svg.group-open\\/section\\:rotate-180")
  end

  it "renders as a borderless summary with a rotating chevron when collapsible" do
    render_header(collapsible: true)

    summary = page.find("summary")
    expect(summary[:class]).to include("list-none", "cursor-pointer", "focus-visible:outline-accent", "[&::-webkit-details-marker]:hidden")
    expect(summary[:class]).not_to include("border-b")
    expect(summary).to have_css("h2#user-42-devices-heading", text: "Trusted Devices")
    expect(summary).to have_css("svg.group-open\\/section\\:rotate-180[aria-hidden='true']")
    expect(page).not_to have_css("header")
  end

  it "renders the optional description and trailing meta" do
    render_header(description: "Skip two-factor", meta: "2 devices", level: :h3)

    expect(page).to have_css("h3#user-42-devices-heading")
    expect(page).to have_css("p.text-text-muted", text: "Skip two-factor")
    expect(page).to have_css("span.tabular-nums", text: "2 devices")
  end

  it "falls back to h2 for an unsupported level and escapes authored text" do
    render_header(title: "<script>x()</script>", description: "<img src=x>", level: :h1)

    expect(page).to have_css("h2", text: "<script>x()</script>")
    expect(page).to have_text("<img src=x>")
    expect(page).not_to have_css("h1, script, img")
  end
end
