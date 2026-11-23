# frozen_string_literal: true

require "rails_helper"

# Area (d) — /:cid/admin/maintenance/platform/module_settings/billing/plans
# Tests: owner-only authorization + CRUD happy paths.
RSpec.describe "admin/maintenance/platform/billing/plans", type: :request do
  let!(:platform_owner) { find_or_create_platform_owner }
  let!(:platform_cid)   { ensure_platform_customer.id }

  let!(:regular_customer) { create(:customer) }
  let!(:regular_admin)    { create(:user, :admin, customer: regular_customer) }

  let!(:plan) { create(:billing_plan, code: "TEST_PLAN", name: "Test Plan", active: true) }

  let(:guard_path) { admin_maintenance_platform_billing_plans_path(platform_cid) }

  it_behaves_like "a platform-owner-guarded GET"

  describe "GET show — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_plan_path(platform_cid, plan.id) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET new — auth guards" do
    let(:guard_path) { new_admin_maintenance_platform_billing_plan_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { edit_admin_maintenance_platform_billing_plan_path(platform_cid, plan.id) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "POST create — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_plans_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_plan_path(platform_cid, plan.id) }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_plan_path(platform_cid, plan.id) }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "regular admin (non-owner)" do
    before { sign_in regular_admin }

    it "is blocked on index via own customer_id" do
      get admin_maintenance_platform_billing_plans_path(regular_customer.id)
      expect(response).not_to have_http_status(:ok)
    end
  end

  # -------------------------------------------------------------------------
  # Happy paths — platform owner
  # -------------------------------------------------------------------------
  describe "platform owner" do
    before { sign_in platform_owner }

    describe "GET index" do
      it "returns 200 and lists plans" do
        get admin_maintenance_platform_billing_plans_path(platform_cid)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Test Plan")
      end
    end

    describe "GET show, new, and edit" do
      it "returns 200 for each form page" do
        [
          admin_maintenance_platform_billing_plan_path(platform_cid, plan.id),
          new_admin_maintenance_platform_billing_plan_path(platform_cid),
          edit_admin_maintenance_platform_billing_plan_path(platform_cid, plan.id)
        ].each do |path|
          get path
          expect(response).to have_http_status(:ok)
        end
      end

      it "keeps the billing tab strip on index, show, new, and edit" do
        [
          admin_maintenance_platform_billing_plans_path(platform_cid),
          admin_maintenance_platform_billing_plan_path(platform_cid, plan.id),
          new_admin_maintenance_platform_billing_plan_path(platform_cid),
          edit_admin_maintenance_platform_billing_plan_path(platform_cid, plan.id)
        ].each do |path|
          get path
          expect(response.body).to include("data-billing-nav")
        end
      end

      it "localizes interval instead of CSS-capitalized English keys" do
        get admin_maintenance_platform_billing_plan_path(platform_cid, plan.id)
        expect(response.body).to include(I18n.t("comp_billing.plan_form.intervals.monthly"))
      end

      it "localizes interval in zh-CN" do
        get admin_maintenance_platform_billing_plan_path(platform_cid, plan.id), params: { locale: "zh-CN" }
        expect(response.body).to include(I18n.t("comp_billing.plan_form.intervals.monthly", locale: :"zh-CN"))
      end
    end

    describe "POST create" do
      it "creates plan record and redirects to index" do
        expect {
          post admin_maintenance_platform_billing_plans_path(platform_cid),
               params: {
                 billing_plan: {
                   code: "NEW_PLAN2", name: "New Plan 2", amount_usd: "49.00",
                   amount_cny: "399.00", interval: "monthly", active: true, is_default: false,
                   trial_days: 0, position: 2
                 }
               }
        }.to change(Billing::Plan, :count).by(1)
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include(
          admin_maintenance_platform_billing_plans_path(platform_cid)
        )
      end
    end

    describe "PATCH update" do
      it "updates plan record and redirects to index" do
        patch admin_maintenance_platform_billing_plan_path(platform_cid, plan.id),
              params: { billing_plan: { name: "Updated Name" } }
        plan.reload
        expect(plan.name).to eq("Updated Name")
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include(
          admin_maintenance_platform_billing_plans_path(platform_cid)
        )
      end
    end

    describe "plan limits persistence" do
      let!(:page_item) do
        Billing::CountableItem.find_or_create_by!(key: "page") do |i|
          i.label = "Pages"
          i.enabled = true
        end
      end

      it "create persists pricing and limits" do
        post admin_maintenance_platform_billing_plans_path(platform_cid), params: {
          billing_plan: {
            code: "starter", name: "Starter", amount_usd: "9.00", amount_cny: "69.00",
            interval: "monthly", trial_days: 0, position: 1, active: "1",
            limits: { "page" => "10" }
          }
        }
        created = Billing::Plan.find_by!(code: "starter")
        expect(created.amount_usd).to eq(9.00)
        expect(created.limit_for("page")).to eq(10)
      end

      it "update changes limits" do
        patch admin_maintenance_platform_billing_plan_path(platform_cid, plan.id), params: {
          billing_plan: { name: "Pro", limits: { "page" => "-1" } }
        }
        expect(plan.reload.limit_for("page")).to eq(Billing::PlanLimit::UNLIMITED)
      end
    end

    describe "DELETE destroy" do
      it "archives the plan without deleting historical identity" do
        expect {
          delete admin_maintenance_platform_billing_plan_path(platform_cid, plan.id)
        }.not_to change(Billing::Plan, :count)
        expect(plan.reload.archived_at).to be_present
        expect(plan.active).to be(false)
        expect(response).to have_http_status(:see_other)
        expect(response.location).to include(
          admin_maintenance_platform_billing_plans_path(platform_cid)
        )
      end

      it "archives a referenced plan while preserving its subscription history" do
        tenant = create(:customer)
        create(:billing_subscription, customer: tenant, plan: plan, status: "active")

        expect {
          delete admin_maintenance_platform_billing_plan_path(platform_cid, plan.id)
        }.not_to change(Billing::Plan, :count)

        expect(response).to have_http_status(:see_other)
        expect(flash[:notice]).to eq(I18n.t("maint_platform.flash.billing.plan_archived"))
        expect(plan.reload.archived_at).to be_present
        expect(plan.reload).to be_persisted
      end
    end

    it "retains submitted Reform values/errors and raw limits without syncing an invalid model" do
      form = Billing::Contracts::Plan.new(plan)
      form.validate(name: "Submitted Name", amount_usd: "not-money")
      result = Billing::Result.new(status: :invalid, record: plan, form: form, errors: form.errors.messages)
      expect(Billing::Catalog::SavePlan).to receive(:call).with(
        plan: plan, params: { "name" => "Submitted Name", "amount_usd" => "not-money" }, limits: { "page" => "broken" }
      ).and_return(result)
      expect_any_instance_of(Admin::Maintenance::Platform::Billing::PlansController).to receive(:render)
        .with(:edit, status: :unprocessable_entity).and_wrap_original do |original, *args, **kwargs|
          expect(original.receiver.instance_variable_get(:@form)).to equal(form)
          expect(original.receiver.instance_variable_get(:@contract)).to equal(form)
          expect(original.receiver.instance_variable_get(:@submitted_limits)).to eq("page" => "broken")
          original.call(*args, **kwargs)
        end
      patch admin_maintenance_platform_billing_plan_path(platform_cid, plan),
            params: { billing_plan: { name: "Submitted Name", amount_usd: "not-money", limits: { page: "broken" } } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(plan.reload.name).to eq("Test Plan")
    end
  end

  # -------------------------------------------------------------------------
  # Cross-tenant: regular admin cannot access platform area even via their own cid
  # -------------------------------------------------------------------------
  describe "cross-tenant isolation for area (d)" do
    before { sign_in regular_admin }

    it "blocks a regular admin from accessing platform plans under the platform cid" do
      get admin_maintenance_platform_billing_plans_path(platform_cid)
      # RouteAuthorization enforces platform_owner? for this controller_path
      expect(response).not_to have_http_status(:ok)
    end
  end
end
