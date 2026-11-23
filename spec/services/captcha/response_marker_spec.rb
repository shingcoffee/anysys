# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::ResponseMarker do
  def env_for(path = "/auth/edit?locale=en")
    Rack::MockRequest.env_for("http://example.test#{path}").merge(
      "rack.session" => {}, "REMOTE_ADDR" => "1.2.3.4"
    )
  end

  it "returns unmarked responses unchanged" do
    response = [200, {}, ["ok"]]
    app = ->(_env) { response }
    expect(described_class.new(app).call(env_for)).to equal(response)
  end

  it "annotates successful downstream responses without converting a failure into a captcha pass" do
    env = env_for
    env["captcha.result"] = false
    app = ->(_env) { [200, { "content-type" => "text/html" }.freeze, ["ok"]] }
    status, headers, body = described_class.new(app).call(env)
    expect(status).to eq(200)
    expect(headers).to include("x-captcha-result" => "false", "cache-control" => "no-store")
    expect(body).to eq(["ok"])
  end

  it "annotates a Warden-style nonlocal redirect and forwards only the result receipt" do
    env = env_for
    request = ActionDispatch::Request.new(env)
    Captcha::RequestPassage.store(request: request, return_to: request.fullpath)
    downstream = ->(_env) { throw :warden, [302, { "location" => "/auth/sign_in?locale=en" }, []] }
    gate = Captcha::RackGate.new(downstream)
    warden = ->(inner_env) { catch(:warden) { gate.call(inner_env) } }

    status, headers, = described_class.new(warden).call(env)
    expect(status).to eq(302)
    expect(headers["x-captcha-result"]).to eq("false")
    expect(headers["cache-control"]).to eq("no-store")
    next_env = env_for("/auth/sign_in?locale=en")
    next_env["rack.session"] = env["rack.session"]
    receipt = Captcha::RequestPassage.take!(ActionDispatch::Request.new(next_env))
    expect(receipt).to include("allow" => false, "captcha_result" => false)
    expect(Captcha::Grant.active?(ip: "1.2.3.4", pattern: "/auth/edit")).to be(false)
  end

  it "preserves a genuine passing marker" do
    env = env_for
    env["captcha.result"] = true
    _, headers, = described_class.new(->(_env) { [200, {}, []] }).call(env)
    expect(headers["x-captcha-result"]).to eq("true")
  end
end
