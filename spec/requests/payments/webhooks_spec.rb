require "rails_helper"

# Controller-contract tests only: the dispatcher is stubbed, so these assert
# WebhooksController's response shaping (ack body + status-code mapping),
# not payment/dispatcher behavior. Full dispatcher + activity integration is
# covered by spec/services/payments/webhook_dispatcher_spec.rb and
# spec/requests/payments/webhooks_stripe_spec.rb.
RSpec.describe "Payments::Webhooks", type: :request do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  def post_webhook(provider, body: "{}")
    post "/payments/webhooks/#{provider}", params: body,
         headers: { "Content-Type" => "application/json" }
  end

  describe "acknowledgement body" do
    it "returns Alipay's required literal \"success\" body on a valid notification" do
      allow(Payments::WebhookDispatcher).to receive(:call).and_return(:accepted)

      post_webhook("alipay")

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("success")
    end

    it "returns an empty body for a non-Alipay provider on a valid notification" do
      allow(Payments::WebhookDispatcher).to receive(:call).and_return(:accepted)

      post_webhook("stripe")

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
    end
  end

  describe "error responses" do
    it "returns 400 when the dispatcher raises SignatureInvalid" do
      allow(Payments::WebhookDispatcher).to receive(:call).and_raise(Payments::Errors::SignatureInvalid)

      post_webhook("alipay")

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 when the dispatcher raises TenantNotFound" do
      allow(Payments::WebhookDispatcher).to receive(:call).and_raise(Payments::Errors::TenantNotFound)

      post_webhook("alipay")

      expect(response).to have_http_status(:not_found)
    end
  end
end
