# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::ManagementComponent, type: :component do
  let_it_be(:customer) { create(:customer, id: 12345678) }
  let(:customer_id) { customer.id.to_s }
  let(:target) { create(:page, :for_member, :for_public, customer: customer, name: "Register <now>", launched: true) }
  let(:shortcut) { PageShortcut.create!(customer: customer, path: "/campaign/register", target_type: "Page", target_id: target.id) }
  let(:targets) { [["Public page — Register <now>", "Page:#{target.id}"]] }
  let(:website_module) { enable_module!("website", customer, name: "Website") }
  let(:website) { create(:website, :published, customer: customer) }

  before { website_module }
  after { Current.reset }

  def render_management(shortcuts: [shortcut], available_targets: targets, **options)
    render_inline(described_class.new(shortcuts: shortcuts, available_targets: available_targets, customer_id: customer_id, **options))
  end

  def rendering_queries
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) do
      queries << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    end
    queries
  end

  it "renders a scoped native create form, semantic responsive rows and escaped destinations" do
    render_management

    expect(page).to have_css("form[action='/12345678/admin/maintenance/page_shortcuts'][method='post'][data-turbo='false']")
    expect(page).to have_field("Path", name: "page_shortcut[path]")
    expect(page).to have_select("Destination", options: ["Choose a destination", "Public page — Register <now>"])
    expect(page).to have_css("#page-shortcut-path[required][aria-describedby='page-shortcut-path-hint']")
    expect(page).to have_css("table caption", text: "Saved shortcuts", visible: :all)
    expect(page).to have_css("th[scope='col']", count: 4)
    expect(page).to have_css("tr[data-shortcut-id='#{shortcut.id}'][class*='md:table-row']")
    expect(page).to have_text("Register <now>")
    expect(page).to have_no_css("now, script, [data-controller]")
    expect(page).to have_link("/12345678/campaign/register", href: "/12345678/campaign/register")
  end

  it "edits through GET and deletes through a native method-override form" do
    render_management

    expect(page).to have_link("Edit", href: "/12345678/admin/maintenance/page_shortcuts?edit=#{shortcut.id}#shortcut-form")
    expect(page.find("a", text: "Edit", exact_text: true)["aria-label"]).to eq("Edit shortcut /campaign/register")
    form = page.find("form[action='/12345678/admin/maintenance/page_shortcuts/#{shortcut.id}']")
    expect(form["data-turbo"]).to eq("false")
    expect(form).to have_css("input[name='_method'][value='delete']", visible: :all)
    expect(form).to have_button("Remove")
    expect(form.find("button")["aria-label"]).to eq("Remove shortcut /campaign/register")
    expect(page).to have_text("Removing a shortcut keeps the page.")
  end

  it "retains root paths and failed destination values with field errors and PATCH" do
    render_management(editing_shortcut: shortcut, form_values: { path: "/", target: "Page:999" },
                      errors: { path: ["Path already taken"], target: ["Destination unavailable"] })

    form = page.find("#shortcut-form form")
    expect(form["action"]).to eq("/12345678/admin/maintenance/page_shortcuts/#{shortcut.id}")
    expect(form).to have_css("input[name='_method'][value='patch']", visible: :all)
    expect(form).to have_field("Path", with: "/")
    expect(form).to have_select("Destination", selected: "Page:999 — unavailable")
    expect(page).to have_css("[role='alert']", text: "Path already taken")
    expect(page).to have_css("#page-shortcut-path[aria-invalid='true'][aria-describedby='page-shortcut-path-hint page-shortcut-path-error']")
    expect(page).to have_css("#page-shortcut-target[aria-invalid='true']")
    expect(page).to have_link("Cancel", href: "/12345678/admin/maintenance/page_shortcuts")
    expect(page).to have_button("Save")
  end

  it "prefills saved input when editing" do
    render_management(editing_shortcut: shortcut)
    expect(page).to have_field("Path", with: "/campaign/register")
    expect(page).to have_select("Destination", selected: targets.first.first)
  end

  it "keeps unavailable destinations identifiable and removable without linking them" do
    target.update!(launched: false)
    render_management(available_targets: [], editing_shortcut: shortcut)

    expect(page).to have_text("Unavailable")
    expect(page).to have_no_link("/12345678/campaign/register")
    expect(page).to have_select("Destination", selected: "Public page — Register <now> — unavailable", disabled: true)
    expect(page).to have_button("Save", disabled: true)
    expect(page).to have_button("Remove")
    expect(page).to have_link("Manage form pages", href: "/12345678/admin/maintenance/pages")
  end

  it "renders deleted targets safely and accepts array error summaries" do
    shortcut
    target.destroy!
    render_management(available_targets: [], editing_shortcut: shortcut, errors: ["Save failed"])
    expect(page).to have_text("Deleted destination")
    expect(page).to have_select("Destination", selected: "Deleted destination — unavailable", disabled: true)
    expect(page).to have_css("[role='alert']", text: "Save failed")
    expect(page).to have_no_link("/12345678/campaign/register")
  end

  it "retains stored names for inactive and non-public form destinations" do
    target.update!(status: :inactive, visible_audiences: %w[admin member])
    render_management(available_targets: [], editing_shortcut: shortcut)

    expect(page).to have_text("Public page — Register <now>")
    expect(page).to have_select("Destination", selected: "Public page — Register <now> — unavailable", disabled: true)
    expect(page).to have_no_link("/12345678/campaign/register")
    expect(page).to have_button("Remove")
  end

  %w[Page WebsitePage].each do |type|
    it "does not expose a foreign #{type} title or borrow its tenant from Current or form input" do
      other_customer = create(:customer, id: 87654321)
      foreign = if type == "Page"
        create(:page, :for_member, :for_public, customer: other_customer, name: "Foreign private title", launched: true)
      else
        site = create(:website, :published, customer: other_customer)
        create(:website_page, :published, website: site, title: "Foreign private title")
      end
      shortcut.update!(target_type: type, target_id: foreign.id)
      Current.customer = other_customer
      render_management(available_targets: [], editing_shortcut: shortcut,
                        form_values: { customer_id: other_customer.id, target: "#{type}:#{foreign.id}" })

      expect(page).to have_text("Deleted destination")
      expect(page).to have_no_text("Foreign private title")
      expect(page).to have_select("Destination", selected: "Deleted destination — unavailable", disabled: true)
      expect(page).to have_no_link("/12345678/campaign/register")
      expect(page.find("#shortcut-form form")["action"]).to eq("/12345678/admin/maintenance/page_shortcuts/#{shortcut.id}")
    end
  end

  it "uses localized untitled labels for a stored blank name" do
    target.update_columns(name: " ")
    render_management(available_targets: [], editing_shortcut: shortcut)
    expect(page).to have_select("Destination", selected: "Public page — Untitled page — unavailable", disabled: true)
    expect(page).to have_text("Public page — Untitled page")
    expect(page).to have_no_text("Deleted destination")

    I18n.with_locale(:"zh-CN") { render_management(available_targets: [], editing_shortcut: shortcut) }
    expect(page).to have_select("目标页面", selected: "公开页面：未命名页面（不可访问）", disabled: true)
    expect(page).to have_text("公开页面：未命名页面")
    expect(page).to have_no_text("Translation missing")
  end

  it "renders shared public form destinations at the URL customer's root" do
    shared = create(:page, :shared, :for_member, :for_public, name: "Shared registration", launched: true)
    shortcut.update!(path: "/", target_id: shared.id)
    render_management(available_targets: [["Public page — Shared registration", "Page:#{shared.id}"]], editing_shortcut: shortcut)

    expect(page).to have_field("Path", with: "/")
    expect(page).to have_text("Public page — Shared registration")
    expect(page).to have_link("/12345678/", href: "/12345678/")
  end

  it "checks saved website publication and module availability" do
    website_page = create(:website_page, :published, website: website, title: "About <us>")
    shortcut.update!(target_type: "WebsitePage", target_id: website_page.id)
    options = [["Website page — About <us>", "WebsitePage:#{website_page.id}"]]
    render_management(available_targets: options)
    expect(page).to have_link("/12345678/campaign/register")
    expect(page).to have_text("Website page — About <us>")
    expect(page).to have_no_css("us")

    website.update!(published: false)
    render_management(available_targets: options)
    expect(page).to have_text("Unavailable")
    expect(page).to have_no_link("/12345678/campaign/register")

    website.update!(published: true)
    website_page.update!(published: false)
    render_management(available_targets: options)
    expect(page).to have_text("Unavailable")
    expect(page).to have_no_link("/12345678/campaign/register")

    website_page.update!(published: true)
    ensure_customer_feature_module(customer, website_module, status: :suspended)
    render_management(available_targets: options)
    expect(page).to have_text("Unavailable")
    expect(page).to have_no_link("/12345678/campaign/register")
  end

  it "marks an automatic-slug collision unavailable without hiding the saved alias" do
    shortcut.update!(path: "/register")
    create(:website_page, website: website, slug: "register", published: false)
    render_management
    expect(page).to have_text("/12345678/register")
    expect(page).to have_text("Unavailable")
    expect(page).to have_no_link("/12345678/register")
  end

  it "keeps an empty creation surface and translates Chinese at render time" do
    I18n.with_locale(:"zh-CN") { render_management(shortcuts: [], available_targets: []) }
    expect(page).to have_text("页面快捷路径")
    expect(page).to have_text("暂无快捷路径")
    expect(page).to have_field("路径")
    expect(page).to have_button("添加快捷路径", disabled: true)
    expect(page).to have_no_text("Translation missing")
  end

  it "uses the request host and retains SCRIPT_NAME on public links" do
    CustomDomainRecord.create!(hostname: "forms.example.com", customer: customer)
    with_request_url("/12345678/admin/maintenance/page_shortcuts", host: "forms.example.com") do
      vc_test_controller.request.script_name = "/app"
      render_management
    end
    expect(page).to have_link("/app/campaign/register", href: "/app/campaign/register")
  end

  it "does not instantiate Page records or load definitions while rendering management" do
    records = PageShortcut.where(id: shortcut.id).to_a
    choices = targets
    instantiated_classes = []
    callback = ->(_name, _start, _finish, _id, payload) { instantiated_classes << payload[:class_name] }
    expect_any_instance_of(Page).not_to receive(:reload_definition_from_head!)

    queries = rendering_queries do
      ActiveSupport::Notifications.subscribed(callback, "instantiation.active_record") do
        render_management(shortcuts: records, available_targets: choices, editing_shortcut: records.first)
      end
    end

    expect(page).to have_text("Public page — Register <now>")
    expect(page).to have_link("/12345678/campaign/register")
    expect(instantiated_classes).not_to include("Page")
    expect(queries.join("\n")).not_to match(/\b(?:page_versions|page_configuration_contents|page_customer_heads)\b/)
  end

  it "keeps SQL bounded from one to many distinct mixed destinations without per-row eligibility queries" do
    records = [shortcut]
    choices = targets
    site = website
    render_management(shortcuts: records, available_targets: choices)
    small = rendering_queries { render_management(shortcuts: records, available_targets: choices) }

    20.times do |index|
      destination = if index.even?
        create(:page, :for_member, :for_public, customer: customer, launched: index % 4 == 0)
      else
        create(:website_page, website: site, published: index % 3 == 0)
      end
      records << PageShortcut.create!(customer: customer, path: "/campaign/extra-#{index}",
                                     target_type: destination.class.name, target_id: destination.id)
    end
    large = rendering_queries { render_management(shortcuts: records, available_targets: choices) }

    expect(page).to have_css("tr[data-shortcut-id]", count: records.size)
    expect(page).to have_text("Available")
    expect(page).to have_text("Unavailable")
    expect(large.size).to be <= small.size + 1
    expect(large.size).to be <= 9
    expect(Current.page_shortcuts_lookup).to be_nil
  end

  it "keeps an outer tenant lookup intact while using the component's own customer and host" do
    other_customer = create(:customer, id: 87654321)
    CustomDomainRecord.create!(hostname: "forms.example.com", customer: customer)
    PageShortcuts::PublicPath.with_lookup(customer_id: other_customer.id, host: "other.example.com") do
      outer_lookup = Current.page_shortcuts_lookup
      with_request_url("/12345678/admin/maintenance/page_shortcuts", host: "forms.example.com") { render_management }

      expect(page).to have_link("/campaign/register", href: "/campaign/register")
      expect(Current.page_shortcuts_lookup).to equal(outer_lookup)
    end
    expect(Current.page_shortcuts_lookup).to be_nil
  end

  it "does not offer a separate domain management link" do
    render_management

    expect(page).to have_no_link("Manage custom domains")
    expect(page).to have_no_css("a[href*='/domains']")
  end
end
