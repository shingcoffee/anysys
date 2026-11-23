# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tenant flowchart I/O introspection", type: :request do
  include_context "admin records"
  let(:other_customer) { create(:customer) }
  let(:member) { create(:user, :member, customer: customer) }
  let(:owner) { find_or_create_platform_owner }

  def step_path(action = "api_call", cid: customer.id)
    "/#{cid}/admin/maintenance/flowcharts/step_actions/#{action}/io_params"
  end

  def element_path(type = "process", cid: customer.id)
    "/#{cid}/admin/maintenance/flowcharts/element_types/#{type}/io_params"
  end

  let(:api_config) { { httpMethod: "GET", url: "ctx[:endpoint]", resultVar: "response", responseFormat: "json" } }

  describe "POST step_actions — auth guards" do
    let(:guard_path) { step_path }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "POST element_types — auth guards" do
    let(:guard_path) { element_path }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  shared_examples "tenant admin I/O authorization" do
    it "forbids a same-tenant admin before extraction" do
      sign_in admin
      expect(CodeGenerators::IoExtractor).not_to receive(extractor_method)
      post endpoint, params: payload, as: :json
      expect(response.status).not_to eq(200)
    end

    it "allows the platform owner on a tenant URL and on their own customer URL" do
      sign_in owner
      post endpoint, params: payload, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to contain_exactly("inputs", "outputs")
      expect(response.parsed_body["outputs"]).to include("pin" => "response", "ctx_key" => "response")

      post endpoint.sub("/#{customer.id}/", "/#{owner.customer_id}/"), params: payload, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "rejects anonymous callers before extraction" do
      expect(CodeGenerators::IoExtractor).not_to receive(extractor_method)
      post endpoint, params: payload, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects same-tenant members before extraction" do
      sign_in member
      expect(CodeGenerators::IoExtractor).not_to receive(extractor_method)
      post endpoint, params: payload, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a tenant admin requesting another customer's URL" do
      sign_in admin
      expect(CodeGenerators::IoExtractor).not_to receive(extractor_method)
      post endpoint.sub("/#{customer.id}/", "/#{other_customer.id}/"), params: payload, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    ["text", [], 42, false].each do |malformed|
      it "returns empty pins for malformed #{malformed.inspect} editor data" do
        sign_in owner
        expect(CodeGenerators::IoExtractor).not_to receive(extractor_method)
        post endpoint, params: { payload.keys.first => malformed }, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq("inputs" => [], "outputs" => [])
      end
    end

    it "accepts an omitted payload for an in-progress editor" do
      sign_in owner
      post endpoint, params: {}, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to contain_exactly("inputs", "outputs")
    end
  end

  describe "step actions" do
    let(:endpoint) { step_path }
    let(:payload) { { config: api_config } }
    let(:extractor_method) { :call }

    include_examples "tenant admin I/O authorization"

    it "returns config-expression pins for api_call without making a request" do
      sign_in owner
      post step_path("api_call"), params: payload, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["inputs"]).to include("pin" => "endpoint", "ctx_key" => "endpoint", "source" => "config_expr")
      expect(response.parsed_body["outputs"]).to include("pin" => "response", "ctx_key" => "response")
    end

    it "resolves query_models values as the surviving model-pluck surface without seeded tenancy pins" do
      sign_in owner
      klass = CodeGenerators::ElementTypes::Process::ModelOperations::QueryModelsGenerator
      config = klass.sample_input.merge("returns" => "values", "select" => %w[name email])
      post step_path("query_models"), params: { config: config }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["outputs"]).to include("pin" => "models", "ctx_key" => "models")
      expect(response.parsed_body["inputs"].map { |pin| pin["pin"] }).not_to include("bound_entity", "customer_id")
    end

    it "returns empty pins for an unregistered action" do
      sign_in owner
      post step_path("unknown"), params: payload, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("inputs" => [], "outputs" => [])
    end
  end

  describe "element types" do
    let(:endpoint) { element_path }
    let(:payload) { { properties: { steps: [{ action: "api_call", config: api_config }] } } }
    let(:extractor_method) { :call_element }

    include_examples "tenant admin I/O authorization"

    it "extracts loop collection inputs and item/index/accumulator outputs" do
      sign_in owner
      post element_path("loop"), params: { properties: {
        loopType: "for_each", collection: "items", itemVariable: "item",
        indexVariable: "idx", collectInto: "bag"
      } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["inputs"]).to include("pin" => "items", "ctx_key" => "items", "source" => "generator_literal")
      expect(response.parsed_body["outputs"].map { |pin| pin["pin"] }).to include("item", "idx", "bag")
    end

    it "does not load or execute a subflow reference belonging to another tenant" do
      foreign_flow = create(:flowchart, customer: other_customer)
      sign_in owner
      expect(CodeGenerators::TestRunner).not_to receive(:execute)
      expect(ActivityGenerator).not_to receive(:new)
      flowchart_sql = []
      subscriber = ->(_name, _start, _finish, _id, data) { flowchart_sql << data[:sql] if data[:sql].match?(/\bflowcharts\b/i) }

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        post element_path("subflow"), params: { properties: { flowchartId: foreign_flow.id } }, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("inputs" => [], "outputs" => [])
      expect(flowchart_sql).to be_empty
    end

    it "returns empty pins for an unknown element type" do
      sign_in owner
      post element_path("unknown"), params: { properties: {} }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("inputs" => [], "outputs" => [])
    end
  end

  describe "platform management stays owner-only" do
    before { sign_in admin }

    {
      get: ["", "/element_types/start/start_generator", "/element_types/start/start_generator/edit"],
      post: ["/source_preview", "/element_types/start/start_generator/test_run", "/api_call/io_params", "/element_types/loop/io_params"],
      patch: ["/element_types/start/start_generator"],
      delete: ["/element_types/start/start_generator"]
    }.each do |verb, suffixes|
      suffixes.each do |suffix|
        it "denies a same-tenant admin #{verb.upcase} code_generators#{suffix}" do
          expect(File).not_to receive(:write)
          expect(File).not_to receive(:delete)
          public_send(verb, "/#{customer.id}/admin/maintenance/platform/code_generators#{suffix}", params: {}, as: :json)
          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end
end
