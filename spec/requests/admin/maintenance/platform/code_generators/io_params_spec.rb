# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::CodeGenerators::IoParamsController, type: :request do
  let(:platform_customer) { ensure_platform_customer }
  let(:tenant_customer)   { create(:customer) }
  let(:platform_owner)    { find_or_create_platform_owner }
  let(:tenant_admin)      { create(:user, :admin, customer: tenant_customer) }

  before { sign_in platform_owner }

  def url_for(action)
    "/#{platform_customer.id}/admin/maintenance/platform/code_generators/#{action}/io_params"
  end

  let(:guard_path) { url_for("api_call") }

  it_behaves_like "a platform-owner-guarded request", :post

  describe "POST /:cid/admin/maintenance/platform/code_generators/:action/io_params" do
    it "returns inputs and outputs for a known action" do
      post url_for("api_call"),
           params: { config: { httpMethod: "GET", url: '"https://example.com"', resultVar: "resp", responseFormat: "json" } },
           as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["outputs"].map { |o| o["pin"] }).to include("resp")
      expect(json["inputs"]).to be_an(Array)
    end

    it "returns empty pins with 200 for unknown action" do
      post url_for("definitely_not_a_real_action"), params: { config: {} }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("inputs" => [], "outputs" => [])
    end

    it "returns empty pins with 200 for malformed config" do
      post url_for("api_call"), params: { config: "not-a-hash" }, as: :json
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["inputs"]).to eq([])
      expect(json["outputs"]).to eq([])
    end
  end

  describe "auth gating" do
    it "rejects anonymous callers" do
      sign_out platform_owner
      post url_for("api_call"), params: { config: {} }, as: :json
      expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
    end

    it "rejects tenant admins (non-platform owners)" do
      sign_out platform_owner
      sign_in tenant_admin
      post "/#{tenant_customer.id}/admin/maintenance/platform/code_generators/api_call/io_params",
           params: { config: {} }, as: :json
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end
end
