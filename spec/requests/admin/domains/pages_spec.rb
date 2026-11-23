# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Domains::Pages", type: :request do
  let(:customer)  { create(:customer) }
  let(:admin)     { create(:user, :admin, customer: customer) }
  let!(:contact)  { create(:entity, customer: customer, name: "Contact", display_label: "Contact") }
  let!(:donation) { create(:entity, customer: customer, name: "Donation", display_label: "Donation") }
  let!(:c1)       { create(:page, customer: customer, entity: contact,  name: "Contact Form A") }
  let!(:d1)       { create(:page, customer: customer, entity: donation, name: "Donation Page") }
  let(:forms_path) { "/#{customer.id}/admin/domains/ungrouped/pages" }

  def table = Nokogiri::HTML(response.body).at_css("#pages-ops-table")

  describe "authorization" do
    let(:guard_path) { forms_path }

    it_behaves_like "an admin-guarded GET"
  end

  context "without domains" do
    before { sign_in admin }

    it "lists every form on the one section's Forms tab with audiences, status and entity" do
      c1.update!(visible_audiences: %w[admin member public])

      get forms_path

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("main h1").text).to include(I18n.t("admin_misc.domains.title"))
      expect(response.body).to include(%(turbo-frame id="pages-ops-table"), %(turbo-frame id="page-publishing"))
      row = doc.css("tbody tr").find { |tr| tr.text.include?("Contact Form A") }
      expect(row.text).to include("Admin", "Member", "Public", "Contact")
      expect(response.body).to include("Visible to Admin, Member, and Public")
      expect(table.text).to include("Donation Page")
      expect(doc.css("thead th").map { |th| th.text.squish }).to include("Page")
      expect(response.body).to include(I18n.t("admin_misc.pages.filters.launch_label"))
    end

    it "heads the list with the section's totals and no Record types / Pages tabs" do
      get forms_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("[data-role='stat-record_types'] dd").text.strip).to eq("2")
      expect(doc.at_css("[data-role='stat-pages'] dd").text.strip).to eq("2")
      expect(doc.at_css("[data-section-nav-tab]")).to be_nil
    end

    it "keeps the Domains menu and sidebar active and offers no Create Entity action" do
      get forms_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("a[data-menu-item-key='entities'][aria-current='page']")).to be_present
      expect(response.body).not_to include(I18n.t("admin_misc.entities.create_entity"))
    end

    it "shows translated wording in Chinese" do
      get forms_path, params: { locale: "zh-CN" }

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("thead th").map(&:text).join).to include("页面")
      expect(doc.at_css("[data-role='stat-record_types'] dt").text).to include("记录类型")
    end

    it "filters by launch state and searches by name" do
      d1.update!(launched: true)

      get forms_path, params: { launched: "true" }
      expect(table.text).to include("Donation Page")
      expect(table.text).not_to include("Contact Form A")

      get forms_path, params: { q: "Contact" }
      expect(table.text).to include("Contact Form A")
      expect(table.text).not_to include("Donation Page")
    end

    it "is ops-only: Manage access and Preview, but no New Page or Edit" do
      get forms_path

      expect(response.body).not_to include(I18n.t("admin_misc.pages.new_page"))
      expect(response.body).not_to include(edit_admin_maintenance_page_path(customer.id, c1))
      expect(response.body).to include(I18n.t("admin_misc.pages.manage_access"), I18n.t("maint_core.pages.preview"))
      expect(response.body).to include(admin_page_path(customer.id, c1))
    end

    it "flags a launched form that can't be submitted" do
      contact.update!(property_schema: [
        { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text",
          "validators" => [{ "type" => "presence" }] }
      ].to_json)
      create(:page, customer: customer, entity: contact, name: "Intake", launched: true)

      get forms_path

      expect(table.text).to include(I18n.t("admin_misc.pages.cannot_submit"))
    end
  end

  context "with domains" do
    let!(:fundraising) { create(:entity_domain, customer: customer, name: "Fundraising", color: "rose") }

    before do
      EntityDomainMembership.create!(customer: customer, entity_domain: fundraising, entity: donation)
      sign_in admin
    end

    it "lists only the forms of the domain's entities under a header naming the domain" do
      get "/#{customer.id}/admin/domains/#{fundraising.id}/pages"

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("main h1").text).to include("Fundraising")
      expect(table.text).to include("Donation Page")
      expect(table.text).not_to include("Contact Form A")
    end

    it "lists ungrouped entities' forms and unbound forms on the Other section" do
      orphan = create(:page, customer: customer, entity: contact, name: "Orphan Form")
      orphan.entity_id = nil
      orphan.save!(validate: false)

      get forms_path

      expect(Nokogiri::HTML(response.body).at_css("main h1").text).to include(I18n.t("chrome.sidebar.entities.ungrouped"))
      expect(table.text).to include("Contact Form A", "Orphan Form")
      expect(table.text).not_to include("Donation Page")
      expect(table.text).to include(I18n.t("admin_misc.pages.uncategorized.row_subtitle"))
    end

    it "keeps the Other section for unbound forms once every entity sits in a domain" do
      EntityDomainMembership.create!(customer: customer, entity_domain: fundraising, entity: contact)
      orphan = create(:page, customer: customer, entity: contact, name: "Orphan Form")
      orphan.entity_id = nil
      orphan.save!(validate: false)

      get forms_path

      expect(response).to have_http_status(:ok)
      expect(table.text).to include("Orphan Form")
      expect(table.text).not_to include("Contact Form A", "Donation Page")
      other = Nokogiri::HTML(response.body).at_css("#app-sidebar a[href='#{"/#{customer.id}/admin/domains/ungrouped"}']")
      expect(other).to be_present
    end

    it "returns 404 for an unknown or foreign domain" do
      foreign = create(:entity_domain, customer: create(:customer), name: "Foreign")

      get "/#{customer.id}/admin/domains/#{foreign.id}/pages"
      expect(response).to have_http_status(:not_found)

      sign_in admin
      get "/#{customer.id}/admin/domains/999999/pages"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "preview — name opens the form in a new tab" do
    before { sign_in admin }

    def preview_href(page_record) = admin_maintenance_page_preview_path(customer.id, page_record)

    def name_links_for(page_record)
      table.css("a[data-row-link-primary]").select { |link| link.text.include?(page_record.name) }
    end

    it "opens a live form's name as a preview in a new tab" do
      c1.update!(launched: true, visible_audiences: %w[admin member])

      get forms_path

      links = name_links_for(c1)
      expect(links.map { |link| link["href"] }.uniq).to eq([preview_href(c1)])
      links.each do |link|
        expect(link["target"]).to eq("_blank")
        expect(link["rel"].split).to contain_exactly("noopener", "noreferrer")
        expect(link["data-turbo-frame"]).to eq("_top")
        expect(link["aria-label"]).to eq(I18n.t("admin_misc.pages.preview_hint", name: c1.name))
      end
      expect(table.css("a[href$='/form']")).to be_empty
      expect(table.css("details a[href='#{preview_href(c1)}']").map(&:text).uniq)
        .to eq([I18n.t("maint_core.pages.preview")])
    end

    it "keeps a shared form's preview in the visited tenant" do
      shared_page = Current.set(customer: nil, shared_resources_mode: true) do
        create(:page, :shared, :for_member, :for_public, name: "Shared admin page", launched: true)
      end

      get forms_path

      expect(name_links_for(shared_page).map { |link| link["href"] }.uniq).to eq([preview_href(shared_page)])
    end

    it "previews a draft from its name" do
      get forms_path

      links = name_links_for(c1)
      expect(links.map { |link| link["href"] }.uniq).to eq([preview_href(c1)])
      expect(links.map { |link| link["target"] }.uniq).to eq(["_blank"])
    end

    it "localizes the preview name in Chinese" do
      get forms_path, params: { locale: "zh-CN" }

      expect(name_links_for(c1).map { |link| link["aria-label"] }.uniq)
        .to eq([I18n.t("admin_misc.pages.preview_hint", name: c1.name, locale: :"zh-CN")])
    end
  end

  describe "cross-tenant isolation" do
    before { sign_in admin }

    it "excludes another tenant's live form" do
      other_customer = create(:customer)
      other_page = create(:page, customer: other_customer, launched: true)

      get forms_path

      expect(table.text).not_to include(other_page.name)
      expect(table.css("a[href*='/pages/#{other_page.id}']")).to be_empty
    end
  end
end
