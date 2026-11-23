# frozen_string_literal: true

require "rails_helper"

# /:cid/admin/settings/billing/cancellation
# (Formerly admin/settings/modules/billing/cancellation — routes consolidated in Task 10.)
# Tests: authorization matrix + happy paths for cancel / resume subscription.
RSpec.describe "admin/settings/billing/cancellations", type: :request do
  let!(:tenant_a)  { create(:customer) }
  let!(:admin_a)   { create(:user, :admin, customer: tenant_a) }
  let(:customer)   { tenant_a }
  let(:admin)      { admin_a }

  let!(:tenant_b)  { create(:customer) }
  let!(:admin_b)   { create(:user, :admin, customer: tenant_b) }

  let!(:plan)   { create(:billing_plan) }
  let!(:sub_a)  { create(:billing_subscription, customer: tenant_a, plan: plan, status: "active") }

  # -------------------------------------------------------------------------
  # Authorization
  # -------------------------------------------------------------------------
  describe "POST create auth" do
    let(:guard_path) { admin_settings_billing_cancellation_path(tenant_a.id) }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "DELETE destroy auth" do
    let(:guard_path) { admin_settings_billing_cancellation_path(tenant_a.id) }

    it_behaves_like "an admin-guarded request", :delete
  end

  # -------------------------------------------------------------------------
  # Happy paths — admin
  # -------------------------------------------------------------------------
  describe "admin of tenant A" do
    before { sign_in admin_a }

    describe "POST cancellation#create (cancel at period end)" do
      it "marks cancel_at_period_end and redirects to subscription" do
        post admin_settings_billing_cancellation_path(tenant_a.id),
             params: { cancellation: { immediately: "false" } }

        expect(response).to have_http_status(:redirect)
        sub_a.reload
        expect(sub_a.cancel_at_period_end).to be(true)
      end
    end

    describe "POST cancellation#create (immediately = true is ignored)" do
      it "still schedules cancellation at period end" do
        post admin_settings_billing_cancellation_path(tenant_a.id),
             params: { cancellation: { immediately: "true" } }

        expect(response).to have_http_status(:redirect)
        sub_a.reload
        expect(sub_a.status).to eq("active")
        expect(sub_a.cancel_at_period_end).to be(true)
      end
    end

    describe "DELETE cancellation#destroy (resume)" do
      let!(:sub_a) do
        create(:billing_subscription, customer: tenant_a, plan: plan,
               status: "active", cancel_at_period_end: true)
      end

      it "clears cancel_at_period_end and redirects" do
        delete admin_settings_billing_cancellation_path(tenant_a.id)
        expect(response).to have_http_status(:redirect)
        sub_a.reload
        expect(sub_a.cancel_at_period_end).to be(false)
      end
    end

    context "when there is no live subscription" do
      let!(:sub_a) do
        create(:billing_subscription, customer: tenant_a, plan: plan,
               status: "cancelled", cancelled_at: Time.zone.now, ended_at: Time.zone.now)
      end

      it "returns 422 rather than claiming cancellation of an ended subscription" do
        post admin_settings_billing_cancellation_path(tenant_a.id)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:notice]).to be_nil
      end
    end

    it "does not resume paused debt when the command refuses" do
      allow(Billing::Activities::ResumeSubscription).to receive(:call).and_return(
        Billing::Result.new(status: :invalid, reason: :resume_blocked)
      )
      delete admin_settings_billing_cancellation_path(tenant_a.id), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:notice]).to be_nil
    end

    it "retains an in-flight cancellation conflict without a false schedule notice" do
      allow(Billing::Activities::CancelSubscription).to receive(:call).and_return(
        Billing::Result.new(status: :conflict, reason: :collection_in_flight)
      )
      post admin_settings_billing_cancellation_path(tenant_a.id), as: :json
      expect(response).to have_http_status(:conflict)
      expect(flash[:notice]).to be_nil
    end
  end

  # -------------------------------------------------------------------------
  # Tenant isolation
  # -------------------------------------------------------------------------
  describe "tenant isolation" do
    before { sign_in admin_a }

    it "blocks admin A from cancelling via tenant B's URL" do
      post admin_settings_billing_cancellation_path(tenant_b.id),
           params: { cancellation: { immediately: "false" } }
      expect(response).to have_http_status(:redirect)
      expect(response.location).not_to include("sign_in")
    end
  end
end
