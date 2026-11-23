# frozen_string_literal: true

require "rails_helper"

# Phase 1 Task 10 — restore payload, in-memory traces, editor URL/label
# attributes, and create-from-template (no hidden configuration field).
RSpec.describe "Admin::Maintenance::Flowcharts phase-1 endpoints", type: :request do
  include_context "as platform owner on tenant"

  let(:entity) { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }
  let(:platform_cid) { Authentication::User::PLATFORM_CUSTOMER_ID }
  let(:owner) { find_or_create_platform_owner }

  def snap!(fc, description: nil)
    content = fc.content_class.store!(customer_id: fc.customer_id, payload: { "_marker" => SecureRandom.hex(8) })
    fc.commit_version!(description: description, content: content)
  end

  def versions_path(fc = flowchart, cid = customer.id)
    "/#{cid}/admin/maintenance/flowcharts/#{fc.id}/versions"
  end

  def traces_path(fc = flowchart, cid = customer.id)
    "/#{cid}/admin/maintenance/flowcharts/#{fc.id}/traces"
  end

  def canvas_urls_from(body)
    el = Nokogiri::HTML(body).at_css("[data-flowchart-canvas-urls-value]")
    JSON.parse(el["data-flowchart-canvas-urls-value"])
  end

  def failing_process_graph
    {
      "elements" => [
        { "id" => "start", "type" => "start", "label" => "Start", "properties" => {} },
        {
          "id" => "process",
          "type" => "process",
          "label" => "Must Fail",
          "properties" => {
            "steps" => [
              { "action" => "find_model", "config" => { "findStrategy" => "find", "idExpression" => "params.id" } }
            ]
          }
        },
        { "id" => "end", "type" => "end", "label" => "End", "properties" => {} }
      ],
      "connections" => [
        { "from" => "start", "to" => "process" },
        { "from" => "process", "to" => "end" }
      ],
      "metadata" => {}
    }
  end

  describe "POST restore (versions#create)" do
    let(:guard_path) { versions_path }

    it_behaves_like "a platform-owner-guarded request", :post

    it "returns JSON with configuration equal to the restored version payload" do
      snap!(flowchart, description: "keep")
      target = flowchart.flowchart_versions.ordered.first
      changed = JSON.parse(flowchart.configuration)
      changed["metadata"] ||= {}
      changed["metadata"]["canvas"] = { "width" => 9999, "height" => 800 }
      flowchart.update!(configuration: changed.to_json)

      post versions_path, params: { version_id: target.id }, as: :json

      expect(response).to have_http_status(:ok)
      payload = flowchart.reload.resolved_current_version.content.payload
      expect(response.parsed_body["configuration"]).to eq(payload)
    end
  end

  describe "POST traces with posted configuration" do
    let(:guard_path) { traces_path }

    it_behaves_like "a platform-owner-guarded request", :post

    it "traces the posted unsaved graph and does not persist" do
      flowchart.reload
      stored_config = flowchart.configuration
      stored_activity = flowchart.activity
      versions_before = FlowchartVersion.count

      post traces_path,
           params: { input: {}, configuration: failing_process_graph.to_json },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["errors"]).to eq([I18n.t("flowchart_runtime.errors.record_not_found")])
      expect(FlowchartVersion.count).to eq(versions_before)
      expect(flowchart.reload.configuration).to eq(stored_config)
      expect(flowchart.activity).to eq(stored_activity)
      expect(flowchart.configuration_json.dig("elements").map { |el| el["label"] }).not_to include("Must Fail")
    end

    it "forbids a cross-tenant admin from tracing another tenant's flowchart" do
      other_admin = create(:user, :admin, customer: create(:customer))
      sign_in other_admin

      post traces_path, params: { input: {}, configuration: failing_process_graph.to_json }, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "traces the posted graph for a shared flowchart on the tenant prefix with no override" do
      shared = create(:flowchart, :shared_type, :simple, :draft, name: "Shared Tenant Preview")
      stored_config = shared.reload.configuration
      stored_activity = shared.activity
      versions_before = FlowchartVersion.count

      post traces_path(shared, customer.id),
           params: { input: {}, configuration: failing_process_graph.to_json },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(false)
      expect(FlowchartVersion.count).to eq(versions_before)
      expect(shared.reload.configuration).to eq(stored_config)
      expect(shared.activity).to eq(stored_activity)
    end

    it "rejects an oversize posted configuration with 422" do
      oversize = failing_process_graph.merge(
        "elements" => Array.new(FlowchartServerValidator::MAX_ELEMENTS + 1) do |i|
          { "id" => "el_#{i}", "type" => "process", "label" => "P#{i}", "properties" => { "steps" => [] } }
        end
      )

      post traces_path, params: { input: {}, configuration: oversize.to_json }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("maint_core.flowcharts.editor.server_check_unavailable"))
    end

    it "rejects malformed configuration JSON with 422" do
      post traces_path, params: { input: {}, configuration: "{not-json" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("maint_core.errors.page_templates.invalid_configuration"))
    end

    it "rejects a configuration without an elements array with 422" do
      post traces_path, params: { input: {}, configuration: { "connections" => [] }.to_json }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("maint_core.errors.page_templates.invalid_configuration"))
    end

    it "rejects code generation that exceeds the server-validator timeout with 422" do
      flowchart
      allow(ActivityGenerator).to receive(:new).and_raise(Timeout::Error)

      post traces_path, params: { input: {}, configuration: failing_process_graph.to_json }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("maint_core.flowcharts.editor.server_check_unavailable"))
    end

    it "runs a page_record flow, includes Save, and rolls back the insert" do
      named = create(:entity, :with_name_status_schema, customer: customer)
      fc = Flowchart.new_with_defaults(
        name: "Phase1 Trace Create",
        customer: customer,
        template: "page_record"
      )
      fc.save!
      create(:page, customer: customer, entity: named, flowchart: fc)

      expect {
        post traces_path(fc),
             params: { input: { params: { "name" => "v" } } },
             as: :json
      }.not_to change(EntityEntry, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(response.parsed_body["errors"]).to eq([])
      expect(response.parsed_body["trace_nodes"].map { |node| node["label"] }).to include(
        I18n.t("flowchart_elements.template_labels.save_model")
      )
    end

    it "returns collected validation errors for a blank required field on page_record" do
      named = create(:entity, customer: customer, property_schema: [
        {
          "name" => "Name",
          "name_slug" => "name",
          "type" => "String",
          "html_type" => "text",
          "validators" => [{ "type" => "presence" }]
        }
      ].to_json)
      fc = Flowchart.new_with_defaults(
        name: "Phase1 Trace Required",
        customer: customer,
        template: "page_record"
      )
      fc.save!
      create(:page, customer: customer, entity: named, flowchart: fc)

      post traces_path(fc), params: { input: { params: {} } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["errors"]).to include(a_string_matching(/can't be blank/i))
    end

    it "redacts password, token, and secret keys in the final context" do
      post traces_path,
           params: {
             input: {
               password: "hunter2",
               user_token: "tok-live",
               client_secret: "shh",
               name: "visible"
             }
           },
           as: :json

      expect(response).to have_http_status(:ok)
      ctx = response.parsed_body["context"]
      expect(ctx["password"]).to eq("[REDACTED]")
      expect(ctx["user_token"]).to eq("[REDACTED]")
      expect(ctx["client_secret"]).to eq("[REDACTED]")
      expect(ctx["name"]).to eq("visible")
      expect(response.body).not_to include("hunter2")
      expect(response.body).not_to include("tok-live")
      expect(response.body).not_to include("shh")
    end

    it "overrides injected customer_id, bound_entity, and authentication from input" do
      create(:page, customer: customer, entity: entity, flowchart: flowchart)
      post traces_path,
           params: {
             input: {
               customer_id: create(:customer).id,
               bound_entity: "injected",
               authentication: { user_id: create(:user).id },
               current_user_id: 0,
               current_user_role: "member",
               audience: "injected",
               device_type: "injected"
             }
           },
           as: :json

      expect(response).to have_http_status(:ok)
      ctx = response.parsed_body["context"]
      expect(ctx["customer_id"]).to eq(customer.id)
      expect(ctx["bound_entity"]).not_to eq("injected")
      expect(ctx["bound_entity"]).to include(entity.id.to_s)
      expect(ctx["authentication"]).to eq("#<FlowchartRuntime::Authentication>")
      expect(ctx["current_user_id"]).to eq(platform_owner.id)
      expect(ctx["current_user_role"]).to eq(platform_owner.primary_role_key)
      expect(ctx["audience"]).not_to eq("injected")
      expect(ctx["device_type"]).to eq(Pages::DeviceType.call(nil))
    end
  end

  describe "GET edit canvas URL prefixes" do
    it "renders platform-prefixed update URL on the Shared Resources edit page" do
      sign_in owner
      shared = create(:flowchart, :shared_type, :simple, :draft, name: "Phase1 Shared Editor")

      get "/#{platform_cid}/admin/maintenance/platform/flowcharts/#{shared.id}/edit"

      expect(response).to have_http_status(:ok)
      urls = canvas_urls_from(response.body)
      expect(urls["update"]).to start_with("/#{platform_cid}/admin/maintenance/platform/flowcharts/")
      expect(urls["stepIoParams"]).to include("__ACTION__")
      expect(urls["elementIoParams"]).to include("__TYPE__")
    end

    it "renders tenant-prefixed update URL on the tenant edit page for 81721200" do
      sign_in owner
      owned = create(:flowchart, :simple, :draft, customer: owner.customer)

      get "/#{platform_cid}/admin/maintenance/flowcharts/#{owned.id}/edit"

      expect(response).to have_http_status(:ok)
      urls = canvas_urls_from(response.body)
      expect(urls["update"]).to start_with("/#{platform_cid}/admin/maintenance/flowcharts/")
      expect(urls["update"]).not_to include("/platform/flowcharts/")
    end

    it "passes editor label values matching the JS defaults" do
      get "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-flowchart-canvas-unsaved-changes-confirm-value="You have unsaved changes. Leave this page?"')
      expect(response.body).to include('data-flowchart-canvas-expand-subflow-title-value="Expand sub-flow"')
      expect(response.body).to include('data-flowchart-canvas-collapse-subflow-title-value="Collapse sub-flow"')
      expect(response.body).to include('data-flowchart-canvas-connection-into-start-rejected-value="A Start element cannot have incoming connections"')
      expect(response.body).to include('data-flowchart-canvas-connection-out-of-end-rejected-value="An End element cannot have outgoing connections"')
      expect(response.body).to include('data-flowchart-canvas-test-decision-branch-format-value="{step} → {branch}"')
      expect(response.body).to include('data-flowchart-canvas-test-trace-truncated-format-value="Showing the first {count} steps; the run had more."')
    end
  end

  describe "GET new" do
    it "renders no flowchart[configuration] input" do
      get "/#{customer.id}/admin/maintenance/flowcharts/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('name="flowchart[configuration]"')
    end
  end

  describe "POST create with page_record template" do
    it "yields the page_record graph" do
      post "/#{customer.id}/admin/maintenance/flowcharts",
           params: { flowchart: { name: "Phase1 Page Record", template: "page_record" } }

      expect(response).to have_http_status(:redirect)
      created = Flowchart.find_by!(name: "Phase1 Page Record")
      expected = Flowchart.template_configurations["page_record"]
      expect(created.configuration_json["elements"]).to eq(expected["elements"])
      expect(created.configuration_json["connections"]).to eq(expected["connections"])
    end
  end
end
