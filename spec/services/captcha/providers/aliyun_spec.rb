# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Providers::Aliyun do
  let(:settings) do
    build_stubbed(:captcha_provider_settings,
                  access_key_id: "AKID",
                  access_key_secret: "AKS",
                  config: { scene_id: "scene-1", prefix: "identity-1", endpoint: "captcha.cn-shanghai.aliyuncs.com", region: "cn-shanghai" }.to_json)
  end
  let(:adapter)  { described_class.new(settings: settings) }
  let(:endpoint) { "https://captcha.cn-shanghai.aliyuncs.com/" }
  # V2 token fields and Result contract from the official server-access guide.
  # https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/server-access
  let(:success_body) { { "Code" => "Success", "Success" => true, "Result" => { "VerifyResult" => true, "VerifyCode" => "T001" } } }
  let(:context) do
    token = { sceneId: "scene-1", certifyId: "certificate-1", deviceToken: "device-token==", data: "behavior-data==" }.to_json
    Captcha::VerificationContext.new(verify_param: token)
  end

  def stub_verify(status:, body:, **opts)
    stub_json(:post, endpoint, status:, body:, **opts)
  end

  it_behaves_like "a captcha provider identity",
                  key: "aliyun", display_name: "Aliyun Captcha", score_based: false

  describe ".verify (class entry point)" do
    it "returns the same shape as instance #verify" do
      stub_verify(status: 200, body: success_body)
      expect(described_class.verify(settings: settings, context: context)[:outcome]).to eq(:success)
    end
  end

  describe ".configured?" do
    it "is false when any required field is blank" do
      bare = build(:captcha_provider_settings, access_key_id: nil, access_key_secret: nil, config: {}.to_json)
      expect(described_class.configured?(bare)).to eq(false)
    end

    it "is true when credentials, scene_id and the V2 identity prefix are present" do
      expect(described_class.configured?(settings)).to eq(true)
    end

    it "is not ready for a browser challenge without the V2 identity prefix" do
      settings.write_config(prefix: nil)
      expect(described_class.configured?(settings)).to be(false)
    end
  end

  describe ".widget" do
    it "returns Stimulus + SDK metadata for the page widget" do
      meta = described_class.widget(settings)
      expect(meta[:stimulus_controller]).to eq("captcha-aliyun")
      expect(meta[:sdk_url]).to start_with("https://")
      expect(meta[:data]["captcha-aliyun-scene-id-value"]).to eq("scene-1")
      expect(meta[:data]["captcha-aliyun-prefix-value"]).to eq("identity-1")
      expect(meta[:data]["captcha-aliyun-region-value"]).to eq("cn")
    end

    it "maps the backend Singapore region to the SDK's sgp region" do
      settings.write_config(region: "ap-southeast-1", endpoint: "captcha.ap-southeast-1.aliyuncs.com")
      expect(described_class.widget(settings)[:data]["captcha-aliyun-region-value"]).to eq("sgp")
    end
  end

  describe "#verify" do
    it "POSTs Action=VerifyIntelligentCaptcha with CaptchaVerifyParam and SceneId" do
      stub_verify(status: 200, body: success_body, headers: { "Content-Type" => "application/json" })

      result = adapter.verify(context: context)

      expect(result).to eq(outcome: :success, http_status: 200, raw: success_body, score: nil)
      expect(WebMock).to have_requested(:post, endpoint).with { |req|
        body = URI.decode_www_form(req.body).to_h
        body["Action"]             == "VerifyIntelligentCaptcha" &&
          body["SceneId"]          == "scene-1" &&
          body["CaptchaVerifyParam"] == context.verify_param &&
          body["AccessKeyId"]      == "AKID" &&
          body["SignatureMethod"]  == "HMAC-SHA1" &&
          body["SignatureVersion"] == "1.0" &&
          body["Format"]           == "JSON" &&
          body["Version"]          == "2023-03-05" &&
          body["Signature"].present?
      }
    end

    it "maps VerifyResult=false to :invalid" do
      stub_verify(status: 200, body: { "Code" => "Success", "Success" => true, "Result" => { "VerifyResult" => false, "VerifyCode" => "F001" } })
      expect(adapter.verify(context: context)).to include(outcome: :invalid, score: nil)
    end

    it "maps HTTP 4xx (e.g. InvalidAccessKeyId) to :configuration_error" do
      stub_verify(status: 400, body: { "Code" => "InvalidAccessKeyId.NotFound", "Message" => "key not found" })
      out = adapter.verify(context: context)
      expect(out[:outcome]).to eq(:configuration_error)
      expect(out[:http_status]).to eq(400)
    end

    it "maps HTTP 5xx to :unreachable" do
      stub_verify(status: 503, body: "")
      expect(adapter.verify(context: context)[:outcome]).to eq(:unreachable)
    end

    it "maps a timeout to :unreachable with a nil http_status" do
      stub_request(:post, endpoint).to_timeout
      out = adapter.verify(context: context)
      expect(out).to eq(outcome: :unreachable, http_status: nil, raw: nil, score: nil)
    end

    ["https://captcha.example.com", "host:443", "user@host", "host/path", "host?query", "bad host", "attacker.example.com", "", nil].each do |endpoint|
      it "maps malformed endpoint #{endpoint.inspect} to a controlled configuration outcome without sending credentials" do
        settings.write_config(endpoint: endpoint)
        expect(OutboundHttp).not_to receive(:request)
        expect(adapter.verify(context: context)).to eq(outcome: :configuration_error, http_status: nil, raw: nil, score: nil)
      end
    end

    it "rejects a region/endpoint mismatch before any outbound request" do
      settings.write_config(region: "ap-southeast-1")
      expect(OutboundHttp).not_to receive(:request)
      expect(adapter.verify(context: context)[:outcome]).to eq(:configuration_error)
    end

    described_class::ENDPOINTS.each do |region, endpoints|
      endpoints.each do |host|
        it "accepts the documented #{region} endpoint #{host}" do
          expect(described_class.valid_configuration?({ "region" => region, "endpoint" => host })).to be(true)
        end
      end
    end

    ["null", "[]", "true"].each do |config|
      it "handles non-object configuration #{config} without raising" do
        settings.config = config
        expect(described_class.configured?(settings)).to be(false)
        expect(adapter.verify(context: context)[:outcome]).to eq(:configuration_error)
      end
    end

    [nil, [], true, { "Result" => true }, { "Result" => { "VerifyResult" => "true" } }].each do |body|
      it "handles malformed verification response #{body.inspect} without a 500 or successful verification" do
        stub_verify(status: 200, body: body)
        expect(adapter.verify(context: context)[:outcome]).to eq(:unreachable)
      end
    end

    it "computes a deterministic signature for a known input (golden test)" do
      allow(SecureRandom).to receive(:uuid).and_return("nonce-fixed")
      allow(Time).to receive(:now).and_return(Time.utc(2026, 5, 12, 12, 0, 0))

      params = adapter.send(:sign_params, adapter.send(:common_params).merge(
        "Action"             => "VerifyIntelligentCaptcha",
        "SceneId"            => "scene-1",
        "CaptchaVerifyParam" => "{}"
      ))

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
end
