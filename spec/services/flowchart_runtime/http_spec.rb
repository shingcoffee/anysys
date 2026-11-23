# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Http do
  let(:ctx) { { customer_id: 81721200, errors: [] } }
  let(:url) { "https://api.example.test/resource" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }
  after { FlowchartRuntime::RunContext.reset }

  def request(**overrides)
    described_class.request(ctx, :get, url, open_timeout: 3, read_timeout: 7, **overrides)
  end

  describe ".parse_json" do
    it "returns an empty hash for a blank body" do
      expect(described_class.parse_json("")).to eq({})
      expect(described_class.parse_json("   ")).to eq({})
    end

    it "parses JSON with symbol keys" do
      expect(described_class.parse_json('{"ok":true}')).to eq(ok: true)
    end

    it "raises on non-JSON when strict" do
      expect { described_class.parse_json("ok") }.to raise_error(JSON::ParserError)
    end

    it "stores non-JSON text when not strict" do
      expect(described_class.parse_json("ok", strict: false)).to eq(body: "ok")
      expect(described_class.parse_json("ok", symbolize_names: false, strict: false)).to eq("body" => "ok")
    end
  end

  describe ".request" do
    it "returns the OutboundHttp response on 2xx" do
      stub_request(:get, url).to_return(status: 200, body: "ok")

      response = request

      expect(response).to be_a(OutboundHttp::Response)
      expect(response.status).to eq(200)
      expect(response.body).to eq("ok")
      expect(ctx[:errors]).to eq([])
    end

    it "retries a GET once after a transport error and then succeeds" do
      attempts = 0
      allow(OutboundHttp).to receive(:request) do |**|
        attempts += 1
        raise OutboundHttp::TransportError, "execution expired" if attempts == 1

        OutboundHttp::Response.new(status: 200, headers: {}, body: "ok")
      end

      response = request(retries: 1)

      expect(response.body).to eq("ok")
      expect(attempts).to eq(2)
    end

    it "never retries a POST when retries is zero" do
      allow(OutboundHttp).to receive(:request).and_raise(OutboundHttp::TransportError, "refused")

      expect(described_class.request(ctx, :post, url, open_timeout: 1, read_timeout: 1, retries: 0)).to be(false)
      expect(OutboundHttp).to have_received(:request).once
      expect(ctx[:error_details].last["code"]).to eq("transport_error")
    end

    it "returns a 4xx response when fail_on_http_error is false" do
      stub_request(:get, url).to_return(status: 404, body: "missing")

      response = request(fail_on_http_error: false)

      expect(response).to be_a(OutboundHttp::Response)
      expect(response.status).to eq(404)
      expect(response.body).to eq("missing")
      expect(ctx[:errors]).to eq([])
    end

    it "does not retry a 503 and fails with http_status" do
      stub_request(:get, url).to_return(status: 503, body: "busy")

      expect(request(retries: 2)).to be(false)
      expect(ctx[:error_details].last).to include("code" => "http_status")
      expect(ctx[:error_details].last["details"]).to eq(status: "503")
      expect(a_request(:get, url)).to have_been_made.once
    end

    it "stops retrying when the remaining budget cannot cover another attempt" do
      FlowchartRuntime::RunContext.with_deadline(1.2) do
        allow(FlowchartRuntime::RunContext).to receive(:remaining).and_return(1.2, 0.4)
        allow(OutboundHttp).to receive(:request).and_raise(OutboundHttp::TransportError, "timeout")

        expect(request(retries: 2, open_timeout: 1, read_timeout: 1)).to be(false)
        expect(OutboundHttp).to have_received(:request).once
      end
    end

    it "fails timed_out without sending when less than one second remains" do
      FlowchartRuntime::RunContext.with_deadline(0.5) do
        allow(FlowchartRuntime::RunContext).to receive(:remaining).and_return(0.4)
        expect(OutboundHttp).not_to receive(:request)

        expect(request).to be(false)
        expect(ctx[:error_details].last["code"]).to eq("timed_out")
      end
    end

    it "clips open and read timeouts to the remaining budget" do
      FlowchartRuntime::RunContext.with_deadline(2) do
        allow(FlowchartRuntime::RunContext).to receive(:remaining).and_return(2.0)
        allow(OutboundHttp).to receive(:request)
          .and_return(OutboundHttp::Response.new(status: 200, headers: {}, body: "ok"))

        request(open_timeout: 5, read_timeout: 9)

        expect(OutboundHttp).to have_received(:request).with(
          :get,
          url,
          hash_including(open_timeout: 2.0, read_timeout: 2.0, public_only: true)
        )
      end
    end

    it "does not send when the breaker is open" do
      5.times { FlowchartRuntime::CircuitBreaker.evaluate(ctx[:customer_id], "payments", outcome: "failure", failure_threshold: 5) }
      expect(OutboundHttp).not_to receive(:request)

      expect(request(breaker: { name: "payments", threshold: 5, reset_seconds: 60 })).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("circuit_open")
    end

    it "records transport errors and 5xx as breaker failures" do
      stub_request(:get, url).to_return(status: 503, body: "busy")

      request(breaker: { name: "payments", threshold: 1, reset_seconds: 60 })
      gate = FlowchartRuntime::CircuitBreaker.evaluate(ctx[:customer_id], "payments", outcome: "none", failure_threshold: 1)

      expect(gate[:state]).to eq("open")
      expect(gate[:allowed]).to be(false)
    end

    it "appends query parameters and forwards redirects" do
      stub_request(:get, "https://api.example.test/resource?q=1")
        .to_return(status: 200, body: "ok")

      allow(OutboundHttp).to receive(:request).and_call_original

      described_class.request(
        ctx, :get, url, query: { q: 1 }, headers: { "Accept" => "text/plain" },
        open_timeout: 1, read_timeout: 1, follow_redirects: true, max_redirects: 2
      )

      expect(OutboundHttp).to have_received(:request).with(
        :get,
        "https://api.example.test/resource?q=1",
        hash_including(
          follow_redirects: true,
          max_redirects: 2,
          headers: { "Accept" => "text/plain" },
          public_only: true
        )
      )
    end

    it "streams a size-capped request through the public-only guard and returns the buffered body" do
      stub_request(:get, url).to_return(status: 200, body: "small")
      allow(OutboundHttp).to receive(:stream).and_call_original
      expect(OutboundHttp).not_to receive(:request)

      response = request(max_bytes: 128)

      expect(response.status).to eq(200)
      expect(response.body).to eq("small")
      expect(OutboundHttp).to have_received(:stream)
        .with(:get, url, hash_including(max_bytes: 128, public_only: true))
    end

    it "keeps only the final hop's status, headers and body when a capped request follows a redirect" do
      stub_request(:get, url)
        .to_return(status: 302, headers: { "Location" => "https://api.example.test/final" }, body: "moved")
      stub_request(:get, "https://api.example.test/final")
        .to_return(status: 200, headers: { "Content-Type" => "text/plain" }, body: "final")

      response = request(max_bytes: 128, follow_redirects: true)

      expect(response.status).to eq(200)
      expect(response.headers["content-type"]).to eq("text/plain")
      expect(response.body).to eq("final")
    end

    it "fails an oversized capped body as transport_error and counts a breaker failure" do
      stub_request(:get, url).to_return(status: 200, body: "x" * 4.kilobytes)

      expect(request(max_bytes: 1.kilobyte, breaker: { name: "downloads", threshold: 1, reset_seconds: 60 })).to be(false)
      expect(ctx[:error_details].last).to include("code" => "transport_error")
      expect(ctx[:error_details].last["details"]).to eq(reason: "ResponseTooLargeError")
      gate = FlowchartRuntime::CircuitBreaker.evaluate(ctx[:customer_id], "downloads", outcome: "none", failure_threshold: 1)
      expect(gate[:allowed]).to be(false)
    end

    it "passes an explicit public_only: false through to OutboundHttp" do
      allow(OutboundHttp).to receive(:request).and_return(OutboundHttp::Response.new(status: 200, headers: {}, body: ""))

      described_class.request(ctx, :post, "http://127.0.0.1:11434/api/chat", public_only: false)

      expect(OutboundHttp).to have_received(:request)
        .with(:post, "http://127.0.0.1:11434/api/chat", hash_including(public_only: false))
    end

    it "fails blocked_destination without retry or a breaker trip" do
      attempts = 0
      allow(OutboundHttp).to receive(:request) do
        attempts += 1
        raise OutboundHttp::BlockedDestinationError, "destination is not allowed"
      end

      expect(request(retries: 2, breaker: { name: "ssrf-guard", threshold: 1, reset_seconds: 60 })).to be(false)
      expect(attempts).to eq(1)
      expect(ctx[:error_details].last["code"]).to eq("blocked_destination")
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.blocked_destination"))

      gate = FlowchartRuntime::CircuitBreaker.evaluate(
        ctx[:customer_id], "ssrf-guard", outcome: "none", failure_threshold: 1
      )
      expect(gate[:allowed]).to be(true)
      expect(gate[:state]).not_to eq("open")
    end
  end
end
