# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShellComponent, type: :component do
  let(:customer) { create(:customer, name: "T") }
  let(:user)     { double(owner?: false, admin?: false, admin_or_owner?: false, platform_owner?: false, first_name: "Test", last_name: "User", email: "test@example.com") }
  let(:tree)     { SidebarTree.new }
  let(:items)    { MenuRegistry.for(user) }

  def render_shell(current_menu_item:, current_path:, **opts)
    render_inline described_class.new(
      customer: customer, user: user, tree: tree,
      menu_items: items, current_menu_item: current_menu_item, current_path: current_path,
      **opts
    )
  end

  it "renders the menu bar" do
    render_shell(current_menu_item: :home, current_path: "/")
    expect(page).to have_selector("nav[aria-label='Dashboard menu']")
  end

  it "omits the sidebar on :home" do
    render_shell(current_menu_item: :home, current_path: "/")
    expect(page).not_to have_selector("aside.hidden.md\\:flex")
  end

  it "omits the sidebar on :assistant" do
    render_shell(current_menu_item: :assistant, current_path: "/81721200/admin/assistant")
    expect(page).not_to have_selector("aside.hidden.md\\:flex")
  end

  it "omits the sidebar and the active tab on :help" do
    render_shell(current_menu_item: :help, current_path: "/81721200/admin/help/docs")
    expect(page).not_to have_selector("aside.hidden.md\\:flex")
    expect(page).not_to have_selector("nav[aria-label='Dashboard menu'] a[aria-current='page']")
  end

  it "renders the sidebar off-home" do
    tree.add(SidebarNode.new(key: "e", label: "E", menu_item: :entities, path: "/x"))
    render_shell(current_menu_item: :entities, current_path: "/x")
    expect(page).to have_selector("aside.hidden.md\\:flex")
  end

  it "starts the sidebar collapsed for top-menu items other than Modules, Communication, Entities, Settings, and Maintenance" do
    registry_user = double(admin_or_owner?: true, platform_owner?: true)
    enable_module!("authentication", customer)
    enable_module!("payment", customer)
    enable_module!("email", customer)
    enable_module!("website", customer)
    visible_items = MenuRegistry.for(registry_user, customer: customer)

    [
      ["/#{customer.id}/admin/modules/authentication/users", :modules, "users"],
      ["/#{customer.id}/admin/modules/payments/transactions", :modules, "payments"],
      ["/#{customer.id}/admin/modules/website", :website_pages, "website_pages"]
    ].each do |path, menu_item, key|
      render_inline described_class.new(
        customer: customer, user: user, tree: tree, menu_items: visible_items,
        current_menu_item: menu_item, current_path: path
      )
      shell = page.find("[data-controller='sidebar-collapsible']", visible: :all)
      expect(shell["data-state"]).to eq("collapsed")
      expect(shell["data-sidebar-collapsible-collapsed-value"]).to eq("true")
      expect(shell["data-sidebar-collapsible-cookie-value"]).to eq("sidebar_state_#{key}")
      expect(page).to have_css("[data-sidebar-collapsible-target='full'][inert]", visible: :all)
      expect(page).to have_css("[data-sidebar-collapsible-target='rail']:not([inert])", visible: :all)
    end

    [
      ["/#{customer.id}/admin/modules", :modules, "modules"],
      ["/#{customer.id}/admin/modules/emails/send_activities", :modules, "communication"],
      ["/#{customer.id}/admin/modules/sms/campaigns", :modules, "communication"],
      ["/#{customer.id}/admin/domains", :entities, "entities"],
      ["/#{customer.id}/admin/settings", :settings, "settings"],
      ["/#{customer.id}/admin/maintenance", :maintenance, "maintenance"],
      ["/#{customer.id}/admin/maintenance/platform/developer_docs", :maintenance, "maintenance"]
    ].each do |path, menu_item, key|
      render_inline described_class.new(
        customer: customer, user: user, tree: tree, menu_items: visible_items,
        current_menu_item: menu_item, current_path: path
      )
      shell = page.find("[data-controller='sidebar-collapsible']", visible: :all)
      expect(shell["data-state"]).to eq("expanded")
      expect(shell["data-sidebar-collapsible-collapsed-value"]).to eq("false")
      expect(shell["data-sidebar-collapsible-cookie-value"]).to eq("sidebar_state_#{key}")
      expect(page).to have_css("[data-sidebar-collapsible-target='full']:not([inert])", visible: :all)
      expect(page).to have_css("[data-sidebar-collapsible-target='rail'][inert]", visible: :all)
    end
  end

  it "renders the state remembered in the session cookie instead of the menu default" do
    tree.add(SidebarNode.new(key: "p", label: "P", menu_item: :pages, path: "/x"))
    vc_test_request.cookies["sidebar_state_pages"] = "expanded"
    render_shell(current_menu_item: :pages, current_path: "/x")
    expect(page.find("#app-sidebar")["data-state"]).to eq("expanded")

    vc_test_request.cookies["sidebar_state_pages"] = "bogus"
    render_shell(current_menu_item: :pages, current_path: "/x")
    expect(page.find("#app-sidebar")["data-state"]).to eq("collapsed")

    vc_test_request.cookies["sidebar_state_maintenance"] = "collapsed"
    render_shell(current_menu_item: :maintenance, current_path: "/42/admin/maintenance")
    expect(page.find("#app-sidebar")["data-state"]).to eq("collapsed")
  end

  it "animates between the icon rail and the sidebar's breakpoint widths" do
    tree.add(SidebarNode.new(key: "e", label: "E", menu_item: :entities, path: "/x"))
    render_shell(current_menu_item: :entities, current_path: "/x")
    classes = page.find("#app-sidebar")[:class].split
    expect(classes).to include("transition-[width]", "motion-reduce:transition-none",
                               "data-[state=collapsed]:w-[4.25rem]", "data-[state=expanded]:w-60",
                               "data-[state=expanded]:lg:w-64", "data-[state=expanded]:xl:w-72")

    render_shell(current_menu_item: :settings, current_path: "/42/admin/settings")
    expect(page.find("#app-sidebar")[:class].split).to include("data-[state=expanded]:lg:w-72")
    expect(page.find("#app-sidebar")[:class].split).not_to include("data-[state=expanded]:md:flex")
  end

  it "keeps the header buttons as the only pointer toggles, with no hidden border strip" do
    render_shell(current_menu_item: :maintenance, current_path: "/42/admin/maintenance")
    expect(page).not_to have_css("#app-sidebar > button", visible: :all)
    expect(page).not_to have_css("#app-sidebar [data-action~='click->sidebar-collapsible#toggle']", visible: :all)
  end

  it "points the toggle chevrons the way the sidebar will move" do
    render_shell(current_menu_item: :maintenance, current_path: "/42/admin/maintenance")
    collapse = page.find("[data-sidebar-collapsible-target='full'] button[aria-label='Collapse sidebar']")
    expand = page.find("[data-sidebar-collapsible-target='rail'] button[aria-label='Expand sidebar']", visible: :all)
    expect(collapse).to have_css("svg path[d='m11 17-5-5 5-5']")
    expect(expand).to have_css("svg path[d='m6 17 5-5-5-5']", visible: :all)
  end

  it "shows the keyboard shortcut on both header toggles" do
    render_shell(current_menu_item: :maintenance, current_path: "/42/admin/maintenance")
    [["full", "Collapse sidebar"], ["rail", "Expand sidebar"]].each do |target, label|
      toggle = page.find("[data-sidebar-collapsible-target='#{target}'] button[aria-label='#{label}']", visible: :all)
      expect(toggle["data-sidebar-rail-shortcut"]).to eq("⌘B")
      expect(toggle["aria-keyshortcuts"]).to eq("Meta+B Control+B")
      expect(toggle["aria-controls"]).to eq("app-sidebar")
    end
    expect(page).to have_css("[role='tooltip'] kbd[data-sidebar-collapsible-target='tooltipShortcut']", visible: :all)
  end

  it "labels the collapsed Domains sidebar after its menu item" do
    render_shell(current_menu_item: :entities, current_path: "/#{customer.id}/admin/domains")

    rail = page.find("[data-sidebar-collapsible-target='rail']")
    expect(rail).to have_css("nav[aria-label='Domains']")
    expect(rail).to have_css("button[aria-label='Expand sidebar']")
    expect(page).to have_css("[data-sidebar-collapsible-target='full'] button[aria-label='Collapse sidebar']")
    expect(page).not_to have_css("[data-sidebar-collapsible-target='full'] button.absolute")
  end

  it "omits the sidebar when container_width is :edge" do
    tree.add(SidebarNode.new(key: "p", label: "P", menu_item: :pages, path: "/x"))
    render_shell(current_menu_item: :pages, current_path: "/x", container_width: :edge)
    expect(page).not_to have_selector("aside.hidden.md\\:flex")
    expect(page).to have_css("main#main-content.overflow-hidden")
  end

  it "exposes a skip link to main content" do
    render_shell(current_menu_item: :home, current_path: "/")
    expect(page).to have_link("Skip to main content", href: "#main-content")
    expect(page).to have_css("main#main-content")
  end

  it "makes main the containing block so absolutely positioned content cannot grow the locked document" do
    render_shell(current_menu_item: :home, current_path: "/")
    expect(page.find("main")["class"].split).to include("relative")
  end

  it "keeps the viewport-locked shell for ordinary settings pages" do
    render_shell(current_menu_item: :settings, current_path: "/42/admin/settings/billing/invoices/1")
    expect(page.find("main")["class"]).to include("overflow-auto")
    expect(page.find("main")["class"]).not_to include("print:")
    expect(page.find("[data-controller='drawer']")["class"]).not_to include("print:")
  end

  it "releases all shell clipping ancestors and hides only chrome for printable settings" do
    rendered = render_inline(described_class.new(
      customer: customer, user: user, tree: tree, menu_items: items,
      current_menu_item: :settings, current_path: "/42/admin/settings/billing/invoices/1/download",
      settings_printable: true
    )) { '<article id="invoice-fixture">Full invoice</article>'.html_safe }
    expect(rendered.at_css("[data-controller='drawer']")["class"]).to include(
      "print:block", "print:h-auto", "print:overflow-visible", "print:[&>*:not([data-shell-workspace])]:hidden"
    )
    expect(rendered.at_css("[data-shell-workspace]")["class"]).to include(
      "print:block", "print:h-auto", "print:overflow-visible", "print:[&>*:not(main)]:hidden"
    )
    expect(rendered.at_css("main")["class"]).to include("print:block", "print:h-auto", "print:overflow-visible")
    expect(rendered.at_css("#invoice-fixture").ancestors.none? { |node| node["class"].to_s.split.include?("print:hidden") }).to be(true)
  end

  it "ignores the settings print option on other admin areas" do
    render_shell(current_menu_item: :maintenance, current_path: "/42/admin/maintenance", settings_printable: true)
    expect(page.find("[data-controller='drawer']")["class"]).not_to include("print:")
    expect(page.find("main")["class"]).not_to include("print:")
  end
end
