# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::RequestPassage do
  let(:session) { {} }

  def request(path: "/auth/edit?locale=en", method: "GET", browser_session: session, host: "example.test", ip: "1.2.3.4")
    env = Rack::MockRequest.env_for("http://#{host}#{path}", method: method)
    env["rack.session"] = browser_session
    env["REMOTE_ADDR"] = ip
    ActionDispatch::Request.new(env)
  end

  def store
    described_class.store(request: request(path: "/captcha/challenge", method: "POST"), return_to: "/auth/edit?locale=en")
  end

  it "permits the exact continuation once without minting a grant" do
    store
    expect(described_class.take!(request)).to include("allow" => true, "captcha_result" => false)
    expect(described_class.take!(request)).to be(false)
    expect(Captcha::Grant.active?(ip: "1.2.3.4", pattern: "/auth/edit")).to be(false)
  end

  it "cannot be used by another session sharing the same IP and receipt token" do
    store
    copied = { described_class::SESSION_KEY => session.fetch(described_class::SESSION_KEY) }
    Captcha::SessionBinding.digest(copied, create: true)
    expect(described_class.take!(request(browser_session: copied))).to be(false)
    expect(described_class.take!(request)).to be_present
  end

  it "does not permit other queries, paths, methods, hosts or IPs" do
    store
    [{ path: "/auth/edit?locale=zh-CN" }, { path: "/auth/sign_in?locale=en" },
     { method: "POST" }, { method: "HEAD" }, { host: "other.test" }, { ip: "9.9.9.9" }].each do |options|
      expect(described_class.take!(request(**options))).to be(false)
    end
    expect(described_class.take!(request)).to be_present
  end

  it "expires without granting future access" do
    store
    travel(described_class::TTL + 1.second) do
      expect(described_class.take!(request)).to be(false)
      expect(session).not_to have_key(described_class::SESSION_KEY)
    end
  end

  it "can carry a server result without bypassing another throttle" do
    described_class.store(request: request, return_to: request.fullpath, allow: false, captcha_result: true)
    expect(described_class.take!(request)).to include("allow" => false, "captcha_result" => true)
  end

  it "forwards the server result through a local redirect without forwarding outage permission" do
    described_class.forward(request: request, location: "/auth/sign_in?locale=en", captcha_result: true)
    result = described_class.take!(request(path: "/auth/sign_in?locale=en"))
    expect(result).to include("allow" => false, "captcha_result" => true)
  end

  [nil, "https://foreign.example/auth/edit", "http://example.test:4000/auth/edit", "https://example.test/auth/edit", "http://user@example.test/auth/edit", "http://bad host/"].each do |location|
    it "does not forward a result to unsafe or absent redirect #{location.inspect}" do
      described_class.forward(request: request, location: location, captcha_result: true)
      expect(session).not_to have_key(described_class::SESSION_KEY)
    end
  end
end
