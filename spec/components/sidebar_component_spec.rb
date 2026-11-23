# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarComponent, type: :component do
  let(:tree) { SidebarTree.new }
  let(:node) { SidebarNode.new(key: "e", label: "Entity", menu_item: :entities, path: "/x") }

  it "renders nodes for the given menu_item" do
    tree.add(node)
    render_inline described_class.new(tree: tree, menu_item: :entities, current_path: "/x")
    expect(page).to have_text("Entity")
    expect(page).not_to have_css("button[aria-label='Collapse sidebar']")
  end

  it "puts the collapse control in the sidebar header" do
    tree.add(node)
    render_inline described_class.new(tree: tree, menu_item: :entities, current_path: "/x", collapsible: true)

    expect(page.find("aside > div:first-child")).to have_text("Domains")
    expect(page).to have_css("button[aria-label='Collapse sidebar']")
    expect(page).not_to have_css("button.absolute")
    expect(page.find("aside > div:last-child")).to have_link("Entity")
  end

  it "gives the shell wrapper the same expanded widths and breakpoint as the desktop aside" do
    expect(described_class.expanded_shell_classes(:entities).split).to eq(
      %w[data-[state=expanded]:md:flex data-[state=expanded]:w-60 data-[state=expanded]:lg:w-64 data-[state=expanded]:xl:w-72]
    )
    expect(described_class.expanded_shell_classes(:settings).split).to eq(
      %w[data-[state=expanded]:lg:flex data-[state=expanded]:lg:w-72]
    )
  end

  it "renders empty state when no nodes" do
    render_inline described_class.new(tree: tree, menu_item: :entities, current_path: "/x")
    expect(page).to have_text("Nothing here yet")
  end

  it "groups section labels and shows a settings search field" do
    tree.add(SidebarNode.new(key: "settings.overview", label: "Overview", menu_item: :settings, path: "/s"))
    tree.add(SidebarNode.new(key: "settings.section.organization", label: "Organization", menu_item: :settings, section_root: true))
    tree.add(SidebarNode.new(key: "settings.member", label: "Member", menu_item: :settings, path: "/s/member"))
    render_inline described_class.new(tree: tree, menu_item: :settings, current_path: "/s")
    expect(page).to have_text("Organization")
    expect(page).to have_field("Search settings...")
    expect(page).to have_link("Overview", href: "/s")
    expect(page).to have_css("nav[aria-label='Settings']")
    expect(page).to have_css("[data-controller='list-filter']")
  end

  it "does not mount search on Domains while staying visible at tablet width" do
    tree.add(node)
    render_inline described_class.new(tree: tree, menu_item: :entities, current_path: "/x")
    expect(page).not_to have_field("Search Domains...")
    expect(page).not_to have_css("input[type='search']")
    expect(page).not_to have_css("[data-controller='list-filter']")
    expect(page.find("aside")[:class]).to include("md:flex")
    expect(page.find("aside")[:class]).not_to include("lg:flex")
  end

  it "does not mount search on menus outside the searchable set" do
    tree.add(SidebarNode.new(key: "maintenance.x", label: "Customers", menu_item: :maintenance, path: "/m"))
    render_inline described_class.new(tree: tree, menu_item: :maintenance, current_path: "/m")
    expect(page).not_to have_css("[data-controller='list-filter']")
    expect(page).not_to have_css("input[type='search']")
  end

  it "uses the settings rail only at desktop width and omits empty filtered groups" do
    tree.add(SidebarNode.new(key: "settings.section.communication", label: "Communication", menu_item: :settings, section_root: true))
    render_inline described_class.new(tree: tree, menu_item: :settings, current_path: "/s")
    expect(page.find("aside")[:class]).to include("lg:flex")
    expect(page.find("aside")[:class]).not_to include("md:flex")
    expect(page).not_to have_text("Communication")
  end

  it "selects only the longest matching item" do
    tree.add(SidebarNode.new(key: "entities.heading", label: "Domains", menu_item: :entities,
                             path: "/1/admin/domains", match_prefix: "/1/admin/domains"))
    tree.add(SidebarNode.new(key: "entities.domain.1", label: "Academics", menu_item: :entities,
                             path: "/1/admin/domains/1", match_prefix: "/1/admin/domains/1"))
    render_inline described_class.new(tree: tree, menu_item: :entities, current_path: "/1/admin/domains/1/pages")
    expect(page).to have_css("a[aria-current='page']", text: "Academics")
    expect(page).not_to have_css("a[aria-current='page']", text: "Domains")
  end

  it "renders the same grouping in the searchable mobile variant with unique input IDs" do
    tree.add(SidebarNode.new(key: "settings.section.members", label: "Members", menu_item: :settings, section_root: true))
    tree.add(SidebarNode.new(key: "settings.member", label: "Member portal", menu_item: :settings, path: "/s/member"))
    render_inline described_class.new(tree: tree, menu_item: :settings, current_path: "/s/member", mobile: true, search_id: "mobile-search")
    expect(page).to have_field("mobile-search")
    expect(page).to have_text("Members")
    expect(page).to have_css("details[open] a[aria-current='page']", text: "Member portal")
    expect(page.find("aside")[:class]).not_to include("hidden")
  end

  it "opens only the Settings section containing the active item, including nested paths" do
    tree.add(SidebarNode.new(key: "settings.section.email", label: "Email", menu_item: :settings, section_root: true))
    tree.add(SidebarNode.new(key: "settings.email.tokens", label: "Personalization", menu_item: :settings,
                             path: "/s/email/tokens", match_prefix: "/s/email/tokens"))
    tree.add(SidebarNode.new(key: "settings.section.billing", label: "Billing", menu_item: :settings, section_root: true))
    tree.add(SidebarNode.new(key: "settings.billing.invoices", label: "Invoices", menu_item: :settings, path: "/s/billing/invoices"))

    render_inline described_class.new(tree: tree, menu_item: :settings, current_path: "/s/email/tokens/12/edit")

    expect(page).to have_css("details[open] > summary", text: "Email")
    expect(page).to have_css("details[open] a[aria-current='page']", text: "Personalization")
    expect(page).to have_css("details:not([open]) > summary", text: "Billing")
    expect(page).not_to have_css("a[aria-current='page']", text: "Invoices")
  end

  it "uses the Modules section and child-link styling for active Settings sections" do
    module_tree = SidebarTree.new
    module_tree.add(SidebarNode.new(key: "modules.email", label: "Email", menu_item: :modules, icon: "M0 0",
                                    children: [SidebarNode.new(key: "modules.email.messages", label: "Messages",
                                                               menu_item: :modules, path: "/m/messages", icon: "M0 0")]))
    render_inline described_class.new(tree: module_tree, menu_item: :modules, current_path: "/m/messages")
    module_summary = page.find("details summary")[:class].split
    module_rail = page.find("details ul")[:class]
    module_link = page.find("details ul a")[:class]

    settings_tree = SidebarTree.new
    settings_tree.add(SidebarNode.new(key: "settings.section.email", label: "Email", menu_item: :settings,
                                      section_root: true, icon: "M0 0"))
    settings_tree.add(SidebarNode.new(key: "settings.email.tokens", label: "Personalization", menu_item: :settings,
                                      path: "/s/tokens", icon: "M0 0"))
    render_inline described_class.new(tree: settings_tree, menu_item: :settings, current_path: "/s/tokens")

    expect(page.find("details summary")[:class]).to eq(module_summary.join(" "))
    expect(page.find("details ul", visible: :all)[:class]).to eq(module_rail)
    expect(page.find("details ul a", visible: :all)[:class]).to eq(module_link)
    expect(page).not_to have_css("details[open] ul a svg")
    expect(page.find("nav > ul")[:class]).to include("gap-0.5")
    expect(page).to have_css("details.group\\/nav[open] > summary", text: "Email")
  end

  describe "category headings" do
    def category(key, label, menu_item: :settings)
      SidebarNode.new(key: key, label: label, menu_item: menu_item, category: true)
    end

    it "wraps Settings sections in labelled, filterable categories after the uncategorized Overview" do
      tree.add(SidebarNode.new(key: "settings.overview", label: "Overview", menu_item: :settings, path: "/s"))
      tree.add(category("settings.category.communication", "Communication"))
      tree.add(SidebarNode.new(key: "settings.section.email", label: "Email", menu_item: :settings, section_root: true))
      tree.add(SidebarNode.new(key: "settings.email.cap", label: "Email limit", menu_item: :settings, path: "/s/email"))
      tree.add(category("settings.category.empty", "Empty"))
      render_inline described_class.new(tree: tree, menu_item: :settings, current_path: "/s/email")

      expect(page.find("nav > ul")[:class]).to include("gap-5")
      expect(page).to have_css("nav > ul > li", count: 2)
      heading = page.find("nav > ul > li h3", text: "Communication")
      list = page.find("ul[aria-labelledby='#{heading[:id]}']")
      expect(heading[:id]).to eq("sidebar-settings-search-settings-category-communication")
      expect(list).to have_css("details[open] a[aria-current='page']", text: "Email limit")
      expect(page.find("nav > ul > li:last-child")["data-list-filter-target"]).to eq("group")
      expect(page).not_to have_text("Empty")
    end

    it "lists Modules groups under their category headings" do
      tree.add(SidebarNode.new(key: "modules.overview", label: "Overview", menu_item: :modules, path: "/m"))
      tree.add(category("modules.category.records", "Records & data", menu_item: :modules))
      tree.add(SidebarNode.new(key: "modules.website", label: "Website", menu_item: :modules, section_root: true, children: [
        SidebarNode.new(key: "modules.website.pages", label: "Pages", menu_item: :modules, path: "/m/website")
      ]))
      render_inline described_class.new(tree: tree, menu_item: :modules, current_path: "/m", mobile: true, search_id: "drawer-modules-search")

      expect(page).to have_field("drawer-modules-search")
      expect(page).to have_css("h3#drawer-modules-search-modules-category-records", text: "Records & data")
      expect(page).to have_css("ul[aria-labelledby='drawer-modules-search-modules-category-records'] details summary", text: "Website")
    end
  end
end
