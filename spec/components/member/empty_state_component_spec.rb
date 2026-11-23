# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::EmptyStateComponent, type: :component do
  def render_empty(headline: "None", body: "x", **opts)
    render_inline(described_class.new(headline: headline, body: body, **opts))
  end

  it "renders headline, body, and an icon container" do
    render_empty(headline: "No payments yet", body: "Will appear here.", icon: :credit_card)
    expect(page).to have_css("h2", text: "No payments yet")
    expect(page).to have_text("Will appear here.")
    expect(page).to have_css("[data-icon='credit_card']")
  end

  it "wraps in a centered site card" do
    render_empty(headline: "X", body: "y", icon: :sparkles)
    expect(page).to have_css("section[data-member-card].text-center.rounded-2xl")
  end

  it "renders an optional CTA when both label and path are provided" do
    render_empty(
      headline: "Empty",
      body: "Add one to get started.",
      icon: :credit_card,
      cta_label: "Add payment",
      cta_path: "/x/member/payments/new"
    )
    expect(page).to have_link("Add payment", href: "/x/member/payments/new")
  end

  it "omits the CTA when label or path is missing" do
    render_empty(headline: "Empty", body: "y", icon: :credit_card)
    expect(page).not_to have_css("a")
  end

  it "defaults to the plus icon" do
    render_empty(icon: :plus)
    expect(page).to have_css("svg path[d='M12 4v16m8-8H4']")
  end

  it "renders the document icon variant" do
    render_empty(icon: :document)
    expect(page).to have_css("svg path[d*='M9 12h6']")
  end

  it "renders the search icon variant" do
    render_empty(icon: :search)
    expect(page).to have_css("svg path[d*='M21 21l-6-6']")
  end

  it "renders the inbox icon variant" do
    render_empty(icon: :inbox)
    expect(page).to have_css("svg path[d*='M20 13V6']")
  end
end
