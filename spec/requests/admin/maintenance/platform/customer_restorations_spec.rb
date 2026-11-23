# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::CustomerRestorations", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  # Customers use RandomIdGeneratable (8-digit IDs) so factory-created customers
  # already satisfy the /:customer_id route constraint (\d{8}).
  let(:soft_deleted_customer) do
    c = create(:customer, name: "Soft Deleted Corp")
    c.soft_delete   # sets status: :inactive (what the controller looks up via only_deleted)
    c
  end

  def restoration_path(outer_cid, inner_cid)
    "/#{outer_cid}/admin/maintenance/platform/customers/#{inner_cid}/restoration"
  end

  let(:guard_path) { restoration_path(platform_customer.id, soft_deleted_customer.id) }

  it_behaves_like "a platform-owner-guarded request", :patch

  # -------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    it "restores a soft-deleted customer and redirects with notice" do
      cid = soft_deleted_customer.id
      patch restoration_path(platform_customer.id, cid)

      expect(response).to redirect_to(admin_maintenance_platform_customers_path(platform_customer.id))
      expect(flash[:notice]).to include("Soft Deleted Corp")
      expect(Customer.unscoped.find(cid).status).to eq("active")
    end

    it "restores through the route helper used by the trash table" do
      cid = soft_deleted_customer.id
      patch restoration_admin_maintenance_platform_customer_path(platform_customer.id, soft_deleted_customer)

      expect(response).to redirect_to(admin_maintenance_platform_customers_path(platform_customer.id))
      expect(Customer.unscoped.find(cid).status).to eq("active")
    end
  end
end
