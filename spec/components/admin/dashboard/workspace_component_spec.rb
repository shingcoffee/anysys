# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Dashboard::WorkspaceComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 81_721_200, name: "Acme") }
  let(:user) { build_stubbed(:user, customer: customer, first_name: "Jane", last_name: "Doe") }
  let(:metric_icon) { "M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375" }

  let(:metrics) do
    [
      OpenStruct.new(key: :entities, label: "Entities", value: 3, sub_label: nil, icon: metric_icon, href: "/#{customer.id}/admin/domains"),
      OpenStruct.new(key: :pages, label: "Pages", value: 5, sub_label: "2 launched", icon: metric_icon, href: "/#{customer.id}/admin/domains"),
      OpenStruct.new(key: :modules, label: "Modules", value: 4, sub_label: nil, icon: metric_icon, href: "/#{customer.id}/admin/maintenance/modules"),
      OpenStruct.new(key: :users, label: "Users", value: 6, sub_label: nil, icon: metric_icon, href: "/#{customer.id}/admin/modules/authentication/users")
    ]
  end

  let(:modules) do
    [
      OpenStruct.new(
        key: "authentication",
        name: "User Authentication",
        description: I18n.t("admin_misc.dashboard.modules.blurbs.authentication"),
        primary: OpenStruct.new(label: "Users", href: "/#{customer.id}/admin/modules/authentication/users"),
        secondaries: [
          OpenStruct.new(label: "Security Log", href: "/#{customer.id}/admin/modules/authentication/events")
        ]
      ),
      OpenStruct.new(
        key: "ai_assistant",
        name: "AI Assistant",
        description: I18n.t("admin_misc.dashboard.modules.blurbs.ai_assistant"),
        primary: OpenStruct.new(label: I18n.t("admin_misc.dashboard.modules.open_assistant"), href: "/#{customer.id}/admin/assistant"),
        secondaries: [
          OpenStruct.new(label: "Settings", href: "/#{customer.id}/admin/settings/modules/ai_assistant")
        ]
      )
    ]
  end

  let(:incomplete_setup) do
    [
      OpenStruct.new(key: :create_entity, label: I18n.t("admin_misc.dashboard.setup.items.create_entity"), done: false, href: "/#{customer.id}/admin/maintenance/entities/new"),
      OpenStruct.new(key: :launch_page, label: I18n.t("admin_misc.dashboard.setup.items.launch_page"), done: false, href: "/#{customer.id}/admin/domains"),
      OpenStruct.new(key: :enable_module, label: I18n.t("admin_misc.dashboard.setup.items.enable_module"), done: false, href: "/#{customer.id}/admin/maintenance/modules"),
      OpenStruct.new(key: :invite_user, label: I18n.t("admin_misc.dashboard.setup.items.invite_user"), done: false, href: "/#{customer.id}/admin/modules/authentication/users/new")
    ]
  end

  let(:complete_setup) do
    incomplete_setup.map { |item| OpenStruct.new(key: item.key, label: item.label, done: true, href: item.href) }
  end

  let(:actions) do
    [
      OpenStruct.new(key: :create_entity, label: "Create entity", description: "Set up a new data type", path: "/entities/new", icon: metric_icon),
      OpenStruct.new(key: :new_page, label: "New page", description: "Bind a form to an entity", path: "/pages/new", icon: metric_icon),
      OpenStruct.new(key: :invite_user, label: "Invite user", description: "Add a teammate", path: "/users/new", icon: metric_icon)
    ]
  end

  let(:recent_pages) do
    [
      OpenStruct.new(name: "Contact form", href: "/#{customer.id}/admin/pages/1", badge: "live")
    ]
  end

  let(:recent_entities) do
    [
      OpenStruct.new(name: "Members", href: "/#{customer.id}/admin/entities/1", badge: nil)
    ]
  end

  let(:home) { build_home }

  def build_home(**overrides)
    OpenStruct.new(
      {
        metrics: metrics,
        modules: modules,
        setup_items: incomplete_setup,
        recent_pages: recent_pages,
        recent_entities: recent_entities,
        actions: actions
      }.merge(overrides)
    )
  end

  def render_workspace(home: self.home)
    with_request_url("/#{customer.id}/admin/dashboard") do
      render_inline(
        described_class.new(
          customer: customer,
          user: user,
          home: home
        )
      )
    end
  end

  it "renders the welcome header, four metric links with icons, recents, and compact quick actions" do
    render_workspace

    expect(page).to have_css("h1", text: "Welcome back, Jane")
    expect(page).to have_text("Acme")
    expect(page).to have_text(I18n.t("admin_misc.dashboard.subtitle"))
    expect(page).to have_css("h2#dashboard-overview-title.sr-only", text: I18n.t("admin_misc.dashboard.snapshot"))
    expect(page).to have_css("section[aria-labelledby='dashboard-overview-title'] a", count: 4)
    expect(page).to have_css("section[aria-labelledby='dashboard-overview-title'] a svg path[d='#{metric_icon}']", count: 4)
    expect(page).to have_link("Entities", href: "/#{customer.id}/admin/domains")
    expect(page).to have_link("Pages", href: "/#{customer.id}/admin/domains")
    expect(page).to have_link("Modules", href: "/#{customer.id}/admin/maintenance/modules")
    expect(page).to have_link("Users", href: "/#{customer.id}/admin/modules/authentication/users")
    expect(page).to have_text("2 launched")
    expect(page).to have_css("a[data-dashboard-metric]", text: I18n.t("admin_misc.dashboard.stats.view"), count: 3)
    expect(page).to have_css("[data-dashboard-region='recents']", text: I18n.t("admin_misc.dashboard.recents.pages_title"))
    expect(page).to have_css("[data-dashboard-region='recents']", text: I18n.t("admin_misc.dashboard.recents.entities_title"))
    expect(page).to have_link("Contact form", href: "/#{customer.id}/admin/pages/1")
    expect(page).to have_link("Members", href: "/#{customer.id}/admin/entities/1")
    expect(page).to have_css("aside[data-dashboard-region='rail'] h2", text: I18n.t("admin_misc.dashboard.quick_actions"))
    expect(page).to have_css("aside a.px-4.py-3", text: "Invite user")
    expect(page).not_to have_css("aside", text: "Create entity")
    expect(page).not_to have_css("aside", text: "New page")
    expect(page).not_to have_css("[data-controller]")
    expect(page).not_to have_css("[data-controller='ai-assistant']")
    expect(page).not_to have_css("[data-dashboard-region='chat']")
    expect(page).not_to have_css("#ai_assistant_composer")
    expect(page).not_to have_text(I18n.t("ai_assistant.assistant.offline.body"))
    expect(page).not_to have_text(/flowchart/i)
  end

  it "promotes new page and create entity to header buttons with create entity as the primary action" do
    render_workspace

    expect(page).to have_css("header a.btn-secondary[href='/pages/new']", text: "New page")
    expect(page).to have_css("header a.btn-primary[href='/entities/new']", text: "Create entity")
    expect(page.all("header a").map(&:text).map(&:strip)).to eq(["New page", "Create entity"])
  end

  it "formats metric values with delimiters and treats nil as zero" do
    big = metrics.map { |m| OpenStruct.new(m.to_h.merge(value: m.key == :entities ? 12_345 : nil)) }
    render_workspace(home: build_home(metrics: big))

    expect(page).to have_css("a[data-dashboard-metric='entities']", text: "12,345")
    expect(page).to have_css("a[data-dashboard-metric='users']", text: "0")
  end

  it "omits the quick actions card when every action is promoted to the header" do
    render_workspace(home: build_home(actions: actions.first(2), setup_items: complete_setup))

    expect(page).not_to have_text(I18n.t("admin_misc.dashboard.quick_actions"))
    expect(page).not_to have_css("aside[data-dashboard-region='rail']")
    expect(page).to have_css("header a.btn-primary", text: "Create entity")
  end

  it "does not request an edge canvas" do
    render_workspace
    expect(page).not_to have_css("[data-dashboard-region='overview'][class*='lg:flex-1']")
  end

  it "renders module cards when home.modules is present" do
    render_workspace
    expect(page).to have_text(I18n.t("admin_misc.dashboard.modules.title"))
    expect(page).to have_text(I18n.t("admin_misc.dashboard.modules.description"))
    expect(page).to have_css("h2#dashboard-modules-title .badge", text: "2")
    expect(page).to have_css("section[aria-labelledby='dashboard-modules-title'] a[href='/#{customer.id}/admin/modules']",
                             text: I18n.t("admin_misc.dashboard.recents.view_all"))
    expect(page).to have_css("h3", text: "User Authentication")
    expect(page).to have_link("Users", href: "/#{customer.id}/admin/modules/authentication/users")
    expect(page).to have_link(I18n.t("admin_misc.dashboard.modules.open_assistant"), href: "/#{customer.id}/admin/assistant")
    expect(page).not_to have_css("[data-controller='ai-assistant']")
  end

  it "omits the enabled-modules section when home.modules is empty" do
    render_workspace(home: build_home(modules: []))
    expect(page).not_to have_text(I18n.t("admin_misc.dashboard.modules.title"))
    expect(page).not_to have_css("h3", text: "User Authentication")
  end

  it "omits getting started when every setup item is done" do
    render_workspace(home: build_home(setup_items: complete_setup))
    expect(page).not_to have_text(I18n.t("admin_misc.dashboard.setup.title"))
    expect(page).not_to have_css("[role='progressbar']")
  end

  it "shows getting started with progress when setup is incomplete" do
    render_workspace
    expect(page).to have_text(I18n.t("admin_misc.dashboard.setup.title"))
    expect(page).to have_text(I18n.t("admin_misc.dashboard.setup.progress", done: 0, total: 4))
    expect(page).to have_css("[role='progressbar'][aria-valuenow='0']")
    expect(page).to have_link(I18n.t("admin_misc.dashboard.setup.items.create_entity"))
  end

  it "renders without crashing when home is nil" do
    render_workspace(home: nil)
    expect(page).to have_text("Welcome back, Jane")
    expect(page).not_to have_css("header a")
    expect(page).not_to have_text(I18n.t("admin_misc.dashboard.quick_actions"))
    expect(page).to have_text(I18n.t("admin_misc.dashboard.recents.pages_empty_title"))
    expect(page).not_to have_text(I18n.t("admin_misc.dashboard.modules.title"))
    expect(page).not_to have_text(I18n.t("admin_misc.dashboard.setup.title"))
  end
end
