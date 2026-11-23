# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::CodeGenerators::TestRuns", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@tr.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@tr.test", password: "password123") }

  let(:real_slug) { "element_types/start/start_generator" }

  def test_run_path(slug = real_slug)
    admin_maintenance_platform_code_generator_test_run_path(platform_customer.id, code_generator_slug: slug)
  end

  let(:guard_path) { test_run_path }

  it_behaves_like "a platform-owner-guarded request", :post

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied" do
      post admin_maintenance_platform_code_generator_test_run_path(other_customer.id, code_generator_slug: real_slug),
           params: { sample_config: "{}" }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied" do
      post admin_maintenance_platform_code_generator_test_run_path(other_customer.id, code_generator_slug: real_slug),
           params: { sample_config: "{}" }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path and branches
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    it "returns JSON result for a known generator with empty config" do
      post test_run_path, params: { sample_config: "{}" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("body")
    end

    it "returns JSON result with no sample_config param (defaults to {})" do
      post test_run_path
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("body")
    end

    it "returns 422 with error message for invalid JSON sample_config" do
      post test_run_path, params: { sample_config: "not-json" }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/Invalid JSON/i)
    end

    ["null", "[]", '"text"', "42", "true", "false"].each do |json|
      it "returns validation errors for JSON root #{json}" do
        post test_run_path, params: { sample_config: json }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["validation_errors"]).to eq([I18n.t("maint_platform.flash.code_generators.config_object_required")])
        expect(response.parsed_body["code"]).to be_nil
      end
    end

    it "returns Decision validation errors instead of generating invalid code" do
      post test_run_path("element_types/decision/decision_generator"), params: { sample_config: "{}" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["validation_errors"]).not_to be_empty
      expect(response.parsed_body["code"]).to be_nil
    end

    it "runs query_models from its exact path" do
      klass = CodeGenerators::ElementTypes::Process::ModelOperations::QueryModelsGenerator
      post test_run_path("element_types/process/model_operations/query_models_generator"),
           params: { sample_config: klass.sample_input.to_json }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["validation_errors"]).to be_empty
      expect(response.parsed_body["body"]).to include("FlowchartRuntime::Entries.query(ctx")
    end

    it "returns 404 for an unknown generator slug" do
      post test_run_path("element_types/nonexistent/nonexistent_generator"),
           params: { sample_config: "{}" }
      expect(response).to have_http_status(:not_found)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/not found/i)
    end

    it "returns 404 for a slug containing dots (route constraint prevents traversal)" do
      post "/#{platform_customer.id}/admin/maintenance/platform/code_generators/../../etc/passwd/test_run",
           params: { sample_config: "{}" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
