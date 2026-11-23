# frozen_string_literal: true

require "rails_helper"

# ---------------------------------------------------------------------------
# Flowchart traces endpoint — POST /:cid/admin/maintenance/flowcharts/:id/traces
#
# Scope:
#  1. Happy path: admin runs a trivial flowchart and gets the structured trace
#     payload back (success/signal/trace/trace_nodes/queries/context/errors/error/timeout)
#  2. Result passthrough: queries (with SQL truncation) and the timeout flag
#     from canned ActivityTracer Results (executing real long activities in a
#     request spec is deliberately avoided)
#  3. Authorization matrix: admin OK, member blocked, anonymous redirected,
#     cross-tenant admin blocked, platform owner allowed
#  4. Tenant scoping parity with FlowchartsController#find_flowchart:
#     foreign flowchart id under own cid → 404; shared flowchart → visible
# ---------------------------------------------------------------------------

RSpec.describe "Maintenance::Flowcharts traces endpoint", type: :request do
  let(:customer)  { create(:customer) }
  let(:admin)     { create(:user, :admin, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }
  let(:entity)    { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

  def traces_path(cid: customer.id, flowchart_id: flowchart.id)
    "/#{cid}/admin/maintenance/flowcharts/#{flowchart_id}/traces"
  end

  def post_trace(input = {}, **path_args)
    post traces_path(**path_args), params: { input: input }, as: :json
  end

  # --- canned ActivityTracer Results (avoid running heavy activities) --------

  def canned_result(**overrides)
    ActivityTracer::Result.new(
      success?: true,
      signal: nil,
      ctx: { answer: 42 },
      trace: "trace output",
      trace_nodes: [
        { id: "process", element_id: "process_1", label: "Process", status: :success, signal: "Class" }
      ],
      error: nil,
      queries: [],
      timeout?: false,
      **overrides
    )
  end

  def stub_tracer(result)
    tracer = instance_double(ActivityTracer, call: result)
    allow(ActivityTracer).to receive(:new).and_return(tracer)
    tracer
  end

  # -------------------------------------------------------------------------
  # Happy path: same-tenant admin, real (trivial) execution
  # -------------------------------------------------------------------------
  context "when signed in as admin (own tenant)" do
    before { sign_in platform_owner }

    it "executes the flowchart and returns the full structured payload" do
      post_trace

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to include(
        "success", "signal", "trace", "trace_nodes", "queries", "context", "errors", "error", "timeout", "trace_truncated"
      )
      expect(body["success"]).to be true
      expect(body["timeout"]).to be false
      expect(body["trace_truncated"]).to be false
      expect(body["error"]).to be_nil
      expect(body["errors"]).to eq([])
      expect(body["trace_nodes"]).to be_an(Array)
      expect(body["trace_nodes"].map { |n| n["element_id"] }).to include("process_1")
      expect(body["queries"]).to be_an(Array)
    end

    it "returns unique non-blank string errors from ctx[:errors] on a failure-track Result" do
      stub_tracer(canned_result(
        success?: false,
        ctx: { errors: ["Name can't be blank", "Name can't be blank", "", 42, nil, "Email is invalid"] }
      ))

      post_trace

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be false
      expect(response.parsed_body["errors"]).to eq(
        ["Name can't be blank", "Email is invalid"]
      )
    end

    it "returns errors: [] when ctx[:errors] is absent" do
      stub_tracer(canned_result(success?: false, ctx: { answer: 1 }))

      post_trace

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["errors"]).to eq([])
    end

    it "passes the deep-symbolized input through to the tracer" do
      tracer = stub_tracer(canned_result)

      post_trace({ name: "Test", nested: { value: 1 } })

      expect(response).to have_http_status(:ok)
      expect(tracer).to have_received(:call).with(
        hash_including(
          name: "Test", nested: { value: 1 }, customer_id: customer.id,
          authentication: an_instance_of(FlowchartRuntime::Authentication),
          bound_entity: nil,
          model: nil,
          page_record: nil,
          current_user_id: platform_owner.id,
          request_ip: kind_of(String),
          user_agent: nil,
          locale: I18n.locale.to_s,
          request_id: kind_of(String)
        )
      )
    end

    it "seeds a new record of the bound page's entity as the runtime model" do
      create(:page, customer: customer, entity: entity, flowchart: flowchart)
      tracer = stub_tracer(canned_result)

      post_trace

      expect(tracer).to have_received(:call) do |input|
        expect(input[:bound_entity]).to eq(entity)
        expect(input[:model]).to be_a(EntityEntry)
        expect(input[:model]).to be_new_record
        expect(input[:model].entity_id).to eq(entity.id)
        expect(input[:model].customer_id).to eq(customer.id)
        expect(input[:page_record]).to eq(input[:model])
      end
    end

    it "runs with no model when no page is bound to the flowchart" do
      tracer = stub_tracer(canned_result)

      post_trace

      expect(tracer).to have_received(:call).with(
        hash_including(bound_entity: nil, model: nil, page_record: nil)
      )
    end

    it "seeds request metadata after posted input so testers cannot overwrite it" do
      tracer = stub_tracer(canned_result)

      post_trace({ request_ip: "1.2.3.4", locale: "injected", request_id: "forged", user_agent: "forged-ua" })

      expect(tracer).to have_received(:call).with(
        hash_including(
          request_ip: kind_of(String),
          locale: I18n.locale.to_s,
          request_id: kind_of(String)
        )
      )
      expect(tracer).not_to have_received(:call).with(hash_including(request_ip: "1.2.3.4"))
      expect(tracer).not_to have_received(:call).with(hash_including(request_id: "forged"))
    end

    it "executes session authentication using the request principal and route tenant, not posted identity data" do
      owner_customer = platform_owner.customer
      owner_entity = create(:entity, customer: owner_customer)
      owner_flowchart = create(:flowchart, :simple, :draft, customer: owner_customer)
      method = CodeGenerators::ElementTypes::Process::Security::AuthenticateGenerator.new(
        { "config" => { "authMethod" => "session" } }, {}
      ).generate_step_method
      owner_flowchart.update_column(:activity, <<~RUBY)
        class SessionTraceActivity < Trailblazer::Activity::Railway
          CANVAS = { steps: { authenticate: "process_1" } }.freeze
          step :authenticate
          #{method}
        end
      RUBY
      post traces_path(cid: owner_customer.id, flowchart_id: owner_flowchart.id),
           params: { input: { authentication: { user_id: create(:user).id }, customer_id: create(:customer).id } },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(response.parsed_body.dig("context", "customer_id")).to eq(owner_customer.id)
      expect(response.parsed_body.dig("context", "authentication")).to eq("#<FlowchartRuntime::Authentication>")
    end

    it "returns an error payload for a flowchart without generated activity code" do
      flowchart.update_column(:activity, nil)

      post_trace

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["success"]).to be false
      expect(body["timeout"]).to be false
      expect(body["error"]).to eq(I18n.t("flowchart_elements.trace.errors.no_activity_code"))
      expect(body["error"]).to eq("No activity code generated")
      expect(body["trace_nodes"]).to eq([])
      expect(body["trace_truncated"]).to be false
    end

    it "keeps SECRET_EXCEPTION_TEXT out of the traces JSON error" do
      patched = flowchart.activity.sub(
        /def process\(ctx, \*\*\)\n    true/,
        "def process(ctx, **)\n    raise \"SECRET_EXCEPTION_TEXT\""
      )
      flowchart.update_column(:activity, patched)

      post_trace

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["success"]).to be false
      expect(body["error"]).to eq(I18n.t("flowchart_elements.trace.errors.execution_failed"))
      expect(body["error"]).not_to include("SECRET_EXCEPTION_TEXT")
      expect(response.body).not_to include("SECRET_EXCEPTION_TEXT")
    end

    it "renders the zh-CN execution_failed message and still omits SECRET_EXCEPTION_TEXT" do
      patched = flowchart.activity.sub(
        /def process\(ctx, \*\*\)\n    true/,
        "def process(ctx, **)\n    raise \"SECRET_EXCEPTION_TEXT\""
      )
      flowchart.update_column(:activity, patched)

      post traces_path, params: { input: {}, locale: "zh-CN" }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["error"]).to eq(I18n.t("flowchart_elements.trace.errors.execution_failed", locale: :"zh-CN"))
      expect(body["error"]).not_to include("SECRET_EXCEPTION_TEXT")
      expect(body["error"]).not_to eq("Execution failed")
    end

    it "redacts password, token, and secret keys in the final context" do
      post_trace({
        password: "hunter2",
        user_token: "tok-live",
        client_secret: "shh",
        name: "visible"
      })

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

    # --- queries passthrough + SQL truncation ---

    it "renders captured queries from the tracer Result" do
      stub_tracer(canned_result(
        queries: [{ sql: "SELECT 1", duration_ms: 0.42, name: "Probe" }]
      ))

      post_trace

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["queries"]).to eq(
        [{ "sql" => "SELECT 1", "duration_ms" => 0.42, "name" => "Probe" }]
      )
    end

    it "truncates query SQL longer than 4000 characters" do
      stub_tracer(canned_result(
        queries: [{ sql: "S" * 5_000, duration_ms: 1.0, name: "Big" }]
      ))

      post_trace

      sql = response.parsed_body["queries"].first["sql"]
      expect(sql.length).to be < 4_100
      expect(sql).to end_with(I18n.t("maint_core.flowcharts.editor.sql_truncated_suffix"))
      expect(I18n.t("maint_core.flowcharts.editor.sql_truncated_suffix", locale: :en)).to eq("…(truncated)")
    end

    it "translates the SQL clamp suffix in zh-CN" do
      stub_tracer(canned_result(
        queries: [{ sql: "S" * 5_000, duration_ms: 1.0, name: "Big" }]
      ))

      post traces_path, params: { input: {}, locale: "zh-CN" }, as: :json

      sql = response.parsed_body["queries"].first["sql"]
      expect(sql).to end_with(I18n.t("maint_core.flowcharts.editor.sql_truncated_suffix", locale: :"zh-CN"))
      expect(sql).not_to end_with("…(truncated)")
    end

    # --- timeout passthrough ---

    it "renders timeout: true with success: false for a timed-out Result" do
      stub_tracer(canned_result(
        success?: false,
        timeout?: true,
        trace: nil,
        trace_nodes: [],
        ctx: {},
        error: "Execution timed out after 10 seconds"
      ))

      post_trace

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["timeout"]).to be true
      expect(body["success"]).to be false
      expect(body["error"]).to include("timed out")
      expect(body["trace_truncated"]).to be false
    end

    it "renders trace_truncated from the Result" do
      stub_tracer(canned_result(truncated: true, trace_nodes: Array.new(500) { |i| { id: "n#{i}" } }))

      post_trace

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["trace_truncated"]).to be true
      expect(response.parsed_body["trace_nodes"].size).to eq(500)
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
      post_trace({}, flowchart_id: foreign_flowchart.id)

      expect(response).to have_http_status(:not_found)
    end

    it "allows tracing a shared flowchart (visible to every tenant)" do
      shared = create(:flowchart, :shared_type)

      post_trace({}, flowchart_id: shared.id)

      expect(response).to have_http_status(:ok)
    end

    it "responds 404 for the tenant's own soft-deleted flowchart" do
      flowchart.soft_delete

      post_trace

      expect(response).to have_http_status(:not_found)
    end
  end

  # -------------------------------------------------------------------------
  # Authorization matrix
  # -------------------------------------------------------------------------

  let(:guard_path) { traces_path }

  it_behaves_like "a platform-owner-guarded request", :post
  it_behaves_like "redirects anonymous away from flowchart editor", :post

  context "when signed in as admin of a DIFFERENT tenant (cross-tenant isolation)" do
    let(:other_customer) { create(:customer) }
    let(:other_admin)    { create(:user, :admin, customer: other_customer) }

    before { sign_in other_admin }

    it "cannot trace another tenant's flowchart" do
      post_trace

      expect(response).not_to have_http_status(:ok)
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "when signed in as the platform owner (cross-tenant access allowed)" do
    before do
      ensure_platform_customer
      sign_in find_or_create_platform_owner
    end

    it "can trace any tenant's flowchart" do
      post_trace

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be true
    end
  end
end
