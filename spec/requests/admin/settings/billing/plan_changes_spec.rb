# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/billing/plan_changes", type: :request do
  include_context "admin records"
  let!(:subscription) { create(:billing_subscription, customer: customer) }
  let!(:change) do
    Billing::PlanChange.create!(customer: customer, subscription: subscription, from_plan: subscription.plan,
      to_plan: create(:billing_plan), request_key: SecureRandom.uuid, kind: "scheduled", status: "scheduled",
      effective_at: subscription.current_period_end, period_start: subscription.current_period_start,
      period_end: subscription.current_period_end)
  end
  let(:guard_path) { admin_settings_billing_subscription_plan_change_path(customer.id) }

  it_behaves_like "an admin-guarded request", :delete

  it "cancels the scoped outstanding change via A and redirects with 303" do
    sign_in admin
    expect(Billing::Activities::CancelPlanChange).to receive(:call).with(subscription: subscription, plan_change: change)
      .and_return(Billing::Result.new(status: :cancelled, plan_change: change))
    delete guard_path, params: { plan_change_id: create(:customer).id }
    expect(response).to have_http_status(:see_other)
  end

  it "retains an in-flight conflict with no false cancellation notice" do
    sign_in admin
    allow(Billing::Activities::CancelPlanChange).to receive(:call).and_return(
      Billing::Result.new(status: :conflict, reason: :collection_in_flight)
    )
    delete guard_path, as: :json
    expect(response).to have_http_status(:conflict)
    expect(flash[:notice]).to be_nil
    expect(change.reload.status).to eq("scheduled")
  end

  it "denies another tenant path before the cancellation API" do
    sign_in admin
    expect(Billing::Activities::CancelPlanChange).not_to receive(:call)
    delete admin_settings_billing_subscription_plan_change_path(create(:customer).id), as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
