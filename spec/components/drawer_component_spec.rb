# frozen_string_literal: true

require "rails_helper"

RSpec.describe DrawerComponent, type: :component do
  let(:customer) { create(:customer, name: "T") }
  let(:items)    { MenuRegistry.for(double(owner?: false, admin_or_owner?: false)) }
  let(:tree)     { SidebarTree.new }

  def render_drawer(current_menu_item:, current_path:)
    render_inline described_class.new(
      customer: customer, tree: tree, menu_items: items,
      current_menu_item: current_menu_item, current_path: current_path
    )
  end

  it "renders a section per menu item" do
    render_drawer(current_menu_item: :entities, current_path: "/")
    items.each do |it|
      expect(page).to have_text(it.label)
    end
  end

  it "renders the current menu_item section expanded" do
    render_drawer(current_menu_item: :entities, current_path: "/")
    current_section = page.find("details[data-menu-item='entities']")
    expect(current_section["open"]).to be_truthy
  end

  it "hides Maintenance for customer admins while showing icon-led destinations" do
    admin_items = MenuRegistry.for(double(admin_or_owner?: true, platform_owner?: false), customer: customer)
    render_inline described_class.new(customer: customer, tree: tree, menu_items: admin_items,
                                      current_menu_item: :home, current_path: "/#{customer.id}/admin/dashboard")

    expect(page).not_to have_css("[data-menu-item='maintenance']")
    expect(page).to have_css("a[data-menu-item='home'] svg[aria-hidden='true']")
  end

  it "has no workspace/zone pill" do
    render_drawer(current_menu_item: :home, current_path: "/")
    expect(page.native.to_s).not_to match(/data-zone-pill/)
  end

  it "shows only the unframed mark in the drawer header" do
    render_drawer(current_menu_item: :home, current_path: "/")

    header = page.find("aside > div:first-child")
    expect(header).to have_css("svg[aria-label='Sapphire']")
    expect(header).not_to have_css("span")
    expect(header).not_to have_text("Sapphire")
  end

  it "renders sidebar nodes inside each menu item" do
    tree.add(SidebarNode.new(key: "e.1", label: "Account", menu_item: :entities, path: "/x"))
    render_drawer(current_menu_item: :entities, current_path: "/x")
    expect(page).to have_link("Account", href: "/x")
  end

  it "lists Domains nodes in the drawer without a search field" do
    tree.add(SidebarNode.new(key: "e.1", label: "Account", menu_item: :entities, path: "/x"))
    render_drawer(current_menu_item: :entities, current_path: "/x")
    section = page.find("details[data-menu-item='entities']")
    expect(section).not_to have_css("input#drawer-entities-search")
    expect(section).not_to have_css("input[type='search']")
    expect(section).to have_css("a[href='/x'][data-action='click->drawer#close']")
  end

  it "adds a native modal settings sheet with the shared searchable destinations" do
    tree.add(SidebarNode.new(key: "settings.member", label: "Member portal", menu_item: :settings, path: "/settings/member"))
    render_drawer(current_menu_item: :settings, current_path: "/settings/member")
    expect(page).to have_css("dialog#settings-navigation-dialog[aria-label='Settings menu']", visible: :all)
    expect(page).to have_css("dialog button[command='close'][commandfor='settings-navigation-dialog']", visible: :all)
    expect(page).to have_css("dialog input#dialog-settings-search", visible: :all)
    expect(page).to have_css("dialog a[aria-current='page'][href='/settings/member']", visible: :all)
  end

  it "does not add a settings dialog on other admin surfaces" do
    render_drawer(current_menu_item: :entities, current_path: "/")
    expect(page).not_to have_css("dialog", visible: :all)
  end

  it "renders a mobile Communication disclosure with the enabled destinations" do
    %w[authentication email sms].each { |key| enable_module!(key, customer) }
    visible_items = MenuRegistry.for(double(admin_or_owner?: true), customer: customer)

    render_inline described_class.new(customer: customer, tree: tree, menu_items: visible_items,
                                      current_menu_item: :modules,
                                      current_path: "/#{customer.id}/admin/modules/emails/send_activities")

    expect(page).to have_link("Users", href: "/#{customer.id}/admin/modules/authentication/users")
    expect(page).not_to have_link("Payments")
    expect(page).to have_css("details[data-menu-item='communication'][open] summary", text: "Communication")
    expect(page).to have_css("details[data-menu-item='communication'] a", text: "Email")
    expect(page).to have_css("details[data-menu-item='communication'] a[aria-current='page']", text: "Email")
    expect(page).to have_css("details[data-menu-item='communication'] a", text: "SMS")
  end

  it "selects Website on mobile without changing module URLs" do
    enable_module!("website", customer)
    visible_items = MenuRegistry.for(double(admin_or_owner?: true), customer: customer)

    render_inline described_class.new(customer: customer, tree: tree, menu_items: visible_items,
                                       current_menu_item: :modules,
                                       current_path: "/#{customer.id}/admin/modules/website/pages/new")

    expect(page).not_to have_css("[data-menu-item='pages']")
    expect(page).to have_css("a[data-menu-item='website_pages'][href='/#{customer.id}/admin/modules/website'][aria-current='page']",
                             text: "Website")
  end
end
