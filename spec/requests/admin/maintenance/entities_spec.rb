# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Entities", type: :request do
  include_context "as admin"

  let!(:entity) { create(:entity, customer: customer) }
  let!(:entity_domain) { create(:entity_domain, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }

  # Only the platform owner creates entities by hand; tenant admins use the assistant.
  before(:each, :entity_author) { sign_in platform_owner }

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "authorization guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET new — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/new" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/#{entity.id}/edit" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "POST create — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities" }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/#{entity.id}" }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "GET show — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/#{entity.id}" }

    it_behaves_like "an admin-guarded GET"
  end

  # ---------------------------------------------------------------------------
  # GET index — HTML
  # ---------------------------------------------------------------------------

  describe "GET index — HTML" do
    it "includes bridge entities when show_bridge=true" do
      bridge = create(:entity, customer: customer,
                               name: "BridgeEnt",
                               category: :bridge)

      get "/#{customer.id}/admin/maintenance/entities", params: { show_bridge: "true" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("BridgeEnt")
    end

    it "renders the Current Version column when rows exist" do
      get "/#{customer.id}/admin/maintenance/entities"
      expect(response.body).to include("Current Version")
    end

    it "renders version info for an entity that has a snapshot" do
      content = entity.content_class.store!(customer_id: entity.customer_id, payload: { "_marker" => SecureRandom.hex(8) })
      entity.commit_version!(description: "v1", content: content)
      get "/#{customer.id}/admin/maintenance/entities"
      expect(response.body).to include("v1")
    end
  end

  # ---------------------------------------------------------------------------
  # GET index — JSON
  # ---------------------------------------------------------------------------

  describe "GET index — JSON" do
    it "returns palette items as JSON" do
      get "/#{customer.id}/admin/maintenance/entities.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_an(Array)
    end

    it "filters by name when search param is present" do
      create(:entity, customer: customer, name: "SearchableEntity")
      create(:entity, customer: customer, name: "OtherEntity")

      get "/#{customer.id}/admin/maintenance/entities.json", params: { search: "Searchable" }

      names = response.parsed_body.map { |e| e["name"] }
      expect(names).to include("SearchableEntity")
      expect(names).not_to include("OtherEntity")
    end

    it "does not 500 when search is an array" do
      create(:entity, customer: customer, name: "SearchableEntity")

      get "/#{customer.id}/admin/maintenance/entities.json", params: { search: ["Searchable"] }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |e| e["name"] }).to include("SearchableEntity")
    end
  end

  # ---------------------------------------------------------------------------
  # GET show / new / edit
  # ---------------------------------------------------------------------------

  describe "GET show, new, and edit HTML" do
    it "shows the base model an extension entity extends" do
      enable_module!("authentication", customer)
        .set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
      student = create(:entity, customer: customer, name: "Student",
                                extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)

      get "/#{customer.id}/admin/maintenance/entities/#{student.id}"

      document = Capybara.string(response.body)
      expect(document).to have_css("[data-role='extends-badge']", text: "Extends User")
      expect(document).to have_css("[data-role='base-model']", text: "User")
      expect(document).to have_css("[data-role='base-model']", text: "(authentication)")
    end

    it "returns 200 for each form page", :entity_author do
      [
        "/#{customer.id}/admin/maintenance/entities/#{entity.id}",
        "/#{customer.id}/admin/maintenance/entities/new",
        "/#{customer.id}/admin/maintenance/entities/#{entity.id}/edit"
      ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
      end
    end

    it "carries a status lifecycle through the editor and summarises it", :entity_author do
      lifecycle = { "transitions" => [{ "from" => "draft", "to" => "submitted", "by" => ["member"] }] }
      application = create(:entity, customer: customer, name: "Application", property_schema: [
        { "name" => "Status", "name_slug" => "status", "html_type" => "select",
          "config" => { "source" => "manual", "options" => [{ "label" => "Draft", "value" => "draft", "default" => true },
                                                            { "label" => "Submitted", "value" => "submitted" }] },
          "lifecycle" => lifecycle }
      ].to_json)

      get "/#{customer.id}/admin/maintenance/entities/#{application.id}/edit"

      document = Capybara.string(response.body)
      expect(JSON.parse(document.find("input[data-input='lifecycle']", visible: :all).value)).to eq(lifecycle)
      expect(document).to have_css("[data-field='lifecycle'] summary", text: "1 status change")
    end
  end

  describe "GET show — JSON" do
    it "returns the palette item with referenced_template" do
      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}.json"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(entity.id)
      expect(body).to have_key("referenced_template")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create
  # ---------------------------------------------------------------------------

  describe "POST create — valid params", :entity_author do
    it "creates an entity and redirects to index" do
      expect {
        post "/#{customer.id}/admin/maintenance/entities",
             params: { entity_domain_id: entity_domain.id, entity: { name: "New Entity" } }
      }.to change(Entity, :count).by_at_least(1)

      expect(response).to have_http_status(:redirect)
    end

    it "creates a version snapshot for a new non-bridge entity" do
      expect {
        post "/#{customer.id}/admin/maintenance/entities",
             params: { entity_domain_id: entity_domain.id, entity: { name: "Versioned Entity", description: "Test entity" } }
      }.to change(EntityVersion, :count).by(1)
    end

    it "still auto-commits a v1 for a bridge entity" do
      bridge = Entity.create!(name: "Bridge Entity", customer: customer, category: :bridge)
      expect(bridge.entity_versions.count).to eq(1)
    end
  end

  describe "POST create — JSON success", :entity_author do
    it "returns 201 with palette item" do
      post "/#{customer.id}/admin/maintenance/entities.json",
           params: { entity_domain_id: entity_domain.id, entity: { name: "JsonEntity" } }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("JsonEntity")
    end
  end

  describe "POST create — invalid params (blank name)", :entity_author do
    it "re-renders new with 422" do
      post "/#{customer.id}/admin/maintenance/entities",
           params: { entity_domain_id: entity_domain.id, entity: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST create — JSON invalid params", :entity_author do
    it "returns 422 with errors" do
      post "/#{customer.id}/admin/maintenance/entities.json",
           params: { entity_domain_id: entity_domain.id, entity: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to have_key("errors")
    end
  end

  describe "POST create — duplicate name allowed", :entity_author do
    it "allows creating two entities with the same name for the same customer" do
      create(:entity, customer: customer, name: "Donor Profile")

      expect {
        post "/#{customer.id}/admin/maintenance/entities",
             params: { entity_domain_id: entity_domain.id, entity: { name: "Donor Profile" } }
      }.to change(Entity, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST create — referenced_template persistence", :entity_author do
    it "persists referenced_template JSON with key blank" do
      template_json = '{"key":"blank","name":"Blank Canvas"}'
      post "/#{customer.id}/admin/maintenance/entities",
           params: { entity_domain_id: entity_domain.id, entity: { name: "Blank Template Entity", referenced_template: template_json } }

      created = Entity.unscoped.find_by!(name: "Blank Template Entity")
      expect(JSON.parse(created.referenced_template)["key"]).to eq("blank")
    end

    it "stores an empty referenced_template as an empty string" do
      post "/#{customer.id}/admin/maintenance/entities",
           params: { entity_domain_id: entity_domain.id, entity: { name: "Empty Template Entity", referenced_template: "" } }

      created = Entity.unscoped.find_by!(name: "Empty Template Entity")
      expect(created.referenced_template).to eq("")
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH update
  # ---------------------------------------------------------------------------

  describe "PATCH update — HTML valid" do
    it "updates name and redirects to show" do
      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}",
            params: { entity: { name: "Renamed Entity" } }

      expect(response).to have_http_status(:redirect)
      expect(entity.reload.name).to eq("Renamed Entity")
    end

    it "creates a version snapshot when a versioned column changes" do
      expect {
        patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}",
              params: { entity: { name: "Updated Name", description: "Test" } }
      }.to change { entity.entity_versions.count }.by(1)
    end

    it "sets the created version as the default version" do
      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}",
            params: { entity: { name: "New Name", description: "Test" } }
      entity.reload
      expect(entity.current_version).not_to be_nil
      expect(entity.current_version.version_number).to eq(entity.entity_versions.maximum(:version_number))
    end
  end

  describe "PATCH update — JSON valid" do
    it "returns 200 with palette item" do
      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}.json",
            params: { entity: { name: "RenamedJson" } }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("RenamedJson")
    end
  end

  describe "PATCH update — extended_model (base-model selection)" do
    before { enable_module!("payment", customer).set_extendable_model!("Payments::Order", true) }

    it "persists the selected base model and derives the extension category" do
      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}",
            params: { entity: { extended_model: "Payments::Order" } }

      expect(entity.reload.extended_model).to eq("Payments::Order")
      expect(entity.category).to eq("extension")
    end
  end

  describe "Extend Base Model on the tenant path", :entity_author do
    before { enable_module!("payment", customer).set_extendable_model!("Payments::Order", true) }

    def base_model_select
      Nokogiri::HTML(response.body).at_css("select#entity_extended_model")
    end

    it "renders an optional base-model select on new" do
      get "/#{customer.id}/admin/maintenance/entities/new"

      select = base_model_select
      expect(select).to be_present
      expect(select["required"]).to be_nil
      expect(select["disabled"]).to be_nil
      expect(select.css("option").map { |o| o["value"] }).to eq(["", "Payments::Order"])
      expect(select.at_css("option[value='']").text.strip).to eq(I18n.t("maint_core.entities.form.no_base_model"))
    end

    it "points tenants at Maintenance / Modules when no base model is available" do
      FeatureModules::Module.find_by!(key: "payment").set_extendable_model!("Payments::Order", false)

      get "/#{customer.id}/admin/maintenance/entities/new"

      expect(base_model_select).to be_nil
      expect(response.body).to include(I18n.t("maint_core.entities.form.no_base_models_tenant"))
    end

    it "creates a customer-owned extension entity" do
      post "/#{customer.id}/admin/maintenance/entities",
           params: { entity_domain_id: entity_domain.id, entity: { name: "Order Extension", extended_model: "Payments::Order" } }

      created = Entity.find_by!(name: "Order Extension")
      expect(response).to have_http_status(:redirect)
      expect(created.customer_id).to eq(customer.id)
      expect(created.extended_model).to eq("Payments::Order")
      expect(created.category).to eq("extension")
    end

    it "creates a plain entity when no base model is chosen" do
      post "/#{customer.id}/admin/maintenance/entities",
           params: { entity_domain_id: entity_domain.id, entity: { name: "Plain Entity", extended_model: "" } }

      created = Entity.find_by!(name: "Plain Entity")
      expect(created.extended_model).to be_nil
      expect(created.category).to eq("plain")
    end

    it "rejects a model that is not approved for the customer" do
      expect {
        post "/#{customer.id}/admin/maintenance/entities",
             params: { entity_domain_id: entity_domain.id, entity: { name: "Sneaky", extended_model: "Authentication::User" } }
      }.not_to change(Entity, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "shows the base model locked when editing a shared entity's override" do
      shared = create(:entity, :shared, name: "SharedOrders")
      shared.update_column(:extended_model, "Payments::Order")

      get "/#{customer.id}/admin/maintenance/entities/#{shared.id}/edit"

      select = base_model_select
      expect(select["disabled"]).to be_present
      expect(select.at_css("option[selected]")["value"]).to eq("Payments::Order")
    end

    context "with a person entity" do
      let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
      let!(:student) do
        enable_module!("authentication", customer).set_extendable_model!(person_model, true)
        create(:entity, customer: customer, name: "Student", extended_model: person_model)
      end

      it "locks the base model on edit" do
        get "/#{customer.id}/admin/maintenance/entities/#{student.id}/edit"

        select = base_model_select
        expect(select["disabled"]).to be_present
        expect(select.at_css("option[selected]")["value"]).to eq(person_model)
        expect(Capybara.string(response.body)).to have_text(I18n.t("maint_core.entities.form.person_extension_locked_hint"))
      end

      it "refuses to remove the User extension" do
        patch "/#{customer.id}/admin/maintenance/entities/#{student.id}", params: { entity: { extended_model: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(student.reload.extended_model).to eq(person_model)
        expect(Capybara.string(response.body)).to have_text(I18n.t("maint_core.errors.validations.person_extension_permanent"))
      end

      it "refuses to switch to another base model" do
        patch "/#{customer.id}/admin/maintenance/entities/#{student.id}", params: { entity: { extended_model: "Payments::Order" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(student.reload.extended_model).to eq(person_model)
      end

      it "still saves other changes" do
        patch "/#{customer.id}/admin/maintenance/entities/#{student.id}", params: { entity: { display_label: "Pupil" } }

        expect(response).to have_http_status(:redirect)
        expect(student.reload).to have_attributes(display_label: "Pupil", extended_model: person_model)
      end
    end

    it "leaves the base model editable on a non-person extension" do
      orders = create(:entity, customer: customer, name: "Orders", extended_model: "Payments::Order")

      get "/#{customer.id}/admin/maintenance/entities/#{orders.id}/edit"

      expect(base_model_select["disabled"]).to be_nil
      expect(Capybara.string(response.body)).not_to have_text(I18n.t("maint_core.entities.form.person_extension_locked_hint"))
    end

    it "omits the base model for bridge entities" do
      bridge = create(:entity, customer: customer, name: "BridgeEnt", category: :bridge)

      get "/#{customer.id}/admin/maintenance/entities/#{bridge.id}/edit"

      expect(response.body).not_to include('id="entity_base_model_section"')
    end
  end

  describe "PATCH update — HTML invalid" do
    it "re-renders edit with 422" do
      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}",
            params: { entity: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH update — JSON invalid" do
    it "returns 422 with errors" do
      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}.json",
            params: { entity: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to have_key("errors")
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — HTML and JSON branches
  # ---------------------------------------------------------------------------

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/#{entity.id}" }

    it_behaves_like "an admin-guarded request", :delete
  end

  describe "GET trash — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/trash" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET template_fields — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/template_fields" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "DELETE empty_trash — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/empty_trash" }

    it_behaves_like "an admin-guarded request", :delete
  end

  describe "DELETE empty_trash" do
    it "permanently deletes a trashed entity that has index-column settings" do
      EntityIndexSetting.for(customer_id: customer.id, entity_id: entity.id).tap do |setting|
        setting.write_overlay(visible_column_keys: %i[name])
        setting.save!
      end
      entity.soft_delete

      expect {
        delete "/#{customer.id}/admin/maintenance/entities/empty_trash"
      }.to change { Entity.unscoped.where(id: entity.id).count }.from(1).to(0)

      expect(response).to have_http_status(:redirect)
      expect(EntityIndexSetting.where(entity_id: entity.id)).to be_empty
    end
  end

  describe "DELETE destroy — HTML success" do
    it "soft-deletes the entity and redirects to index" do
      delete "/#{customer.id}/admin/maintenance/entities/#{entity.id}"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("entities")
    end
  end

  describe "DELETE destroy — JSON success" do
    it "returns 204 no content" do
      delete "/#{customer.id}/admin/maintenance/entities/#{entity.id}.json"
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "DELETE destroy — blocked by associations" do
    let!(:source_entity) { create(:entity, customer: customer, name: "Source Entity") }
    let!(:target_entity) do
      create(:entity, customer: customer, name: "Target Entity",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end

    before do
      source_entity.associations_json = [{
        "target_entity_id" => target_entity.id,
        "target_entity_name" => target_entity.name,
        "display_field" => "name",
        "display_field_label" => "Name",
        "additional_attributes" => []
      }]
      source_entity.save!
      source_entity.sync_bridge_entities!
    end

    it "prevents deletion when entity has associations as source" do
      delete "/#{customer.id}/admin/maintenance/entities/#{source_entity.id}"

      expect(source_entity.reload.status).to eq("active")
      expect(flash[:alert]).to include("Cannot delete entity that has associations")
    end

    it "prevents deletion when entity is a target of associations" do
      delete "/#{customer.id}/admin/maintenance/entities/#{target_entity.id}"

      expect(target_entity.reload.status).to eq("active")
      expect(flash[:alert]).to include("Cannot delete entity that has associations")
    end

    it "allows deletion when all associations are removed" do
      source_entity.associations_json = []
      source_entity.save!

      delete "/#{customer.id}/admin/maintenance/entities/#{source_entity.id}"

      expect(source_entity.reload.status).to eq("inactive")
      expect(flash[:notice]).to eq("Entity was successfully deleted.")
    end

    it "returns 422 JSON with the association error" do
      delete "/#{customer.id}/admin/maintenance/entities/#{source_entity.id}.json"

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to include(
        "Cannot delete entity that has associations. Please remove all associations first."
      )
    end
  end

  # ---------------------------------------------------------------------------
  # GET trash
  # ---------------------------------------------------------------------------

  describe "GET trash" do
    it "lists a soft-deleted entity and omits an active entity" do
      deleted = create(:entity, customer: customer, name: "Trashed Donor")
      create(:entity, customer: customer, name: "Active Witness")
      deleted.soft_delete

      get "/#{customer.id}/admin/maintenance/entities/trash"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Trashed Donor")
      expect(response.body).not_to include("Active Witness")
    end

    it "does not dump every trashed entity on one fake page" do
      first = create(:entity, customer: customer, name: "DumpA")
      second = create(:entity, customer: customer, name: "DumpB")
      first.soft_delete
      second.soft_delete

      get "/#{customer.id}/admin/maintenance/entities/trash", params: { per_page: 1 }

      expect(response).to have_http_status(:ok)
      shown = [response.body.include?("DumpA"), response.body.include?("DumpB")]
      expect(shown.count(true)).to eq(1)
      expect(response.body).to include(
        I18n.t("maint_core.entities.trash.empty_confirm", count: 2)
      )
    end
  end

  # ---------------------------------------------------------------------------
  # template_fields collection action
  # ---------------------------------------------------------------------------

  describe "GET template_fields — unknown template key" do
    it "returns 404 with error message" do
      get "/#{customer.id}/admin/maintenance/entities/template_fields.json",
          params: { key: "nonexistent_template_key" }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("not found")
    end
  end

  describe "GET template_fields — valid template key" do
    it "returns 200 with fields, groups, and template" do
      # "blank" is guaranteed to exist by the application
      get "/#{customer.id}/admin/maintenance/entities/template_fields.json",
          params: { key: "blank" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key("fields")
      expect(body).to have_key("groups")
      expect(body).to have_key("template")
    end
  end

  describe "GET template_fields — contact_simple" do
    it "returns nonempty fields with name/name_slug/html_type, groups, and group_key" do
      get "/#{customer.id}/admin/maintenance/entities/template_fields.json",
          params: { key: "contact_simple" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["fields"]).to be_an(Array)
      expect(body["fields"].length).to be > 0
      field = body["fields"].first
      expect(field).to have_key("name")
      expect(field).to have_key("name_slug")
      expect(field).to have_key("html_type")
      expect(body["groups"]).to be_an(Array)
      expect(body["fields"]).to all(have_key("group_key"))
      expect(body["template"]["key"]).to eq("contact_simple")
    end
  end

  # ---------------------------------------------------------------------------
  # Attribute grouping — toolbar availability and persistence
  # ---------------------------------------------------------------------------

  describe "attribute grouping controls availability" do
    it "renders the grouping toolbar and groups input on a NEW entity (no attributes yet)", :entity_author do
      get "/#{customer.id}/admin/maintenance/entities/new"
      expect(response).to have_http_status(:ok)
      # Grouping must be available before any attribute exists, so newly-added
      # attributes can be grouped — not just server-rendered ones.
      expect(response.body).to include('data-entity-form-target="groupingToolbar"')
      expect(response.body).to include('data-entity-form-target="attributeGroupsInput"')
      expect(response.body).to include("entity-form#openMoveToGroup")
    end

    it "renders exactly one grouping toolbar/input when the entity already has attributes" do
      ent = create(:entity, customer: customer, name: "Lead", property_schema: [{ name: "email", name_slug: "email", html_type: "email" }].to_json)
      get "/#{customer.id}/admin/maintenance/entities/#{ent.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body.scan('data-entity-form-target="groupingToolbar"').size).to eq(1)
      expect(response.body.scan('data-entity-form-target="attributeGroupsInput"').size).to eq(1)
    end
  end

  describe "PATCH update — with attribute_groups" do
    let!(:grouped_entity) do
      create(:entity, customer: customer, name: "Lead")
    end

    it "persists groups and group_id references" do
      patch "/#{customer.id}/admin/maintenance/entities/#{grouped_entity.id}", params: {
        entity: {
          name: grouped_entity.name,
          attribute_groups: [
            { id: "g_1", name: "Contact", description: "", icon: "mail", color: "indigo" }
          ].to_json,
          property_schema: [
            { name: "email", name_slug: "email", html_type: "email", group_id: "g_1" }
          ].to_json
        }
      }

      expect(response).to have_http_status(:redirect).or have_http_status(:ok)
      persisted = Entity.unscoped.find(grouped_entity.id)
      expect(persisted.attribute_groups_json.map { |g| g["id"] }).to eq(["g_1"])
      expect(persisted.property_schema_json.first["group_id"]).to eq("g_1")
    end
  end

  describe "POST create — display_label and visibility round-trip", :entity_author do
    it "persists display_label and visibility through property_schema" do
      schema = [
        {
          "name" => "Email",
          "name_slug" => "email",
          "display_label" => "Email Address",
          "html_type" => "email",
          "validators" => [],
          "visibility" => { "admin" => true, "member" => false, "public" => true },
          "description" => ""
        }
      ]

      post "/#{customer.id}/admin/maintenance/entities", params: {
        entity_domain_id: entity_domain.id,
        entity: {
          name: "Subscriber",
          property_schema: schema.to_json
        }
      }

      expect(response).to have_http_status(:redirect)
      created = Entity.unscoped.find_by!(name: "Subscriber")
      attr = created.property_schema_json.first
      expect(attr["display_label"]).to eq("Email Address")
      expect(attr["visibility"]).to eq("admin" => true, "member" => false, "public" => true)
    end
  end

  # ---------------------------------------------------------------------------
  # Owner-only creation into a domain
  # ---------------------------------------------------------------------------

  describe "creating an entity into a domain" do
    let(:entities_path) { "/#{customer.id}/admin/maintenance/entities" }

    it "refuses the new form and create to a tenant admin" do
      get "#{entities_path}/new"
      expect(response).to have_http_status(:found)
      expect(flash[:alert]).to eq(I18n.t("common.errors.authorization.platform_owner_required"))

      expect {
        post entities_path, params: { entity_domain_id: entity_domain.id, entity: { name: "Sneaky" } }
      }.not_to change(Entity, :count)
      expect(response).to have_http_status(:found)

      post "#{entities_path}.json", params: { entity_domain_id: entity_domain.id, entity: { name: "Sneaky" } }
      expect(response).to have_http_status(:forbidden)
    end

    it "requires a domain and keeps the form open without one", :entity_author do
      create(:entity_domain, customer: customer, name: "Second")

      expect {
        post entities_path, params: { entity: { name: "Orphan" } }
      }.not_to change(Entity, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("maint_core.entity_domains.errors.domain_required"))
    end

    it "refuses another customer's domain", :entity_author do
      foreign = create(:entity_domain, customer: create(:customer))

      expect {
        post entities_path, params: { entity_domain_id: foreign.id, entity: { name: "Foreign" } }
      }.not_to change(Entity, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "places the new entity in the chosen domain and returns to it", :entity_author do
      post entities_path, params: { entity_domain_id: entity_domain.id, entity: { name: "Placed" } }

      created = Entity.find_by!(name: "Placed")
      expect(EntityDomains::Memberships.domain_id_for(customer.id, created.id)).to eq(entity_domain.id)
      expect(response).to redirect_to("#{entities_path}?domain_id=#{entity_domain.id}")
    end

    it "preselects the domain the new form was opened from", :entity_author do
      create(:entity_domain, customer: customer, name: "Second")

      get "#{entities_path}/new", params: { domain_id: entity_domain.id }

      select = Nokogiri::HTML(response.body).at_css("select#entity_domain_id")
      expect(select["required"]).to be_present
      expect(select.at_css("option[selected]")["value"]).to eq(entity_domain.id.to_s)
    end

    it "points the owner at creating a domain first when the customer has none", :entity_author do
      entity_domain.destroy!

      get "#{entities_path}/new"

      expect(response.body).to include(I18n.t("maint_core.entities.form.no_domains"))
      expect(Nokogiri::HTML(response.body).at_css("select#entity_domain_id")).to be_nil
    end

    it "moves the bridges an entity declares into that entity's domain on save", :entity_author do
      course = create(:entity, :with_name_status_schema, customer: customer, name: "Course")
      student = create(:entity, customer: customer, name: "Student")
      EntityDomains::Memberships.place!(student, entity_domain)

      patch "#{entities_path}/#{student.id}", params: {
        entity: { associations: [{ "target_entity_id" => course.id, "target_entity_name" => "Course",
                                   "display_field" => "name", "display_field_label" => "Name" }].to_json }
      }
      expect(response).to have_http_status(:redirect)

      bridge = Entity.find_by!(customer_id: customer.id, name: "assoc_student_course")
      expect(EntityDomains::Memberships.domain_id_for(customer.id, bridge.id)).to eq(entity_domain.id)
      expect(EntityDomains::Memberships.domain_id_for(customer.id, course.id)).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "cross-tenant isolation" do
    let(:other_customer)  { create(:customer) }
    let!(:other_entity)   { create(:entity, customer: other_customer) }

    it "returns 404 on show for another tenant's entity" do
      get "/#{customer.id}/admin/maintenance/entities/#{other_entity.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 on edit for another tenant's entity" do
      get "/#{customer.id}/admin/maintenance/entities/#{other_entity.id}/edit"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 on update for another tenant's entity" do
      patch "/#{customer.id}/admin/maintenance/entities/#{other_entity.id}",
            params: { entity: { name: "Hacked" } }
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 on destroy for another tenant's entity" do
      delete "/#{customer.id}/admin/maintenance/entities/#{other_entity.id}"
      expect(response).to have_http_status(:not_found)
    end
  end
end

# ---------------------------------------------------------------------------
# Plan-limit enforcement on entity creation
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::Entities — plan limit enforcement", type: :request do
  def create_plan_with_entity_limit(limit_value)
    plan = create(:billing_plan)
    Billing::PlanLimit.create!(plan: plan, item_key: "entity", limit_value: limit_value)
    plan
  end

  def live_sub_for(cust, plan)
    create(:billing_subscription, customer: cust, plan: plan, status: "active")
  end

  def enable_countable_item!
    Billing::CountableItem.find_or_create_by!(key: "entity") do |i|
      i.label    = "Entities"
      i.enabled  = true
      i.position = 2
    end.tap { |i| i.update!(enabled: true) }
  end

  let_it_be(:customer) { create(:customer) }
  let(:entity_domain) { create(:entity_domain, customer: customer) }
  let(:valid_params) { { entity_domain_id: entity_domain.id, entity: { name: "Quota Test Entity" } } }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }

  before do
    sign_in platform_owner
    enable_countable_item!
    Current.customer = customer
  end

  after { Current.customer = nil }


  describe "with accepted capacity for one additional entity" do
    before do
      # Provisioning owns an Authentication::User entity. Its real usage counts;
      # accept one additional slot rather than weakening the production counter.
      plan = create_plan_with_entity_limit(Billing::Countable::Registry.count_for("entity", customer) + 1)
      live_sub_for(customer, plan)
    end

    it "allows creating the first entity (under limit)" do
      expect {
        post "/#{customer.id}/admin/maintenance/entities", params: valid_params
      }.to change(Entity, :count).by_at_least(1)

      expect(response).to have_http_status(:redirect)
    end

    it "blocks creating when at the limit — HTML returns 422 and does not persist the record" do
      create(:entity, customer: customer, name: "Existing Entity")

      expect {
        post "/#{customer.id}/admin/maintenance/entities", params: valid_params
      }.not_to change(Entity, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Upgrade your plan")
    end

    it "blocks creating when at the limit — JSON returns 422 with error key" do
      create(:entity, customer: customer, name: "Existing Entity")

      expect {
        post "/#{customer.id}/admin/maintenance/entities.json", params: valid_params
      }.not_to change(Entity, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("Upgrade your plan")
    end
  end

  describe "with an unlimited plan (-1)" do
    before do
      plan = create_plan_with_entity_limit(Billing::PlanLimit::UNLIMITED)
      live_sub_for(customer, plan)
    end

    it "allows creating past 1 entity" do
      create(:entity, customer: customer, name: "Existing Entity")

      expect {
        post "/#{customer.id}/admin/maintenance/entities", params: valid_params
      }.to change(Entity, :count).by_at_least(1)

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "platform owner bypass (customer 81721200)" do
    before { ensure_platform_customer }

    it "bypasses limits even with a zero-limit plan" do
      platform_customer = Customer.find(Authentication::User::PLATFORM_CUSTOMER_ID)
      plan = create_plan_with_entity_limit(0)
      live_sub_for(platform_customer, plan)

      platform_owner = find_or_create_platform_owner
      sign_in platform_owner
      Current.customer = platform_customer

      expect {
        post "/#{platform_customer.id}/admin/maintenance/entities",
             params: { entity_domain_id: create(:entity_domain, customer: platform_customer).id,
                       entity: { name: "Owner Entity" } }
      }.to change(Entity, :count).by_at_least(1)

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "multi-tenant isolation" do
    let(:customer_b) { create(:customer) }

    before do
      # Customer A: limit of 1, already at limit
      plan_a = create_plan_with_entity_limit(Billing::Countable::Registry.count_for("entity", customer) + 1)
      live_sub_for(customer, plan_a)
      create(:entity, customer: customer, name: "A Entity")

      # Customer B: limit of 5 (plenty of room)
      plan_b = create_plan_with_entity_limit(Billing::Countable::Registry.count_for("entity", customer_b) + 5)
      live_sub_for(customer_b, plan_b)
    end

    it "customer A at limit does not block customer B" do
      Current.customer = customer_b

      expect {
        post "/#{customer_b.id}/admin/maintenance/entities",
             params: { entity_domain_id: create(:entity_domain, customer: customer_b).id,
                       entity: { name: "B Entity" } }
      }.to change(Entity, :count).by_at_least(1)

      expect(response).to have_http_status(:redirect)
    end
  end

  # ---------------------------------------------------------------------------
  # Sharing scope (customer_specific / shared)
  # ---------------------------------------------------------------------------

  describe "sharing scope authorization" do
    let(:owner)          { find_or_create_platform_owner }
    let(:owner_customer) { owner.customer }

    before { sign_in admin }

    it "forces tenant-created entities to be customer-owned" do
      sign_in platform_owner
      post "/#{customer.id}/admin/maintenance/entities",
           params: { entity_domain_id: entity_domain.id, entity: { name: "Forced" } }
      created = Entity.unscoped.find_by(name: "Forced")
      expect(created).to be_customer_owned
      expect(created.customer_id).to eq(customer.id)
    end

    it "lets the platform owner create a shared entity from Shared Resources" do
      sign_in owner
      post "/#{owner_customer.id}/admin/maintenance/platform/entities",
           params: { entity: { name: "SharedByOwner" } }
      created = Entity.unscoped.find_by(name: "SharedByOwner")
      expect(created).to be_shared
      expect(created.customer_id).to be_nil
    end

    it "lets a non-owner admin edit a shared entity as a per-customer override (definition only)" do
      shared = Current.with_customer(nil) { Entity.create!(name: "SharedDef", description: "global") }
      patch "/#{customer.id}/admin/maintenance/entities/#{shared.id}",
            params: { entity: { description: "custom for tenant" } }
      expect(response).to have_http_status(:found)
      # A per-customer override was recorded; the global default is untouched.
      expect(EntityCustomerHead.find_by(entity_id: shared.id, customer_id: customer.id)).to be_present
      Current.with_customer(nil) { expect(Entity.find(shared.id).description).to eq("global") }
      Current.with_customer(customer) do
        expect(Entity.find(shared.id).description).to eq("custom for tenant")
      end
    end

    it "ignores identity changes (name) from a non-owner on a shared entity" do
      shared = Current.with_customer(nil) { Entity.create!(name: "SharedDef2", description: "global") }
      patch "/#{customer.id}/admin/maintenance/entities/#{shared.id}",
            params: { entity: { name: "Hacked", description: "x" } }
      expect(shared.reload.name).to eq("SharedDef2")
      expect(shared.reload).to be_shared
    end

    it "resets a customer's override, reverting to the global default" do
      shared = Current.with_customer(nil) { Entity.create!(name: "SharedDef3", description: "global") }
      patch "/#{customer.id}/admin/maintenance/entities/#{shared.id}",
            params: { entity: { description: "custom" } }
      expect(EntityCustomerHead.find_by(entity_id: shared.id, customer_id: customer.id)).to be_present

      delete "/#{customer.id}/admin/maintenance/entities/#{shared.id}/override"
      expect(response).to have_http_status(:found)
      expect(EntityCustomerHead.find_by(entity_id: shared.id, customer_id: customer.id)).to be_nil
      Current.with_customer(customer) do
        expect(Entity.find(shared.id).description).to eq("global")
      end
    end

    it "blocks a non-owner from destroying a shared entity" do
      shared = create(:entity, :shared, name: "SharedDel")
      delete "/#{customer.id}/admin/maintenance/entities/#{shared.id}"
      expect(response).to have_http_status(:found).or have_http_status(:forbidden)
      expect(Entity.unscoped.exists?(shared.id)).to be(true)
    end

    it "blocks the platform owner from destroying a shared entity on the tenant path" do
      sign_in owner
      shared = create(:entity, :shared, name: "OwnerTenantDel")
      delete "/#{owner_customer.id}/admin/maintenance/entities/#{shared.id}"
      expect(Entity.exists?(shared.id)).to be(true)
    end

    it "lets a non-owner admin read (show) a shared entity" do
      shared = create(:entity, :shared, name: "SharedReadable")
      get "/#{customer.id}/admin/maintenance/entities/#{shared.id}"
      expect(response).to have_http_status(:ok)
    end

    it "lets the platform owner edit a shared entity" do
      sign_in owner
      shared = create(:entity, :shared, name: "OwnerEditable")
      patch "/#{owner_customer.id}/admin/maintenance/platform/entities/#{shared.id}",
            params: { entity: { name: "OwnerRenamed" } }
      expect(response).to have_http_status(:found)
      expect(shared.reload.name).to eq("OwnerRenamed")
    end

    it "lets the platform owner edit a shared entity from tenant maintenance as a 81721200 override" do
      sign_in owner
      shared = Current.with_customer(nil) { Entity.create!(name: "OwnerTenantEdit", description: "global") }
      patch "/#{owner_customer.id}/admin/maintenance/entities/#{shared.id}",
            params: { entity: { description: "owner tenant edit" } }
      expect(response).to have_http_status(:found)
      expect(EntityCustomerHead.find_by(entity_id: shared.id, customer_id: owner_customer.id)).to be_present
      expect(shared.reload.entity_versions.where(customer_id: owner_customer.id)).to be_present
      Current.with_customer(nil) { expect(Entity.find(shared.id).description).to eq("global") }
      Current.with_customer(owner_customer) do
        expect(Entity.find(shared.id).description).to eq("owner tenant edit")
      end
    end

    it "advances the global default when the platform owner edits from Shared Resources" do
      sign_in owner
      shared = Current.with_customer(nil) { Entity.create!(name: "OwnerPlatformEdit", description: "global") }
      patch "/#{owner_customer.id}/admin/maintenance/platform/entities/#{shared.id}",
            params: { entity: { description: "new global" } }
      expect(response).to have_http_status(:found)
      expect(EntityCustomerHead.where(entity_id: shared.id)).to be_empty
      Current.with_customer(nil) { expect(Entity.find(shared.id).description).to eq("new global") }
      Current.with_customer(customer) { expect(Entity.find(shared.id).description).to eq("new global") }
    end

    it "ignores identity changes from the platform owner on the tenant path" do
      sign_in owner
      shared = Current.with_customer(nil) { Entity.create!(name: "KeepName", description: "global") }
      patch "/#{owner_customer.id}/admin/maintenance/entities/#{shared.id}",
            params: { entity: { name: "Hacked", description: "x" } }
      expect(shared.reload.name).to eq("KeepName")
    end

    it "shows reset-to-default for the platform owner on the tenant path when an override exists" do
      sign_in owner
      shared = Current.with_customer(nil) { Entity.create!(name: "OwnerResetUi", description: "global") }
      patch "/#{owner_customer.id}/admin/maintenance/entities/#{shared.id}",
            params: { entity: { description: "owner tenant edit" } }
      get "/#{owner_customer.id}/admin/maintenance/entities/#{shared.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("maint_core.entities.show.reset_to_default"))
    end

    it "does not show reset-to-default on Shared Resources" do
      sign_in owner
      shared = Current.with_customer(nil) { Entity.create!(name: "OwnerPlatformResetUi", description: "global") }
      patch "/#{owner_customer.id}/admin/maintenance/entities/#{shared.id}",
            params: { entity: { description: "owner tenant edit" } }
      get "/#{owner_customer.id}/admin/maintenance/platform/entities/#{shared.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(I18n.t("maint_core.entities.show.reset_to_default"))
    end

    it "does not render a type or sharing-scope field on tenant new" do
      sign_in platform_owner
      get "/#{customer.id}/admin/maintenance/entities/new"
      expect(response.body).not_to include('name="entity[type]"')
      expect(response.body).not_to include("Sharing Scope")
    end

    it "does not offer a sharing-scope field on platform new" do
      sign_in owner
      get "/#{owner_customer.id}/admin/maintenance/platform/entities/new"
      expect(response.body).not_to include("Sharing Scope")
      expect(response.body).not_to include('name="entity[type]"')
    end
  end
end

RSpec.describe "Admin::Maintenance::Entities trash cascade", type: :request do
  let(:cascade_customer) { create(:customer) }
  let(:cascade_admin) { create(:user, :admin, customer: cascade_customer) }

  it "takes the entity's live forms offline and says so" do
    sign_in cascade_admin
    entity = create(:entity, customer: cascade_customer, name: "Timesheet")
    form = create(:page, customer: cascade_customer, entity: entity, launched: true)

    delete "/#{cascade_customer.id}/admin/maintenance/entities/#{entity.id}"

    expect(flash[:notice]).to eq(
      "#{I18n.t('maint_core.flash.entities.deleted')} #{I18n.t('maint_core.flash.entities.forms_taken_offline', count: 1)}"
    )
    expect(form.reload.launched).to be(false)
  end

  it "keeps the plain notice when no form was live" do
    sign_in cascade_admin
    entity = create(:entity, customer: cascade_customer)

    delete "/#{cascade_customer.id}/admin/maintenance/entities/#{entity.id}"

    expect(flash[:notice]).to eq(I18n.t("maint_core.flash.entities.deleted"))
  end
end
