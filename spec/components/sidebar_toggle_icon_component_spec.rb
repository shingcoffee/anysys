# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarToggleIconComponent, type: :component do
  it "points left while the sidebar is open" do
    render_inline(described_class.new(expanded: true))
    expect(page).to have_css("svg[aria-hidden='true'] path[d='m11 17-5-5 5-5']", visible: :all)
    expect(page).to have_css("svg path[d='m18 17-5-5 5-5']", visible: :all)
    expect(page).not_to have_css("svg path[d='m6 17 5-5-5-5']", visible: :all)
  end

  it "points right while the sidebar is an icon rail" do
    render_inline(described_class.new(expanded: false))
    expect(page).to have_css("svg path[d='m6 17 5-5-5-5']", visible: :all)
    expect(page).to have_css("svg path[d='m13 17 5-5-5-5']", visible: :all)
    expect(page).not_to have_css("svg path[d='m11 17-5-5 5-5']", visible: :all)
  end
end
