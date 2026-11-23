# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::FlowchartRestorations", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }

  # Create a soft-deleted flowchart via soft_delete so it appears in only_deleted.
  let!(:deleted_flowchart) do
    f = create(:flowchart, customer: customer)
    f.soft_delete
    f
  end

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "PATCH update — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/#{deleted_flowchart.id}/restoration" }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  describe "PATCH update — admin restores a soft-deleted flowchart" do
    before { sign_in platform_owner }

    it "restores the flowchart and redirects to the flowcharts index" do
      patch "/#{customer.id}/admin/maintenance/flowcharts/#{deleted_flowchart.id}/restoration"

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(admin_maintenance_flowcharts_url(customer.id))

      restored = Flowchart.unscoped.find(deleted_flowchart.id)
      expect(restored.deleted?).to be(false)
      expect(restored.status).to eq("draft")
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "PATCH update — cross-tenant access is forbidden" do
    let(:other_customer)    { create(:customer) }
    let!(:other_deleted) do
      f = create(:flowchart, customer: other_customer)
      f.soft_delete
      f
    end

    before { sign_in platform_owner }

    it "returns 404 for another tenant's deleted flowchart" do
      patch "/#{customer.id}/admin/maintenance/flowcharts/#{other_deleted.id}/restoration"
      expect(response).to have_http_status(:not_found)
    end
  end
end
