# frozen_string_literal: true

require "rails_helper"

RSpec.describe OutboundHttp do
  describe ".request" do
    it "performs a GET and returns a Response" do
      stub_request(:get, "https://api.example.com/ping")
        .to_return(status: 200, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })

      res = described_class.request(:get, "https://api.example.com/ping")

      expect(res).to be_a(OutboundHttp::Response)
      expect(res.status).to eq(200)
      expect(res.code).to eq("200")
      expect(res.body).to eq('{"ok":true}')
      expect(res).to be_success
    end

    it "sends a String body as-is" do
      stub = stub_request(:post, "https://api.example.com/raw")
             .with(body: '{"amount":100}')
             .to_return(status: 200, body: "")

      described_class.request(:post, "https://api.example.com/raw", body: '{"amount":100}')

      expect(stub).to have_been_requested
    end

    it "JSON-encodes a Hash body" do
      stub = stub_request(:post, "https://api.example.com/json")
             .with(body: '{"amount":100}', headers: { "Content-Type" => "application/json" })
             .to_return(status: 200, body: "")

      described_class.request(:post, "https://api.example.com/json", body: { amount: 100 })

      expect(stub).to have_been_requested
    end

    it "URL-encodes form params and sets the form content type" do
      stub = stub_request(:post, "https://api.example.com/form")
             .with(
               body: "a=1&b=two",
               headers: { "Content-Type" => "application/x-www-form-urlencoded" }
             )
             .to_return(status: 200, body: "")

      described_class.request(:post, "https://api.example.com/form", form: { a: 1, b: "two" })

      expect(stub).to have_been_requested
    end

    it "encodes multipart fields and files with a boundary" do
      file = Faraday::Multipart::FilePart.new(StringIO.new("file body"), "text/plain", "note.txt")
      stub = stub_request(:post, "https://api.example.com/multipart")
             .with { |request|
               request.headers["Content-Type"].match?(/\Amultipart\/form-data; boundary=.+/) &&
                 request.body.include?('name="title"') &&
                 request.body.include?("Example") &&
                 request.body.include?('filename="note.txt"') &&
                 request.body.include?("file body")
             }
             .to_return(status: 200, body: "")

      described_class.request(
        :post,
        "https://api.example.com/multipart",
        multipart: { "title" => "Example", "file" => file }
      )

      expect(stub).to have_been_requested
    end

    it "encodes text-only multipart fields with a boundary" do
      stub = stub_request(:post, "https://api.example.com/multipart-fields")
             .with { |request|
               request.headers["Content-Type"].match?(/\Amultipart\/form-data; boundary=.+/) &&
                 request.body.include?('name="title"') &&
                 request.body.include?("Example")
             }
             .to_return(status: 200, body: "")

      described_class.request(
        :post,
        "https://api.example.com/multipart-fields",
        multipart: { "title" => "Example" }
      )

      expect(stub).to have_been_requested
    end

    it "passes request headers through" do
      stub = stub_request(:get, "https://api.example.com/hdr")
             .with(headers: { "X-Custom" => "yes" })
             .to_return(status: 200, body: "")

      described_class.request(:get, "https://api.example.com/hdr", headers: { "X-Custom" => "yes" })

      expect(stub).to have_been_requested
    end

    it "returns non-2xx responses without raising" do
      stub_request(:get, "https://api.example.com/missing").to_return(status: 404, body: "nope")

      res = described_class.request(:get, "https://api.example.com/missing")

      expect(res.status).to eq(404)
      expect(res).not_to be_success
      expect(res).not_to be_redirect
    end

    it "flags 3xx responses as redirects" do
      stub_request(:get, "https://api.example.com/moved")
        .to_return(status: 302, body: "", headers: { "Location" => "https://api.example.com/new" })

      res = described_class.request(:get, "https://api.example.com/moved")

      expect(res).to be_redirect
      expect(res).not_to be_success
    end

    it "raises TransportError on timeout, flagged as timeout" do
      stub_request(:get, "https://api.example.com/slow").to_timeout

      expect {
        described_class.request(:get, "https://api.example.com/slow")
      }.to raise_error(OutboundHttp::TransportError, &:timeout?)
    end

    it "raises TransportError on refused connections, not flagged as timeout" do
      stub_request(:get, "https://api.example.com/refused").to_raise(Errno::ECONNREFUSED)

      begin
        described_class.request(:get, "https://api.example.com/refused")
        raise "expected TransportError"
      rescue OutboundHttp::TransportError => e
        expect(e.timeout?).to be(false)
      end
    end

    it "follows redirects when follow_redirects: true" do
      stub_request(:get, "https://api.example.com/old")
        .to_return(status: 302, headers: { "Location" => "https://api.example.com/new" }, body: "")
      stub_request(:get, "https://api.example.com/new")
        .to_return(status: 200, body: "ok")

      res = described_class.request(:get, "https://api.example.com/old", follow_redirects: true)

      expect(res.status).to eq(200)
      expect(res.body).to eq("ok")
    end

    it "does not follow redirects by default" do
      stub_request(:get, "https://api.example.com/old")
        .to_return(status: 302, headers: { "Location" => "https://api.example.com/new" }, body: "")

      res = described_class.request(:get, "https://api.example.com/old")

      expect(res).to be_redirect
      expect(res.status).to eq(302)
    end

    it "raises a redirect error after max_redirects" do
      stub_request(:get, "https://api.example.com/a")
        .to_return(status: 302, headers: { "Location" => "https://api.example.com/b" }, body: "")
      stub_request(:get, "https://api.example.com/b")
        .to_return(status: 302, headers: { "Location" => "https://api.example.com/c" }, body: "")

      expect {
        described_class.request(:get, "https://api.example.com/a", follow_redirects: true, max_redirects: 1)
      }.to raise_error(OutboundHttp::RedirectError, /maximum redirects/)
    end

    it "strips sensitive headers on cross-origin redirects" do
      first = stub_request(:get, "https://api.example.com/start")
              .with(headers: { "Authorization" => "Bearer secret", "Cookie" => "sid=1", "X-Signature" => "sig", "X-Trace" => "trace" })
              .to_return(status: 302, headers: { "Location" => "https://other.example.net/next" })
      second = stub_request(:get, "https://other.example.net/next")
               .with { |request|
                 request.headers["X-Trace"] == "trace" &&
                   request.headers["Authorization"].nil? &&
                   request.headers["Cookie"].nil? &&
                   request.headers["X-Signature"].nil?
               }
               .to_return(status: 200, body: "ok")

      described_class.request(
        :get,
        "https://api.example.com/start",
        headers: { "Authorization" => "Bearer secret", "Cookie" => "sid=1", "X-Signature" => "sig", "X-Trace" => "trace" },
        follow_redirects: true
      )

      expect(first).to have_been_requested
      expect(second).to have_been_requested
    end

    it "preserves method and body for 307 and 308 redirects" do
      [307, 308].each do |status|
        stub_request(:post, "https://api.example.com/#{status}")
          .to_return(status:, headers: { "Location" => "/#{status}/next" })
        redirected = stub_request(:post, "https://api.example.com/#{status}/next")
                     .with(body: '{"amount":100}', headers: { "Content-Type" => "application/json" })
                     .to_return(status: 200)

        described_class.request(:post, "https://api.example.com/#{status}", body: { amount: 100 }, follow_redirects: true)

        expect(redirected).to have_been_requested
      end
    end

    it "replays complete nested multipart uploads for 307 and 308 redirects" do
      [307, 308].each do |status|
        upload_body = "multipart payload for #{status}"
        file = Faraday::Multipart::FilePart.new(StringIO.new(upload_body), "text/plain", "note.txt")
        bodies = []

        stub_request(:post, "https://api.example.com/#{status}/multipart")
          .to_return do |request|
            bodies << request.body
            { status:, headers: { "Location" => "/#{status}/multipart/next" } }
          end
        stub_request(:post, "https://api.example.com/#{status}/multipart/next")
          .to_return do |request|
            bodies << request.body
            { status: 200 }
          end

        described_class.request(
          :post,
          "https://api.example.com/#{status}/multipart",
          multipart: { "metadata" => { "uploads" => [file] } },
          follow_redirects: true
        )

        expect(bodies.size).to eq(2)
        expect(bodies).to all(include(upload_body))
      end
    end

    it "normalizes multipart rewind failures to an OutboundHttp error" do
      io = StringIO.new("file body")
      rewind_count = 0
      allow(io).to receive(:rewind).and_wrap_original do |original|
        rewind_count += 1
        raise IOError, "cannot rewind upload" if rewind_count > 1

        original.call
      end
      file = Faraday::UploadIO.new(io, "text/plain", "note.txt")

      stub_request(:post, "https://api.example.com/rewind")
        .to_return(status: 307, headers: { "Location" => "/rewind/next" })
      stub_request(:post, "https://api.example.com/rewind/next")
        .to_return(status: 200)

      expect {
        described_class.request(
          :post,
          "https://api.example.com/rewind",
          multipart: { "nested" => [{ "file" => file }] },
          follow_redirects: true
        )
      }.to raise_error(OutboundHttp::InvalidRequestError, /rewind multipart upload/)
    end

    it "converts POST to GET for 301, 302, and 303 redirects" do
      [301, 302, 303].each do |status|
        stub_request(:post, "https://api.example.com/#{status}")
          .to_return(status:, headers: { "Location" => "/#{status}/next" })
        redirected = stub_request(:get, "https://api.example.com/#{status}/next")
                     .with { |request| request.body.to_s.empty? && request.headers["Content-Type"].nil? }
                     .to_return(status: 200)

        described_class.request(:post, "https://api.example.com/#{status}", body: { amount: 100 }, follow_redirects: true)

        expect(redirected).to have_been_requested
      end
    end

    it "raises an explicit error for invalid request methods" do
      expect {
        described_class.request(:trace, "https://api.example.com")
      }.to raise_error(OutboundHttp::InvalidRequestError, /unsupported method/)
    end

    it "raises an explicit error for invalid timeouts" do
      expect {
        described_class.request(:get, "https://api.example.com", read_timeout: 0)
      }.to raise_error(OutboundHttp::InvalidRequestError, /read_timeout must be positive/)
    end

    it "rejects conflicting request body modes" do
      expect {
        described_class.request(
          :post,
          "https://api.example.com",
          body: "raw",
          multipart: { "field" => "value" }
        )
      }.to raise_error(OutboundHttp::InvalidRequestError, /only one of body, form, or multipart/)
    end

    it "blocks a hostname that resolves to the instance metadata address when public_only is true", :real_dns_guard do
      allow(OutboundHttp::PublicAddress).to receive(:resolve).with("evil.example.com").and_return(["169.254.169.254"])
      stub_request(:get, "http://evil.example.com/latest").to_return(status: 200, body: "ami-id")

      expect {
        described_class.request(:get, "http://evil.example.com/latest", public_only: true)
      }.to raise_error(OutboundHttp::BlockedDestinationError)

      expect(a_request(:get, "http://evil.example.com/latest")).not_to have_been_made
    end

    it "blocks a literal private IP URL when public_only is true", :real_dns_guard do
      allow(OutboundHttp::PublicAddress).to receive(:resolve).with("10.0.0.1").and_return(["10.0.0.1"])
      stub_request(:get, "http://10.0.0.1/secret").to_return(status: 200, body: "nope")

      expect {
        described_class.request(:get, "http://10.0.0.1/secret", public_only: true)
      }.to raise_error(OutboundHttp::BlockedDestinationError)

      expect(a_request(:get, "http://10.0.0.1/secret")).not_to have_been_made
    end

    it "blocks a redirect hop to a private host when public_only is true", :real_dns_guard do
      allow(OutboundHttp::PublicAddress).to receive(:resolve) do |host|
        case host
        when "api.example.com" then ["93.184.216.34"]
        when "10.0.0.8" then ["10.0.0.8"]
        else
          raise "unexpected host #{host}"
        end
      end
      stub_request(:get, "https://api.example.com/start")
        .to_return(status: 302, headers: { "Location" => "http://10.0.0.8/internal" })
      stub_request(:get, "http://10.0.0.8/internal").to_return(status: 200, body: "secret")

      expect {
        described_class.request(:get, "https://api.example.com/start", public_only: true, follow_redirects: true)
      }.to raise_error(OutboundHttp::BlockedDestinationError)

      expect(a_request(:get, "https://api.example.com/start")).to have_been_made.once
      expect(a_request(:get, "http://10.0.0.8/internal")).not_to have_been_made
    end

    it "allows a public host when public_only is true" do
      stub_request(:get, "https://api.example.com/ping").to_return(status: 200, body: "ok")

      res = described_class.request(:get, "https://api.example.com/ping", public_only: true)

      expect(res.status).to eq(200)
      expect(res.body).to eq("ok")
    end

    it "does not apply the public-address guard by default" do
      stub_request(:get, "http://127.0.0.1/ping").to_return(status: 200, body: "ok")

      res = described_class.request(:get, "http://127.0.0.1/ping")

      expect(res.body).to eq("ok")
    end

    it "rejects a non-http scheme when public_only is true" do
      expect {
        described_class.request(:get, "ftp://example.com/file", public_only: true)
      }.to raise_error(OutboundHttp::InvalidRequestError, /HTTP or HTTPS/)
    end
  end

  describe ".stream" do
    it "delivers chunks through Faraday on_data without retaining the response body" do
      payload = "x" * 40.kilobytes
      stub_request(:get, "https://api.example.com/large").to_return(status: 200, body: payload)
      received = +""

      response = described_class.stream(:get, "https://api.example.com/large") do |chunk|
        received << chunk
      end

      expect(received).to eq(payload)
      expect(response.body).to be_empty
    end

    it "enforces max_bytes before yielding an oversized chunk" do
      payload = "x" * 40.kilobytes
      stub_request(:get, "https://api.example.com/too-large").to_return(status: 200, body: payload)
      received = +""

      expect {
        described_class.stream(:get, "https://api.example.com/too-large", max_bytes: 20.kilobytes) do |chunk|
          received << chunk
        end
      }.to raise_error(OutboundHttp::ResponseTooLargeError, /exceeds maximum size/)

      expect(received.bytesize).to be <= 20.kilobytes
    end

    it "blocks a metadata destination and a private redirect hop when public_only is true", :real_dns_guard do
      allow(OutboundHttp::PublicAddress).to receive(:resolve) do |host|
        { "evil.example.com" => ["169.254.169.254"], "api.example.com" => ["93.184.216.34"], "10.0.0.8" => ["10.0.0.8"] }.fetch(host)
      end
      stub_request(:get, "http://evil.example.com/latest").to_return(status: 200, body: "ami-id")
      stub_request(:get, "https://api.example.com/start")
        .to_return(status: 302, headers: { "Location" => "http://10.0.0.8/internal" })
      stub_request(:get, "http://10.0.0.8/internal").to_return(status: 200, body: "secret")

      expect {
        described_class.stream(:get, "http://evil.example.com/latest", public_only: true) { |_chunk| }
      }.to raise_error(OutboundHttp::BlockedDestinationError)
      expect {
        described_class.stream(:get, "https://api.example.com/start", public_only: true, follow_redirects: true) { |_chunk| }
      }.to raise_error(OutboundHttp::BlockedDestinationError)

      expect(a_request(:get, "http://evil.example.com/latest")).not_to have_been_made
      expect(a_request(:get, "http://10.0.0.8/internal")).not_to have_been_made
    end

    it "streams from a public host when public_only is true" do
      stub_request(:get, "https://api.example.com/ping").to_return(status: 200, body: "ok")
      received = +""

      response = described_class.stream(:get, "https://api.example.com/ping", public_only: true) { |chunk| received << chunk }

      expect(response.status).to eq(200)
      expect(received).to eq("ok")
    end

    it "normalizes invalid stream configuration" do
      expect {
        described_class.stream(:get, "https://api.example.com", max_bytes: -1) { |_chunk| }
      }.to raise_error(OutboundHttp::InvalidRequestError, /max_bytes must be a non-negative integer/)

      expect {
        described_class.stream(:get, "https://api.example.com")
      }.to raise_error(OutboundHttp::InvalidRequestError, /block is required/)
    end
  end
end
