# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::Customers::ProfileComponent, type: :component do
  let(:customer) do
    build_stubbed(
      :customer,
      id: 39972103,
      name: "Northwind Traders",
      alias: "Northwind",
      contact: "Ada Lovelace",
      phone: "+1 555 0100",
      address: "1 Harbor Street\nLondon",
      industry: :technology,
      tier: :enterprise,
      locale: "zh-CN",
      domain: "northwind.example",
      status: :active,
      created_at: Time.zone.parse("2026-03-01 09:00"),
      updated_at: Time.zone.parse("2026-04-02 15:30")
    )
  end

  def render_profile(record = customer)
    render_inline(described_class.new(customer: record))
  end

  it "groups identity, contact, and account without a role" do
    render_profile

    expect(page).to have_css("h2", text: "Organization")
    expect(page).to have_css("h2", text: "Primary contact")
    expect(page).to have_css("h2", text: "Account")
    expect(page).to have_text("Northwind Traders")
    expect(page).to have_text("northwind.example")
    expect(page).to have_text("Northwind")
    expect(page).to have_text("Technology")
    expect(page).to have_text("简体中文")
    expect(page).to have_link("+1 555 0100", href: "tel:+15550100")
    expect(page).to have_text("1 Harbor Street")
    expect(page).to have_text("39972103")
    expect(page).to have_text("Enterprise")
    expect(page).to have_text("Active")
    expect(page).to have_no_text("Role")
    expect(page).to have_no_text("Owner")
    expect(page).to have_no_css("[role='status']")
  end

  it "labels blank optional fields and an unset language" do
    customer.alias = nil
    customer.contact = ""
    customer.phone = nil
    customer.address = nil
    customer.locale = nil
    customer.domain = nil
    render_profile

    expect(page).to have_text("Not set", count: 5)
    expect(page).to have_text("Follows the browser")
    expect(page).to have_no_link(href: /^tel:/)
  end

  it "explains an inactive account that can be restored" do
    customer.status = :inactive
    component = described_class.new(customer: customer)

    expect(component).to be_in_trash
    expect(component).not_to be_active
    expect(component.header_badges).to include(hash_including(label: "Inactive", variant: :default))

    render_inline(component)
    expect(page).to have_css("[role='status']", text: "This organization is in the trash")
    expect(page).to have_text("Inactive")
  end

  it "escapes the organization name" do
    customer.name = "Acme <script>alert(1)</script>"
    render_profile
    expect(page).to have_text("Acme <script>alert(1)</script>")
    expect(page).to have_no_css("script")
  end

  it "translates the profile in zh-CN" do
    I18n.with_locale(:"zh-CN") { render_profile }

    expect(page).to have_css("h2", text: "组织资料")
    expect(page).to have_css("h2", text: "主要联系人")
    expect(page).to have_css("h2", text: "账户")
    expect(page).to have_text("简体中文")
    expect(page).to have_no_text("Translation missing")
  end
end
