# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::RackGate do
  def env_for(path, script_name: "/anysys", **opts)
    Rack::MockRequest.env_for(path, { "SCRIPT_NAME" => script_name }.merge(opts))
  end

  def call_gate(env, app: ->(_env) { [200, { "Content-Type" => "text/plain" }, ["ok"]] })
    described_class.new(app).call(env)
  end

  it "classifies throttle rules on PATH_INFO when SCRIPT_NAME prefixes request.path" do
    env = env_for("/auth/sign_in")
    request = ActionDispatch::Request.new(env)
    expect(request.path).to eq("/anysys/auth/sign_in")
    expect(request.path_info).to eq("/auth/sign_in")

    allow(Captcha::UrlMatcher).to receive(:skip?).and_return(false)
    allow(Captcha::UrlMatcher).to receive(:match).and_return(nil)

    status, = call_gate(env)

    expect(status).to eq(200)
    expect(Captcha::UrlMatcher).to have_received(:skip?).with("/auth/sign_in")
    expect(Captcha::UrlMatcher).to have_received(:match).with("/auth/sign_in")
  end

  it "exempts RFC 8058 one-click unsubscribe when SCRIPT_NAME prefixes the path" do
    env = env_for(
      "/unsubscribe/token",
      method: "POST",
      "HTTP_LIST_UNSUBSCRIBE" => "One-Click"
    )
    allow(Captcha::UrlMatcher).to receive(:skip?).and_return(false)
    allow(Captcha::UrlMatcher).to receive(:match)

    status, = call_gate(env)

    expect(status).to eq(200)
    expect(Captcha::UrlMatcher).not_to have_received(:match)
  end

  it "does not swallow or retry downstream CSRF failures when passing through" do
    app = double("downstream application")
    expect(app).to receive(:call).once.and_raise(ActionController::InvalidAuthenticityToken)
    expect { call_gate(env_for("/up"), app: app) }.to raise_error(ActionController::InvalidAuthenticityToken)
  end

  it "fails open for a captcha-processing exception and calls the app exactly once" do
    allow(Captcha::UrlMatcher).to receive(:for_request).and_raise(ActiveRecord::StatementInvalid)
    app = double("downstream application")
    expect(app).to receive(:call).once.and_return([200, {}, ["ok"]])
    expect(call_gate(env_for("/auth/sign_in"), app: app)[0]).to eq(200)
  end

  it "does not swallow the original request's CSRF failure during capture" do
    rule = Captcha::UrlMatcher.match("/auth/sign_in")
    allow(Captcha::UrlMatcher).to receive(:for_request).and_return(rule.with(every_hit: true))
    allow(Captcha::ProviderSettings).to receive(:active).and_return(double("configured provider"))
    allow(Captcha::RequestSnapshot).to receive(:capture).and_raise(ActionController::InvalidAuthenticityToken)
    app = double("downstream application")
    expect(app).not_to receive(:call)
    expect { call_gate(env_for("/auth/sign_in", method: "POST"), app: app) }.to raise_error(ActionController::InvalidAuthenticityToken)
  end
end
