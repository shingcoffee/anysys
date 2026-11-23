# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PageHeaderComponent, type: :component do
  def render_header(**opts)
    render_inline(described_class.new(**opts))
  end

  it "renders a title and subtitle" do
    render_header(title: "Payments", subtitle: "Your account history")
    expect(page).to have_css("h1", text: "Payments")
    expect(page).to have_text("Your account history")
  end

  it "renders the title in the public site headline type" do
    render_header(title: "Payments")
    expect(page).to have_css("h1[data-member-title]")
    expect(page.find("h1")[:class]).to include("font-site-heading", "text-site-4xl")
  end

  it "renders an eyebrow link when given a hash" do
    render_header(
      title:   "Payment ABC",
      eyebrow: { label: "Back to payments", path: "/12345678/member/payments" }
    )
    expect(page).to have_link("Back to payments", href: "/12345678/member/payments")
  end

  it "renders a meta badge with the requested tone" do
    render_header(title: "X", meta: { label: "succeeded", tone: :success })
    expect(page).to have_css("span.badge.badge-success", text: "succeeded")
  end

  it "renders action links with the right variant class" do
    render_header(
      title:   "X",
      actions: [
        { label: "Edit",   path: "/edit",   variant: :primary },
        { label: "Cancel", path: "/cancel", variant: :ghost }
      ]
    )
    expect(page).to have_link("Edit", href: "/edit")
    expect(page.find_link("Edit")[:class]).to include("rounded-full", "bg-sky-600")
    expect(page.find_link("Cancel")[:class]).to include("rounded-full")
  end

  it "omits subtitle, eyebrow, meta, and actions when not given" do
    render_header(title: "Just a title")
    expect(page).to have_css("h1", text: "Just a title")
    expect(page).not_to have_css("span.badge")
    expect(page).not_to have_css("a")
  end
end
