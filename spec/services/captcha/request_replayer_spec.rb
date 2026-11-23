# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::RequestReplayer do
  # This spec isolates Rack serialization; CSRF and real routing are covered by
  # the CSRF-enabled request examples in page_shortcut_gate_spec.rb.
  before { allow(Captcha::OriginalRequestVerifier).to receive(:verify!) }

  it "rebuilds a mounted alias POST and clears stale challenge, parser and routing state" do
    env = Rack::MockRequest.env_for("http://forms.example.test/join?locale=zh-CN&tag=a&tag=b", method: "POST",
                                    params: { "name" => "Alice", "customer_id" => "12345678", "authenticity_token" => "old-token" })
    env["SCRIPT_NAME"] = "/anysys"
    env["REMOTE_ADDR"] = "1.2.3.4"
    env["rack.session"] = {}
    env["HTTP_ORIGIN"] = "http://forms.example.test"
    env["HTTP_X_CSRF_TOKEN"] = "original-header-token"
    original_request = ActionDispatch::Request.new(env)
    token = Captcha::RequestSnapshot.capture(original_request).token
    payload = Captcha::RequestSnapshot.take!(token, request: original_request, path: "/anysys/join")

    challenge_env = Rack::MockRequest.env_for("http://forms.example.test/captcha/challenge?return_to=forged", method: "POST",
                                              params: { "captcha_verify_param" => "token", "return_to" => "/wrong" })
    challenge_env["SCRIPT_NAME"] = "/anysys"
    challenge_env["rack.session"] = env["rack.session"]
    challenge_env["HTTP_ORIGIN"] = "http://forged.example.test"
    challenge_env["HTTP_X_CSRF_TOKEN"] = "challenge-header-token"
    challenge_env["action_controller.csrf_token"] = "challenge-cached-token"
    challenge_env["REQUEST_URI"] = "/anysys/captcha/challenge?return_to=forged"
    challenge_request = ActionDispatch::Request.new(challenge_env)
    challenge_request.params
    Rack::Request.new(challenge_env).POST
    challenge_env[PageShortcuts::Resolver::CACHE_KEY] = { ["forms.example.test", "/join"] => :stale_target }
    challenge_env[PageShortcuts::RouteConstraint::MATCH_KEY] = :stale_route

    allow(Rails.application).to receive(:call) do |replay_env|
      req = ActionDispatch::Request.new(replay_env)
      expect(req).to have_attributes(path_info: "/join", script_name: "/anysys", path: "/anysys/join",
                                    request_method: "POST", host: "forms.example.test")
      expect(replay_env["REQUEST_URI"]).to eq("/anysys/join?locale=zh-CN&tag=a&tag=b")
      expect(replay_env["captcha.replay"]).to be(true)
      expect(replay_env[PageShortcuts::Resolver::CACHE_KEY]).to be_nil
      expect(replay_env[PageShortcuts::RouteConstraint::MATCH_KEY]).to be_nil
      expect(req.query_parameters).to include("locale" => "zh-CN", "tag" => "b")
      expect(req.request_parameters).to include("name" => "Alice", "customer_id" => "12345678", "authenticity_token" => "old-token")
      expect(req.origin).to eq("http://forms.example.test")
      expect(req.x_csrf_token).to eq("original-header-token")
      expect(replay_env["action_controller.csrf_token"]).to be_nil
      expect(req.request_parameters).not_to have_key("captcha_verify_param")
      [303, { "Location" => "/anysys/join?locale=zh-CN" }, []]
    end

    response = described_class.call(env: challenge_env, payload: payload)
    expect(response[0]).to eq(303)
    expect(challenge_env["PATH_INFO"]).to eq("/captcha/challenge")
    expect(challenge_env[PageShortcuts::RouteConstraint::MATCH_KEY]).to eq(:stale_route)
  end

  it "refuses direct replay with another session even on the same host" do
    env = Rack::MockRequest.env_for("http://forms.example.test/captcha/challenge")
    env["rack.session"] = {}
    payload = { "binding" => Captcha::SessionBinding.digest({}, create: true), "origin" => "http://forms.example.test", "files" => {} }
    expect(Rails.application).not_to receive(:call)
    expect { described_class.call(env: env, payload: payload) }.to raise_error(ActionController::InvalidAuthenticityToken)
  end

  it "preserves the target's session rotation when the outer challenge commits" do
    env = Rack::MockRequest.env_for("http://example.test/auth/sign_in", method: "POST", params: { "authenticity_token" => "original" })
    env["rack.session"] = {}
    request = ActionDispatch::Request.new(env)
    token = Captcha::RequestSnapshot.capture(request).token
    payload = Captcha::RequestSnapshot.take!(token, request: request)
    env["action_controller.csrf_token"] = "challenge-cached-token"
    rotated = { "signed_in_user" => 123 }
    options = { renew: true }
    allow(Rails.application).to receive(:call) do |replay|
      replay["rack.session"] = rotated
      replay["rack.session.options"] = options
      replay.delete("action_controller.csrf_token")
      [303, { "Location" => "/" }, []]
    end
    described_class.call(env: env, payload: payload)
    expect(env["rack.session"]).to equal(rotated)
    expect(env["rack.session.options"]).to equal(options)
    expect(env).not_to have_key("action_controller.csrf_token")
  end
end
