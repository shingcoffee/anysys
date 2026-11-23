# frozen_string_literal: true

require "rails_helper"

# ---------------------------------------------------------------------------
# Flowchart validation endpoint — POST /:cid/admin/maintenance/flowcharts/:id/validation
#
# Scope:
#  1. Happy path: admin submits an in-memory canvas configuration and gets
#     structured problems back (camelCase keys), or an empty list when clean
#  2. Parameter guard: missing / non-hash configuration → 422 with problems: []
#  3. Authorization matrix: admin OK, member blocked, anonymous redirected,
#     cross-tenant admin blocked, platform owner allowed
#  4. Tenant scoping parity with FlowchartsController#find_flowchart:
#     foreign flowchart id under own cid → 404; shared flowchart → visible
# ---------------------------------------------------------------------------

RSpec.describe "Maintenance::Flowcharts validation endpoint", type: :request do
  include_context "as platform owner on tenant"

  let(:entity)    { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

  def validation_path(cid: customer.id, flowchart_id: flowchart.id)
    "/#{cid}/admin/maintenance/flowcharts/#{flowchart_id}/validation"
  end

  let(:guard_path) { validation_path }

  # --- configuration builders (mirror spec/factories/flowcharts.rb shapes) ---

  def element(id, type, label, properties = {})
    {
      "id" => id, "type" => type, "x" => 100, "y" => 100,
      "width" => 100, "height" => 45, "label" => label,
      "properties" => properties
    }
  end

  def linear_config(middle_element)
    {
      "elements" => [
        element("start_1", "start", "Start"),
        middle_element,
        element("end_1", "end", "End")
      ],
      "connections" => [
        { "id" => "c1", "from" => "start_1", "to" => middle_element["id"] },
        { "id" => "c2", "from" => middle_element["id"], "to" => "end_1" }
      ],
      "metadata" => {}
    }
  end

  def clean_config
    linear_config(element("process_1", "process", "Do Work", { "steps" => [] }))
  end

  def bad_subflow_config
    linear_config(
      element("subflow_1", "subflow", "Call Subflow", { "flowchartId" => 999_999_999 })
    )
  end

  def post_validation(configuration, **path_args)
    post validation_path(**path_args), params: { configuration: configuration }, as: :json
  end

  # -------------------------------------------------------------------------
  # Happy path: same-tenant admin
  # -------------------------------------------------------------------------
  context "when signed in as admin (own tenant)" do
    before { sign_in platform_owner }

    it "returns problems for a configuration with a broken subflow reference" do
      post_validation(bad_subflow_config)

      expect(response).to have_http_status(:ok)
      problems = response.parsed_body["problems"]
      expect(problems).to be_an(Array)
      expect(problems.map { |p| p["type"] }).to include("subflow_inaccessible")
    end

    it "renders problems with camelCase keys (elementId, connectionId, field, fixHint)" do
      post_validation(bad_subflow_config)

      problem = response.parsed_body["problems"].find { |p| p["type"] == "subflow_inaccessible" }
      expect(problem.keys).to match_array(%w[type severity message elementId connectionId field fixHint])
      expect(problem["elementId"]).to eq("subflow_1")
      expect(problem["connectionId"]).to be_nil
      expect(problem["field"]).to be_nil
      expect(problem["severity"]).to eq("error")
      expect(problem["fixHint"]).to be_present
    end

    it "includes ConfigValidator field on step_config_invalid problems" do
      bad_step = element(
        "process_1",
        "process",
        "Do Work",
        {
          "steps" => [
            {
              "id" => "s1",
              "action" => "find_model",
              "label" => "Look Up User",
              "config" => { "findBy" => "nonsense_strategy" }
            }
          ]
        }
      )
      post_validation(linear_config(bad_step))

      problem = response.parsed_body["problems"].find { |p| p["type"] == "step_config_invalid" }
      expect(problem).to be_present
      expect(problem["field"]).to eq("findBy")
      expect(problem["elementId"]).to eq("process_1")
      expect(problem["message"]).to include("findBy")
    end

    it "returns an empty problems list for a clean configuration" do
      post_validation(clean_config)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["problems"]).to eq([])
    end

    it "never persists the submitted configuration" do
      expect {
        post_validation(bad_subflow_config)
      }.not_to change { flowchart.reload.configuration }
    end

    it "reports invalid Decision topology and empty structured conditions" do
      decision = element(
        "decision_1",
        "decision",
        "Route",
        {
          "routeBy" => "condition",
          "condition" => {
            "type" => "group",
            "joins" => [],
            "conditions" => [
              { "kind" => "field", "leftOperand" => "", "operator" => "==", "rightOperand" => "x" }
            ]
          }
        }
      )

      post_validation(linear_config(decision))

      expect(response).to have_http_status(:ok)
      messages = response.parsed_body["problems"].map { |problem| problem["message"] }.join(" ")
      expect(messages).to include("requires at least two outgoing connections")
      expect(messages).to include("Condition row 1 needs a value to compare")
    end

    # --- parameter guard ---

    it "returns 422 with problems: [] when configuration is missing" do
      post validation_path, params: {}, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["problems"]).to eq([])
    end

    it "returns 422 with problems: [] when configuration is not a hash" do
      post_validation("not a hash")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["problems"]).to eq([])
    end

    it "returns 422 with problems: [] when configuration has no elements array" do
      post_validation({ "elements" => "nope" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["problems"]).to eq([])
    end

    it "never responds 500 for garbage entries INSIDE the elements array" do
      # Non-hash elements pass the controller's shape guard (elements IS an
      # array) and must be absorbed downstream: the subflow scan skips them
      # and the codegen dry-run converts any raise into a codegen_failed
      # problem rather than a server error.
      garbage = { "elements" => [123, "junk", nil, []], "connections" => [], "metadata" => {} }

      post_validation(garbage)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["problems"].map { |p| p["type"] }).to include("codegen_failed")
    end

    it "returns 422 with problems: [] when the validator raises unexpectedly" do
      allow(FlowchartServerValidator).to receive(:new).and_raise(RuntimeError, "boom")

      post_validation(clean_config)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["problems"]).to eq([])
    end
  end

  # -------------------------------------------------------------------------
  # Tenant scoping parity with FlowchartsController#find_flowchart
  # -------------------------------------------------------------------------
  context "tenant scoping (find_flowchart parity)" do
    let(:other_customer)   { create(:customer) }
    let(:other_entity)     { create(:entity, customer: other_customer) }
    let(:foreign_flowchart) do
      create(:flowchart, :simple, :draft, customer: other_customer)
    end

    before { sign_in platform_owner }

    it "responds 404 for another tenant's flowchart id under the admin's own cid" do
      post_validation(clean_config, flowchart_id: foreign_flowchart.id)

      expect(response).to have_http_status(:not_found)
    end

    it "allows validating a shared flowchart (visible to every tenant)" do
      shared = create(:flowchart, :shared_type)

      post_validation(clean_config, flowchart_id: shared.id)

      expect(response).to have_http_status(:ok)
    end

    it "responds 404 for the tenant's own soft-deleted flowchart (default scope excludes deleted)" do
      # Parity with FlowchartsController#find_flowchart: Flowchart.accessible
      # rides on default_scope { visible }, so a trashed flowchart is
      # indistinguishable from a missing id — validation of deleted
      # flowcharts is not a thing.
      flowchart.soft_delete

      post_validation(clean_config)

      expect(response).to have_http_status(:not_found)
    end
  end

  # -------------------------------------------------------------------------
  # Authorization matrix
  # -------------------------------------------------------------------------

  it_behaves_like "a platform-owner-guarded request", :post
  it_behaves_like "redirects anonymous away from flowchart editor", :post

  context "when signed in as admin of a DIFFERENT tenant (cross-tenant isolation)" do
    let(:other_customer) { create(:customer) }
    let(:other_admin)    { create(:user, :admin, customer: other_customer) }

    before { sign_in other_admin }

    it "cannot validate another tenant's flowchart" do
      post_validation(bad_subflow_config)

      expect(response).not_to have_http_status(:ok)
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "when signed in as the platform owner (cross-tenant access allowed)" do
    before do
      ensure_platform_customer
      sign_in find_or_create_platform_owner
    end

    it "can validate any tenant's flowchart" do
      post_validation(bad_subflow_config)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["problems"].map { |p| p["type"] })
        .to include("subflow_inaccessible")
    end
  end
end
