# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::CodeGenerators::ElementTypeIoParamsController, type: :request do
  let(:platform_customer) { ensure_platform_customer }
  let(:tenant_customer)   { create(:customer) }
  let(:platform_owner)    { find_or_create_platform_owner }
  let(:tenant_admin)      { create(:user, :admin, customer: tenant_customer) }

  before { sign_in platform_owner }

  def url_for(element_type)
    "/#{platform_customer.id}/admin/maintenance/platform/code_generators/element_types/#{element_type}/io_params"
  end

  let(:guard_path) { url_for("loop") }

  it_behaves_like "a platform-owner-guarded request", :post

  describe "POST /:cid/admin/maintenance/platform/code_generators/element_types/:element_type/io_params" do
    it "returns 200 with extracted pins for a known element_type" do
      post url_for("loop"),
           params: { properties: { loopType: "for_each", collection: "items",
                                   itemVariable: "item", indexVariable: "idx",
                                   collectInto: "bag" } },
           as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["outputs"].map { |o| o["pin"] }).to include("item", "idx", "bag")
    end

    it "returns empty pins for an unknown element_type" do
      post url_for("__nope__"), params: { properties: {} }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("inputs" => [], "outputs" => [])
    end

    it "returns empty pins when properties is a bare string" do
      post url_for("loop"), params: { properties: "junk" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("inputs" => [], "outputs" => [])
    end

    it "returns 200 with unioned pins for a process element with steps" do
      post url_for("process"),
           params: {
             properties: {
               steps: [
                 { action: "api_call",
                   config: { httpMethod: "GET",
                             url:        '"https://example.com"',
                             resultVar:  "resp",
                             responseFormat: "json" } }
               ]
             }
           },
           as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["outputs"].map { |o| o["pin"] }).to include("resp")
    end

    it "returns empty pins for a process element with no steps" do
      post url_for("process"), params: { properties: { steps: [] } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("inputs" => [], "outputs" => [])
    end
  end

  describe "auth gating" do
    it "rejects anonymous callers" do
      sign_out platform_owner
      post url_for("loop"), params: { properties: {} }, as: :json
      expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
    end

    it "rejects tenant admins (non-platform owners)" do
      sign_out platform_owner
      sign_in tenant_admin
      post "/#{tenant_customer.id}/admin/maintenance/platform/code_generators/element_types/loop/io_params",
           params: { properties: {} }, as: :json
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end
end
