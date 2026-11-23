# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Pages", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  # -------------------------------------------------------------------------
  # Authorization guards
  # -------------------------------------------------------------------------

  describe "GET index — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET new — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/new" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET show — auth guards" do
    let!(:page_record) { create(:page, customer: customer) }
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/#{page_record.id}" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET edit — auth guards" do
    let!(:page_record) { create(:page, customer: customer) }
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let!(:page_record) { create(:page, customer: customer) }
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/#{page_record.id}" }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "POST create — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages" }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "DELETE destroy — auth guards" do
    let!(:page_record) { create(:page, customer: customer) }
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/#{page_record.id}" }

    it_behaves_like "an admin-guarded request", :delete
  end

  describe "GET trash — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/trash" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET trash" do
    before { sign_in admin }

    it "does not dump every trashed page on one fake page" do
      first = create(:page, customer: customer, name: "DumpA")
      second = create(:page, customer: customer, name: "DumpB")
      first.soft_delete
      second.soft_delete

      get "/#{customer.id}/admin/maintenance/pages/trash", params: { per_page: 1 }

      expect(response).to have_http_status(:ok)
      shown = [response.body.include?("DumpA"), response.body.include?("DumpB")]
      expect(shown.count(true)).to eq(1)
      expect(response.body).to include(
        I18n.t("maint_core.pages.trash.empty_confirm", count: 2)
      )
    end
  end

  describe "DELETE empty_trash — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/empty_trash" }

    it_behaves_like "an admin-guarded request", :delete
  end

  # -------------------------------------------------------------------------
  # Validation error path — Task 3 Steps 5-7
  # -------------------------------------------------------------------------

  describe "PATCH update — calculation referencing an unknown field" do
    let!(:page_record) { create(:page, customer: customer) }

    before { sign_in admin }

    it "returns 422 with an error message identifying the unknown field" do
      bad_config = {
        "pages" => [{ "id" => "p1", "fields" => [{ "id" => "qty", "property_type" => "number" }] }],
        "calculations" => [{ "id" => "c1", "target_field_id" => "qty", "formula" => "{ghost}+1" }],
        "rules" => [],
        "metadata" => {}
      }

      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: { configuration: bad_config.to_json,
                              updated_at: page_record.updated_at.iso8601(6) } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body["status"]).to eq("error")
      expect(body["errors"].join).to match(/unknown field 'ghost'/i)
    end

    it "allows a valid configuration through (success path unchanged)" do
      # Preserve the entity metadata from the factory-built page so the
      # entity_id_must_be_present validation does not trip. Replace
      # calculations with a valid (non-circular) formula.
      existing_meta = JSON.parse(page_record.configuration).fetch("metadata", {})
      good_config = {
        "pages" => [{ "id" => "p1", "fields" => [
          { "id" => "qty",   "property_type" => "number" },
          { "id" => "price", "property_type" => "number" }
        ] }],
        "calculations" => [{ "id" => "c1", "target_field_id" => "qty", "formula" => "{price} * 2" }],
        "rules" => [],
        "metadata" => existing_meta
      }

      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: { configuration: good_config.to_json,
                              updated_at: page_record.updated_at.iso8601(6) } },
            as: :json

      expect(response).to have_http_status(:ok), -> { response.parsed_body.inspect }
      expect(response.parsed_body["status"]).to eq("success")
    end
  end

  # -------------------------------------------------------------------------
  # Captcha toggle (moved into Form Settings) persists via the JSON update path
  # -------------------------------------------------------------------------

  describe "PATCH update — captcha toggle (Form Settings)" do
    let!(:page_record) { create(:page, customer: customer) }

    before { sign_in admin }

    it "persists the captcha flag folded into the configuration JSON" do
      existing_meta = JSON.parse(page_record.configuration).fetch("metadata", {})
      config = {
        "pages" => [{ "id" => "p1", "fields" => [] }],
        "rules" => [],
        "calculations" => [],
        "metadata" => existing_meta,
        "captcha" => { "enabled" => true }
      }

      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: { configuration: config.to_json,
                              updated_at: page_record.updated_at.iso8601(6) } },
            as: :json

      expect(response).to have_http_status(:ok), -> { response.parsed_body.inspect }
      expect(page_record.reload.captcha_enabled?).to be(true)
    end
  end

  # -------------------------------------------------------------------------
  # Cross-tenant isolation
  # -------------------------------------------------------------------------

  describe "PATCH update — cross-tenant access is forbidden" do
    let(:other_customer) { create(:customer) }
    let!(:other_page)    { create(:page, customer: other_customer) }

    before { sign_in admin }

    it "cannot reach a page belonging to another customer" do
      patch "/#{customer.id}/admin/maintenance/pages/#{other_page.id}",
            params: { page: { name: "Hijacked" } },
            as: :json

      # find_page uses Page.for_current_customer which raises ActiveRecord::RecordNotFound
      expect(response).to have_http_status(:not_found)
    end
  end

  # -------------------------------------------------------------------------
  # GET index
  # -------------------------------------------------------------------------

  describe "GET index" do
    let!(:page_record) { create(:page, customer: customer) }

    before { sign_in admin }

    it "returns JSON list" do
      get "/#{customer.id}/admin/maintenance/pages", as: :json
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to be_an(Array)
      expect(body.first["name"]).to eq(page_record.name)
    end

    it "renders index with a launched page (exercises launched? cell lambda)" do
      page_record.update_column(:launched, true)
      get "/#{customer.id}/admin/maintenance/pages"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Yes")
    end

    it "renders the Current Version column when rows exist" do
      get "/#{customer.id}/admin/maintenance/pages"
      expect(response.body).to include("Current Version")
    end

    it "renders version info for a page that has a snapshot" do
      content = page_record.content_class.store!(customer_id: page_record.customer_id, payload: { "_marker" => SecureRandom.hex(8) })
      page_record.commit_version!(description: "v1", content: content)
      get "/#{customer.id}/admin/maintenance/pages"
      expect(response.body).to include("v1")
    end
  end

  # -------------------------------------------------------------------------
  # GET show
  # -------------------------------------------------------------------------

  describe "GET show, new, and edit HTML" do
    let!(:page_record) { create(:page, customer: customer) }

    before { sign_in admin }

    it "returns 200 for each form page" do
      [
        "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
        "/#{customer.id}/admin/maintenance/pages/new",
        "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"
      ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET new — entity picker" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }

    def association_to(target)
      slug = Array(target.property_schema_json).find { |attribute| attribute["html_type"] == "text" }&.fetch("name_slug", "name")
      {
        "target_entity_id" => target.id,
        "target_entity_name" => target.name,
        "display_field" => slug,
        "display_field_label" => slug.to_s.capitalize,
        "additional_attributes" => []
      }
    end

    def person_entity(owner, name)
      enable_module!("authentication", owner).set_extendable_model!(person_model, true)
      create(:entity, customer: owner, name: name, extended_model: person_model,
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end

    def bind_bridges(source, targets)
      source.associations_json = targets.map { |target| association_to(target) }
      source.save!
      source.sync_bridge_entities!
      source.reload.associations_list.map do |assoc|
        Entity.find(assoc.fetch("bridge_entity_id"))
      end
    end

    before { sign_in admin }

    it "lists every active entity, bridges included, never a trashed one or a flowchart" do
      student = person_entity(customer, "Student")
      teacher = person_entity(customer, "Teacher")
      course = create(:entity, customer: customer, name: "Course",
                      property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
      album = create(:entity, customer: customer, name: "Album",
                     property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
      enrollment, mentorship, trashed = bind_bridges(student, [course, teacher, album])
      create(:flowchart, :launched_status, customer: customer, name: "Enroll member")
      trashed.soft_delete

      get "/#{customer.id}/admin/maintenance/pages/new"

      expect(response).to have_http_status(:ok)
      options = Nokogiri::HTML(response.body).css("#page_entity_id option").map(&:text)
      expect(options).to include(student.display_label, course.display_label, enrollment.display_label, mentorship.display_label)
      expect(options).not_to include(trashed.display_label)
      expect(response.body).not_to include("Enroll member")
    end

    it "lists only shared entities, bridges included, on the shared-resources platform path" do
      platform = ensure_platform_customer
      owner = find_or_create_platform_owner
      sign_in owner
      shared = create(:entity, :shared, name: "Shared Catalog")
      shared_bridge = create(:entity, :shared, category: :bridge, name: "Shared Enrollment")
      own = create(:entity, customer: platform, name: "PlatformCourse")

      get "/#{platform.id}/admin/maintenance/platform/pages/new"

      expect(response).to have_http_status(:ok)
      options = Nokogiri::HTML(response.body).css("#page_entity_id option").map(&:text)
      expect(options).to include(shared.display_label, shared_bridge.display_label)
      expect(options).not_to include(own.display_label)
    end
  end

  describe "GET show JSON" do
    let!(:page_record) { create(:page, customer: customer) }

    before { sign_in admin }

    it "returns JSON with page attributes" do
      get "/#{customer.id}/admin/maintenance/pages/#{page_record.id}", as: :json
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(page_record.id)
      expect(body["name"]).to eq(page_record.name)
    end
  end

  # -------------------------------------------------------------------------
  # POST create
  # -------------------------------------------------------------------------

  describe "POST create" do
    let(:entity)             { create(:entity, customer: customer) }
    let(:entity_with_fields) { create(:entity, :with_name_status_schema, customer: customer) }
    let(:entity_with_name_email) do
      create(:entity, name: "User", customer: customer, property_schema: [
        { "name" => "Name", "name_slug" => "name", "type" => "String" },
        { "name" => "Email", "name_slug" => "email", "type" => "String" }
      ].to_json)
    end

    before { sign_in admin }

    it "creates a page with entity and redirects to edit" do
      expect {
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Simple Page", entity_id: entity.id.to_s } }
      }.to change(Page, :count).by(1)

      expect(response).to redirect_to(
        edit_admin_maintenance_page_path(customer.id, Page.last)
      )
    end

    it "allows creating two pages with the same name" do
      create(:page, customer: customer, entity: entity, name: "Duplicate Page Name")

      expect {
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Duplicate Page Name", entity_id: entity.id.to_s } }
      }.to change(Page, :count).by(1)

      expect(response).to redirect_to(
        edit_admin_maintenance_page_path(customer.id, Page.last)
      )
    end

    it "creates a page with entity fields and applies default layout template" do
      # entity_with_fields has properties so PageFieldPopulator returns non-empty pages,
      # hitting the template-application branch (lines 81-104 of pages_controller)
      expect {
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "With Template", entity_id: entity_with_fields.id.to_s,
                               layout_template: "default" } }
      }.to change(Page, :count).by(1)

      expect(response).to redirect_to(
        edit_admin_maintenance_page_path(customer.id, Page.last)
      )
    end

    it "creates a page applying a theme_preset when template is 'blank'" do
      # layout_template "blank" skips template application but theme_preset is present
      # → hits elsif branch (line 98 of pages_controller)
      expect {
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Themed Page", entity_id: entity_with_fields.id.to_s,
                               layout_template: "blank", theme_preset: "default" } }
      }.to change(Page, :count).by(1)
    end

    it "renders new with 422 on blank name" do
      post "/#{customer.id}/admin/maintenance/pages",
           params: { page: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    context "with entity auto-population" do
      it "pre-populates fields from entity when entity_id is provided" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Auto Page", entity_id: entity_with_name_email.id.to_s } }

        fields = Page.last.fields
        expect(fields).not_to be_empty
        expect(fields.any? { |f| f["property_slug"] == "name" }).to be true
        expect(fields.any? { |f| f["property_slug"] == "email" }).to be true
      end

      it "organizes fields into pages named after the entity" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Auto Page", entity_id: entity_with_name_email.id.to_s } }

        pages = Page.last.configuration_json["pages"]
        expect(pages).to be_present
        expect(pages.first["name"]).to eq("User")
      end
    end

    context "with layout template" do
      it "applies compact_two_column field width half" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: {
               name: "Template Page",
               entity_id: entity_with_name_email.id.to_s,
               layout_template: "compact_two_column"
             } }

        fields = Page.last.fields.select { |f| f["property_type"] != "layout" }
        expect(fields.first["width"]).to eq("half")
      end

      it "applies contact_detailed default theme primary_color indigo" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: {
               name: "Template Page",
               entity_id: entity_with_name_email.id.to_s,
               layout_template: "contact_detailed"
             } }

        theme = Page.last.configuration_json["theme"]
        expect(theme).to be_present
        expect(theme["primary_color"]).to eq("indigo")
      end

      it "allows theme_preset bold to override template theme to rose" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: {
               name: "Template Page",
               entity_id: entity_with_name_email.id.to_s,
               layout_template: "contact_detailed",
               theme_preset: "bold"
             } }

        expect(Page.last.configuration_json["theme"]["primary_color"]).to eq("rose")
      end

      it "keeps fields when the blank template is selected" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: {
               name: "Blank Page",
               entity_id: entity_with_name_email.id.to_s,
               layout_template: "blank"
             } }

        fields = Page.last.fields.select { |f| f["property_type"] != "layout" }
        expect(fields).not_to be_empty
      end

      it "applies elegant theme violet on a blank template" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: {
               name: "Blank with Theme",
               entity_id: entity_with_name_email.id.to_s,
               layout_template: "blank",
               theme_preset: "elegant"
             } }

        expect(Page.last.configuration_json["theme"]["primary_color"]).to eq("violet")
      end
    end

    context "with entity bound but no layout template chosen" do
      it "falls back to the default layout_template_key" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Auto-default Page", entity_id: entity_with_name_email.id.to_s } }

        expect(Page.last.configuration_json["metadata"]["layout_template_key"]).to eq("default")
      end

      it "applies the default template theme (modern indigo)" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Auto-default Page", entity_id: entity_with_name_email.id.to_s } }

        theme = Page.last.configuration_json["theme"]
        expect(theme).to be_present
        expect(theme["primary_color"]).to eq("indigo")
      end

      it "allows theme_preset bold to override the default fallback to rose" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: {
               name: "Auto-default with Theme",
               entity_id: entity_with_name_email.id.to_s,
               theme_preset: "bold"
             } }

        expect(Page.last.configuration_json["theme"]["primary_color"]).to eq("rose")
      end

      it "does not set layout_template_key when no entity fields are populated" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Standalone Page", entity_id: entity.id.to_s } }

        expect(Page.last.configuration_json["metadata"]["layout_template_key"]).to be_nil
      end
    end

    context "with entity-plus-associations bound and no layout template chosen" do
      let!(:student_entity) do
        create(:entity, name: "Student", customer: customer, property_schema: [
          { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
        ].to_json)
      end

      let!(:course_entity) do
        create(:entity, name: "Course", customer: customer, property_schema: [
          { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
        ].to_json)
      end

      let!(:teacher_entity) do
        create(:entity, name: "Teacher", customer: customer, property_schema: [
          { "name" => "Full Name", "name_slug" => "full_name", "html_type" => "text" }
        ].to_json)
      end

      let!(:enrollment_bridge) do
        create(:entity, name: "Enrollment", customer: customer, property_schema: [
          { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student_entity.id },
          { "name" => "Course",  "name_slug" => "course",  "type" => "EntityReference", "entity_id" => course_entity.id },
          { "name" => "Grade",   "name_slug" => "grade",   "html_type" => "text" }
        ].to_json)
      end

      let!(:mentorship_bridge) do
        create(:entity, name: "Mentorship", customer: customer, property_schema: [
          { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student_entity.id },
          { "name" => "Teacher", "name_slug" => "teacher", "type" => "EntityReference", "entity_id" => teacher_entity.id },
          { "name" => "Subject", "name_slug" => "subject", "html_type" => "text" }
        ].to_json)
      end

      before do
        student_entity.associations_json = [
          { "target_entity_id" => course_entity.id,  "target_entity_name" => "Course",  "bridge_entity_id" => enrollment_bridge.id,  "bridge_entity_name" => "Enrollment",  "association_type" => "has_many", "display_field" => "title", "display_field_label" => "Title" },
          { "target_entity_id" => teacher_entity.id, "target_entity_name" => "Teacher", "bridge_entity_id" => mentorship_bridge.id, "bridge_entity_name" => "Mentorship", "association_type" => "has_many", "display_field" => "full_name", "display_field_label" => "Full Name" }
        ]
        student_entity.save!
      end

      it "builds one page from the primary entity and leaves the associations out" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Student Publish Page", entity_id: student_entity.id.to_s } }

        pages = Page.last.configuration_json["pages"]
        expect(pages.map { |p| p["name"] }).to eq(%w[Student])
        sources = pages.first["fields"].reject { |f| f["property_type"] == "layout" }.map { |f| f["source"] }
        expect(sources.uniq).to eq(["entity"])
      end

      it "applies the default template per page (each page carries a section field)" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Student Publish Page", entity_id: student_entity.id.to_s } }

        Page.last.configuration_json["pages"].each do |page_config|
          section_headers = page_config["fields"].select { |f| f["field_type"] == "section" }
          expect(section_headers).not_to be_empty
        end
      end

      it "generates single-step form content rather than a wizard" do
        post "/#{customer.id}/admin/maintenance/pages",
             params: { page: { name: "Student Publish Page", entity_id: student_entity.id.to_s } }

        created_page = Page.last
        content = created_page.content.presence || created_page.generate_content

        expect(content).to include("FormFields::FormComponent")
        expect(content).not_to include("FormFields::WizardComponent")
      end
    end
  end

  # -------------------------------------------------------------------------
  # PATCH update — HTML success redirect
  # -------------------------------------------------------------------------

  describe "PATCH update — HTML success" do
    let!(:page_record) { create(:page, customer: customer) }

    before { sign_in admin }

    it "redirects to show page on HTML success" do
      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: { name: "Updated Name", updated_at: page_record.updated_at.iso8601(6) } }

      expect(response).to redirect_to(
        admin_maintenance_page_path(customer.id, page_record)
      )
    end

    it "creates a version snapshot when configuration changes" do
      updated_config = JSON.parse(page_record.configuration)
      updated_config["_marker"] = SecureRandom.hex(8)

      expect {
        patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
              params: { page: { configuration: updated_config.to_json, updated_at: page_record.updated_at.iso8601(6) } },
              as: :json
      }.to change { PageVersion.count }.by(1)
      page_record.reload
      expect(page_record.current_version.version_number).to eq(2)
    end

    it "does not create a version snapshot when only name changes" do
      expect {
        patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
              params: { page: { name: "New Name", updated_at: page_record.updated_at.iso8601(6) } }
      }.not_to change { PageVersion.count }
    end
  end

  # -------------------------------------------------------------------------
  # PATCH update — stale-client conflict
  # -------------------------------------------------------------------------

  describe "PATCH update — stale-client conflict detection" do
    let!(:page_record) { create(:page, customer: customer) }

    before { sign_in admin }

    it "returns 409 conflict JSON when updated_at is stale" do
      stale_stamp = 1.hour.ago.iso8601(6)
      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: { name: "Stale", updated_at: stale_stamp } },
            as: :json

      expect(response).to have_http_status(:conflict)
      body = response.parsed_body
      expect(body["status"]).to eq("conflict")
    end

    it "redirects HTML when updated_at is stale" do
      stale_stamp = 1.hour.ago.iso8601(6)
      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: { name: "Stale", updated_at: stale_stamp } }

      expect(response).to redirect_to(
        edit_admin_maintenance_page_path(customer.id, page_record)
      )
      expect(flash[:alert]).to include("updated in another tab")
    end

    it "returns 409 when updated_at param is missing (treated as stale)" do
      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: { name: "NoStamp" } },
            as: :json

      expect(response).to have_http_status(:conflict)
    end

    it "returns 409 when updated_at param is unparseable" do
      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: { name: "BadStamp", updated_at: "not-a-date" } },
            as: :json

      expect(response).to have_http_status(:conflict)
    end
  end

  # -------------------------------------------------------------------------
  # DELETE destroy
  # -------------------------------------------------------------------------

  describe "DELETE destroy" do
    let!(:page_record) { create(:page, customer: customer) }

    before { sign_in admin }

    it "soft-deletes the page and redirects" do
      delete "/#{customer.id}/admin/maintenance/pages/#{page_record.id}"

      expect(response).to redirect_to("/#{customer.id}/admin/maintenance/pages")
      expect(page_record.reload.status).to eq("inactive")
    end
  end

  # NOTE: Page preview is served by Admin::Maintenance::PagePreviewsController
  # via the dedicated `resource :preview` route. Its coverage lives in
  # spec/requests/admin/maintenance/page_previews_spec.rb.

  # -------------------------------------------------------------------------
  # GET edit — entity-linked page
  # -------------------------------------------------------------------------

  describe "GET edit with entity-linked page" do
    let(:entity)       { create(:entity, customer: customer, name: "BoundContactEntity") }
    let!(:page_record) { create(:page, customer: customer, entity: entity) }

    before { sign_in admin }

    it "renders no flows section or form action binding in the page builder" do
      create(:flowchart, :simple, :launched_status, customer: customer, name: "Entity Flow Alpha")

      get "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(I18n.t("comp_page_builder.flows_section.empty_desc"))
      expect(response.body).not_to include("data-page-builder-available-flowcharts-value")
      expect(response.body).not_to include("data-page-builder-select-flowchart-option-value")
    end

    it "includes entity_name from metadata in the HTML" do
      get "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(entity.name)
    end
  end

  describe "GET edit — Used in journeys panel" do
    let!(:page_record) { create(:page, customer: customer, action_key: "student_new") }
    let!(:journey) { create(:journey, customer: customer, name: "Enrolment") }

    def edit_path = "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"

    it "is absent for a tenant admin" do
      sign_in admin
      get edit_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(I18n.t("journeys.admin.usage.title"), "data-role=\"journey-usage\"", "Enrolment")
    end

    it "lists the tenant's journeys using the page for the platform owner" do
      create(:journey, name: "Someone else's")
      sign_in find_or_create_platform_owner
      get edit_path

      expect(response).to have_http_status(:ok)
      panel = Capybara.string(response.body).find("aside [data-role='journey-usage']")
      expect(panel).to have_link("Enrolment", href: "/#{customer.id}/admin/maintenance/entities/journeys/#{journey.id}/edit")
      expect(panel).not_to have_text("Someone else's")
    end

    it "lists only the platform customer's journeys for a shared page on the platform path" do
      platform = ensure_platform_customer
      shared = create(:page, :shared, action_key: "student_new")
      own = create(:journey, customer: platform, name: "Platform intake")
      sign_in find_or_create_platform_owner

      get "/#{platform.id}/admin/maintenance/platform/pages/#{shared.id}/edit"

      expect(response).to have_http_status(:ok)
      panel = Capybara.string(response.body).find("aside [data-role='journey-usage']")
      expect(panel).to have_link("Platform intake", href: "/#{platform.id}/admin/maintenance/entities/journeys/#{own.id}/edit")
      expect(panel).not_to have_text("Enrolment")
    end
  end

  describe "GET edit — identity field sidebar" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }

    def person_entity(name)
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      create(:entity, customer: customer, name: name, extended_model: person_model,
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end

    def identity_items(html)
      Nokogiri::HTML(html).css('[data-source="identity"]')
    end

    before { sign_in admin }

    it "renders the Account group for a person entity with identity source items" do
      student = person_entity("Student")
      page_record = create(:page, customer: customer, entity: student)

      get "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"

      expect(response).to have_http_status(:ok)
      group = Nokogiri::HTML(response.body).at_css('[data-searchable-section="identity"]')
      expect(group).to be_present
      expect(group.text).to include(I18n.t("maint_core.pages.editor.identity_group"))
      expect(group.text).to include(I18n.t("maint_core.pages.editor.identity_group_help"))

      items = identity_items(response.body)
      expect(items.map { |item| item["data-property-slug"] }).to eq(People::IDENTITY_KEYS)
      People::IDENTITY_KEYS.each do |key|
        item = items.find { |node| node["data-property-slug"] == key }
        expect(item["data-source"]).to eq("identity")
        expect(item["data-property-name"]).to eq(I18n.t("member.profiles.show.fields.#{key}"))
      end
      expect(items.find { |node| node["data-property-slug"] == "email" }["data-property-html-type"]).to eq("email")
    end

    it "does not render the Account group for a non-person entity" do
      course = create(:entity, customer: customer, name: "Course",
                      property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
      page_record = create(:page, customer: customer, entity: course)

      get "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css('[data-searchable-section="identity"]')).to be_nil
      expect(identity_items(response.body)).to be_empty
    end

    it "renders identity labels from I18n in zh-CN" do
      student = person_entity("Student")
      page_record = create(:page, customer: customer, entity: student)

      get "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit", params: { locale: "zh-CN" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("maint_core.pages.editor.identity_group", locale: :"zh-CN"))
      expect(response.body).to include(I18n.t("maint_core.pages.editor.identity_group_help", locale: :"zh-CN"))
      People::IDENTITY_KEYS.each do |key|
        expect(response.body).to include(I18n.t("member.profiles.show.fields.#{key}", locale: :"zh-CN"))
      end
    end
  end
end

# ---------------------------------------------------------------------------
# Plan-limit enforcement on page creation
# ---------------------------------------------------------------------------
RSpec.describe "Admin::Maintenance::Pages — plan limit enforcement", type: :request do
  def create_plan_with_page_limit(limit_value)
    plan = create(:billing_plan)
    Billing::PlanLimit.create!(plan: plan, item_key: "page", limit_value: limit_value)
    plan
  end

  def live_sub_for(cust, plan)
    create(:billing_subscription, customer: cust, plan: plan, status: "active")
  end

  def enable_countable_item!
    Billing::CountableItem.find_or_create_by!(key: "page") do |i|
      i.label    = "Pages"
      i.enabled  = true
      i.position = 1
    end.tap { |i| i.update!(enabled: true) }
  end

  let(:customer) { create(:customer) }
  let(:valid_params) { { page: { name: "Quota Test Page", entity_id: entity.id.to_s } } }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:entity)   { create(:entity, customer: customer) }

  before do
    sign_in admin
    enable_countable_item!
    Current.customer = customer
  end

  after { Current.customer = nil }


  describe "with a plan limit of 1" do
    before do
      plan = create_plan_with_page_limit(1)
      live_sub_for(customer, plan)
    end

    it "allows creating the first page (under limit)" do
      expect {
        post "/#{customer.id}/admin/maintenance/pages", params: valid_params
      }.to change(Page, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end

    it "blocks creating when at the limit — returns 422 and does not persist the record" do
      create(:page, customer: customer, entity: entity, name: "Existing Page")

      expect {
        post "/#{customer.id}/admin/maintenance/pages", params: valid_params
      }.not_to change(Page, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Upgrade your plan")
    end
  end

  describe "with an unlimited plan (-1)" do
    before do
      plan = create_plan_with_page_limit(Billing::PlanLimit::UNLIMITED)
      live_sub_for(customer, plan)
    end

    it "allows creating past 1 page" do
      create(:page, customer: customer, entity: entity, name: "Existing Page")

      expect {
        post "/#{customer.id}/admin/maintenance/pages", params: valid_params
      }.to change(Page, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "platform owner bypass (customer 81721200)" do
    before { ensure_platform_customer }

    it "bypasses limits even with a zero-limit plan" do
      platform_customer = Customer.find(Authentication::User::PLATFORM_CUSTOMER_ID)
      platform_entity = create(:entity, customer: platform_customer)
      plan = create_plan_with_page_limit(0)
      live_sub_for(platform_customer, plan)

      platform_owner = find_or_create_platform_owner
      sign_in platform_owner
      Current.customer = platform_customer

      expect {
        post "/#{platform_customer.id}/admin/maintenance/pages",
             params: { page: { name: "Owner Page", entity_id: platform_entity.id.to_s } }
      }.to change(Page, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "multi-tenant isolation" do
    let(:customer_b) { create(:customer) }
    let(:admin_b)    { create(:user, :admin, customer: customer_b) }
    let(:entity_b)   { create(:entity, customer: customer_b) }

    before do
      # Customer A: limit of 1, already at limit
      plan_a = create_plan_with_page_limit(1)
      live_sub_for(customer, plan_a)
      create(:page, customer: customer, entity: entity, name: "A Page")

      # Customer B: limit of 5 (plenty of room)
      plan_b = create_plan_with_page_limit(5)
      live_sub_for(customer_b, plan_b)
    end

    it "customer A at limit does not block customer B" do
      sign_in admin_b
      Current.customer = customer_b

      expect {
        post "/#{customer_b.id}/admin/maintenance/pages",
             params: { page: { name: "B Page", entity_id: entity_b.id.to_s } }
      }.to change(Page, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end
  end
end

RSpec.describe "Admin::Maintenance::Pages out-of-date badge", type: :request do
  let(:badge_customer) { create(:customer) }
  let(:badge_admin) { create(:user, :admin, customer: badge_customer) }

  it "shows Out of date when the entity moved past the form's version" do
    sign_in badge_admin
    name = { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" }
    entity = create(:entity, customer: badge_customer, name: "Student", property_schema: [name].to_json)
    form = create(:page, customer: badge_customer, entity: entity)
    form.update_column(:entity_version_id, entity.current_version_id)
    entity.property_schema_json = [name, name.merge("name" => "Email", "name_slug" => "email")]
    entity.save!(validate: false)

    get "/#{badge_customer.id}/admin/maintenance/pages/#{form.id}"

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).text).to include(I18n.t("admin_misc.pages.out_of_date"))
  end
end
