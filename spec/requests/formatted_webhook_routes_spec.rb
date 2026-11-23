# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhook provider optional-format dispatch", type: :request do
  let(:body) { { event: "route dispatch" }.to_json }
  let(:headers) { { "Content-Type" => "application/json" } }

  %w[stripe alipay].each do |provider|
    [nil, "json", "xml"].each do |format|
      it "dispatches #{provider}#{format && ".#{format}"} using the formatless payment provider" do
        expect(Payments::WebhookDispatcher).to receive(:call)
          .with(provider: provider, headers: kind_of(Hash), body: body).and_return(:accepted)

        post "/payments/webhooks/#{provider}#{format && ".#{format}"}", params: body, headers: headers

        expect(response).to have_http_status(:ok)
        expect(request.path_parameters).to include(controller: "payments/webhooks", action: "create", provider: provider)
        expect(request.path_parameters[:format]).to eq(format)
        expect(response.body).to eq(provider == "alipay" ? "success" : "")
      end
    end
  end

  it "does not let a forged provider query replace the actual formatted payment path" do
    expect(Payments::WebhookDispatcher).to receive(:call)
      .with(provider: "alipay", headers: kind_of(Hash), body: body).and_return(:accepted)

    post "/payments/webhooks/alipay.json?provider=stripe", params: body, headers: headers,
         env: { "SCRIPT_NAME" => "/anysys" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("success")
  end

  it "still dispatches a formatted payment callback to signature rejection" do
    expect(Payments::WebhookDispatcher).to receive(:call).with(provider: "stripe", headers: kind_of(Hash), body: body)
      .and_raise(Payments::Errors::SignatureInvalid)
    post "/payments/webhooks/stripe.json", params: body, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  describe "email provider dispatch" do
    let!(:credential) do
      create(:email_credential, provider: "ses", password: "route-test-secret", config: {
        "access_key_id" => "route-test-key", "from_email" => "routes@example.com",
        "sns_topic_arn" => "arn:aws:sns:us-east-1:123456789012:route-tests"
      })
    end

    [nil, "json", "xml"].each do |format|
      it "dispatches ses#{format && ".#{format}"} to the registered provider and its verification boundary" do
        expect(Email::Providers).to receive(:for).with("ses").and_call_original
        expect_any_instance_of(Email::Providers::Ses).to receive(:verify_webhook!) do |_adapter, request|
          expect(request.raw_post).to eq(body)
        end
        expect_any_instance_of(Email::Providers::Ses).to receive(:parse_events).and_return([])

        post "/email/webhooks/ses#{format && ".#{format}"}", params: body, headers: headers

        expect(response).to have_http_status(:ok)
        expect(request.path_parameters).to include(controller: "emails/webhooks", action: "create", provider: "ses")
        expect(request.path_parameters[:format]).to eq(format)
      end
    end

    it "still verifies and rejects an invalid signature on the formatted email route" do
      expect_any_instance_of(Email::Providers::Ses).to receive(:verify_webhook!).and_raise(Email::Errors::SignatureInvalid)
      expect_any_instance_of(Email::Providers::Ses).not_to receive(:parse_events)

      post "/email/webhooks/ses.json", params: body, headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  %w[payments email].each do |family|
    it "rejects an unregistered formatted #{family} provider despite a forged query" do
      expect(Payments::WebhookDispatcher).not_to receive(:call)
      expect(Email::Providers).not_to receive(:for)

      post "/#{family}/webhooks/routes_audit_missing_provider.json?provider=stripe", params: body, headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
