# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::OpsTableComponent, type: :component do
  let(:customer_id) { 81_721_200 }
  let(:page_live) do
    build_stubbed(:page, :for_member, :launched, name: "Intake Form",
                         updated_at: 2.days.ago)
  end
  let(:page_draft) do
    build_stubbed(:page, name: "Welcome", launched: false,
                         updated_at: 5.hours.ago)
  end

  def render_table(**overrides)
    with_request_url("/#{customer_id}/admin/domains/ungrouped/pages", host: "www.example.com") do
      render_inline(described_class.new(**{
        rows:          [page_live, page_draft],
        pagination:    { page: 1, per_page: 25, total: 2, total_pages: 1 },
        params:        {},
        customer_id:   customer_id,
        base_path:     "/#{customer_id}/admin/domains/ungrouped/pages",
        search:        { param: :q, placeholder: "Search pages…" },
        filters:       [],
        empty_state:   { title: "No pages yet", description: "Nothing here." }
      }.merge(overrides)))
    end
  end

  before { render_table }

  it "renders a card shell inside the pages-ops-table turbo-frame" do
    expect(page).to have_css(%(turbo-frame[id="pages-ops-table"]))
    expect(page).to have_css("section.card")
  end

  it "shows page names and every visible audience without badge clusters" do
    expect(page).to have_text("Intake Form")
    expect(page).to have_text("Welcome")
    expect(page).to have_css("[aria-label='Visible to Admin and Member']")
    expect(page).to have_text("Member")
    expect(page).to have_text("Admin")
    expect(page).not_to have_css("td .badge")
    expect(page).to have_css("table.table-fixed")
  end

  it "shows Live/Draft as dot status pills" do
    expect(page).to have_css("td span.rounded-full.text-success", text: "Live")
    expect(page).to have_css("td span.rounded-full.text-text-secondary", text: "Draft")
    expect(page).not_to have_css(".badge-success")
  end

  it "opens every form name as a preview in a new tab" do
    live_href = "/#{customer_id}/admin/maintenance/pages/#{page_live.id}/preview"
    draft_href = "/#{customer_id}/admin/maintenance/pages/#{page_draft.id}/preview"
    live_links = page.all("a[data-row-link-primary]", text: "Intake Form")
    draft_links = page.all("a[data-row-link-primary]", text: "Welcome")
    expect(live_links.size).to eq(2)
    expect(draft_links.size).to eq(2)
    live_links.each do |link|
      expect(link["href"]).to eq(live_href)
      expect(link["target"]).to eq("_blank")
      expect(link["rel"].split).to contain_exactly("noopener", "noreferrer")
      expect(link["data-turbo-frame"]).to eq("_top")
      expect(link["aria-label"]).to eq(I18n.t("admin_misc.pages.preview_hint", name: "Intake Form"))
    end
    expect(draft_links.map { |link| link["href"] }.uniq).to eq([draft_href])
    expect(page).to have_css("tbody[data-controller='row-link'][data-action='click->row-link#open']")
    expect(page).to have_css("tr[data-row-link-row]", count: 2)
    expect(page).not_to have_css("a[href$='/form']", visible: :all)
    expect(page).not_to have_link(I18n.t("admin_misc.pages.fill_in"), visible: :all)
  end

  it "keeps Manage access in the row menu, opening the publishing frame" do
    manage_href = "/#{customer_id}/admin/pages/#{page_live.id}"
    menu_manage = page.all("[role='menu'] a", text: I18n.t("admin_misc.pages.manage_access"), visible: :all)
    expect(menu_manage.map { |link| link["href"] }).to include(manage_href)
    expect(menu_manage.map { |link| link["data-turbo-frame"] }.uniq).to eq(["page-publishing"])
    expect(page).to have_css("[data-controller='menu-placement']")
    expect(page).not_to have_link(I18n.t("admin_misc.pages.manage_access"))
  end

  it "gives the header cells responsive widths so Form takes the remaining space" do
    headers = page.all("thead th")
    expect(headers.first["class"].split.grep(/\A(\w+:)?w-/)).to be_empty
    expect(headers.drop(1).map { |th| th["class"] }).to match([
      a_string_including("hidden md:table-cell md:w-44"),
      a_string_including("w-28"),
      a_string_including("hidden lg:table-cell lg:w-40"),
      a_string_including("w-12")
    ])
    expect(page).to have_css("tbody td.hidden.md\\:table-cell", count: 2)
    expect(page).to have_css("tbody td.hidden.lg\\:table-cell", count: 2)
  end

  {
    "mobile" => "section.card > div[class~='sm:hidden']",
    "desktop" => "section.card > div[class~='sm:block']"
  }.each do |layout, selector|
    context "#{layout} row menu" do
      let(:responsive_branch) { page.find(selector, visible: :all) }

      it "lists Manage access, Preview and Take offline for a live form" do
        preview_path = "/#{customer_id}/admin/maintenance/pages/#{page_live.id}/preview"
        preview = responsive_branch.find("[role='menu'] a[href='#{preview_path}']", visible: :all)
        expect(preview["target"]).to eq("_blank")
        expect(preview["rel"].split).to contain_exactly("noopener", "noreferrer")
        expect(preview["data-turbo-frame"]).to eq("_top")
        menu_links = preview.find(:xpath, "..", visible: :all).all("a", visible: :all)
        expect(menu_links.map { |item| item.text(:all) }).to eq([
          I18n.t("admin_misc.pages.manage_access"),
          I18n.t("maint_core.pages.preview"),
          I18n.t("admin_misc.pages.take_offline")
        ])
        expect(responsive_branch).not_to have_css("a[href$='/form']", visible: :all)
      end

      it "lists Launch for a draft and still previews in a new tab" do
        preview_path = "/#{customer_id}/admin/maintenance/pages/#{page_draft.id}/preview"
        preview = responsive_branch.find("[role='menu'] a[href='#{preview_path}']", visible: :all)
        menu_links = preview.find(:xpath, "..", visible: :all).all("a", visible: :all)
        expect(menu_links.map { |item| item.text(:all) }).to eq([
          I18n.t("admin_misc.pages.manage_access"), I18n.t("maint_core.pages.preview"), I18n.t("admin_misc.pages.launch")
        ])
      end

      it "translates the menu at render time in Chinese" do
        I18n.with_locale(:"zh-CN") do
          render_table

          preview_path = "/#{customer_id}/admin/maintenance/pages/#{page_live.id}/preview"
          link = responsive_branch.find("[role='menu'] a[href='#{preview_path}']", visible: :all)
          menu_links = link.find(:xpath, "..", visible: :all).all("a", visible: :all)
          expect(menu_links.map { |item| item.text(:all) }).to eq([
            "管理访问", "预览", I18n.t("admin_misc.pages.take_offline")
          ])
          expect(responsive_branch).not_to have_link("Open in new tab", visible: :all)
        end
      end

      context "a different visited customer" do
        let(:customer_id) { 42_424_242 }

        it "uses the visited tenant rather than the owned row's customer for the preview URL" do
          expect(page_live.customer_id).not_to eq(customer_id)
          preview_path = "/#{customer_id}/admin/maintenance/pages/#{page_live.id}/preview"
          expect(responsive_branch).to have_css("a[data-row-link-primary][href='#{preview_path}']", visible: :all)
          expect(responsive_branch).not_to have_css(
            "a[href='/#{page_live.customer_id}/admin/maintenance/pages/#{page_live.id}/preview']", visible: :all
          )
        end

        it "keeps the visited tenant for a shared page with no customer ID" do
          shared_page = build_stubbed(:page, :shared, :for_member, :for_public, :launched)
          render_table(rows: [shared_page])

          expect(shared_page.customer_id).to be_nil
          expect(responsive_branch).to have_css(
            "a[data-row-link-primary][href='/#{customer_id}/admin/maintenance/pages/#{shared_page.id}/preview']",
            visible: :all
          )
        end
      end
    end
  end

  it "renders the shared toolbar and a summary footer" do
    expect(page).to have_css("form[role='search'][data-controller='admin-table'] input[type='search'][name='q']")
    expect(page).to have_css("footer", text: "2 results")
  end

  it "offers rows-per-page choices once there is more than one page" do
    render_table(pagination: { page: 1, per_page: 10, total: 30, total_pages: 3 }, params: { q: "form" })
    expect(page).to have_link("25", href: "/#{customer_id}/admin/domains/ungrouped/pages?per_page=25&q=form", visible: :all)
    expect(page).to have_css("nav[aria-label='#{I18n.t('chrome.pagination.navigation')}']")
  end

  it "marks the active sort column with aria-sort and flips the direction link" do
    render_table(params: { sort: "name", dir: "asc" })
    th = page.find("th[aria-sort='ascending']")
    expect(th).to have_link(href: "/#{customer_id}/admin/domains/ungrouped/pages?dir=desc&sort=name")
    expect(page).to have_css("th[aria-sort]", count: 1)
  end

  it "mounts the tooltip controller and overflow-gated tooltip triggers" do
    expect(page).to have_css("section[data-controller='tooltip']")
    expect(page).to have_css("[data-tooltip-overflow='true']")
  end

  it "sets data-tooltip with the full text on truncated page cells" do
    expect(page).to have_css("td a[data-tooltip='Intake Form'][data-tooltip-overflow='true']")
    expect(page).to have_css("td a[data-tooltip='Welcome'][data-tooltip-overflow='true']")
  end

  it "sets data-tooltip with the joined audience list on the visibility cell" do
    # page_live is member-visible => Admin + Member; page_draft is admin-visible => Admin
    expect(page).to have_css("td [data-tooltip='Admin, Member'][data-tooltip-overflow='true']")
  end

  context "on a single entity's list" do
    it "omits the entity subtitle" do
      page_live.define_singleton_method(:metadata) { { "entity_name" => "Contact" } }
      render_table(show_entity: false, rows: [page_live])
      expect(page).to have_text("Intake Form")
      expect(page).not_to have_text("Contact")
    end
  end

  it "resolves the entity subtitle from the bound entity display_label by entity_id" do
    entity = build_stubbed(:entity, name: "Contacts", display_label: "VIP Contacts")
    allow(page_live).to receive(:entity).and_return(entity)
    render_table(rows: [page_live])
    expect(page).to have_text("VIP Contacts")
  end

  it "shows a form's status badge on both the card and the row" do
    status = Pages::FormHealth::Status.new(kind: :cannot_submit, problems: ["Offline"], built: nil, current: nil, entity_name: nil)
    render_table(statuses: { page_live.id => status })

    expect(page).to have_css(".badge-danger", text: I18n.t("admin_misc.pages.cannot_submit"), count: 2)
  end

  it "shows no status badge without statuses" do
    render_table(statuses: nil)

    expect(page).not_to have_css(".badge-danger, .badge-warning")
  end
end
