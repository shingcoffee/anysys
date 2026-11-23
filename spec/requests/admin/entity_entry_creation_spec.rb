# frozen_string_literal: true

require "rails_helper"

# GET /:cid/admin/entities/:entity_id/entries/new renders the entity's
# launched create page. The form submits to the page's public endpoint, which
# saves the entry, and the admin comes back to the entity's entries area.
RSpec.describe "Admin entity entry creation", type: :request do
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
    create(:entity, customer: customer, name: "PrimaryRecord",
                    property_schema: property_schema.to_json,
                    default_properties: { "title" => "Default title" }.to_json)
  end

  def entity_fields(for_entity)
    Array(for_entity.property_schema_json).map do |attribute|
      { "id" => "f_#{attribute['name_slug']}", "property_slug" => attribute["name_slug"], "source" => "entity",
        "label" => attribute["name"], "html_type" => attribute["html_type"] || "text",
        "dynamic_options" => attribute.dig("config", "options_source") ? attribute["config"] : nil }.compact
    end
  end

  def create_entry_page(for_entity = entity, modes: nil, **attributes)
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: for_entity, launched: true, name: "#{for_entity.name} form", **attributes,
                    configuration: {
                      form_settings: { modes: modes }.compact,
                      metadata: { entity_id: for_entity.id, entity_name: for_entity.name },
                      pages: [{ "id" => "page_1", "fields" => entity_fields(for_entity) }]
                    }.to_json)
    end
  end

  let!(:entry_page) { create_entry_page }
  let(:new_path) { new_admin_entity_entry_path(customer.id, entity) }
  def doc = Nokogiri::HTML(response.body)

  def submit_path(page = entry_page, **query)
    "/#{customer.id}/page/#{page.public_uuid}?#{{ return_to: PageRendering::ENTITY_ENTRY_RETURN, **query }.to_query}"
  end

  def frame_headers(depth = 0) = { "Turbo-Frame" => Admin::Entities::QuickAddDialogComponent.frame_id(depth) }

  describe "GET new authorization" do
    it "redirects an anonymous browser to sign in" do
      sign_out admin
      get new_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "returns 401 for an anonymous JSON request" do
      sign_out admin
      get new_path, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "redirects a same-tenant member to their member landing page" do
      member = create(:user, :member, customer: customer)
      sign_in member
      get new_path

      expect(response).to redirect_to(Authentication::LandingPath.for(member))
    end

    it "redirects a foreign admin to their own tenant even with forged customer IDs" do
      foreign_admin = create(:user, :admin, customer: create(:customer))
      sign_in foreign_admin
      get new_path, params: { customer_id: foreign_admin.customer_id }

      expect(response).to redirect_to(Authentication::LandingPath.for(foreign_admin))
    end

    it "returns 403 for a foreign admin's JSON request" do
      sign_in create(:user, :admin, customer: create(:customer))
      get new_path, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to include("error" => "access_denied")
    end
  end

  describe "GET new entity boundary" do
    it "returns 404 for a missing path entity" do
      get new_admin_entity_entry_path(customer.id, 0), params: { entity_id: entity.id }

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for another tenant's entity on the authorized tenant path" do
      foreign = create(:entity, customer: create(:customer), property_schema: property_schema.to_json)
      get new_admin_entity_entry_path(customer.id, foreign.id)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an inactive entity" do
      entity.update!(status: :inactive)
      get new_path

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a bridge entity" do
      bridge = create(:entity, customer: customer, category: :bridge)
      get new_admin_entity_entry_path(customer.id, bridge.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET new" do
    it "renders the entity's create page in the dashboard, submitting to the page with the entity-entry return" do
      get new_path, headers: { "Turbo-Frame" => "entity-entry-detail" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<!DOCTYPE html>")
      form = doc.at_css("main form[action='#{submit_path}']")
      expect(form["data-turbo-frame"]).to eq("_top")
      expect(form.at_css("input[name='_page_id']")["value"]).to eq(entry_page.id.to_s)
      expect(form.at_css("input[name='entity[title]']")["value"]).to eq("Default title")
      expect(form.at_css("textarea[name='entity[notes]']")).to be_present
      expect(form.at_css("[name='entity[hidden]']")).to be_nil
      expect(form.css("[name^='entry[data]']")).to be_empty
      expect(form.at_css("a[href='#{admin_entity_path(customer.id, entity)}']").text.strip).to eq(I18n.t("common.actions.cancel"))
      expect(doc.at_css("main h1").text).to include(I18n.t("admin_misc.entities.entry_form.title", name: entity.display_label))
      expect(doc.at_css("dialog#entity-quick-add-dialog-0 turbo-frame#entity-quick-add-frame-0")).to be_present
    end

    it "prefills from the query like the page form" do
      get new_path, params: { prefill: { title: "From query" } }

      expect(doc.at_css("input[name='entity[title]']")["value"]).to eq("From query")
    end

    it "uses Rails negotiation for an unsupported JSON form response" do
      get new_path, as: :json

      expect(response).to have_http_status(:not_acceptable)
    end

    it "shows an empty state when the entity has no usable create page" do
      other = create(:entity, customer: customer, name: "Other", property_schema: property_schema.to_json)
      drafts = {
        "a draft" => -> { create_entry_page(launched: false) },
        "a page hidden from admins" => -> { create_entry_page(audience_admin: false, audience_member: true) },
        "an update-only page" => -> { create_entry_page(modes: ["update"]) },
        "another entity's page" => -> { create_entry_page(other) }
      }
      entry_page.destroy!

      drafts.each do |label, build|
        build.call
        get new_path

        expect(response).to have_http_status(:ok), label
        expect(doc.at_css("main h3").text).to eq(I18n.t("admin_misc.entities.entry_page.missing_title")), label
        expect(doc.at_css("main form[action*='/page/']")).to be_nil, label
      end
    end
  end

  describe "submitting the page" do
    it "creates the entry through the page and lands on it with the created notice" do
      expect {
        post submit_path, params: { _page_id: entry_page.id, entity: { title: "New record", notes: "Some notes" } }
      }.to change(EntityEntry.where(customer_id: customer.id, entity_id: entity.id), :count).by(1)

      entry = EntityEntry.order(:id).last
      expect(entry.data_json).to include("title" => "New record", "notes" => "Some notes")
      expect(response).to redirect_to(admin_entity_entry_path(customer.id, entity, entry))
      expect(flash[:notice]).to eq(I18n.t("admin_misc.entities.entry_form.created"))
      expect(flash[:reveal_section]).to be_nil
    end

    it "returns to the entry form with the typed values and each error beside its field" do
      expect {
        post submit_path, params: { _page_id: entry_page.id, entity: { title: "", notes: "Keep these notes" } }
      }.not_to change(EntityEntry, :count)

      expect(URI(response.location).path).to eq(new_path)
      expect(Rack::Utils.parse_query(URI(response.location).query)["run"]).to be_present
      expect(flash[:alert]).to eq(I18n.t("public_views.flash.response_field_errors"))
      follow_redirect!
      expect(response.body).to include(CGI.escapeHTML(flash[:alert]))
      expect(doc.at_css("#f_title_errors").text).to include("can't be blank")
      expect(doc.at_css("#f_title")["aria-describedby"]).to include("f_title_errors")
      expect(doc.at_css("textarea[name='entity[notes]']").text.strip).to eq("Keep these notes")

      get response.request.fullpath
      expect(doc.at_css("#f_title_errors")).to be_nil
    end

    it "returns to the entity's Forms tab without the entity-entry token" do
      post "/#{customer.id}/page/#{entry_page.public_uuid}", params: { entity: { title: "Elsewhere" } }

      expect(response).to redirect_to(admin_entity_pages_path(customer.id, entity))
    end

    it "ignores the entity-entry token for a member" do
      entry_page.update!(audience_member: true)
      sign_in create(:user, :member, customer: customer)

      post submit_path, params: { entity: { title: "Member record" } }

      expect(response).to redirect_to(member_page_path(customer_id: customer.id, id: entry_page.id))
    end
  end

  describe "+ Add New dialog" do
    def frame = doc.at_css("turbo-frame#entity-quick-add-frame-0")

    it "renders only the dialog frame with the page form submitting into it" do
      get new_path, params: { label_field: "title" }, headers: frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("app-sidebar")
      form = frame.at_css("form")
      expect(form["action"]).to eq(submit_path(label_field: "title"))
      expect(form["data-turbo-frame"]).to be_nil
      expect(form.at_css("input[name='entity[title]']")["value"]).to eq("Default title")
      expect(frame.at_css("button[data-action='entity-quick-add-dialog#close']").text.squish).to eq(I18n.t("common.actions.cancel"))
      expect(frame.at_css("dialog#entity-quick-add-dialog-1 turbo-frame#entity-quick-add-frame-1")).to be_present
    end

    it "hands the saved entry back to the dialog through its frame" do
      post submit_path(label_field: "title"), params: { entity: { title: "Quick record" } }, headers: frame_headers
      entry = EntityEntry.order(:id).last
      expect(response).to redirect_to(admin_entity_entry_path(customer.id, entity, entry, label_field: "title"))

      get response.location, headers: frame_headers

      marker = frame.at_css("[data-entity-quick-add-dialog-target='created']")
      expect(marker["data-entry-id"]).to eq(entry.id.to_s)
      expect(marker["data-entry-label"]).to eq("Quick record")
      expect(marker.text.squish).to eq(I18n.t("admin_misc.entities.entry_form.created"))
    end

    it "labels the entry by id when the label field is not visible to admins, and numbers a taken label" do
      hidden = create(:entity_entry, customer: customer, entity: entity, data: { "title" => "Taken" }.to_json)
      taken = create(:entity_entry, customer: customer, entity: entity, data: { "title" => "Taken" }.to_json)

      get admin_entity_entry_path(customer.id, entity, hidden, label_field: "hidden"), headers: frame_headers
      expect(frame.at_css("[data-entry-label]")["data-entry-label"]).to eq("Untitled (##{hidden.id})")

      get admin_entity_entry_path(customer.id, entity, taken, label_field: "title"), headers: frame_headers
      expect(frame.at_css("[data-entry-label]")["data-entry-label"]).to eq("Taken (##{taken.id})")
    end

    it "shows the entry page, not the marker, for requests from other frames" do
      entry = create(:entity_entry, customer: customer, entity: entity, data: { "title" => "Shown" }.to_json)

      ["something-else", "entity-quick-add-frame", "entity-quick-add-frame-99"].each do |other|
        get admin_entity_entry_path(customer.id, entity, entry), headers: { "Turbo-Frame" => other }

        expect(response.body).to include("Shown")
        expect(response.body).not_to include("data-entity-quick-add-dialog-target=\"created\"")
      end
    end

    it "returns a rejected submission to the frame's form with the error" do
      post submit_path(label_field: "title"), params: { entity: { title: "" } }, headers: frame_headers
      expect(URI(response.location).path).to eq(new_admin_entity_entry_path(customer.id, entity))
      expect(Rack::Utils.parse_query(URI(response.location).query)).to include("label_field" => "title")
      alert = flash[:alert]

      get response.location, headers: frame_headers

      expect(frame.text).to include(alert)
      expect(frame.text).to include("can't be blank")
      expect(frame.at_css("form[action='#{submit_path(label_field: 'title')}']")).to be_present
    end

    it "shows the empty state in the frame when the entity has no create page" do
      entry_page.destroy!

      get new_path, headers: frame_headers

      expect(frame.at_css("h3").text).to eq(I18n.t("admin_misc.entities.entry_page.missing_title"))
      expect(frame.at_css("form, dialog")).to be_nil
    end
  end

  describe "+ Add New on reference dropdowns, nested per referenced entity" do
    let(:teacher) do
      create(:entity, customer: customer, name: "Teacher",
                      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end
    let(:course) do
      create(:entity, customer: customer, name: "Course", property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Teacher", "name_slug" => "teacher", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => teacher.id.to_s, "label_field" => "name" } }
      ].to_json)
    end
    def quick_add = doc.at_css("[data-controller='entity-quick-add']")

    before { create_entry_page(course) }

    it "opens the referenced entity's form in the first dialog from the full page" do
      get new_admin_entity_entry_path(customer.id, course)

      expect(quick_add["data-entity-quick-add-url-value"]).to eq(new_admin_entity_entry_path(customer.id, teacher, label_field: "name"))
      expect(quick_add["data-entity-quick-add-entity-quick-add-dialog-outlet"]).to eq("#entity-quick-add-dialog-0")
      expect(quick_add.css("select option").last.text).to eq(I18n.t("admin_misc.entities.quick_add.option"))
    end

    it "opens the next level from a dialog, with that level's dialog inside the frame" do
      get new_admin_entity_entry_path(customer.id, course, label_field: "title"), headers: frame_headers(2)

      frame = doc.at_css("turbo-frame#entity-quick-add-frame-2")
      expect(frame.at_css("form [data-controller='entity-quick-add']")["data-entity-quick-add-entity-quick-add-dialog-outlet"])
        .to eq("#entity-quick-add-dialog-3")
      expect(frame.at_css("form dialog")).to be_nil
      expect(frame.at_css("dialog#entity-quick-add-dialog-3 turbo-frame#entity-quick-add-frame-3")).to be_present
    end

    it "offers no further level at the deepest dialog" do
      max = Admin::Entities::QuickAddDialogComponent::MAX_DEPTH
      get new_admin_entity_entry_path(customer.id, course), headers: frame_headers(max)

      expect(doc.at_css("turbo-frame#entity-quick-add-frame-#{max} select[name='entity[teacher]']")).to be_present
      expect(doc.css("[data-controller='entity-quick-add'], dialog")).to be_empty
    end
  end

  describe "existing entry actions with forged query/body IDs" do
    let!(:entry) { create(:entity_entry, customer: customer, entity: entity, data: { "title" => "Path entry" }.to_json) }
    let!(:other_entity) { create(:entity, customer: customer, property_schema: property_schema.to_json) }
    let!(:other_entry) do
      create(:entity_entry, customer: customer, entity: other_entity, data: { "title" => "Other entry" }.to_json)
    end
    let(:forged) { { customer_id: create(:customer).id, entity_id: other_entity.id, id: other_entry.id } }

    it "shows the path-scoped entry" do
      get admin_entity_entry_path(customer.id, entity, entry), params: forged

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Path entry")
      expect(response.body).not_to include("Other entry")
    end

    it "destroys only the path-scoped entry" do
      expect {
        delete admin_entity_entry_path(customer.id, entity, entry), params: forged
      }.to change(EntityEntry, :count).by(-1)

      expect(response).to redirect_to(admin_entity_path(customer.id, entity))
      expect(EntityEntry.exists?(entry.id)).to be(false)
      expect(EntityEntry.exists?(other_entry.id)).to be(true)
    end

    it "keeps batch deletion within the path entity" do
      expect {
        delete batch_admin_entity_entries_path(customer.id, entity), params: forged.merge(ids: [entry.id, other_entry.id])
      }.to change(EntityEntry, :count).by(-1)

      expect(response).to redirect_to(admin_entity_path(customer.id, entity))
      expect(EntityEntry.exists?(entry.id)).to be(false)
      expect(EntityEntry.exists?(other_entry.id)).to be(true)
    end
  end
end
