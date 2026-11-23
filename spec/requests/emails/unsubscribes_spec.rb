# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Emails::Unsubscribes", type: :request do
  # Lazy: the tampered-token examples never reference these, so no user is
  # created there (preserving their no-setup behavior).
  let(:user)  { create(:user) }
  let(:token) { Emails::SendActivities::SendActivityUnsubscribe.token_for(user) }

  it "rejects an incomplete signed recipient envelope on GET and POST without profile fallback" do
    service = Emails::SendActivities::SendActivityUnsubscribe
    incomplete = service.verifier.generate({ "user_id" => user.id, "email" => user.email }, purpose: service::PURPOSE)

    get email_unsubscribe_path(token: incomplete)
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(user.email)
    expect {
      post email_unsubscribe_create_path(token: incomplete)
    }.not_to change(Emails::Suppression, :count)
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(user.email)
  end

  describe "GET /unsubscribe/:token" do
    it "renders the unsubscribe confirmation page for a valid token" do
      get email_unsubscribe_path(token: token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Unsubscribe")
      expect(response.body).to include(user.email)
    end

    it "shows the emailed address after the profile email changes" do
      original = user.email
      signed = Emails::SendActivities::SendActivityUnsubscribe.token_for(user)
      user.update!(email: "new-inbox-#{SecureRandom.hex(4)}@example.com")

      get email_unsubscribe_path(token: signed)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(original)
      expect(response.body).not_to include(user.email)
    end

    it "renders for an Alipay in-app browser that Rails :modern would 406" do
      get email_unsubscribe_path(token: token), headers: {
        "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 AliApp(AP/10.5.36.6000) AlipayClient/10.5.36.6000"
      }

      expect(response).to have_http_status(:ok)
    end

    it "renders not_found (404) for a tampered/garbage token" do
      get email_unsubscribe_path(token: "totally-garbage-token")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /unsubscribe/:token" do
    [Authentication::MfaObligation::VERIFY, Authentication::MfaObligation::ENROLL].each do |obligation|
      it "honors token-only GET and POST while a signed-in user's MFA obligation is #{obligation}" do
        sign_in user
        allow(Authentication::MfaObligation).to receive(:for).and_return(obligation)

        get email_unsubscribe_path(token: token)
        expect(response).to have_http_status(:ok)
        post email_unsubscribe_create_path(token: token), params: { "List-Unsubscribe" => "One-Click" }

        expect(response).to have_http_status(:ok)
        expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: user.email)).to be(true)
        expect(Authentication::MfaObligation).not_to have_received(:for)
      end
    end

    it "records an unsubscribe suppression for the user" do
      post email_unsubscribe_create_path(token: token)

      expect(response).to have_http_status(:ok)
      expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: user.email)).to be(true)
      expect(response.body).to include(user.email)
    end

    it "confirms the emailed address after the profile email changes" do
      original = user.email
      signed = Emails::SendActivities::SendActivityUnsubscribe.token_for(user)
      user.update!(email: "new-inbox-#{SecureRandom.hex(4)}@example.com")

      post email_unsubscribe_create_path(token: signed)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(original)
      expect(response.body).not_to include(user.email)
      expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: original)).to be(true)
    end

    it "renders not_found (404) for a tampered/garbage token" do
      post email_unsubscribe_create_path(token: "garbage-token-xyz")

      expect(response).to have_http_status(:not_found)
    end

    # RFC 8058: mailbox providers POST `List-Unsubscribe=One-Click` with no
    # session and no CSRF token — the signed token is the sole authorization.
    it "honors the one-click POST even with CSRF protection active" do
      ActionController::Base.allow_forgery_protection = true
      begin
        post email_unsubscribe_create_path(token: token),
             params: { "List-Unsubscribe" => "One-Click" }
      ensure
        ActionController::Base.allow_forgery_protection = false
      end

      expect(response).to have_http_status(:ok)
      expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: user.email)).to be(true)
    end

    context "when a captcha provider is active" do
      before do
        Captcha::Providers::Aliyun
        create(:captcha_provider_settings, enabled: true)
      end

      it "does not captcha-block an RFC 8058 List-Unsubscribe One-Click POST" do
        Captcha::UrlThrottle.create!(
          match_kind: "template",
          url_pattern: "/unsubscribe/:token",
          surface_key: "emails/unsubscribes",
          every_hit: true
        )
        Captcha::ThrottleRegistry.bust!

        post email_unsubscribe_create_path(token: token),
             params: { "List-Unsubscribe" => "One-Click" }

        expect(response).to have_http_status(:ok)
        expect(response).not_to have_http_status(:redirect)
        expect(Emails::Suppression.suppressed?(customer_id: user.customer_id, email: user.email)).to be(true)
      end
    end
  end
end
