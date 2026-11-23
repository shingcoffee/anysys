# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::CodeGenerators::SourcePreviews", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@src-prev.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@src-prev.test", password: "password123") }

  let(:valid_params) do
    {
      kind: "element_type",
      file_name: "my_generator",
      category: "",
      description: "Test",
      version: "1.0.0",
      registered_names: "",
      methods_body: "def generate_body\n  \"true\"\nend\n"
    }
  end

  def source_preview_path
    admin_maintenance_platform_source_preview_path(platform_customer.id)
  end

  let(:guard_path) { source_preview_path }

  it_behaves_like "a platform-owner-guarded request", :post

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied" do
      post admin_maintenance_platform_source_preview_path(other_customer.id), params: valid_params
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied" do
      post admin_maintenance_platform_source_preview_path(other_customer.id), params: valid_params
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    it "returns JSON with source, highlighted, and line_count" do
      post source_preview_path, params: valid_params
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("source", "highlighted", "line_count")
      expect(body["line_count"]).to be_a(Integer).and be_positive
    end

    it "accepts step_action kind" do
      post source_preview_path,
           params: valid_params.merge(kind: "step_action", category: "data_operations")
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["source"]).to be_present
    end
  end
end
