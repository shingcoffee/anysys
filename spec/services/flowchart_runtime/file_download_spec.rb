# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::FileDownload do
  let(:ctx) { { customer_id: 81721200, errors: [] } }
  let(:url) { "https://files.example.test/a.csv" }

  it "returns a file payload for the response body" do
    stub_request(:get, url).to_return(status: 200, body: "ok")

    payload = described_class.fetch(ctx, url)
    expect(payload["content"]).to eq("ok")
    expect(payload["filename"]).to eq("a.csv")
  end

  it "rejects a disallowed content type" do
    stub_request(:get, url).to_return(status: 200, body: "ok", headers: { "Content-Type" => "application/pdf" })

    expect {
      described_class.fetch(ctx, url, allowed_content_types: ["text/csv"])
    }.to raise_error(described_class::Error, /content type/)
  end

  it "returns false after Http fails" do
    stub_request(:get, url).to_return(status: 404, body: "missing")

    expect(described_class.fetch(ctx, url)).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("http_status")
  end
end
