# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::UserMenuComponent, type: :component do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer, first_name: "Lin", last_name: "Vega") }

  def render_menu
    render_inline(described_class.new(customer: customer, user: user))
  end

  it "renders the user's initials inside the avatar trigger" do
    render_menu

    expect(page).to have_css("[data-component='member-user-menu']")
    expect(page).to have_text("LV")
  end

  it "renders a compact header trigger with the display name from the sm breakpoint" do
    render_menu

    trigger = page.find("button[data-user-menu-target='trigger']")
    expect(trigger[:class]).to include("rounded-full")
    expect(trigger[:class]).not_to include("w-full")
    expect(trigger["aria-haspopup"]).to eq("menu")
    expect(trigger["aria-expanded"]).to eq("false")
    expect(trigger["data-action"]).to eq("click->user-menu#toggle")

    name = trigger.find("span.truncate")
    expect(name.text).to eq(user.display_name)
    expect(name[:class]).to include("sm:inline")
  end

  it "opens the panel downward from the header" do
    render_menu

    panel = page.find("div[role='menu']", visible: :all)
    expect(panel[:class]).to include("top-full", "mt-2", "origin-top-right", "rounded-2xl")
    expect(panel[:class]).not_to include("bottom-full")
  end

  it "links to profile, security, and the sign-out destroy path" do
    render_menu

    expect(page).to have_link("Your profile", href: "/#{customer.id}/member/profile")
    expect(page).to have_link("Security",     href: "/#{customer.id}/member/security")
    expect(page).to have_css(
      "a[data-turbo-method='delete'][href='/auth/sign_out']",
      text: "Sign out"
    )
  end
end
