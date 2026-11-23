# frozen_string_literal: true

require "rails_helper"

# CVE-2026-40295 regression: on a non-GET :timeout failure, FailureApp
# must build its redirect location from the Referer's PATH only. Before
# the 5.0.4 fix the scheme + host + path were all used, allowing an
# attacker-controlled Referer to redirect the user off-origin.
#
# This spec drives Devise::FailureApp directly with a hostile Referer
# and verifies the resulting Location header is a same-origin path,
# not the attacker's host.
RSpec.describe Devise::FailureApp do
  let(:hostile_referer) { "https://evil.example.com/pwn?foo=bar" }
  let(:warden_options)  { { scope: :user, message: :timeout, attempted_path: "/profile" } }

  def build_env(method:, referer:)
    Rack::MockRequest.env_for(
      "/profile",
      method: method,
      "HTTP_HOST" => "app.example.com",
      "HTTP_REFERER" => referer,
      "warden.options" => warden_options,
      "warden" => instance_double("Warden::Proxy", message: :timeout)
    )
  end

  it "does not include the attacker host in the redirect Location for non-GET timeout" do
    env = build_env(method: "POST", referer: hostile_referer)
    status, headers, _body = described_class.call(env)

    expect(status).to be_between(300, 399)
    expect(headers["Location"]).not_to include("evil.example.com")
  end

  it "extracts only the path (+ query) from the Referer, discarding scheme and host" do
    env = build_env(method: "POST", referer: hostile_referer)
    _status, headers, _body = described_class.call(env)

    expect(headers["Location"]).to end_with("/pwn?foo=bar")
    expect(headers["Location"]).not_to start_with("https://evil.example.com")
  end
end
