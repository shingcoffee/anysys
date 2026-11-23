# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Entities::Pages", type: :request do
  let(:customer)  { create(:customer) }
  let(:admin)     { create(:user, :admin, customer: customer) }
  let!(:contact)  { create(:entity, customer: customer, name: "Contact", display_label: "Contact") }
  let!(:donation) { create(:entity, customer: customer, name: "Donation", display_label: "Donation") }
  let!(:c1)       { create(:page, customer: customer, entity: contact, name: "Contact Form A", launched: true) }
  let!(:c2)       { create(:page, customer: customer, entity: contact, name: "Contact Form B") }
  let!(:d1)       { create(:page, customer: customer, entity: donation, name: "Donation Page") }
  let(:forms_path) { "/#{customer.id}/admin/entities/#{contact.id}/pages" }

  def table = Nokogiri::HTML(response.body).at_css("#pages-ops-table")

  describe "authorization" do
    let(:guard_path) { forms_path }

    it_behaves_like "an admin-guarded GET"
  end

  context "as an admin" do
    before { sign_in admin }

    it "lists only the entity's forms without repeating the entity on each row" do
      get forms_path

      expect(response).to have_http_status(:ok)
      expect(table.text).to include("Contact Form A", "Contact Form B")
      expect(table.text).not_to include("Donation Page")
      expect(table.css("tbody tr p").map(&:text).join).not_to include("Contact")
      expect(response.body).to include(%(turbo-frame id="page-publishing"))
      name = table.css("a[data-row-link-primary]").find { |link| link.text.include?("Contact Form A") }
      expect(name["href"]).to eq(admin_maintenance_page_preview_path(customer.id, c1))
      expect(name["target"]).to eq("_blank")
      expect(name["rel"].split).to contain_exactly("noopener", "noreferrer")
    end

    it "sits beside the Entries tab, with counts, under the entity header and its Create Entry action" do
      create(:entity_entry, customer: customer, entity: contact)

      get forms_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("main h1").text).to include("Contact")
      entries = doc.at_css("a[data-section-nav-tab='entries']")
      forms = doc.at_css("a[data-section-nav-tab='pages']")
      expect(entries["href"]).to eq("/#{customer.id}/admin/entities/#{contact.id}")
      expect(entries.at_css("[data-role='tab-count']").text).to eq("1")
      expect(forms["aria-current"]).to eq("page")
      expect(forms.at_css("[data-role='tab-count']").text).to eq("2")
      expect(doc.css("main a[href='#{new_admin_entity_entry_path(customer.id, contact)}']")).to be_present
      expect(response.body).not_to include(I18n.t("admin_misc.entities.show.export_csv"))
      expect(doc.at_css("#app-sidebar a[href='/#{customer.id}/admin/entities/#{contact.id}'][aria-current='page']")).to be_present
    end

    it "filters by launch state and searches by name" do
      get forms_path, params: { launched: "true" }
      expect(table.text).to include("Contact Form A")
      expect(table.text).not_to include("Contact Form B")

      get forms_path, params: { q: "Form B" }
      expect(table.text).to include("Contact Form B")
      expect(table.text).not_to include("Contact Form A")
    end

    it "shows an empty state for an entity without forms" do
      lonely = create(:entity, customer: customer, name: "Lonely", display_label: "Lonely")

      get "/#{customer.id}/admin/entities/#{lonely.id}/pages"

      expect(response).to have_http_status(:ok)
      expect(table.text).to include(I18n.t("admin_misc.entities.pages.empty_title"))
    end

    it "serves a shared platform entity" do
      shared = create(:entity, :shared)

      get "/#{customer.id}/admin/entities/#{shared.id}/pages"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for another tenant's entity and for a bridge entity" do
      foreign = create(:entity, customer: create(:customer))
      bridge = create(:entity, customer: customer, category: :bridge)

      get "/#{customer.id}/admin/entities/#{foreign.id}/pages"
      expect(response).to have_http_status(:not_found)

      sign_in admin
      get "/#{customer.id}/admin/entities/#{bridge.id}/pages"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the Entries tab" do
    before { sign_in admin }

    it "links to the entity's Forms tab with its count" do
      get "/#{customer.id}/admin/entities/#{contact.id}"

      forms = Nokogiri::HTML(response.body).at_css("a[data-section-nav-tab='pages']")
      expect(forms["href"]).to eq(forms_path)
      expect(forms.at_css("[data-role='tab-count']").text).to eq("2")
      expect(response.body).to include(I18n.t("admin_misc.entities.show.export_csv"))
    end

    it "shows no tabs for a bridge entity" do
      bridge = create(:entity, customer: customer, category: :bridge)

      get "/#{customer.id}/admin/entities/#{bridge.id}"

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css("a[data-section-nav-tab]")).to be_empty
    end
  end
end
