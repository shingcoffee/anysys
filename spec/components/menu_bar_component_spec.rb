# frozen_string_literal: true

require "rails_helper"

RSpec.describe MenuBarComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 12345678) }
  let(:items) { MenuRegistry.for(double(owner?: false, admin_or_owner?: false)) }

  it "renders one link per visible item" do
    render_inline described_class.new(customer: customer, items: items, current_menu_item: :home)
    expect(page).to have_link("Home", href: "/12345678/admin/dashboard")
    expect(page).to have_link("AI Assistant", href: "/12345678/admin/assistant")
    expect(page).to have_link("Domains", href: "/12345678/admin/domains")
    expect(page).not_to have_css("[data-menu-item-key='pages']")
    expect(page).not_to have_text("Content")
    expect(page).not_to have_link("Website")
    expect(page).to have_link("Modules")
    expect(page).to have_link("Settings")
    expect(page).not_to have_css("[data-menu-item-key='maintenance']")
  end

  it "marks the current item active via aria-current" do
    render_inline described_class.new(customer: customer, items: items, current_menu_item: :entities)
    active = page.find("a", text: "Domains")
    expect(active["aria-current"]).to eq("page")
    expect(active).to have_css("svg[aria-hidden='true']")
    expect(active[:class]).to include("after:bg-accent")
    expect(active.find("span")[:class]).to include("text-text-primary")

    idle = page.find("a", text: "Home")
    expect(idle[:class]).not_to include("after:bg-accent")
    expect(idle.find("span")[:class]).to include("text-text-secondary")
  end

  it "keeps the owner-only Maintenance link visible beside Settings outside the scrolling destinations" do
    owner_items = MenuRegistry.for(double(admin_or_owner?: true, platform_owner?: true))
    render_inline described_class.new(customer: customer, items: owner_items, current_menu_item: :maintenance)

    utility = page.find("nav [data-menu-bar-utility]")
    expect(utility).to have_link("Settings")
    expect(utility).to have_link("Maintenance", href: "/12345678/admin/maintenance")
    expect(utility).to have_css("a[data-menu-item-key='maintenance'][aria-current='page']")
  end

  it "keeps utility labels accessible while showing them as icons below xl" do
    render_inline described_class.new(customer: customer, items: items, current_menu_item: :home)

    settings = page.find("[data-menu-bar-utility] a[data-menu-item-key='settings']")
    expect(settings["title"]).to eq("Settings")
    expect(settings).to have_css("span.sr-only.xl\\:not-sr-only", text: "Settings")
  end

  it "describes each dropdown destination with an icon tile and translated summary" do
    enabled_customer = create(:customer)
    enable_module!("email", enabled_customer)
    visible_items = MenuRegistry.for(double(admin_or_owner?: true), customer: enabled_customer)
    render_inline described_class.new(customer: enabled_customer, items: visible_items, current_menu_item: :home)

    email = page.find("details[data-menu-item-key='communication'] a", text: "Email", visible: :all)
    expect(email).to have_css("svg[aria-hidden='true']", visible: :all)
    expect(email).to have_text(:all, "Send emails and track delivery")

    I18n.with_locale(:"zh-CN") do
      render_inline described_class.new(customer: enabled_customer, items: visible_items, current_menu_item: :home)
      expect(page).to have_css("details[data-menu-item-key='communication'] a", text: "发送邮件，跟踪投递状态", visible: :all)
    end
  end

  it "does not render when there are zero items" do
    render_inline described_class.new(customer: customer, items: [], current_menu_item: :home)
    expect(page).not_to have_selector("nav")
  end

  it "renders the ordered tenant shortcuts and an accessible Communication disclosure" do
    enabled_customer = create(:customer)
    %w[authentication payment email sms].each { |key| enable_module!(key, enabled_customer) }
    visible_items = MenuRegistry.for(double(admin_or_owner?: true), customer: enabled_customer)

    render_inline described_class.new(customer: enabled_customer, items: visible_items,
                                      current_menu_item: :home)

    nav = page.find("nav[aria-label='Dashboard menu']")
    expect(nav.all("a[data-menu-item-key], details[data-menu-item-key]").first(5).map { |element|
      element["data-menu-item-key"]
    }).to eq(%w[home assistant users payments communication])
    expect(nav).to have_link("Users", href: "/#{enabled_customer.id}/admin/modules/authentication/users")
    expect(nav).to have_link("Payments", href: "/#{enabled_customer.id}/admin/modules/payments/transactions")
    expect(nav).to have_css("details summary", text: "Communication")
    expect(nav).to have_css("details a[href='/#{enabled_customer.id}/admin/modules/emails/send_activities']", text: "Email", visible: :all)
    expect(nav).to have_css("details a[href='/#{enabled_customer.id}/admin/modules/sms/campaigns']", text: "SMS", visible: :all)
  end

  it "highlights the direct destination instead of Modules on nested module pages" do
    enabled_customer = create(:customer)
    %w[authentication payment email].each { |key| enable_module!(key, enabled_customer) }
    visible_items = MenuRegistry.for(double(admin_or_owner?: true), customer: enabled_customer)

    render_inline described_class.new(customer: enabled_customer, items: visible_items,
                                      current_menu_item: :modules,
                                      current_path: "/#{enabled_customer.id}/admin/modules/emails/send_activities/new")

    expect(page).to have_css("details[data-menu-item-key='communication'] summary[aria-current='page']")
    expect(page).to have_css("details[data-menu-item-key='communication'] a[aria-current='page']", text: "Email", visible: :all)
    expect(page).not_to have_css("a[data-menu-item-key='modules'][aria-current='page']")
  end

  it "highlights Website on module list and editor routes" do
    enabled_customer = create(:customer)
    enable_module!("website", enabled_customer)
    visible_items = MenuRegistry.for(double(admin_or_owner?: true), customer: enabled_customer)

    ["/#{enabled_customer.id}/admin/modules/website", "/#{enabled_customer.id}/admin/modules/website/pages/new"].each do |path|
      render_inline described_class.new(customer: enabled_customer, items: visible_items,
                                        current_menu_item: :modules, current_path: path)

      expect(page).to have_css("a[data-menu-item-key='website_pages'][href='/#{enabled_customer.id}/admin/modules/website'][aria-current='page']",
                               text: "Website")
      expect(page).not_to have_css("a[data-menu-item-key='modules'][aria-current='page']")
    end
  end

  it "highlights Domains on a form's publishing panel" do
    render_inline described_class.new(customer: customer, items: items, current_menu_item: :entities,
                                      current_path: "/12345678/admin/pages/1")

    expect(page).to have_css("a[data-menu-item-key='entities'][aria-current='page']", text: "Domains")
  end
end
