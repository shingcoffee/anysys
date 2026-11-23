# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Maintenance::FlowchartCopies", type: :request do
  include_context "as platform owner on tenant"

  let(:source) { create(:flowchart, customer: customer) }
  let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/#{source.id}/copy" }

  it_behaves_like "a platform-owner-guarded GET"

  describe "GET /:cid/admin/maintenance/flowcharts/:flowchart_id/copy" do
    context "with a customer_specific source" do
      let(:source) { create(:flowchart, customer: customer) }

      it "renders the new form with a customer-owned copy" do
        get "/#{customer.id}/admin/maintenance/flowcharts/#{source.id}/copy"
        expect(response).to have_http_status(:ok)
        copy = assigns(:flowchart)
        expect(copy).to be_customer_owned
        expect(copy.customer_id).to eq(customer.id)
      end
    end

    context "with a shared source" do
      let(:shared_source) { create(:flowchart, :shared_type, name: "Global") }

      it "returns 404 — tenant overrides replace copy-to-customer" do
        get "/#{customer.id}/admin/maintenance/flowcharts/#{shared_source.id}/copy"
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
