# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarRailComponent, type: :component do
  let(:tree) { SidebarTree.new }

  def render_rail(menu_item: :maintenance, path: "/m")
    render_inline described_class.new(tree: tree, menu_item: menu_item, current_path: path)
  end

  it "renders an icon link for the current destination and a monogram when there is no icon" do
    tree.add(SidebarNode.new(key: "maintenance.entities", label: "Entities", menu_item: :maintenance,
                             path: "/m/entities", icon: "M1 1"))
    tree.add(SidebarNode.new(key: "maintenance.notes", label: " 笔记", menu_item: :maintenance, path: "/m/notes"))

    render_rail(path: "/m/entities")

    current = page.find("a[aria-current='page']")
    expect(current["aria-label"]).to eq("Entities")
    expect(current["data-sidebar-rail-label"]).to eq("Entities")
    expect(current[:href]).to eq("/m/entities")
    expect(current).to have_css("svg path[d='M1 1']")
    expect(current[:class]).to include("bg-accent-subtle")

    notes = page.find("a[aria-label=' 笔记']")
    expect(notes).to have_text("笔")
    expect(notes[:class]).to include("text-text-muted")
    expect(notes["aria-current"]).to be_nil
  end

  it "keeps settings groups as one icon and uses a divider between ungrouped sections" do
    tree.add(SidebarNode.new(key: "settings.overview", label: "Overview", menu_item: :settings, path: "/s", icon: "M0 0"))
    tree.add(SidebarNode.new(key: "settings.section.billing", label: "Billing", menu_item: :settings, section_root: true, icon: "M9 9"))
    tree.add(SidebarNode.new(key: "settings.invoices", label: "Invoices", menu_item: :settings, path: "/s/invoices", icon: "M2 2"))
    tree.add(SidebarNode.new(key: "settings.section.trailing", label: "Trailing", menu_item: :settings, section_root: true))

    render_rail(menu_item: :settings, path: "/s/invoices")

    expect(page).to have_css("a[aria-label='Overview'][href='/s']")
    billing = page.find("button[aria-label='Billing']")
    expect(billing["data-action"]).to include("sidebar-collapsible#expandGroup")
    expect(billing[:class]).to include("bg-accent-subtle")
    expect(billing).to have_css("svg path[d='M9 9']")
    expect(page).not_to have_css("a[aria-label='Invoices']")
    expect(page).not_to have_css("[aria-label='Trailing']")

    maintenance = SidebarTree.new
    maintenance.add(SidebarNode.new(key: "maintenance.entities", label: "Entities", menu_item: :maintenance, path: "/m/entities", icon: "M1 1"))
    maintenance.add(SidebarNode.new(key: "maintenance.section.platform", label: "Platform", menu_item: :maintenance, section_root: true))
    maintenance.add(SidebarNode.new(key: "maintenance.customers", label: "Customers", menu_item: :maintenance, path: "/m/customers", icon: "M2 2"))
    maintenance.add(SidebarNode.new(key: "maintenance.section.trailing", label: "Trailing", menu_item: :maintenance, section_root: true))
    render_inline described_class.new(tree: maintenance, menu_item: :maintenance, current_path: "/m/customers")

    expect(page).to have_css("nav[aria-label='Maintenance'] div.bg-border-subtle", count: 1)
    expect(page).to have_css("a[aria-label='Customers'][aria-current='page']")
    expect(page).not_to have_css("[aria-label='Platform'], [aria-label='Trailing']")
  end

  it "keeps a group as one icon that opens the full sidebar and highlights an active child" do
    tree.add(SidebarNode.new(
      key: "modules.email", label: "Email", menu_item: :modules, icon: "M3 3", section_root: true,
      children: [SidebarNode.new(key: "modules.email.messages", label: "Messages", menu_item: :modules,
                                 path: "/modules/email/messages", icon: "M4 4")]
    ))

    render_rail(menu_item: :modules, path: "/modules/email/messages")

    button = page.find("button[aria-label='Email']")
    expect(button["data-action"]).to include("sidebar-collapsible#expandGroup")
    expect(button["data-sidebar-rail-label"]).to eq("Email")
    expect(button[:class]).to include("bg-accent-subtle")
    expect(page).not_to have_css("a", text: "Messages")
    expect(page).to have_css("nav[aria-label='Modules']")
  end

  it "divides category headings without rendering them as icons" do
    tree.add(SidebarNode.new(key: "modules.category.records", label: "Records & data", menu_item: :modules, category: true))
    tree.add(SidebarNode.new(key: "modules.website", label: "Website", menu_item: :modules, icon: "M1 1", section_root: true,
                             children: [SidebarNode.new(key: "modules.website.pages", label: "Pages", menu_item: :modules, path: "/w")]))
    tree.add(SidebarNode.new(key: "modules.category.growth", label: "Growth", menu_item: :modules, category: true))
    tree.add(SidebarNode.new(key: "modules.captcha", label: "Captcha", menu_item: :modules, icon: "M2 2", section_root: true,
                             children: [SidebarNode.new(key: "modules.captcha.howto", label: "How to use", menu_item: :modules, path: "/c")]))

    render_rail(menu_item: :modules, path: "/c")

    expect(page).to have_css("nav[aria-label='Modules'] div.bg-border-subtle", count: 1)
    expect(page).to have_css("button[aria-label='Captcha'].bg-accent-subtle")
    expect(page).not_to have_css("[aria-label='Records & data'], [aria-label='Growth']")
  end

  it "names the Domains rail from the top menu and renders nothing when the tree is empty" do
    render_rail(menu_item: :entities, path: "/domains")

    expect(page).to have_css("nav[aria-label='Domains']")
    expect(page).to have_css("button[aria-label='Expand sidebar']")
    expect(page).not_to have_css("nav a, nav button")
    expect(page).not_to have_css("[data-action*='expandSearch']")
  end

  it "offers a search control on searchable menus that opens the full sidebar's search" do
    tree.add(SidebarNode.new(key: "modules.m", label: "Email", menu_item: :modules, path: "/modules/email", icon: "M1 1"))
    render_rail(menu_item: :modules, path: "/modules/email")

    search = page.find("button[aria-label='Search Modules...']")
    expect(search["data-action"]).to eq("click->sidebar-collapsible#expandSearch")
    expect(search["data-sidebar-rail-label"]).to eq("Search Modules...")
  end

  it "omits the search control on menus without search" do
    tree.add(SidebarNode.new(key: "maintenance.c", label: "Customers", menu_item: :maintenance, path: "/m/c", icon: "M1 1"))
    render_rail(path: "/m/c")

    expect(page).not_to have_css("[data-action*='expandSearch']")
  end

  it "omits the search control on the Domains rail" do
    tree.add(SidebarNode.new(key: "entities.e", label: "Students", menu_item: :entities, path: "/e/1", icon: "M1 1"))
    render_rail(menu_item: :entities, path: "/e/1")

    expect(page).not_to have_css("[data-action*='expandSearch']")
  end
end
