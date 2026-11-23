# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::StyleTriggerComponent, type: :component do
  it "renders a disclosure button for its panel" do
    render_inline(described_class.new(panel_id: "website-style-sec_1-headline", label: "Headline"))

    label = I18n.t("website.admin.pages.style.trigger", target: "Headline")
    button = page.find("button[data-style-trigger]")
    expect(button["data-action"]).to eq("click->website-builder#toggleStyle")
    expect(button["aria-controls"]).to eq("website-style-sec_1-headline")
    expect(button["aria-expanded"]).to eq("false")
    expect(button["aria-label"]).to eq(label)
    expect(button["title"]).to eq(label)
    expect(button["data-edited"]).to be_nil
  end

  it "has one always-visible size for every element" do
    classes = %w[Section Headline Buttons].map do |label|
      render_inline(described_class.new(panel_id: "p", label: label))
      page.find("button[data-style-trigger]")[:class].split
    end

    expect(classes.uniq.size).to eq(1)
    expect(classes.first).to include("size-7", "pointer-coarse:size-9")
    expect(classes.first.grep(/opacity/)).to be_empty
  end

  it "reveals on its design group's hover or focus with a mouse, keeping edited and open triggers shown" do
    render_inline(described_class.new(panel_id: "p", label: "Headline", reveal: true))
    revealed = page.find("button[data-style-trigger]")[:class].split
    render_inline(described_class.new(panel_id: "p", label: "Headline"))
    plain = page.find("button[data-style-trigger]")[:class].split

    expect(revealed - plain).to contain_exactly(
      "pointer-fine:opacity-0", "group-hover/design:opacity-100", "group-focus-within/design:opacity-100",
      "focus-visible:opacity-100", "aria-expanded:opacity-100", "data-[edited]:opacity-100"
    )
    expect(plain - revealed).to be_empty
  end

  it "flags edited elements with an accent dot" do
    render_inline(described_class.new(panel_id: "p", label: "Headline", edited: true))

    expect(page).to have_css("button[data-style-trigger][data-edited]")
    expect(page).to have_css("button span.group-data-\\[edited\\]\\/style-trigger\\:block", visible: :all)
  end
end
