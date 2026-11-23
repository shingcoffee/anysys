# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TabsComponent, type: :component do
  it "renders tabs" do
    render_inline(described_class.new(tabs: [
      { label: "Tab 1", path: "/tab1", active: true },
      { label: "Tab 2", path: "/tab2", active: false }
    ]))

    expect(page).to have_css("nav[aria-label='Tabs']")
    expect(page).to have_css("nav.flex.gap-6")
    expect(page).to have_link("Tab 1", href: "/tab1")
    expect(page).to have_link("Tab 2", href: "/tab2")
    expect(page).to have_css("a[aria-current='page']", text: "Tab 1")
  end
end
