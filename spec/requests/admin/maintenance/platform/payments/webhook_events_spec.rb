# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Payments::WebhookEvents", type: :request do
  let(:guard_path) { "/#{ensure_platform_customer.id}/admin/maintenance/platform/module_settings/payment/webhook_events" }

  it_behaves_like "a platform-owner-guarded GET"

  describe "POST redrive — auth guards" do
    let(:event) { create_event }
    let(:guard_path) { "/#{ensure_platform_customer.id}/admin/maintenance/platform/module_settings/payment/webhook_events/#{event.id}/redrive" }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  def create_event(status: "failed", **over)
    create(:payment_webhook_event,
      { provider: "stripe", event_type: "payment_intent.succeeded",
        signing_merchant_id: "acct_1", status: status,
        payload: Payments::WebhookEvent.payload_with_verification({}, signing_account_id: 777) }.merge(over)
    )
  end

  context "as platform owner" do
    include_context "as platform owner"

    it "lists webhook events (cross-tenant)" do
      create_event
      get "/#{customer.id}/admin/maintenance/platform/module_settings/payment/webhook_events"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Credit / Debit Card (Stripe)")
      expect(response.body).to include(I18n.t("comp_payments.webhook_events.statuses.failed"))
    end

    it "redrives a failed event: status back to received + job enqueued" do
      event = create_event(status: "failed")
      allow(Payments::ProcessWebhookEventJob).to receive(:perform_later)

      post "/#{customer.id}/admin/maintenance/platform/module_settings/payment/webhook_events/#{event.id}/redrive"

      expect(response).to have_http_status(:redirect)
      expect(event.reload.status).to eq("received")
      expect(Payments::ProcessWebhookEventJob).to have_received(:perform_later).with(event.id, "acct_1", 777)
    end

    it "refuses to redrive an already-processed event" do
      event = create_event(status: "processed")
      allow(Payments::ProcessWebhookEventJob).to receive(:perform_later)

      post "/#{customer.id}/admin/maintenance/platform/module_settings/payment/webhook_events/#{event.id}/redrive"

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("comp_payments.flash.webhook_redrive_not_retryable"))
      expect(event.reload.status).to eq("processed")
      expect(Payments::ProcessWebhookEventJob).not_to have_received(:perform_later)
    end
  end

  context "as a non-owner admin" do
    include_context "as admin"

    it "is denied access to the platform ledger" do
      get "/#{customer.id}/admin/maintenance/platform/module_settings/payment/webhook_events"
      expect(response).not_to have_http_status(:ok)
    end
  end
end
