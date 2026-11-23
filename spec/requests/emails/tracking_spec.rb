require 'rails_helper'

RSpec.describe "Email Tracking", type: :request do
  let(:message) { create(:email_message) }
  let(:verifier) { Rails.application.message_verifier(:email_tracking) }

  describe "GET /email/track/:message_id/open.gif" do
    it "returns 404 for a missing message" do
      sig = verifier.generate(0)
      get "/email/track/0/open.gif?sig=#{sig}"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a bad signature on an existing message" do
      get "/email/track/#{message.id}/open.gif?sig=not-a-signature"
      expect(response).to have_http_status(:not_found)
      expect(Emails::MessageEvent.where(message: message, event_type: "open").count).to eq(0)
    end
  end

  describe "GET /email/track/:message_id/click" do
    it "records click and redirects" do
      url = "https://example.com"
      sig = verifier.generate({ message_id: message.id, url: url })

      get "/email/track/#{message.id}/click", params: { url: url, sig: sig }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(url)
      expect(Emails::MessageEvent.where(message: message, event_type: "click", url: url).count).to eq(1)
    end

    it "rejects a javascript: URL even when the signature is valid" do
      url = "javascript:alert(1)"
      sig = verifier.generate({ message_id: message.id, url: url })

      get "/email/track/#{message.id}/click", params: { url: url, sig: sig }

      expect(response).to have_http_status(:bad_request)
      expect(Emails::MessageEvent.where(message: message, event_type: "click").count).to eq(0)
    end

    it "redirects a long signed URL without 500ing" do
      url = "https://example.com/path?" + ("utm=x&" * 80)
      sig = verifier.generate({ message_id: message.id, url: url })

      get "/email/track/#{message.id}/click", params: { url: url, sig: sig }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(url)
    end
  end
end
