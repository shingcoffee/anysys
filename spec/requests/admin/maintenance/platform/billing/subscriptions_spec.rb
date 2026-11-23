# frozen_string_literal: true

require "rails_helper"

# Area (d) — /:cid/admin/maintenance/platform/module_settings/billing/subscriptions
# Tests: owner-only authorization + cross-tenant oversight + cancellation.
RSpec.describe "admin/maintenance/platform/billing/subscriptions", type: :request do
  let!(:platform_owner) { find_or_create_platform_owner }
  let!(:platform_cid)   { ensure_platform_customer.id }

  let!(:regular_customer) { create(:customer) }
  let!(:regular_admin)    { create(:user, :admin, customer: regular_customer) }

  let!(:tenant_a) { create(:customer) }
  let!(:tenant_b) { create(:customer) }

  let!(:plan)  { create(:billing_plan) }
  let!(:sub_a) { create(:billing_subscription, customer: tenant_a, plan: plan, status: "active") }
  let!(:sub_b) { create(:billing_subscription, customer: tenant_b, plan: plan, status: "active") }
  let(:guard_path) { admin_maintenance_platform_billing_subscriptions_path(platform_cid) }

  it_behaves_like "a platform-owner-guarded GET"

  describe "GET show — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_subscription_path(platform_cid, sub_a.id) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "POST cancellation — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_subscription_cancellation_path(platform_cid, sub_a.id) }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "regular admin (non-owner)" do
    before { sign_in regular_admin }

    it "is blocked on subscriptions index" do
      get admin_maintenance_platform_billing_subscriptions_path(regular_customer.id)
      expect(response).not_to have_http_status(:ok)
    end
  end

  # -------------------------------------------------------------------------
  # Happy paths — platform owner cross-tenant oversight
  # -------------------------------------------------------------------------
  describe "platform owner" do
    before { sign_in platform_owner }

    describe "GET index" do
      it "includes subscriptions from multiple tenants" do
        get admin_maintenance_platform_billing_subscriptions_path(platform_cid)
        expect(response).to have_http_status(:ok)
        # Both tenant A and B customer IDs should appear (unscoped cross-tenant list)
        expect(response.body).to include(tenant_a.id.to_s).and include(tenant_b.id.to_s)
      end

      it "filters plan name/code, state and target tenant without changing owner route identity" do
        get admin_maintenance_platform_billing_subscriptions_path(platform_cid),
            params: { q: plan.code, status: "active", tenant_id: tenant_a.id }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(tenant_a.id.to_s)
        expect(response.body).not_to include(tenant_b.id.to_s)
      end
    end

    describe "GET show" do
      it "returns subscriptions from multiple tenants via the platform cid" do
        get admin_maintenance_platform_billing_subscription_path(platform_cid, sub_a.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(sub_a.id.to_s)

        get admin_maintenance_platform_billing_subscription_path(platform_cid, sub_b.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(sub_b.id.to_s)
      end

      it "paginates only that subscription's invoice history past 100 rows" do
        first = create(:billing_invoice, :open, customer: tenant_a, subscription: sub_a, number: "FIRST-HISTORY")
        100.times do |i|
          create(:billing_invoice, :open, customer: tenant_a, subscription: sub_a, number: "DETAIL-HISTORY-#{i}")
        end
        foreign = create(:billing_invoice, :open, customer: tenant_b, subscription: sub_b, number: "FOREIGN-HISTORY")
        get admin_maintenance_platform_billing_subscription_path(platform_cid, sub_a), params: { page: 5 }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(first.number)
        expect(response.body).not_to include(foreign.number)
      end
    end

    describe "POST cancellation#create (immediate)" do
      it "cancels the subscription and redirects to subscription show" do
        post admin_maintenance_platform_billing_subscription_cancellation_path(
               platform_cid, sub_a.id
             )
        sub_a.reload
        expect(sub_a.status).to eq("cancelled")
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include(
          admin_maintenance_platform_billing_subscription_path(platform_cid, sub_a.id)
        )
      end

      it "reports an unchanged ended request without claiming a new cancellation" do
        allow(Billing::Activities::CancelSubscription).to receive(:call).and_return(Billing::Result.new(status: :unchanged))
        post admin_maintenance_platform_billing_subscription_cancellation_path(platform_cid, sub_a)
        expect(response).to have_http_status(:see_other)
        expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.subscriptions.unchanged"))
      end
    end
  end
end
