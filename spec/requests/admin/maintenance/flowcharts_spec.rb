# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Flowcharts", type: :request do
  include_context "as platform owner on tenant"

  let!(:flowchart) { create(:flowchart, customer: customer) }
  let(:platform_cid) { Authentication::User::PLATFORM_CUSTOMER_ID }

  def flowcharts_path(cid = customer.id) = "/#{cid}/admin/maintenance/flowcharts"
  def flowchart_path(fc = flowchart) = "#{flowcharts_path}/#{fc.id}"

  # Force a genuinely new version row (content-addressed store dedups equal
  # payloads, so `commit_version!` alone would no-op). Mirrors the old
  # `create_version_snapshot!`, which unconditionally created a new version.
  def snap!(fc, description: nil, based_on_version_id: nil)
    content = fc.content_class.store!(customer_id: fc.customer_id, payload: { "_marker" => SecureRandom.hex(8) })
    fc.commit_version!(description: description, based_on_version_id: based_on_version_id, content: content)
  end

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "authorization guards" do
    let(:guard_path) { flowcharts_path }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET new — auth guards" do
    let(:guard_path) { "#{flowcharts_path}/new" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { "#{flowchart_path}/edit" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "POST create — auth guards" do
    let(:guard_path) { flowcharts_path }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { flowchart_path }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "GET show — auth guards" do
    let(:guard_path) { flowchart_path }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { flowchart_path }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  # ---------------------------------------------------------------------------
  # GET index — HTML
  # ---------------------------------------------------------------------------

  describe "GET index — HTML" do
    it "returns 200 and lists flowcharts" do
      get flowcharts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(flowchart.name)
    end

    it "renders the version-history modal controller on the list page" do
      get flowcharts_path
      expect(response.body).to include('data-controller="versions"')
      expect(response.body).to include("data-versions-customer-id-value")
    end

    it "shows the default version number in the versions column, not a count" do
      snap!(flowchart, description: "v1")
      v = snap!(flowchart, description: "v2")

      get flowcharts_path
      expect(response.body).to match(/>\s*v#{v.version_number}\s*</)
    end

    it "offers no entity filter, since flowcharts are not bound to an entity" do
      get flowcharts_path

      expect(Nokogiri::HTML(response.body).css("select[name='entity_id']")).to be_empty
    end
  end

  describe "GET new — templates" do
    it "offers the blank and page-record templates without an entity picker" do
      get "#{flowcharts_path}/new"

      html = Nokogiri::HTML(response.body)
      expect(html.css("[data-flowchart-form-target='templateCard']").map { |card| card["data-template"] }).to eq(%w[blank page_record])
      expect(html.at_css("select[name='flowchart[entity_id]']")).to be_nil
      expect(html.at_css("select[name='flowchart[crud_type]']")).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # GET index — JSON (except_id branch)
  # ---------------------------------------------------------------------------

  describe "GET index — JSON" do
    it "returns a JSON array of flowcharts with elements" do
      get "#{flowcharts_path}.json"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_an(Array)
    end

    it "excludes the specified flowchart when except_id is provided" do
      other = create(:flowchart, customer: customer)

      get "#{flowcharts_path}.json", params: { except_id: flowchart.id }

      ids = response.parsed_body.map { |f| f["id"] }
      expect(ids).not_to include(flowchart.id)
    end
  end

  # JSON index is unpaginated (returns every flowchart with elements). Pagination
  # is HTML-only via Listable, so these examples hit the HTML list.
  describe "GET index — pagination" do
    it "does not honour a crafted per_page query param" do
      create_list(:flowchart, 3, customer: customer)

      get flowcharts_path, params: { per_page: 2 }

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css("tbody tr").size).to eq(4)
    end

    it "paginates the index at the application default page size" do
      create_list(:flowchart, Listable::DEFAULT_PER_PAGE, customer: customer)

      get flowcharts_path

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css("tbody tr").size).to eq(Listable::DEFAULT_PER_PAGE)
    end
  end

  # ---------------------------------------------------------------------------
  # GET show / new / edit
  # ---------------------------------------------------------------------------

  describe "GET show, new, and edit HTML" do
    it "returns 200 for each form page" do
      [flowchart_path, "#{flowcharts_path}/new", "#{flowchart_path}/edit"].each do |path|
        get path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET show — HTML" do
    it "returns 404 for a non-existent flowchart" do
      get "#{flowcharts_path}/non-existent"
      expect(response).to have_http_status(:not_found)
    end

    it "lists the tenant's pages bound to the flowchart" do
      entity = create(:entity, customer: customer, display_label: "Student")
      bound = create(:page, customer: customer, entity: entity, flowchart: flowchart, name: "Enrol student")
      create(:page, customer: customer, entity: entity, name: "Unrelated page")

      get flowchart_path

      list = Nokogiri::HTML(response.body).at_css("[data-role='bound-pages']")
      expect(list.text).to include(bound.name, "Student")
      expect(list.text).not_to include("Unrelated page")
    end

    it "lists only this tenant's pages for a shared flowchart" do
      shared = create(:flowchart, :shared_type, :launched_status, name: "Shared save")
      mine = create(:page, customer: customer, flowchart: shared, name: "My page")
      other_customer = create(:customer)
      theirs = Current.set(customer: other_customer) { create(:page, customer: other_customer, flowchart: shared, name: "Their page") }

      get flowchart_path(shared)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mine.name)
      expect(response.body).not_to include(theirs.name)
    end
  end

  describe "GET show — JSON" do
    it "returns the flowchart as JSON with expected fields" do
      get "#{flowchart_path}.json"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(flowchart.id)
      expect(body["name"]).to eq(flowchart.name)
      expect(body).to have_key("configuration")
      expect(body).to have_key("updated_at")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create
  # ---------------------------------------------------------------------------

  describe "POST create — valid params" do
    it "creates a flowchart and redirects to the edit page" do
      entity = create(:entity, customer: customer)

      expect {
        post flowcharts_path,
             params: { flowchart: { name: "My New Flowchart", entity_id: entity.id } }
      }.to change(Flowchart, :count).by(1)

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("edit")
    end
  end

  describe "POST create — invalid params (blank name)" do
    it "re-renders new with 422" do
      post flowcharts_path, params: { flowchart: { name: "" } }

      # A flowchart without name fails validation — entity also required for
      # customer_specific type; either error causes the re-render.
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH update
  # ---------------------------------------------------------------------------

  describe "PATCH update — HTML, configuration unchanged" do
    it "updates the name and redirects to show" do
      patch flowchart_path, params: { flowchart: { name: "Renamed Flowchart" } }

      expect(response).to have_http_status(:redirect)
      expect(flowchart.reload.name).to eq("Renamed Flowchart")
    end
  end

  describe "PATCH update — JSON, configuration changed" do
    def widened(fc, width)
      JSON.parse(fc.configuration).tap { |config| config["metadata"]["canvas"] = { "width" => width } }.to_json
    end

    it "revises the head version of a draft flowchart in place" do
      head = flowchart.current_version

      expect {
        patch "#{flowchart_path}.json", params: { flowchart: { name: flowchart.name, configuration: widened(flowchart, 1400) } }
      }.not_to change { FlowchartVersion.where(flowchart: flowchart).count }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("success")
      expect(flowchart.reload.current_version_id).to eq(head.id)
      expect(JSON.parse(head.reload.payload).dig("metadata", "canvas", "width")).to eq(1400)
    end

    context "when the flowchart is launched" do
      let!(:flowchart) { create(:flowchart, :launched_status, customer: customer) }

      it "forks a draft version and keeps the launched version and its activity live" do
        launched = flowchart.launched_version
        activity = flowchart.activity

        expect {
          patch "#{flowchart_path}.json", params: { flowchart: { configuration: widened(flowchart, 1400) } }, as: :json
        }.to change { FlowchartVersion.where(flowchart: flowchart).count }.by(1)

        expect(response).to have_http_status(:ok)
        flowchart.reload
        expect(flowchart).to be_launched
        expect(flowchart.launched_version_id).to eq(launched.id)
        expect(flowchart.current_version.based_on_version_id).to eq(launched.id)
        expect(flowchart.activity).to eq(activity)
        expect(response.parsed_body["version_id"]).to eq(flowchart.current_version_id)
      end

      it "revises that draft version on the next save" do
        patch "#{flowchart_path}.json", params: { flowchart: { configuration: widened(flowchart, 1400) } }, as: :json
        draft_id = flowchart.reload.current_version_id

        expect {
          patch "#{flowchart_path}.json", params: { flowchart: { configuration: widened(flowchart, 1500) } }, as: :json
        }.not_to change { FlowchartVersion.where(flowchart: flowchart).count }

        flowchart.reload
        expect(flowchart.current_version_id).to eq(draft_id)
        expect(JSON.parse(flowchart.current_version.payload).dig("metadata", "canvas", "width")).to eq(1500)
        expect(JSON.parse(flowchart.launched_version.payload).dig("metadata", "canvas", "width")).not_to eq(1500)
      end

      it "refuses a rename while launched" do
        patch flowchart_path, params: { flowchart: { name: "Renamed while live" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flowchart.reload.name).not_to eq("Renamed while live")
      end
    end
  end

  describe "PATCH update — head-version conflict" do
    def changed_config(fc, width)
      JSON.parse(fc.configuration).merge("metadata" => { "canvas" => { "width" => width } }).to_json
    end

    let!(:loaded_head) { flowchart.current_line_head_version_id }

    it "returns the line head and its new revision on success" do
      loaded_revision = flowchart.current_line_head_revision
      patch "#{flowchart_path}.json",
            params: { flowchart: { configuration: changed_config(flowchart, 1401) },
                      expected_head_version_id: loaded_head, expected_head_revision: loaded_revision },
            as: :json

      expect(response).to have_http_status(:ok)
      flowchart.reload
      expect(response.parsed_body["version_id"]).to eq(flowchart.current_line_head_version_id)
      expect(response.parsed_body["head_revision"]).to eq(flowchart.current_line_head_revision)
      expect(response.parsed_body["head_revision"]).not_to eq(loaded_revision)
    end

    it "answers 409 JSON with the current head and saves nothing when another save moved the head" do
      snap!(flowchart, description: "saved in another tab")
      flowchart.reload
      head = flowchart.current_line_head_version_id

      expect {
        patch "#{flowchart_path}.json",
              params: { flowchart: { configuration: changed_config(flowchart, 1402) }, expected_head_version_id: loaded_head },
              as: :json
      }.not_to(change { [flowchart.reload.configuration, FlowchartVersion.where(flowchart: flowchart).count] })

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq(
        "status" => "conflict",
        "message" => I18n.t("maint_core.flash.flowcharts.save_conflict"),
        "head_version_id" => head,
        "head_revision" => flowchart.current_line_head_revision
      )
    end

    it "answers 409 when another tab revised the same draft head in place" do
      loaded_revision = flowchart.current_line_head_revision
      travel(1.second) { Flowchart.find(flowchart.id).update!(configuration: changed_config(flowchart, 1405)) }
      expect(flowchart.reload.current_line_head_version_id).to eq(loaded_head)

      expect {
        patch "#{flowchart_path}.json",
              params: { flowchart: { configuration: changed_config(flowchart, 1406) },
                        expected_head_version_id: loaded_head, expected_head_revision: loaded_revision },
              as: :json
      }.not_to(change { flowchart.reload.configuration })

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["head_revision"]).to eq(flowchart.current_line_head_revision)
    end

    it "redirects an HTML save back with the conflict alert" do
      snap!(flowchart)

      patch flowchart_path, params: { flowchart: { name: "Renamed" }, expected_head_version_id: loaded_head }

      expect(response).to redirect_to("#{flowchart_path}/edit")
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.flowcharts.save_conflict"))
      expect(flowchart.reload.name).not_to eq("Renamed")
    end

    it "treats an explicitly empty expected head as stale once the line has a head" do
      patch "#{flowchart_path}.json",
            params: { flowchart: { configuration: changed_config(flowchart, 1403) }, expected_head_version_id: "" },
            as: :json

      expect(response).to have_http_status(:conflict)
    end

    it "treats a missing head revision as stale" do
      expect {
        patch "#{flowchart_path}.json",
              params: { flowchart: { configuration: changed_config(flowchart, 1407) }, expected_head_version_id: loaded_head },
              as: :json
      }.not_to(change { flowchart.reload.configuration })

      expect(response).to have_http_status(:conflict)
    end

    it "overwrites when resent with the conflicting head" do
      edited = changed_config(flowchart, 1404)
      snap!(flowchart)
      flowchart.reload
      head = flowchart.current_line_head_version_id

      patch "#{flowchart_path}.json",
            params: { flowchart: { configuration: edited }, expected_head_version_id: head,
                      expected_head_revision: flowchart.current_line_head_revision },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(flowchart.reload.configuration).dig("metadata", "canvas", "width")).to eq(1404)
    end

    it "does not snapshot an unchanged save whose based_on is the head itself" do
      expect {
        patch "#{flowchart_path}.json",
              params: { flowchart: { configuration: flowchart.configuration },
                        expected_head_version_id: loaded_head, expected_head_revision: flowchart.current_line_head_revision,
                        based_on_version_id: loaded_head },
              as: :json
      }.not_to(change { FlowchartVersion.where(flowchart: flowchart).count })

      expect(response.parsed_body["version_id"]).to eq(loaded_head)
    end

    context "with a tenant override of a shared flowchart" do
      let(:shared_flowchart) { create(:flowchart, :shared_type, :draft) }
      let(:global_head) { shared_flowchart.current_version_id }

      before do
        ensure_platform_customer
        sign_in platform_owner
      end

      def override_head = FlowchartCustomerHead.find_by(flowchart_id: shared_flowchart.id, customer_id: customer.id)

      it "checks and returns the tenant's line head, never touching the global head" do
        global_revision = shared_flowchart.current_version.updated_at.utc.iso8601(6)
        patch "#{flowchart_path(shared_flowchart)}.json",
              params: { flowchart: { configuration: changed_config(shared_flowchart, 1405) },
                        expected_head_version_id: global_head, expected_head_revision: global_revision },
              as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["version_id"]).to eq(override_head.current_version_id)
        expect(shared_flowchart.reload.current_version_id).to eq(global_head)

        patch "#{flowchart_path(shared_flowchart)}.json",
              params: { flowchart: { configuration: changed_config(shared_flowchart, 1406) }, expected_head_version_id: global_head },
              as: :json

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body["head_version_id"]).to eq(override_head.current_version_id)
      end
    end
  end

  describe "PATCH update — JSON, invalid params" do
    it "returns 422 with status:error in the body when name is blank" do
      patch "#{flowchart_path}.json", params: { flowchart: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["status"]).to eq("error")
      expect(response.parsed_body["errors"]).to be_an(Array)
    end
  end

  describe "PATCH update — HTML, invalid params" do
    it "re-renders edit with 422" do
      patch flowchart_path, params: { flowchart: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy
  # ---------------------------------------------------------------------------

  describe "DELETE destroy" do
    it "soft-deletes the flowchart and redirects to index" do
      delete flowchart_path

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("flowcharts")
      expect(Flowchart.unscoped.find(flowchart.id).status).to eq("deleted")
      expect(Flowchart.exists?(flowchart.id)).to be(false)
      expect(Flowchart.only_deleted.exists?(flowchart.id)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Shared flowchart guard — regular tenant admin cannot mutate shared flowcharts
  # ---------------------------------------------------------------------------

  describe "guard_shared_write! — owner override of shared flowchart on a tenant path" do
    let(:shared_flowchart) do
      create(:flowchart, :shared_type, :draft)
    end

    before { ensure_platform_customer }

    it "writes a configuration override on HTML PATCH and ignores name" do
      sign_in platform_owner
      config = JSON.parse(shared_flowchart.configuration)
      config["elements"][1]["label"] = "Tenant Step"
      patch flowchart_path(shared_flowchart), params: { flowchart: { name: "Hacked", configuration: config.to_json } }

      expect(response).to have_http_status(:redirect)
      expect(shared_flowchart.reload.name).not_to eq("Hacked")
      expect(FlowchartCustomerHead.find_by(flowchart_id: shared_flowchart.id, customer_id: customer.id)).to be_present
    end

    it "writes a configuration override on JSON PATCH" do
      sign_in platform_owner
      config = JSON.parse(shared_flowchart.configuration)
      config["elements"][1]["label"] = "Tenant Json Step"
      patch "#{flowchart_path(shared_flowchart)}.json", params: { flowchart: { name: "Hacked", configuration: config.to_json } }

      expect(response).to have_http_status(:ok)
      expect(shared_flowchart.reload.name).not_to eq("Hacked")
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let!(:other_flowchart) { create(:flowchart, customer: other_customer) }

    it "returns 404 when accessing another tenant's flowchart via show" do
      get flowchart_path(other_flowchart)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when trying to edit another tenant's flowchart" do
      get "#{flowchart_path(other_flowchart)}/edit"
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # Platform owner — shared flowchart visibility in index
  # ---------------------------------------------------------------------------

  describe "shared flowchart visibility in index" do
    let!(:shared_flowchart) do
      create(:flowchart, :shared_type, name: "Shared Blueprint Flow")
    end

    before { ensure_platform_customer }

    it "lists shared flowcharts in the platform owner's index" do
      sign_in find_or_create_platform_owner

      get flowcharts_path(platform_cid)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Shared Blueprint Flow")
    end

    it "denies a regular customer admin the flowchart index" do
      sign_in admin

      get flowcharts_path
      expect(response.status).not_to eq(200)
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH update — version lineage (based_on tagging + default promotion)
  # ---------------------------------------------------------------------------

  describe "PATCH update — version lineage" do
    let(:entity)         { create(:entity, customer: customer) }
    let(:lineage_chart) { create(:flowchart, :simple, :draft, customer: customer) }

    def new_config = '{"elements":[{"id":"el_x","type":"start","x":1,"y":1,"width":100,"height":45,"label":"S","properties":{"inputs":[],"outputs":[]}}],"connections":[],"metadata":{}}'

    it "promotes a new snapshot to default and tags based_on when an older version is provided" do
      parent = lineage_chart.current_version
      snap!(lineage_chart, description: "v2")
      patch "#{flowchart_path(lineage_chart)}.json",
            params: { flowchart: { configuration: new_config }, based_on_version_id: parent.id }, as: :json
      expect(response).to have_http_status(:ok)
      lineage_chart.reload
      snap = lineage_chart.flowchart_versions.ordered.first
      expect(snap.version_number).to eq(3)
      expect(lineage_chart.current_version_id).to eq(snap.id)
      expect(snap.based_on_version_id).to eq(parent.id)
    end

    it "revises a draft head in place when based_on names the head itself" do
      head = snap!(lineage_chart, description: "v2")
      expect {
        patch "#{flowchart_path(lineage_chart)}.json",
              params: { flowchart: { configuration: new_config }, based_on_version_id: head.id }, as: :json
      }.not_to change { lineage_chart.flowchart_versions.count }
      expect(lineage_chart.reload.current_version_id).to eq(head.id)
      expect(JSON.parse(head.reload.payload)).to eq(JSON.parse(new_config))
    end

    it "drops a foreign based_on_version_id (falls back to the current head)" do
      other = create(:flowchart, :simple, :draft, customer: customer)
      foreign = snap!(other)
      head_before = lineage_chart.current_version_id
      patch "#{flowchart_path(lineage_chart)}.json",
            params: { flowchart: { configuration: new_config }, based_on_version_id: foreign.id }, as: :json
      snap = lineage_chart.reload.flowchart_versions.ordered.first
      # The foreign id belongs to another flowchart, so it is ignored; lineage
      # falls back to this flowchart's current head (no longer nil under auto-commit).
      expect(snap.based_on_version_id).not_to eq(foreign.id)
      expect(snap.based_on_version_id).to eq(head_before)
    end

    it "tags based_on with the launched version when no explicit id is given (Edit from list)" do
      lineage_chart.launch!
      launched = lineage_chart.launched_version
      patch "#{flowchart_path(lineage_chart)}.json",
            params: { flowchart: { configuration: new_config } }, as: :json
      expect(response).to have_http_status(:ok)
      snap = lineage_chart.reload.flowchart_versions.ordered.first
      expect(lineage_chart.current_version_id).to eq(snap.id)
      expect(snap.based_on_version_id).to eq(launched.id)
    end

    it "does not snapshot or change default when configuration is unchanged" do
      v = snap!(lineage_chart, description: "v1")
      expect {
        patch "#{flowchart_path(lineage_chart)}.json",
              params: { flowchart: { name: "Renamed only" } }, as: :json
      }.not_to change { lineage_chart.flowchart_versions.count }
      expect(lineage_chart.reload.current_version_id).to eq(v.id)
    end
  end
end
