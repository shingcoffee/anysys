# frozen_string_literal: true

require "rails_helper"

RSpec.describe SectionNavComponent, type: :component do
  let(:two_tabs) do
    [
      { id: :overview, label: "Overview", path: "/overview", active: true },
      { id: :developer, label: "Developer", path: "/developer", active: false }
    ]
  end

  it "renders nothing with fewer than two tabs" do
    render_inline(described_class.new(label: "Sections", tabs: [{ id: :only, label: "Only", path: "/only" }]))

    expect(page).not_to have_css("nav")
  end

  it "renders nothing with an empty tab list" do
    render_inline(described_class.new(label: "Sections", tabs: []))

    expect(page).not_to have_css("nav")
  end

  it "marks the active tab with aria-current=page and emits data-section-nav-tab" do
    render_inline(described_class.new(label: "Module sections", tabs: two_tabs))

    expect(page).to have_css("nav[aria-label='Module sections']")
    expect(page).to have_css("a[role='listitem'][data-section-nav-tab='overview'][aria-current='page']", text: "Overview")
    expect(page).to have_css("a[role='listitem'][data-section-nav-tab='developer']")
    expect(page).not_to have_css("a[data-section-nav-tab='developer'][aria-current='page']")
    expect(page).to have_link("Overview", href: "/overview")
    expect(page).to have_link("Developer", href: "/developer")
  end

  it "renders the optional icon when icon_path is present" do
    tabs = [
      { id: :overview, label: "Overview", path: "/overview", active: true, icon_path: "M12 4v16m8-8H4" },
      { id: :developer, label: "Developer", path: "/developer", active: false }
    ]
    render_inline(described_class.new(label: "Sections", tabs: tabs))

    expect(page).to have_css("a[data-section-nav-tab='overview'] svg path[d='M12 4v16m8-8H4']")
    expect(page).not_to have_css("a[data-section-nav-tab='developer'] svg")
  end

  it "renders an optional count badge, accented on the active tab and omitted when absent" do
    tabs = [
      { id: :forms, label: "Forms", path: "/forms", active: true, count: 1200 },
      { id: :entries, label: "Entries", path: "/entries", active: false, count: 0 },
      { id: :other, label: "Other", path: "/other", active: false }
    ]
    render_inline(described_class.new(label: "Sections", tabs: tabs))

    active = page.find("a[data-section-nav-tab='forms'] [data-role='tab-count']")
    expect(active.text).to eq("1,200")
    expect(active[:class]).to include("text-accent")
    idle = page.find("a[data-section-nav-tab='entries'] [data-role='tab-count']")
    expect(idle.text).to eq("0")
    expect(idle[:class]).to include("text-text-tertiary")
    expect(page).not_to have_css("a[data-section-nav-tab='other'] [data-role='tab-count']")
  end

  it "merges caller data attributes onto the nav" do
    render_inline(described_class.new(
      label: "Billing sections",
      tabs: two_tabs,
      data: { billing_nav: true }
    ))

    expect(page).to have_css("nav[data-billing-nav='true'][aria-label='Billing sections']")
  end
end
