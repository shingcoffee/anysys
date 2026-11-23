# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::FlowchartDocuments", type: :request do
  let(:customer)  { create(:customer) }
  let(:admin)     { create(:user, :admin, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }
  let!(:flowchart) { create(:flowchart, customer: customer) }

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET show — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/document" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  describe "GET show — admin fetches flowchart document" do
    before { sign_in platform_owner }

    it "returns 200 with markdown and filename" do
      get "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/document", as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key("markdown")
      expect(body).to have_key("filename")
      expect(body["filename"]).to end_with("-docs.md")
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "GET show — cross-tenant isolation" do
    let(:other_customer)  { create(:customer) }
    let!(:other_flowchart) { create(:flowchart, customer: other_customer) }

    before { sign_in platform_owner }

    it "returns 404 for another tenant's flowchart" do
      get "/#{customer.id}/admin/maintenance/flowcharts/#{other_flowchart.id}/document",
          as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
