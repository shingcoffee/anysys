# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::AudienceReachComponent, type: :component do
  def render_for(*traits)
    page = build_stubbed(:page, *traits)
    render_inline(described_class.new(page: page))
  end

  it "lists only Admin for admin visibility" do
    render_for
    expect(page).to have_text("Admin")
    expect(page).not_to have_text("Member")
    expect(page).not_to have_text("Public")
    expect(page).to have_css("span.rounded-full", count: 1)
    expect(page).not_to have_css(".badge")
  end

  it "lists Admin and Member for member visibility" do
    render_for(:for_member)
    expect(page).to have_text("Admin")
    expect(page).to have_text("Member")
    expect(page).not_to have_text("Public")
    expect(page).to have_css("span.rounded-full", count: 2)
  end

  it "lists Admin, Member, and Public for public visibility" do
    render_for(:for_member, :for_public)
    expect(page).to have_text("Admin")
    expect(page).to have_text("Member")
    expect(page).to have_text("Public")
    expect(page).to have_css("span.rounded-full", count: 3)
  end

  it "exposes an aria-label listing every visible audience" do
    render_for(:for_member, :for_public)
    expect(page).to have_css("[aria-label='Visible to Admin, Member, and Public']")
  end
end
