# frozen_string_literal: true

require "rails_helper"

RSpec.describe TopbarComponent, type: :component do
  let(:customer) { create(:customer, id: 12345678, name: "ACME Industries") }
  let(:user) do
    Authentication::User.new(customer_id: customer.id, email: "u@t.io",
                              first_name: "Ada", last_name: "Lovelace")
  end

  before { render_inline described_class.new(customer: customer, user: user) }

  it "renders the Sapphire brand logo linking to the dashboard" do
    # /admin/ has no route (404); the brand logo must land on the dashboard.
    expect(page).to have_link(href: "/#{customer.id}/admin/dashboard")
    expect(page).to have_css(
      %(a[aria-label="Sapphire — Dashboard"][href="/#{customer.id}/admin/dashboard"] svg)
    )
    brand_link = page.find("header a[href='/#{customer.id}/admin/dashboard']")
    expect(brand_link).to have_css("svg[aria-label='Sapphire']")
    expect(brand_link).not_to have_css("span")
    expect(brand_link.text).to be_blank
    expect(page).not_to have_css("header span[title='ACME Industries']")
  end

  it "renders the inline search in the middle region" do
    expect(page.native.to_s).to match(/data-controller=["'][^"']*inline-search/)
  end

  it "renders help and user menu in the right region" do
    html = page.native.to_s
    expect(html).to match(/data-controller=["'][^"']*help-menu/)
    expect(html).to match(/data-controller=["'][^"']*user-menu/)
  end

  it "renders notifications button" do
    expect(page).to have_css('button[aria-label="Notifications"]')
  end

  it "does NOT render a workspace switcher" do
    expect(page.native.to_s).not_to match(/dashboard-workspace-switcher/)
  end
end
