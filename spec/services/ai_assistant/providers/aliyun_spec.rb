# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Providers::Aliyun do
  let(:settings) do
    build_stubbed(:ai_assistant_provider_settings,
                  provider: "aliyun",
                  api_key: "AKS",
                  config: { access_key_id: "AKID", app_key: "app-1", region: "cn-shanghai" }.to_json)
  end
  let(:adapter) { described_class.new(settings: settings) }
  let(:io) { StringIO.new("fake-audio") }
  let(:token_host) { "https://nls-meta.cn-shanghai.aliyuncs.com/" }
  let(:flash_host) { "https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/FlashRecognizer" }

  def transcribe(language: "en")
    adapter.transcribe(io: io, filename: "clip.wav", content_type: "audio/wav", language: language)
  end

  def stub_token(status: 200, body: { "Token" => { "Id" => "tok-1" } })
    stub_request(:post, token_host).to_return(
      status: status,
      body: body.is_a?(String) ? body : body.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  def stub_flash(status: 200, body:, filename: "clip.wav")
    stub_request(:post, %r{\A#{Regexp.escape(flash_host)}}).to_return(
      status: status,
      body: body.is_a?(String) ? body : body.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  it_behaves_like "an AI Assistant registered provider",
                  key: "aliyun",
                  display_name: "Aliyun",
                  supports_transcribe: true,
                  supports_generation: false,
                  configured_on_api_key: false

  describe ".configured?" do
    it "is false when required credentials are blank" do
      bare = build(:ai_assistant_provider_settings, provider: "aliyun", api_key: nil, config: {}.to_json)
      expect(described_class.configured?(bare)).to eq(false)
    end

    it "is true when secret, access key id, and app key are present" do
      expect(described_class.configured?(settings)).to eq(true)
    end
  end

  describe "#transcribe" do
    it "returns :success from flash sentences and never hits a live Aliyun endpoint" do
      stub_token
      stub_flash(body: { "status" => 20_000_000, "flash_result" => { "sentences" => [ { "text" => "你好" } ] } })

      result = transcribe
      expect(result[:outcome]).to eq(:success)
      expect(result[:text]).to eq("你好")
      expect(WebMock).to have_requested(:post, token_host)
      expect(WebMock).to have_requested(:post, %r{\A#{Regexp.escape(flash_host)}}).with { |req|
        query = URI.parse(req.uri).query
        params = URI.decode_www_form(query).to_h
        params["appkey"] == "app-1" && params["token"] == "tok-1" && params["format"] == "wav"
      }
    end

    it "maps webm clips to opus format" do
      stub_token
      stub_flash(body: { "status" => 20_000_000, "flash_result" => { "sentences" => [ { "text" => "ok" } ] } })
      adapter.transcribe(io: io, filename: "clip.webm", content_type: "audio/webm", language: "auto")
      expect(WebMock).to have_requested(:post, %r{\A#{Regexp.escape(flash_host)}}).with { |req|
        URI.decode_www_form(URI.parse(req.uri).query).to_h["format"] == "opus"
      }
    end

    it "returns :empty when flash sentences are blank" do
      stub_token
      stub_flash(body: { "status" => 20_000_000, "flash_result" => { "sentences" => [ { "text" => "  " } ] } })
      expect(transcribe[:outcome]).to eq(:empty)
    end

    it "returns :configuration_error when credentials are missing without calling Aliyun" do
      settings.api_key = nil
      expect(OutboundHttp).not_to receive(:request)
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps a CreateToken 4xx to :configuration_error" do
      stub_token(status: 403, body: { "Code" => "InvalidAccessKeyId.NotFound" })
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps a CreateToken 5xx to :unreachable" do
      stub_token(status: 503, body: "")
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "maps a blank token id to :configuration_error" do
      stub_token(body: { "Token" => { "Id" => "" } })
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps a flash vendor error status to :configuration_error" do
      stub_token
      stub_flash(body: { "status" => 40_000_001, "message" => "GATEWAY:INVALID_APPKEY" })
      expect(transcribe[:outcome]).to eq(:configuration_error)
    end

    it "maps a flash 5xxxxxxx vendor status to :unreachable" do
      stub_token
      stub_flash(body: { "status" => 50_000_000, "message" => "GATEWAY:INTERNAL" })
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "maps a flash HTTP 5xx to :unreachable" do
      stub_token
      stub_flash(status: 502, body: "")
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "maps a timeout to :unreachable" do
      stub_request(:post, token_host).to_timeout
      expect(transcribe[:outcome]).to eq(:unreachable)
    end

    it "computes a deterministic signature for a known input (golden test)" do
      allow(SecureRandom).to receive(:uuid).and_return("nonce-fixed")
      allow(Time).to receive(:now).and_return(Time.utc(2026, 5, 12, 12, 0, 0))

      params = adapter.sign_params(adapter.common_params.merge("Action" => "CreateToken"))
      sorted = params.except("Signature").sort.map { |k, v|
        kp = CGI.escape(k.to_s).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~")
        vp = CGI.escape(v.to_s).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~")
        "#{kp}=#{vp}"
      }.join("&")
      to_sign  = "POST&%2F&" + CGI.escape(sorted).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~")
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", "AKS&", to_sign))

      expect(params["Signature"]).to eq(expected)
    end
  end

  describe "#chat" do
    it "fail-closes because this vendor is transcription-only" do
      expect(adapter.chat(messages: [])).to eq(outcome: :configuration_error, text: nil, raw: nil)
    end
  end
end
