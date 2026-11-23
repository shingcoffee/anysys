# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::CodeGenerators::Previews", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@cg-prev.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@cg-prev.test", password: "password123") }

  let(:real_slug) { "element_types/start/start_generator" }

  def preview_path(slug = real_slug)
    admin_maintenance_platform_code_generator_preview_path(platform_customer.id, code_generator_slug: slug)
  end

  let(:guard_path) { preview_path }

  it_behaves_like "a platform-owner-guarded GET"

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied" do
      get admin_maintenance_platform_code_generator_preview_path(other_customer.id, code_generator_slug: real_slug)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied" do
      get admin_maintenance_platform_code_generator_preview_path(other_customer.id, code_generator_slug: real_slug)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    it "returns JSON with preview_code for a known generator" do
      get preview_path
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("preview_code")
    end

    it "previews Decision with its valid sample configuration" do
      get preview_path("element_types/decision/decision_generator")
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["preview_code"]).to include(%(ctx[:status] == "active"))
    end

    it "previews query_models using full path identity and its sample" do
      get preview_path("element_types/process/model_operations/query_models_generator")
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["preview_code"]).to include("ctx[:models] = FlowchartRuntime::Entries.query(ctx")
    end

    it "returns JSON with preview_code: nil for an unknown generator" do
      get preview_path("element_types/nonexistent/nonexistent_generator")
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["preview_code"]).to be_nil
    end

    it "returns 404 for a slug containing dots (route constraint prevents traversal)" do
      get "/#{platform_customer.id}/admin/maintenance/platform/code_generators/../../etc/passwd/preview"
      expect(response).to have_http_status(:not_found)
    end
  end
end
