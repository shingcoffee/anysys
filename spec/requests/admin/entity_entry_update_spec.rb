# frozen_string_literal: true

require "rails_helper"

# GET /:cid/admin/entities/:entity_id/entries/:id/edit renders the entity's
# launched page prefilled with the entry. The form submits to the page's
# public endpoint naming the entry, which saves it, and the admin comes back
# to the entity's entries.
RSpec.describe "Admin entity entry editing", type: :request do
  include_context "as admin"

  let(:property_schema) do
    [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text",
        "validators" => [{ "type" => "presence" }] },
      { "name" => "Notes", "name_slug" => "notes", "type" => "String", "html_type" => "textarea" },
      { "name" => "Hidden", "name_slug" => "hidden", "type" => "String", "html_type" => "text",
        "visibility" => { "admin" => false, "member" => true, "public" => false } }
    ]
  end
  let!(:entity) do
    create(:entity, customer: customer, name: "PrimaryRecord", property_schema: property_schema.to_json,
                    default_properties: { "title" => "Default title" }.to_json)
  end
  let!(:entry) do
    create(:entity_entry, :with_data, customer: customer, entity: entity,
                                      entry_data: { "title" => "Stored title", "notes" => "Stored notes", "hidden" => "secret" })
  end

  def create_entry_page(modes: nil, **attributes)
    fields = property_schema.map do |attribute|
      { "id" => "f_#{attribute['name_slug']}", "property_slug" => attribute["name_slug"], "source" => "entity",
        "label" => attribute["name"], "html_type" => attribute["html_type"] }
    end
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: entity, launched: true, name: "#{entity.name} form", **attributes,
                    configuration: {
                      form_settings: { modes: modes }.compact,
                      metadata: { entity_id: entity.id, entity_name: entity.name },
                      pages: [{ "id" => "page_1", "fields" => fields }]
                    }.to_json)
    end
  end

  let!(:entry_page) { create_entry_page }
  let(:edit_path) { edit_admin_entity_entry_path(customer.id, entity, entry) }
  def doc = Nokogiri::HTML(response.body)
  def stored_data = entry.reload.data_json

  def submit_path(page = entry_page, entry_id: entry.id)
    "/#{customer.id}/page/#{page.public_uuid}?#{{ entry_id: entry_id, return_to: PageRendering::ENTITY_ENTRY_RETURN }.to_query}"
  end

  describe "authorization" do
    let(:guard_path) { edit_path }

    it_behaves_like "an admin-guarded GET"

    it "redirects a foreign admin to their own tenant even with forged customer IDs" do
      foreign_admin = create(:user, :admin, customer: create(:customer))
      sign_in foreign_admin
      get edit_path, params: { customer_id: foreign_admin.customer_id }

      expect(response).to redirect_to(Authentication::LandingPath.for(foreign_admin))
    end
  end

  describe "record boundary" do
    it "returns 404 for another tenant's entry under this tenant's entity" do
      foreign = create(:entity_entry, :with_data, entity: create(:entity, property_schema: property_schema.to_json),
                                                  entry_data: { "title" => "Foreign" })
      get edit_admin_entity_entry_path(customer.id, entity, foreign)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an entry of a different entity of this tenant" do
      other = create(:entity, customer: customer, property_schema: property_schema.to_json)
      get edit_admin_entity_entry_path(customer.id, other, entry)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an inactive entity" do
      entity.update!(status: :inactive)
      get edit_path

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an entry of a bridge entity" do
      bridge = create(:entity, customer: customer, category: :bridge, property_schema: property_schema.to_json)
      junction = create(:entity_entry, :with_data, customer: customer, entity: bridge, entry_data: { "title" => "Junction" })
      get edit_admin_entity_entry_path(customer.id, bridge, junction)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET edit" do
    it "renders the entity's page with the stored values, submitting the entry to the page" do
      get edit_path

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("main h1").text.strip).to eq(
        I18n.t("admin_misc.entities.entry_form.edit_title", id: entry.id, name: entity.display_label)
      )
      form = doc.at_css("main form[action='#{submit_path}']")
      expect(form["data-turbo-frame"]).to eq("_top")
      expect(form.at_css("input[name='_page_id']")["value"]).to eq(entry_page.id.to_s)
      expect(form.at_css("input[name='entity[title]']")["value"]).to eq("Stored title")
      expect(form.at_css("textarea[name='entity[notes]']").text.strip).to eq("Stored notes")
      expect(form.at_css("[name='entity[hidden]']")).to be_nil
      expect(form.at_css("button[type='submit']").text.strip).to eq(I18n.t("admin_misc.entities.entry_form.update"))
      expect(form.at_css("a[href='#{admin_entity_path(customer.id, entity)}']").text.strip).to eq(I18n.t("common.actions.cancel"))
      expect(doc.at_css("dialog#entity-quick-add-dialog-0")).to be_present
    end

    it "keeps a stored blank value instead of the entity's default" do
      entry.update!(data: { "title" => "", "notes" => "Stored notes" }.to_json)
      get edit_path

      expect(doc.at_css("input[name='entity[title]']")["value"]).to be_blank
    end

    it "uses Rails negotiation for an unsupported JSON form response" do
      get edit_path, as: :json

      expect(response).to have_http_status(:not_acceptable)
    end

    it "shows an empty state when the entity's page only creates" do
      entry_page.destroy!
      create_entry_page(modes: ["create"])
      get edit_path

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("main h3").text).to eq(I18n.t("admin_misc.entities.entry_page.missing_title"))
      expect(doc.at_css("main form[action*='/page/']")).to be_nil
    end
  end

  describe "submitting the page" do
    it "updates the entry through the page and returns to the entity with the updated notice" do
      expect {
        post submit_path, params: { _page_id: entry_page.id, entity: { title: "Edited title", notes: "Edited notes" } }
      }.not_to change(EntityEntry, :count)

      expect(stored_data).to eq("title" => "Edited title", "notes" => "Edited notes", "hidden" => "secret")
      expect(response).to redirect_to(admin_entity_path(customer.id, entity))
      expect(flash[:notice]).to eq(I18n.t("admin_misc.entities.entry_form.updated"))
    end

    it "returns to the edit form with the error when the entity rejects the submission" do
      post submit_path, params: { _page_id: entry_page.id, entity: { title: "" } }

      expect(stored_data["title"]).to eq("Stored title")
      expect(URI(response.location).path).to eq(edit_path)
      expect(flash[:alert]).to eq(I18n.t("public_views.flash.response_field_errors"))
      follow_redirect!
      expect(doc.at_css("#f_title_errors").text).to include("can't be blank")
      expect(doc.at_css("#f_title")["value"]).to eq("")
    end

    it "lets the pinned owner edit another tenant's entry under that tenant's URL" do
      sign_in find_or_create_platform_owner

      post submit_path, params: { entity: { title: "Owner edit" } }

      expect(stored_data["title"]).to eq("Owner edit")
      expect(entry.reload.customer_id).to eq(customer.id)
    end

    it "never writes an entry outside the tenant and the page's entity, nor for a malformed id" do
      foreign = create(:entity_entry, :with_data, entity: create(:entity, property_schema: property_schema.to_json),
                                                  entry_data: { "title" => "Foreign" })
      sibling = create(:entity_entry, :with_data, customer: customer,
                                                  entity: create(:entity, customer: customer, property_schema: property_schema.to_json),
                                                  entry_data: { "title" => "Sibling" })

      expect {
        [foreign.id, sibling.id, "#{entry.id}abc", "0"].each do |entry_id|
          post submit_path(entry_id: entry_id), params: { entity: { title: "Forged" } }
        end
      }.not_to change(EntityEntry, :count)

      expect([foreign, sibling, entry].map { |record| record.reload.data_json["title"] }).to eq(%w[Foreign Sibling Stored\ title])
    end

    it "never lets a member name an entry to edit" do
      entry_page.update!(audience_member: true)
      sign_in create(:user, :member, customer: customer)

      expect {
        post submit_path, params: { entity: { title: "Member edit" } }
      }.not_to change(EntityEntry, :count)

      expect(stored_data["title"]).to eq("Stored title")
    end
  end

  describe "entries browser" do
    it "offers row edit links and detail-page Edit / Delete header actions for an active entity" do
      get admin_entity_path(customer.id, entity)
      expect(doc.css("a[href='#{edit_path}'][data-turbo-frame='_top']")).not_to be_empty

      get admin_entity_entry_path(customer.id, entity, entry)
      expect(doc.at_css("a.btn[href='#{edit_path}']")).to be_present
      delete = doc.at_css("a.btn[href='#{admin_entity_entry_path(customer.id, entity, entry)}'][data-turbo-method='delete']")
      expect(delete["data-turbo-confirm"]).to eq(I18n.t("comp_admin.entries_table.delete_entry_confirm"))
    end

    it "hides Edit for a bridge entity's entry but keeps Delete on the detail page" do
      bridge = create(:entity, customer: customer, category: :bridge, property_schema: property_schema.to_json)
      junction = create(:entity_entry, :with_data, customer: customer, entity: bridge, entry_data: { "title" => "Junction" })

      get admin_entity_entry_path(customer.id, bridge, junction)

      expect(doc.css("a.btn").map { |link| link.text.strip }).to eq([I18n.t("common.actions.delete")])
    end
  end
end
