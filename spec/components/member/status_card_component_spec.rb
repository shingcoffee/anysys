# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::StatusCardComponent, type: :component do
  it "renders the label, value, and CTA link" do
    render_inline(described_class.new(
      label: "Profile", value: "Complete", icon: :user,
      cta_label: "Update profile", cta_path: "/123/member/profile"
    ))

    expect(page).to have_text("Profile")
    expect(page).to have_text("Complete")
    expect(page).to have_link("Update profile", href: "/123/member/profile")
  end

  it "renders an icon for the given symbol" do
    render_inline(described_class.new(
      label: "Security", value: "On", icon: :shield_check,
      cta_label: "Manage", cta_path: "/x"
    ))

    expect(page).to have_css("[data-icon='shield_check']")
  end
end
