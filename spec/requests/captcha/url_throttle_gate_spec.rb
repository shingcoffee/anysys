# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Captcha URL throttle gate", type: :request do
  before do
    Captcha::Providers::Aliyun
    create(:captcha_provider_settings, enabled: true)
    Captcha::UrlThrottle.create!(
      match_kind: "template",
      url_pattern: "/auth/sign_in",
      surface_key: "authentication/sessions",
      every_hit: true
    )
    Captcha::ThrottleRegistry.bust!
  end

  it "redirects an over-limit GET to the challenge and preserves return_to" do
    get "/auth/sign_in"

    expect(response).to have_http_status(:redirect)
    expect(response.location).to include("/captcha/challenge")
    expect(response.location).to include("return_to=%2Fauth%2Fsign_in")
  end

  it "does not throttle admin paths" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end

  it "does not challenge a skipped URL even when every_hit is set" do
    Captcha::UrlThrottle.find_by!(url_pattern: "/auth/sign_in").update!(skipped: true)
    Captcha::ThrottleRegistry.bust!

    get "/auth/sign_in"
    expect(response).to have_http_status(:ok)
    expect(response.location.to_s).not_to include("/captcha/challenge")
  end

  it "404s an unsafe return_to on the challenge page" do
    get "/captcha/challenge", params: { return_to: "https://evil.example" }
    expect(response).to have_http_status(:not_found)
  end

  it "renders the challenge interstitial for a throttled GET" do
    get "/auth/sign_in"
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("captcha.challenge.title"))
    expect(response.body).to include(I18n.t("captcha.challenge.continue"))
  end

  it "grants the remainder of the window after a passing challenge" do
    allow(Captcha::Activities::Verify).to receive(:call).and_return(
      Captcha::Activities::Verify::Result.new(outcome: :success)
    )

    post "/captcha/challenge", params: {
      return_to: "/auth/sign_in",
      captcha_verify_param: "ok-token"
    }

    expect(response).to redirect_to("/auth/sign_in")
    get "/auth/sign_in"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(I18n.t("captcha.challenge.title"))
  end

  it "replays a captured POST after a passing challenge" do
    allow(Captcha::Activities::Verify).to receive(:call).and_return(
      Captcha::Activities::Verify::Result.new(outcome: :success)
    )

    post "/auth/sign_in", params: { user: { email: "gate@example.com", password: "wrong" } }
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include("/captcha/challenge")
    expect(response.location).not_to include("snapshot=")
    expect(response.cookies[Captcha::RequestSnapshot::COOKIE]).to be_present

    post "/captcha/challenge", params: {
      return_to: "/auth/sign_in",
      captcha_verify_param: "ok-token"
    }

    expect(response).not_to have_http_status(:redirect)
    expect(response.location.to_s).not_to include("/captcha/challenge")
  end

  it "lets a fail-closed surface through when captcha is disabled, without minting a Grant" do
    allow(Captcha::Activities::Verify).to receive(:call).and_return(
      Captcha::Activities::Verify::Result.new(outcome: :disabled)
    )

    post "/captcha/challenge", params: {
      return_to: "/auth/sign_in",
      captcha_verify_param: ""
    }

    expect(response).to redirect_to("/auth/sign_in")
    get "/auth/sign_in"
    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Captcha-Result"]).to eq("false")
    get "/auth/sign_in"
    expect(response.location).to include("/captcha/challenge")
  end

  it "does not skip later hits after a fail-open vendor outage" do
    allow(Captcha::Activities::Verify).to receive(:call).and_return(
      Captcha::Activities::Verify::Result.new(outcome: :unreachable)
    )

    post "/captcha/challenge", params: {
      return_to: "/auth/sign_in",
      captcha_verify_param: "dummy"
    }

    expect(response).to have_http_status(:unprocessable_content)
    get "/auth/sign_in"
    expect(response.location).to include("/captcha/challenge")
  end

  it "does not challenge when no captcha provider is configured" do
    Captcha::ProviderSettings.delete_all

    get "/auth/sign_in"
    expect(response).to have_http_status(:ok)
    expect(response.location.to_s).not_to include("/captcha/challenge")
  end

  %w[html json arbitrary].each do |format|
    it "challenges a formatted sign-in URL (.#{format}) before rendering the target" do
      get "/auth/sign_in.#{format}"
      expect(response.location).to include("/captcha/challenge")
      expect(response.location).to include("return_to=%2Fauth%2Fsign_in.#{format}")
    end
  end

  it "renders the challenge for an embedded payment browser excluded by the modern-browser policy" do
    get "/captcha/challenge", params: { return_to: "/auth/sign_in" }, headers: {
      "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 MicroMessenger/7.0.0"
    }
    expect(response).to have_http_status(:ok)
    expect(response.headers["Referrer-Policy"]).to eq("same-origin")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  describe "outage failure policy" do
    before do
      create(:captcha_url_throttle, match_kind: "exact", url_pattern: "/auth/edit", every_hit: true)
      Captcha::ThrottleRegistry.bust!
    end

    it "honors the saved global closed policy on an otherwise open surface" do
      Captcha::ProviderSettings.where(enabled: true).update_all(fail_policy: "closed")
      allow(Captcha::Activities::Verify).to receive(:call).and_return(
        Captcha::Activities::Verify::Result.new(outcome: :unreachable, fail_policy: "closed")
      )
      post "/captcha/challenge", params: { return_to: "/auth/edit", captcha_verify_param: "token" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.headers["X-Captcha-Result"]).to eq("false")
      expect(Captcha::Grant.active?(ip: request.remote_ip, pattern: "/auth/edit")).to be(false)
    end

    it "uses an exact one-use GET continuation under fail-open, then challenges again" do
      allow(Captcha::Activities::Verify).to receive(:call).and_return(
        Captcha::Activities::Verify::Result.new(outcome: :configuration_error, fail_policy: "open")
      )
      post "/captcha/challenge", params: { return_to: "/auth/edit?locale=en", captcha_verify_param: "token" }
      expect(response).to redirect_to("/auth/edit?locale=en")
      get "/auth/edit?locale=zh-CN"
      expect(response.location).to include("/captcha/challenge")
      get "/auth/edit?locale=en"
      # Anonymous Devise auth/edit redirects to sign-in; it has passed the gate.
      expect(response.location.to_s).not_to include("/captcha/challenge")
      expect(response.headers["X-Captcha-Result"]).to eq("false")
      get "/auth/edit?locale=en"
      expect(response.location).to include("/captcha/challenge")
      expect(Captcha::Grant.active?(ip: request.remote_ip, pattern: "/auth/edit")).to be(false)
    end
  end
end
