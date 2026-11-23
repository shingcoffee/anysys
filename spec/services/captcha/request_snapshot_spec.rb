# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::RequestSnapshot do
  let(:session) { {} }

  def post_request(params:, ip: "1.2.3.4", path: "/auth/sign_in", browser_session: session)
    env = Rack::MockRequest.env_for(path, method: "POST", params: params)
    env["REMOTE_ADDR"] = ip
    env["rack.session"] = browser_session
    ActionDispatch::Request.new(env)
  end

  it "round-trips a captured POST for the same IP and path" do
    capture = described_class.capture(post_request(params: { "user" => { "email" => "a@b.c" } }))
    payload = described_class.take!(capture.token, request: post_request(params: {}), path: "/auth/sign_in")

    expect(payload["path"]).to eq("/auth/sign_in")
    expect(payload.dig("params", "user", "email")).to eq("a@b.c")
    expect(payload["binding"]).to eq(Digest::SHA256.hexdigest(session.fetch(Captcha::SessionBinding::KEY)))
    expect(described_class.take!(capture.token, request: post_request(params: {}), path: "/auth/sign_in")).to be_nil
  end

  it "does not consume a snapshot for a different IP" do
    capture = described_class.capture(post_request(params: { "n" => "1" }))
    expect(described_class.take!(capture.token, request: post_request(params: {}, ip: "9.9.9.9"))).to be_nil
    expect(described_class.take!(capture.token, request: post_request(params: {}))).to be_present
  end

  it "does not consume a snapshot when the return path does not match" do
    capture = described_class.capture(post_request(params: { "n" => "1" }, path: "/auth/sign_in"))
    expect(described_class.take!(capture.token, request: post_request(params: {}), path: "/auth/sign_up")).to be_nil
    expect(described_class.take!(capture.token, request: post_request(params: {}), path: "/auth/sign_in")).to be_present
  end

  it "rejects the same-IP snapshot cookie in another session without consuming the original" do
    capture = described_class.capture(post_request(params: { "n" => "1" }))
    other = post_request(params: {}, browser_session: {})
    Captcha::SessionBinding.digest(other.session, create: true)
    expect(described_class.take!(capture.token, request: other)).to be_nil
    expect(described_class.take!(capture.token, request: post_request(params: {}))).to be_present
  end

  it "binds the full query and host, not just the path" do
    capture = described_class.capture(post_request(params: {}, path: "/auth/sign_in?locale=en"))
    request = post_request(params: {})
    expect(described_class.take!(capture.token, request: request, query: "locale=zh-CN")).to be_nil
    request.set_header("HTTP_HOST", "other.example.test")
    expect(described_class.take!(capture.token, request: request, query: "locale=en")).to be_nil
    expect(described_class.take!(capture.token, request: post_request(params: {}), query: "locale=en")).to be_present
  end

  it "does not persist uploads or metadata before Rails verifies the original request" do
    request = post_request(params: {})
    allow(Captcha::OriginalRequestVerifier).to receive(:verify!).with(request).and_raise(ActionController::InvalidAuthenticityToken)
    expect(ActiveStorage::Blob).not_to receive(:create_and_upload!)
    expect(described_class.cache).not_to receive(:write)
    expect { described_class.capture(request) }.to raise_error(ActionController::InvalidAuthenticityToken)
  end

  it "purges unattached snapshot blobs older than the TTL" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x"),
      filename: "x.txt",
      content_type: "text/plain",
      key: "#{described_class::BLOB_KEY_PREFIX}#{SecureRandom.uuid}"
    )
    blob.update_columns(created_at: 20.minutes.ago)

    described_class.prune_orphans!(older_than: 10.minutes.ago)

    expect(ActiveStorage::Blob.where(id: blob.id)).not_to exist
  end
end
