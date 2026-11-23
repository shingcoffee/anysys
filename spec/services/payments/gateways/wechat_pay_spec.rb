require "rails_helper"

RSpec.describe Payments::Gateways::WechatPay do
  let_it_be(:customer) { create(:customer) }
  let(:private_pem) { File.read("spec/fixtures/payments/keys/test_rsa_private.pem") }
  let(:public_pem)  { File.read("spec/fixtures/payments/keys/test_rsa_public.pem") }
  let(:account) do
    create(:payment_merchant_account,
           provider: "wechat_pay", mode: "sandbox", merchant_id: "wx_m1", status: "active",
           credentials: {
             appid: "wxappid123", api_key_v3: "apikey", private_key_pem: private_pem,
             platform_public_key_pem: public_pem, wechat_cert_serial: "SER1"
           })
  end
  let(:gateway) { described_class.new(account: account) }
  let(:order) { create(:payment_order, external_ref: "e1", amount: 1.00, subject: "x") }
  let(:payment) do
    create(:payment, payment_order: order, provider: "wechat_pay", flow: "qr",
           out_trade_no: "ot-1", amount: 1.00)
  end

  before do
    Current.customer = customer
    allow_any_instance_of(described_class).to receive(:notify_url)
      .and_return("https://example.com/payments/webhooks/wechat_pay")
  end

  it_behaves_like "a registered payment gateway", key: "wechat_pay"

  describe "registry hooks" do
    it "declares vendor-specific credential fields" do
      names = described_class.credential_fields.map { |f| f[:name] }
      expect(names).to contain_exactly(:appid, :api_key_v3, :private_key_pem, :platform_public_key_pem, :wechat_cert_serial)
    end

    it "exposes a JSAPI UA pattern matching the WeChat in-app browser" do
      expect("Mozilla/5.0 MicroMessenger/8.0").to match(described_class.jsapi_user_agent_pattern)
    end

    it "extracts the merchant_id from a webhook body's resource.mchid" do
      body = { "resource" => { "mchid" => "wx_m1" } }.to_json
      expect(described_class.extract_merchant_id({}, body)).to eq("wx_m1")
    end

    it "decrypts a WeChat v3 encrypted resource to find the merchant_id" do
      key = "0123456789abcdef0123456789abcdef"
      account.write_credentials(api_key_v3: key)
      account.save!

      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = key
      cipher.iv = "nonce-12byte"
      cipher.auth_data = "transaction"
      plaintext = { "mchid" => "wx_m1", "out_trade_no" => "ot-enc" }.to_json
      ct = cipher.update(plaintext) + cipher.final
      body = {
        "resource" => {
          "algorithm" => "AEAD_AES_256_GCM",
          "ciphertext" => Base64.strict_encode64(ct + cipher.auth_tag),
          "associated_data" => "transaction",
          "nonce" => "nonce-12byte"
        }
      }.to_json

      expect(described_class.extract_merchant_id({}, body)).to eq("wx_m1")
    end

    ["null", "[]", '{"resource":[]}', '{"resource":{"amount":[]}}'].each do |body|
      it "rejects malformed routing containers: #{body}" do
        expect { described_class.extract_merchant_id({}, body) }.to raise_error(Payments::Errors::SignatureInvalid)
      end
    end
  end

  it "charges via Native (QR) API and returns code_url" do
    stub_request(:post, "#{described_class::HOST}/v3/pay/transactions/native")
      .to_return(status: 200,
                 body: File.read("spec/fixtures/payments/wechat/native_prepay.json"),
                 headers: { "Content-Type" => "application/json" })
    result = gateway.charge(order: order, payment: payment, flow: :qr)
    expect(result[:prepay_payload]).to eq(code_url: "weixin://wxpay/bizpayurl?pr=abcd1234")
  end

  it "signs requests with APIv3 RSA-SHA256 Authorization header" do
    captured = nil
    stub_request(:post, "#{described_class::HOST}/v3/pay/transactions/native")
      .with { |req| captured = req; true }
      .to_return(status: 200, body: '{"code_url":"x"}',
                 headers: { "Content-Type" => "application/json" })
    gateway.charge(order: order, payment: payment, flow: :qr)
    expect(captured.headers["Authorization"]).to start_with("WECHATPAY2-SHA256-RSA2048 ")
    expect(captured.headers["Authorization"]).to include(%Q(mchid="wx_m1"))
    expect(captured.headers["Authorization"]).to include(%Q(serial_no="SER1"))
    expect(captured.headers["Content-Type"]).to eq("application/json")
  end

  it "maps query trade_state SUCCESS to :succeeded" do
    stub_request(:get, %r{/v3/pay/transactions/out-trade-no/ot-1})
      .to_return(status: 200,
                 body: '{"trade_state":"SUCCESS","transaction_id":"TX123"}',
                 headers: { "Content-Type" => "application/json" })
    res = gateway.query(payment: payment)
    expect(res[:status]).to eq(:succeeded)
    expect(res[:psp_transaction_id]).to eq("TX123")
  end

  it "returns the PSP's cents/currency/offset timestamp as normalized query assertions" do
    stub_request(:get, %r{/v3/pay/transactions/out-trade-no/ot-1}).to_return(status: 200, body: {
      trade_state: "SUCCESS", transaction_id: "TX123", amount: { total: 100, currency: "CNY" },
      success_time: "2026-10-10T23:30:00+08:00"
    }.to_json)
    expect(gateway.query(payment: payment)).to include(amount: BigDecimal("1.00"), currency: "CNY", settled_at: Time.utc(2026, 10, 10, 15, 30))
  end

  it "raises SignatureInvalid when notification signature headers missing" do
    expect {
      gateway.verify_notification(headers: {}, body: "{}")
    }.to raise_error(Payments::Errors::SignatureInvalid, /missing/)
  end

  it "raises SignatureInvalid on bad signature" do
    # Use a fresh timestamp so the freshness check passes and the
    # signature check is the one that fails — what the test is asserting.
    fresh_ts = Time.now.to_i.to_s
    expect {
      gateway.verify_notification(
        headers: { "Wechatpay-Signature" => Base64.strict_encode64("bad"), "Wechatpay-Timestamp" => fresh_ts, "Wechatpay-Nonce" => "n" },
        body: "{}"
      )
    }.to raise_error(Payments::Errors::SignatureInvalid, /invalid/)
  end

  it "rejects notifications with a stale timestamp even when signed correctly" do
    # Replay protection: a captured-and-replayed notification with a
    # signature that's still cryptographically valid must be rejected
    # because its timestamp is outside the freshness window.
    key = OpenSSL::PKey::RSA.new(private_pem)
    stale_ts = (Time.now.to_i - 3600).to_s
    body = '{"replay":"true"}'
    nonce = "abc"
    message = "#{stale_ts}\n#{nonce}\n#{body}\n"
    sig = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, message))
    expect {
      gateway.verify_notification(
        headers: { "Wechatpay-Signature" => sig, "Wechatpay-Timestamp" => stale_ts, "Wechatpay-Nonce" => nonce },
        body: body
      )
    }.to raise_error(Payments::Errors::SignatureInvalid, /timestamp/)
  end

  it "verifies a correctly-signed notification" do
    key = OpenSSL::PKey::RSA.new(private_pem)
    body = '{"event_type":"TRANSACTION.SUCCESS"}'
    ts = Time.now.to_i.to_s; nonce = "abc"
    message = "#{ts}\n#{nonce}\n#{body}\n"
    sig = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, message))
    result = gateway.verify_notification(
      headers: { "Wechatpay-Signature" => sig, "Wechatpay-Timestamp" => ts, "Wechatpay-Nonce" => nonce },
      body: body
    )
    expect(result).to eq({ "event_type" => "TRANSACTION.SUCCESS" })
  end

  describe "platform certificate rotation (Wechatpay-Serial)" do
    let(:api_v3_key) { "0123456789abcdef0123456789abcdef" } # 32 bytes for AES-256-GCM
    let(:certs_url)  { "https://api.mch.weixin.qq.com/v3/certificates" }

    before do
      account.write_credentials(api_key_v3: api_v3_key)
      account.save!
      Rails.cache.clear
    end

    # AEAD-encrypt an arbitrary blob (a cert PEM) the way WeChat wraps certs.
    def encrypt_blob(plaintext, key:, nonce: "certnonce123", aad: "certificate")
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = key
      cipher.iv = nonce
      cipher.auth_data = aad
      ct = cipher.update(plaintext) + cipher.final
      { "algorithm" => "AEAD_AES_256_GCM", "ciphertext" => Base64.strict_encode64(ct + cipher.auth_tag),
        "associated_data" => aad, "nonce" => nonce }
    end

    def self_signed_cert(key, serial: 424242)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial  = serial
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=WeChatPlatformTest")
      cert.public_key = key.public_key
      cert.not_before = Time.now - 3600
      cert.not_after  = Time.now + 3600
      cert.sign(key, OpenSSL::Digest::SHA256.new)
      cert
    end

    def signed_notification(key, serial:, body: '{"event_type":"TRANSACTION.SUCCESS"}')
      ts = Time.now.to_i.to_s
      nonce = "rot-nonce"
      sig = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, "#{ts}\n#{nonce}\n#{body}\n"))
      { headers: { "Wechatpay-Signature" => sig, "Wechatpay-Timestamp" => ts,
                   "Wechatpay-Nonce" => nonce, "Wechatpay-Serial" => serial }, body: body }
    end

    it "verifies a notification signed by a rotated cert fetched from /v3/certificates" do
      rotated_key = OpenSSL::PKey::RSA.new(2048)
      cert_pem    = self_signed_cert(rotated_key).to_pem
      stub_request(:get, certs_url).to_return(
        status: 200,
        body: { data: [{ serial_no: "NEW-SERIAL",
                         encrypt_certificate: encrypt_blob(cert_pem, key: api_v3_key) }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      req = signed_notification(rotated_key, serial: "NEW-SERIAL")
      result = gateway.verify_notification(headers: req[:headers], body: req[:body])

      expect(result).to eq({ "event_type" => "TRANSACTION.SUCCESS" })
      expect(a_request(:get, certs_url)).to have_been_made
    end

    it "falls back to the stored platform key when the cert fetch is unavailable" do
      stub_request(:get, certs_url).to_return(status: 500, body: "err")

      # Signed by the stored key (private_pem ↔ platform_public_key_pem), header
      # names a serial we can't fetch — verification still succeeds via fallback.
      req = signed_notification(OpenSSL::PKey::RSA.new(private_pem), serial: "UNKNOWN")
      result = gateway.verify_notification(headers: req[:headers], body: req[:body])

      expect(result).to eq({ "event_type" => "TRANSACTION.SUCCESS" })
    end

    it "rate-limits re-downloads of platform certs for an unknown serial (L2)" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      # No stored fallback key either — an unresolved serial must raise, not
      # silently succeed via the fallback, so we can observe the cooldown.
      allow(account).to receive(:credential).and_call_original
      allow(account).to receive(:credential).with(:platform_public_key_pem).and_return(nil)
      allow(gateway).to receive(:download_platform_certs).and_return({})
      # Pre-warm the plain (non-refresh) 12h cert cache so both verify_notification
      # calls below exercise only the cooldown-gated refresh path.
      Rails.cache.write(gateway.send(:platform_certs_cache_key), {}, expires_in: 12.hours)

      req = signed_notification(OpenSSL::PKey::RSA.new(private_pem), serial: "UNKNOWN-SERIAL")

      expect {
        gateway.verify_notification(headers: req[:headers], body: req[:body])
      }.to raise_error(Payments::Errors::SignatureInvalid)
      expect {
        gateway.verify_notification(headers: req[:headers], body: req[:body])
      }.to raise_error(Payments::Errors::SignatureInvalid)

      expect(gateway).to have_received(:download_platform_certs).once
    end
  end

  describe "encrypted notification resources (APIv3 AEAD_AES_256_GCM)" do
    let(:api_v3_key) { "0123456789abcdef0123456789abcdef" } # 32 bytes

    before do
      account.write_credentials(api_key_v3: api_v3_key)
      account.save!
    end

    # Build a realistic v3 notification: the transaction object is AES-256-GCM
    # encrypted into resource.ciphertext exactly the way WeChat delivers it
    # (ciphertext || 16-byte auth tag, base64), then the whole body is signed.
    def encrypt_resource(transaction, key:, nonce: "0123456789ab", aad: "transaction")
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = key
      cipher.iv = nonce
      cipher.auth_data = aad
      ciphertext = cipher.update(transaction.to_json) + cipher.final
      {
        "original_type" => "transaction",
        "algorithm" => "AEAD_AES_256_GCM",
        "ciphertext" => Base64.strict_encode64(ciphertext + cipher.auth_tag),
        "associated_data" => aad,
        "nonce" => nonce
      }
    end

    def signed_headers_for(body)
      key = OpenSSL::PKey::RSA.new(private_pem)
      ts = Time.now.to_i.to_s
      nonce = "sig-nonce"
      sig = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, "#{ts}\n#{nonce}\n#{body}\n"))
      { "Wechatpay-Signature" => sig, "Wechatpay-Timestamp" => ts, "Wechatpay-Nonce" => nonce }
    end

    let(:transaction) do
      { "mchid" => "wx_m1", "out_trade_no" => "ot-1", "transaction_id" => "TX-enc-9",
        "trade_state" => "SUCCESS", "amount" => { "total" => 100 } }
    end

    let(:body) do
      {
        "id" => "EV-1", "event_type" => "TRANSACTION.SUCCESS", "resource_type" => "encrypt-resource",
        "resource" => encrypt_resource(transaction, key: api_v3_key)
      }.to_json
    end

    it "decrypts the resource and merges the transaction fields into it" do
      result = gateway.verify_notification(headers: signed_headers_for(body), body: body)
      expect(result.dig("resource", "out_trade_no")).to eq("ot-1")
      expect(result.dig("resource", "transaction_id")).to eq("TX-enc-9")
      expect(result.dig("resource", "trade_state")).to eq("SUCCESS")
      # envelope fields survive the merge
      expect(result.dig("resource", "algorithm")).to eq("AEAD_AES_256_GCM")
      expect(result["event_type"]).to eq("TRANSACTION.SUCCESS")
    end

    it "rejects a tampered ciphertext (auth tag mismatch)" do
      payload = JSON.parse(body)
      raw = Base64.strict_decode64(payload["resource"]["ciphertext"])
      raw[0] = (raw[0].ord ^ 0xFF).chr
      payload["resource"]["ciphertext"] = Base64.strict_encode64(raw)
      tampered = payload.to_json
      expect {
        gateway.verify_notification(headers: signed_headers_for(tampered), body: tampered)
      }.to raise_error(Payments::Errors::SignatureInvalid, /decrypt/i)
    end

    it "rejects a decrypted transaction whose mchid is not this account's" do
      foreign = transaction.merge("mchid" => "SOMEONE_ELSE")
      evil_body = {
        "id" => "EV-2", "event_type" => "TRANSACTION.SUCCESS",
        "resource" => encrypt_resource(foreign, key: api_v3_key)
      }.to_json
      expect {
        gateway.verify_notification(headers: signed_headers_for(evil_body), body: evil_body)
      }.to raise_error(Payments::Errors::SignatureInvalid, /mchid/i)
    end

    it "raises CredentialsMissing when the APIv3 key is not configured" do
      # write_credentials treats blank as "keep existing", so stub the read instead.
      allow(account).to receive(:credential).and_call_original
      allow(account).to receive(:credential).with(:api_key_v3).and_return(nil)
      expect {
        gateway.verify_notification(headers: signed_headers_for(body), body: body)
      }.to raise_error(Payments::Errors::CredentialsMissing, /APIv3/i)
    end

    it "rejects an unsupported resource algorithm" do
      payload = JSON.parse(body)
      payload["resource"]["algorithm"] = "AEAD_AES_256_CBC"
      weird = payload.to_json
      expect {
        gateway.verify_notification(headers: signed_headers_for(weird), body: weird)
      }.to raise_error(Payments::Errors::SignatureInvalid, /algorithm/i)
    end

    it "leaves plaintext (non-encrypted) resources untouched" do
      plain_body = { "resource" => { "mchid" => "wx_m1", "out_trade_no" => "ot-plain" } }.to_json
      result = gateway.verify_notification(headers: signed_headers_for(plain_body), body: plain_body)
      expect(result.dig("resource", "out_trade_no")).to eq("ot-plain")
    end

    it "still resolves an encrypted notification after disabling the merchant's new charges" do
      account.update!(status: "disabled")
      expect(described_class.extract_merchant_id({}, body)).to eq(account.merchant_id)
    end

    [nil, []].each do |resource|
      it "rejects a signed encrypted resource whose plaintext is #{resource.inspect}" do
        payload = { "resource" => encrypt_resource(resource, key: api_v3_key) }.to_json
        expect { gateway.verify_notification(headers: signed_headers_for(payload), body: payload) }
          .to raise_error(Payments::Errors::SignatureInvalid)
      end
    end

    it "classifies a malformed configured APIv3 key as configuration failure" do
      account.write_credentials(api_key_v3: "short-key")
      expect { gateway.verify_notification(headers: signed_headers_for(body), body: body) }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end
  end

  describe "charge — flow branches" do
    it "charges via H5 API with required scene_info and returns h5_url" do
      stub_request(:post, "#{described_class::HOST}/v3/pay/transactions/h5")
        .with { |req|
          body = JSON.parse(req.body)
          body.dig("scene_info", "payer_client_ip") == "203.0.113.10" &&
            body.dig("scene_info", "h5_info", "type") == "Wap"
        }
        .to_return(status: 200,
                   body: '{"h5_url":"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?prepay_id=wx123"}',
                   headers: { "Content-Type" => "application/json" })
      result = gateway.charge(order: order, payment: payment, flow: :h5, client_ip: "203.0.113.10")
      expect(result[:prepay_payload]).to have_key(:h5_url)
      expect(result[:prepay_payload][:h5_url]).to include("prepay_id")
    end

    it "charges via JSAPI and returns signed jsapi_params" do
      stub_request(:post, "#{described_class::HOST}/v3/pay/transactions/jsapi")
        .to_return(status: 200,
                   body: '{"prepay_id":"wx20241101abc"}',
                   headers: { "Content-Type" => "application/json" })
      result = gateway.charge(order: order, payment: payment, flow: :jsapi, openid: "oUser123")
      payload = result[:prepay_payload]
      expect(payload).to have_key(:appId)
      expect(payload).to have_key(:paySign)
      expect(payload[:signType]).to eq("RSA")
      expect(payload[:package]).to eq("prepay_id=wx20241101abc")
    end

    it "includes payer.openid in JSAPI body when openid provided" do
      captured = nil
      stub_request(:post, "#{described_class::HOST}/v3/pay/transactions/jsapi")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: '{"prepay_id":"wx_jsapi"}',
                   headers: { "Content-Type" => "application/json" })
      gateway.charge(order: order, payment: payment, flow: :jsapi, openid: "oOpenId99")
      body_json = JSON.parse(captured.body)
      expect(body_json.dig("payer", "openid")).to eq("oOpenId99")
    end

    it "omits payer from JSAPI body when openid is absent" do
      captured = nil
      stub_request(:post, "#{described_class::HOST}/v3/pay/transactions/jsapi")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: '{"prepay_id":"wx_jsapi_no_openid"}',
                   headers: { "Content-Type" => "application/json" })
      gateway.charge(order: order, payment: payment, flow: :jsapi)
      body_json = JSON.parse(captured.body)
      expect(body_json).not_to have_key("payer")
    end

    it "raises ArgumentError for an unsupported flow" do
      expect {
        gateway.charge(order: order, payment: payment, flow: :bogus)
      }.to raise_error(ArgumentError, /unsupported WeChat Pay flow/)
    end
  end

  describe "per-tenant appid (multi-tenant isolation)" do
    # appid is a per-merchant credential, NOT a global ENV — each tenant binds
    # its own official-account / mini-program appid to its WeChat Pay merchant.
    it "stamps the account's appid in the native charge body" do
      captured = nil
      stub_request(:post, "#{described_class::HOST}/v3/pay/transactions/native")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: '{"code_url":"x"}',
                   headers: { "Content-Type" => "application/json" })
      gateway.charge(order: order, payment: payment, flow: :qr)
      expect(JSON.parse(captured.body)["appid"]).to eq("wxappid123")
    end

    it "signs JSAPI params with the account's appid" do
      stub_request(:post, "#{described_class::HOST}/v3/pay/transactions/jsapi")
        .to_return(status: 200, body: '{"prepay_id":"wx_jsapi_appid"}',
                   headers: { "Content-Type" => "application/json" })
      payload = gateway.charge(order: order, payment: payment, flow: :jsapi)[:prepay_payload]
      expect(payload[:appId]).to eq("wxappid123")
    end
  end

  describe "refund" do
    it "reports an explicit WeChat parameter rejection as non-execution" do
      stub_request(:post, "#{described_class::HOST}/v3/refund/domestic/refunds")
        .to_return(status: 400, body: { code: "PARAM_ERROR", message: "Invalid refund amount" }.to_json)
      refund = double(out_refund_no: "rf-invalid", amount: 0.50, reason: "refund")
      expect { gateway.refund(payment: payment, refund: refund) }
        .to raise_error(Payments::Errors::ApiError) { |error| expect(error).to be_definitive }
    end

    it "retains the original operation for an unspecified WeChat business outcome" do
      stub_request(:post, "#{described_class::HOST}/v3/refund/domestic/refunds")
        .to_return(status: 400, body: { code: "OUT_REFUND_NO_USED", message: "Refund identity already used" }.to_json)
      refund = double(out_refund_no: "rf-existing", amount: 0.50, reason: "refund")
      expect { gateway.refund(payment: payment, refund: refund) }
        .to raise_error(Payments::Errors::ApiError) { |error| expect(error).to be_uncertain }
    end

    it "returns psp_refund_id and succeeded status on success" do
      stub_request(:post, "#{described_class::HOST}/v3/refund/domestic/refunds")
        .to_return(status: 200,
                   body: File.read("spec/fixtures/payments/wechat/refund_success.json"),
                   headers: { "Content-Type" => "application/json" })
      refund = double("refund", out_refund_no: "rf-1", amount: 1.00, reason: "test refund")
      res = gateway.refund(payment: payment, refund: refund)
      expect(res[:psp_refund_id]).to eq("50300000001")
      expect(res[:status]).to eq(:succeeded)
    end

    it "maps PROCESSING refund status to :processing" do
      stub_request(:post, "#{described_class::HOST}/v3/refund/domestic/refunds")
        .to_return(status: 200,
                   body: '{"refund_id":"rf-2","status":"PROCESSING"}',
                   headers: { "Content-Type" => "application/json" })
      refund = double("refund", out_refund_no: "rf-2", amount: 0.50, reason: "partial")
      res = gateway.refund(payment: payment, refund: refund)
      expect(res[:status]).to eq(:processing)
    end

    it "maps CLOSED refund status to :failed" do
      stub_request(:post, "#{described_class::HOST}/v3/refund/domestic/refunds")
        .to_return(status: 200,
                   body: '{"refund_id":"rf-3","status":"CLOSED"}',
                   headers: { "Content-Type" => "application/json" })
      refund = double("refund", out_refund_no: "rf-3", amount: 0.50, reason: "expired")
      res = gateway.refund(payment: payment, refund: refund)
      expect(res[:status]).to eq(:failed)
    end

    it "maps ABNORMAL refund status to :failed" do
      stub_request(:post, "#{described_class::HOST}/v3/refund/domestic/refunds")
        .to_return(status: 200,
                   body: '{"refund_id":"rf-4","status":"ABNORMAL"}',
                   headers: { "Content-Type" => "application/json" })
      refund = double("refund", out_refund_no: "rf-4", amount: 0.50, reason: "abnormal")
      res = gateway.refund(payment: payment, refund: refund)
      expect(res[:status]).to eq(:failed)
    end

    it "maps unknown refund status to :processing" do
      stub_request(:post, "#{described_class::HOST}/v3/refund/domestic/refunds")
        .to_return(status: 200,
                   body: '{"refund_id":"rf-5","status":"SOMETHING_ELSE"}',
                   headers: { "Content-Type" => "application/json" })
      refund = double("refund", out_refund_no: "rf-5", amount: 0.50, reason: "unknown")
      res = gateway.refund(payment: payment, refund: refund)
      expect(res[:status]).to eq(:processing)
    end
  end

  describe "close" do
    it "returns status :closed" do
      stub_request(:post, %r{/v3/pay/transactions/out-trade-no/.+/close})
        .to_return(status: 204, body: "")
      res = gateway.close(payment: payment)
      expect(res[:status]).to eq(:closed)
    end
  end

  describe "NotImplementedError stubs" do
    it "subscribe raises NotImplementedError" do
      subscription = double("subscription")
      expect {
        gateway.subscribe(subscription: subscription)
      }.to raise_error(NotImplementedError, /WeChat contract-pay stub/)
    end

    it "cancel_subscription raises NotImplementedError" do
      subscription = double("subscription")
      expect {
        gateway.cancel_subscription(subscription: subscription)
      }.to raise_error(NotImplementedError, /WeChat contract-pay stub/)
    end

    it "charge_subscription raises NotImplementedError" do
      subscription = double("subscription")
      expect {
        gateway.charge_subscription(subscription: subscription, payment: payment)
      }.to raise_error(NotImplementedError, /WeChat contract-pay stub/)
    end
  end

  describe "download_bill" do
    let(:bill_csv) do
      "交易时间,微信订单号,商户订单号,交易状态,货币种类,订单金额\n" \
        "`2026-01-01 10:00:00,`WX1,`ot-1,`SUCCESS,`CNY,`1.00\n" \
        "总交易单数,订单总金额\n`1,`1.00\n"
    end

    it "signs the exact download path/query and returns native bytes plus normalized rows" do
      bill_url = "https://api.mch.weixin.qq.com/v3/billdownload/file?token=abc123"
      stub_request(:get, %r{/v3/bill/tradebill})
        .to_return(status: 200,
                    body: { download_url: bill_url, hash_type: "SHA1", hash_value: Digest::SHA1.hexdigest(bill_csv) }.to_json,
                    headers: { "Content-Type" => "application/json" })
      stub_request(:get, bill_url)
        .with do |request|
          attributes = request.headers["Authorization"].scan(/(\w+)="([^"]*)"/).to_h
          message = "GET\n/v3/billdownload/file?token=abc123\n#{attributes['timestamp']}\n#{attributes['nonce_str']}\n\n"
          expect(attributes).to include("mchid" => "wx_m1", "serial_no" => "SER1")
          expect(OpenSSL::PKey::RSA.new(public_pem).verify(OpenSSL::Digest::SHA256.new,
                                                        Base64.decode64(attributes.fetch("signature")), message)).to be(true)
          true
        end
        .to_return(status: 200, body: bill_csv)
      res = gateway.download_bill(bill_date: Date.new(2026, 1, 1), bill_type: "ALL")
      expect(res[:csv]).to eq(bill_csv)
      expect(res[:rows].sole).to include("kind" => "payment", "out_trade_no" => "ot-1", "amount" => BigDecimal("1.00"), "currency" => "CNY")
      expect(res[:raw_summary]["bill_summary"]).to eq("总交易单数" => "1", "订单总金额" => "1.00")
    end

    it "rejects a checksum mismatch before reconciling corrupted bytes" do
      url = "https://api.mch.weixin.qq.com/v3/billdownload/file?token=hash"
      stub_request(:get, %r{/v3/bill/tradebill}).to_return(status: 200, body: {
        download_url: url, hash_type: "SHA1", hash_value: "0" * 40
      }.to_json)
      stub_request(:get, url).to_return(status: 200, body: bill_csv)
      expect { gateway.download_bill(bill_date: Date.current, bill_type: "all") }
        .to raise_error(Payments::Errors::TransportError, /checksum/)
    end

    it "does not send merchant authorization to an unexpected download origin" do
      stub_request(:get, %r{/v3/bill/tradebill}).to_return(status: 200, body: {
        download_url: "https://unrelated.example/v3/billdownload/file?token=x"
      }.to_json)
      expect { gateway.download_bill(bill_date: Date.current, bill_type: "all") }
        .to raise_error(Payments::Errors::ApiError)
      expect(a_request(:get, /unrelated/)).not_to have_been_made
    end
  end

  describe "key configuration failures" do
    it "maps invalid merchant PEM to a Payments configuration error" do
      account.write_credentials(private_key_pem: "invalid-secret-pem")
      expect { gateway.charge(order: order, payment: payment, flow: :qr) }
        .to raise_error(Payments::Errors::CredentialsMissing) { |error| expect(error.message).not_to include("invalid-secret-pem") }
    end

    it "rejects a public-only merchant signing key" do
      account.write_credentials(private_key_pem: public_pem)
      expect { gateway.charge(order: order, payment: payment, flow: :qr) }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end

    it "maps invalid stored platform certificate/key to a Payments configuration error" do
      account.write_credentials(platform_public_key_pem: "-----BEGIN CERTIFICATE-----\ninvalid")
      expect {
        gateway.verify_notification(headers: { "Wechatpay-Signature" => "bad", "Wechatpay-Timestamp" => Time.current.to_i.to_s,
                                               "Wechatpay-Nonce" => "nonce" }, body: "{}")
      }.to raise_error(Payments::Errors::CredentialsMissing)
    end
  end

  describe "map_status branches" do
    it "maps NOTPAY to :pending" do
      stub_request(:get, %r{/v3/pay/transactions/out-trade-no/ot-1})
        .to_return(status: 200,
                   body: '{"trade_state":"NOTPAY","transaction_id":"TX-NP"}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.query(payment: payment)
      expect(res[:status]).to eq(:pending)
    end

    it "maps USERPAYING to :pending" do
      stub_request(:get, %r{/v3/pay/transactions/out-trade-no/ot-1})
        .to_return(status: 200,
                   body: '{"trade_state":"USERPAYING","transaction_id":"TX-UP"}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.query(payment: payment)
      expect(res[:status]).to eq(:pending)
    end

    it "maps CLOSED to :closed" do
      stub_request(:get, %r{/v3/pay/transactions/out-trade-no/ot-1})
        .to_return(status: 200,
                   body: '{"trade_state":"CLOSED","transaction_id":"TX-CL"}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.query(payment: payment)
      expect(res[:status]).to eq(:closed)
    end

    it "maps REVOKED to :closed" do
      stub_request(:get, %r{/v3/pay/transactions/out-trade-no/ot-1})
        .to_return(status: 200,
                   body: '{"trade_state":"REVOKED","transaction_id":"TX-RV"}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.query(payment: payment)
      expect(res[:status]).to eq(:closed)
    end

    it "maps unknown trade_state to :failed" do
      stub_request(:get, %r{/v3/pay/transactions/out-trade-no/ot-1})
        .to_return(status: 200,
                   body: '{"trade_state":"PAYERROR","transaction_id":"TX-PE"}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.query(payment: payment)
      expect(res[:status]).to eq(:failed)
    end
  end
end
