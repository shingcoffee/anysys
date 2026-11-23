require "rails_helper"

RSpec.describe Payments::Gateways::Alipay do
  let_it_be(:customer) { create(:customer) }
  let(:priv) { File.read("spec/fixtures/payments/keys/test_rsa_private.pem") }
  let(:pub)  { File.read("spec/fixtures/payments/keys/test_rsa_public.pem") }
  let(:account) do
    create(:payment_merchant_account, provider: "alipay", mode: "sandbox",
           merchant_id: "2088app", status: "active",
           credentials: { private_key_pem: priv, platform_public_key_pem: pub })
  end
  let(:order) { create(:payment_order, external_ref: "e1", amount: 1.00, subject: "x") }
  let(:payment) do
    create(:payment, payment_order: order, provider: "alipay", flow: "qr",
           out_trade_no: "ot-1", amount: 1.00)
  end
  let(:gateway) { described_class.new(account: account) }

  before do
    Current.customer = customer
    allow_any_instance_of(described_class).to receive(:notify_url)
      .and_return("https://example.com/payments/webhooks/alipay")
  end

  it_behaves_like "a registered payment gateway", key: "alipay"

  describe "registry hooks" do
    it "declares vendor-specific credential fields" do
      names = described_class.credential_fields.map { |f| f[:name] }
      expect(names).to contain_exactly(:private_key_pem, :platform_public_key_pem)
    end

    it "exposes a JSAPI UA pattern matching the Alipay in-app browser" do
      expect("AlipayClient/9.9").to match(described_class.jsapi_user_agent_pattern)
    end

    it "extracts the merchant_id from a webhook body's app_id" do
      body = URI.encode_www_form(app_id: "2088app", trade_status: "TRADE_SUCCESS")
      expect(described_class.extract_merchant_id({}, body)).to eq("2088app")
    end
  end

  it "charges via alipay.trade.precreate for QR flow" do
    stub_request(:post, described_class::GATEWAY)
      .to_return(status: 200,
                 body: File.read("spec/fixtures/payments/alipay/qr_precreate.json"),
                 headers: { "Content-Type" => "application/json" })
    res = gateway.charge(order: order, payment: payment, flow: :qr)
    expect(res[:prepay_payload][:qr_code]).to start_with("https://qr.alipay.com/")
  end

  it "signs with RSA2 — sign param present" do
    captured = nil
    stub_request(:post, described_class::GATEWAY)
      .with { |req| captured = req; true }
      .to_return(status: 200, body: "{}")
    gateway.charge(order: order, payment: payment, flow: :qr) rescue nil
    expect(captured.body).to include("sign=")
    expect(captured.body).to include("sign_type=RSA2")
    expect(captured.body).to include("app_id=2088app")
    expect(captured.body).to include("method=alipay.trade.precreate")
  end

  it "raises ApiError when code != 10000" do
    stub_request(:post, described_class::GATEWAY)
      .to_return(status: 200,
                 body: '{"alipay_trade_precreate_response":{"code":"40004","msg":"Biz Error"}}',
                 headers: { "Content-Type" => "application/json" })
    expect {
      gateway.charge(order: order, payment: payment, flow: :qr)
    }.to raise_error(Payments::Errors::ApiError, /Biz Error/)
  end

  it "maps query trade_status TRADE_SUCCESS to :succeeded" do
    stub_request(:post, described_class::GATEWAY)
      .to_return(status: 200,
                  body: '{"alipay_trade_query_response":{"code":"10000","trade_status":"TRADE_SUCCESS","trade_no":"T99"}}',
                 headers: { "Content-Type" => "application/json" })
    res = gateway.query(payment: payment)
    expect(res[:status]).to eq(:succeeded)
    expect(res[:psp_transaction_id]).to eq("T99")
  end

  it "verifies a correctly-signed notification" do
    key = OpenSSL::PKey::RSA.new(priv)
    params = { "out_trade_no" => "ot-1", "trade_status" => "TRADE_SUCCESS", "app_id" => "2088app" }
    to_sign = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
    sig = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, to_sign))
    body = URI.encode_www_form(params.merge("sign" => sig, "sign_type" => "RSA2"))
    result = gateway.verify_notification(headers: {}, body: body)
    expect(result["out_trade_no"]).to eq("ot-1")
    expect(result["trade_status"]).to eq("TRADE_SUCCESS")
  end

  it "raises SignatureInvalid on bad notification signature" do
    body = URI.encode_www_form(out_trade_no: "ot-1", sign: Base64.strict_encode64("bad"), sign_type: "RSA2")
    expect {
      gateway.verify_notification(headers: {}, body: body)
    }.to raise_error(Payments::Errors::SignatureInvalid)
  end

  def signed_notification(params)
    key = OpenSSL::PKey::RSA.new(priv)
    to_sign = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
    sig = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, to_sign))
    URI.encode_www_form(params.merge("sign" => sig, "sign_type" => "RSA2"))
  end

  it "accepts a signed notification with a fresh notify_time" do
    fresh = Time.now.in_time_zone("Asia/Shanghai").strftime("%Y-%m-%d %H:%M:%S")
    body  = signed_notification("out_trade_no" => "ot-1", "trade_status" => "TRADE_SUCCESS",
                                "notify_time" => fresh)
    expect(gateway.verify_notification(headers: {}, body: body)["out_trade_no"]).to eq("ot-1")
  end

  it "accepts a redelivery notification a couple hours old (within Alipay's 10m/1h/2h/6h/15h redelivery schedule)" do
    couple_hours_old = 2.hours.ago.in_time_zone("Asia/Shanghai").strftime("%Y-%m-%d %H:%M:%S")
    body = signed_notification("out_trade_no" => "ot-1", "trade_status" => "TRADE_SUCCESS",
                               "notify_time" => couple_hours_old)
    expect(gateway.verify_notification(headers: {}, body: body)["out_trade_no"]).to eq("ot-1")
  end

  it "rejects a validly-signed but stale notification well beyond Alipay's redelivery schedule (replay window)" do
    stale = 3.days.ago.in_time_zone("Asia/Shanghai").strftime("%Y-%m-%d %H:%M:%S")
    body  = signed_notification("out_trade_no" => "ot-1", "trade_status" => "TRADE_SUCCESS",
                                "notify_time" => stale)
    expect {
      gateway.verify_notification(headers: {}, body: body)
    }.to raise_error(Payments::Errors::SignatureInvalid, /out of window/)
  end

  describe "charge — flow branches" do
    # alipay.trade.wap.pay is a page API: the H5 URL is built and signed
    # locally and opened by the user's browser — no server-side call is made
    # (an unstubbed request here would make webmock fail the test).
    it "builds a fully-signed alipay.trade.wap.pay page URL for H5 flow" do
      res = gateway.charge(order: order, payment: payment, flow: :h5)
      url = res[:prepay_payload][:h5_url]
      expect(url).to start_with("#{described_class::GATEWAY}?")

      params = CGI.parse(URI.parse(url).query).transform_values(&:first)
      expect(params["method"]).to eq("alipay.trade.wap.pay")
      expect(params["app_id"]).to eq("2088app")
      expect(params["sign_type"]).to eq("RSA2")
      expect(params["notify_url"]).to eq("https://example.com/payments/webhooks/alipay")
      expect(params["return_url"]).to include("/#{customer.id}/payments/result/ot-1")

      biz = JSON.parse(params["biz_content"])
      expect(biz["out_trade_no"]).to eq("ot-1")
      expect(biz["total_amount"]).to eq("1.00")
      expect(biz["subject"]).to eq("x")
      expect(biz["product_code"]).to eq("QUICK_WAP_WAY")

      # The RSA2 signature over the sorted params must verify with the keypair.
      sign = params.delete("sign")
      to_sign = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
      public_key = OpenSSL::PKey::RSA.new(pub)
      expect(public_key.verify(OpenSSL::Digest::SHA256.new, Base64.decode64(sign.to_s), to_sign)).to be true

      # Timestamp is pinned to Alipay's timezone (Asia/Shanghai).
      stamped = ActiveSupport::TimeZone["Asia/Shanghai"].parse(params["timestamp"])
      expect(stamped).to be_within(2.minutes).of(Time.current)
    end

    it "signs API calls with an Asia/Shanghai timestamp regardless of server TZ" do
      captured = nil
      stub_request(:post, described_class::GATEWAY)
        .with { |req| captured = req; true }
        .to_return(status: 200,
                   body: '{"alipay_trade_precreate_response":{"code":"10000","qr_code":"qr://x"}}',
                   headers: { "Content-Type" => "application/json" })
      gateway.charge(order: order, payment: payment, flow: :qr)
      params = CGI.parse(captured.body).transform_values(&:first)
      stamped = ActiveSupport::TimeZone["Asia/Shanghai"].parse(params["timestamp"])
      expect(stamped).to be_within(2.minutes).of(Time.current)
    end

    it "charges via alipay.trade.create for JSAPI flow and returns trade_no" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_trade_create_response":{"code":"10000","msg":"Success","trade_no":"T-JSAPI-1"}}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.charge(order: order, payment: payment, flow: :jsapi, openid: "user_openid")
      expect(res[:prepay_payload]).to have_key(:trade_no)
      expect(res[:prepay_payload][:trade_no]).to eq("T-JSAPI-1")
    end

    it "omits buyer_id for JSAPI when openid is absent" do
      captured = nil
      stub_request(:post, described_class::GATEWAY)
        .with { |req| captured = req; true }
        .to_return(status: 200,
                   body: '{"alipay_trade_create_response":{"code":"10000","msg":"Success","trade_no":"T-1"}}',
                   headers: { "Content-Type" => "application/json" })
      gateway.charge(order: order, payment: payment, flow: :jsapi)
      expect(captured.body).not_to include("buyer_id")
    end

    it "raises ArgumentError for an unsupported flow" do
      expect {
        gateway.charge(order: order, payment: payment, flow: :bogus)
      }.to raise_error(ArgumentError, /unsupported Alipay flow/)
    end
  end

  describe "refund" do
    it "returns psp_refund_id and succeeded status on success" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: File.read("spec/fixtures/payments/alipay/refund_success.json"),
                   headers: { "Content-Type" => "application/json" })
      refund = double("refund",
                      out_refund_no: "rf-1",
                      amount: 0.50,
                      reason: "test refund")
      res = gateway.refund(payment: payment, refund: refund)
      expect(res[:status]).to eq(:succeeded)
      expect(res[:psp_refund_id]).to eq("2026042722001")
    end

    it "raises ApiError when refund response code != 10000" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_trade_refund_response":{"code":"40004","msg":"Refund Failed"}}',
                   headers: { "Content-Type" => "application/json" })
      refund = double("refund", out_refund_no: "rf-err", amount: 0.50, reason: "test")
      expect {
        gateway.refund(payment: payment, refund: refund)
      }.to raise_error(Payments::Errors::ApiError, /Refund Failed/)
    end
  end

  describe "close" do
    it "calls alipay.trade.close and returns status :closed" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_trade_close_response":{"code":"10000","msg":"Success"}}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.close(payment: payment)
      expect(res[:status]).to eq(:closed)
    end
  end

  describe "subscribe" do
    it "calls alipay.user.agreement.page.sign and returns sign_url_or_params" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_user_agreement_page_sign_response":{"code":"10000","sign_str":"sign_param_string"}}',
                   headers: { "Content-Type" => "application/json" })
      subscription = double("subscription",
                            external_ref: "sub-ref-1",
                            cycle: "month",
                            amount: 9.99)
      res = gateway.subscribe(subscription: subscription)
      expect(res[:sign_url_or_params]).to eq("sign_param_string")
    end
  end

  describe "cancel_subscription" do
    it "calls alipay.user.agreement.unsign and returns status :cancelled" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_user_agreement_unsign_response":{"code":"10000","msg":"Success"}}',
                   headers: { "Content-Type" => "application/json" })
      subscription = double("subscription", psp_agreement_id: "agree-123", billing_owned?: false)
      res = gateway.cancel_subscription(subscription: subscription)
      expect(res[:status]).to eq(:cancelled)
    end
  end

  describe "charge_subscription" do
    it "returns psp_transaction_id on success and charges payment.amount" do
      captured = nil
      stub_request(:post, described_class::GATEWAY)
        .with { |req| captured = req; true }
        .to_return(status: 200,
                   body: '{"alipay_trade_pay_response":{"code":"10000","msg":"Success","trade_no":"T-SUB-1"}}',
                   headers: { "Content-Type" => "application/json" })
      subscription = double("subscription",
                             billing_owned?: false,
                             amount: 9.99,
                            plan_name: "Premium Monthly",
                            psp_agreement_id: "agree-123")
      res = gateway.charge_subscription(subscription: subscription, payment: payment)
      expect(res[:psp_transaction_id]).to eq("T-SUB-1")
      biz = JSON.parse(CGI.parse(captured.body).fetch("biz_content").first)
      expect(biz["total_amount"]).to eq("1.00")
    end

    it "raises ApiError when charge_subscription response code != 10000" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_trade_pay_response":{"code":"40004","msg":"Balance Insufficient"}}',
                   headers: { "Content-Type" => "application/json" })
      subscription = double("subscription",
                             billing_owned?: false,
                             amount: 9.99,
                            plan_name: "Premium",
                            psp_agreement_id: "agree-err")
      expect {
        gateway.charge_subscription(subscription: subscription, payment: payment)
      }.to raise_error(Payments::Errors::ApiError, /Balance Insufficient/)
    end
  end

  describe "download_bill" do
    it "calls bill.downloadurl.query and returns csv content" do
      bill_url = "https://billfiles.alipay.com/bill.csv"
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: %({"alipay_data_dataservice_bill_downloadurl_query_response":{"code":"10000","bill_download_url":"#{bill_url}"}}),
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, bill_url)
        .to_return(status: 200, body: "date,amount\n2026-01-01,100.00\n")
      res = gateway.download_bill(bill_date: Date.new(2026, 1, 1), bill_type: "trade")
      expect(res[:csv]).to include("date,amount")
    end
  end

  describe "map_status branches" do
    before do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200, body: '{}', headers: { "Content-Type" => "application/json" })
    end

    it "maps TRADE_FINISHED to :succeeded" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_trade_query_response":{"code":"10000","trade_status":"TRADE_FINISHED","trade_no":"T-FIN"}}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.query(payment: payment)
      expect(res[:status]).to eq(:succeeded)
    end

    it "maps WAIT_BUYER_PAY to :pending" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_trade_query_response":{"code":"10000","trade_status":"WAIT_BUYER_PAY","trade_no":"T-W"}}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.query(payment: payment)
      expect(res[:status]).to eq(:pending)
    end

    it "maps TRADE_CLOSED to :closed" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_trade_query_response":{"code":"10000","trade_status":"TRADE_CLOSED","trade_no":"T-C"}}',
                   headers: { "Content-Type" => "application/json" })
      res = gateway.query(payment: payment)
      expect(res[:status]).to eq(:closed)
    end

    it "does not turn an unknown trade_status into a definitive failure" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_trade_query_response":{"code":"10000","trade_status":"UNKNOWN_STATE","trade_no":"T-U"}}',
                   headers: { "Content-Type" => "application/json" })
      expect { gateway.query(payment: payment) }.to raise_error(Payments::Errors::TransportError)
    end

    it "does not turn an absent trade_status into a definitive failure" do
      stub_request(:post, described_class::GATEWAY)
        .to_return(status: 200,
                   body: '{"alipay_trade_query_response":{"code":"10000","trade_no":"T-NIL"}}',
                   headers: { "Content-Type" => "application/json" })
      expect { gateway.query(payment: payment) }.to raise_error(Payments::Errors::TransportError)
    end
  end

  describe "HTTP-200 business failures" do
    {
      charge: ["alipay_trade_precreate_response", ->(gw, payment, order) { gw.charge(order: order, payment: payment, flow: :qr) }],
      query: ["alipay_trade_query_response", ->(gw, payment, _) { gw.query(payment: payment) }],
      close: ["alipay_trade_close_response", ->(gw, payment, _) { gw.close(payment: payment) }],
      cancel: ["alipay_user_agreement_unsign_response", ->(gw, _, subscription) { gw.cancel_subscription(subscription: subscription) }]
    }.each do |operation, (root, invoke)|
      it "rejects #{operation} business errors instead of reporting local success/failure" do
        payload = { root => { "code" => "40004", "msg" => "Business Failed", "sub_code" => "ACQ.INVALID_PARAMETER" } }
        stub_request(:post, described_class::GATEWAY).to_return(status: 200, body: payload.to_json)

        argument = operation == :cancel ? double(psp_agreement_id: "agree-1", billing_owned?: false) : order
        expect { invoke.call(gateway, payment, argument) }.to raise_error(Payments::Errors::ApiError) do |error|
          expect(error.code).to eq("40004")
          expect(error.payload).to eq(payload[root])
          expect(error).to be_definitive
        end
      end

      it "keeps #{operation} uncertain when Alipay reports Service Currently Unavailable" do
        stub_request(:post, described_class::GATEWAY).to_return(
          status: 200, body: { root => { code: "20000", msg: "Service Currently Unavailable" } }.to_json
        )
        argument = operation == :cancel ? double(psp_agreement_id: "agree-1", billing_owned?: false) : order
        expect { invoke.call(gateway, payment, argument) }.to raise_error(Payments::Errors::TransportError)
      end
    end

    it "does not classify a processing agreement charge as declined or captured" do
      stub_request(:post, described_class::GATEWAY).to_return(
        status: 200, body: { alipay_trade_pay_response: { code: "10003", msg: "Order Processing" } }.to_json
      )
      subscription = double(plan_name: "Monthly", psp_agreement_id: "agree-1", billing_owned?: false)
      expect { gateway.charge_subscription(subscription: subscription, payment: payment) }
        .to raise_error(Payments::Errors::TransportError)
    end

    it "handles the common error_response root" do
      stub_request(:post, described_class::GATEWAY).to_return(
        status: 200, body: { error_response: { code: "40002", msg: "Invalid Arguments" } }.to_json
      )
      expect { gateway.close(payment: payment) }.to raise_error(Payments::Errors::ApiError)
    end

    it "does not infer non-execution from an unrecognized Alipay business failure" do
      stub_request(:post, described_class::GATEWAY).to_return(status: 200, body: {
        alipay_trade_precreate_response: { code: "40004", msg: "Business Failed", sub_code: "ACQ.UNKNOWN_OUTCOME" }
      }.to_json)
      expect { gateway.charge(order: order, payment: payment, flow: :qr) }
        .to raise_error(Payments::Errors::ApiError) { |error| expect(error).to be_uncertain }
    end

    ["{}", '{"alipay_trade_close_response":[]}', '{"alipay_trade_close_response":{}}', "null", "[]"].each do |body|
      it "keeps a malformed business reply uncertain: #{body}" do
        stub_request(:post, described_class::GATEWAY).to_return(status: 200, body: body)
        expect { gateway.close(payment: payment) }.to raise_error(Payments::Errors::TransportError)
      end
    end

    it "does not try to download a nil bill URL after a business failure" do
      stub_request(:post, described_class::GATEWAY).to_return(
        status: 200, body: { alipay_data_dataservice_bill_downloadurl_query_response: { code: "40004", msg: "Bill unavailable" } }.to_json
      )
      expect { gateway.download_bill(bill_date: Date.current, bill_type: "all") }
        .to raise_error(Payments::Errors::ApiError)
      expect(a_request(:get, /.*/)).not_to have_been_made
    end
  end

  describe "normalized query assertions" do
    it "returns major units, currency and Beijing-local settlement time" do
      stub_request(:post, described_class::GATEWAY).to_return(status: 200, body: {
        alipay_trade_query_response: { code: "10000", trade_status: "TRADE_SUCCESS", trade_no: "T1",
                                      total_amount: "1.00", send_pay_date: "2026-10-10 23:30:00" }
      }.to_json)
      result = gateway.query(payment: payment)
      expect(result).to include(amount: BigDecimal("1.00"), currency: "CNY", settled_at: Time.utc(2026, 10, 10, 15, 30))
    end
  end

  describe "invalid key configuration" do
    it "maps malformed signing PEM to CredentialsMissing before making a PSP request" do
      account.write_credentials(private_key_pem: "not a PEM")
      expect { gateway.charge(order: order, payment: payment, flow: :qr) }
        .to raise_error(Payments::Errors::CredentialsMissing)
      expect(a_request(:post, described_class::GATEWAY)).not_to have_been_made
    end

    it "rejects a public-only signing key with a controlled configuration error" do
      account.write_credentials(private_key_pem: pub)
      expect { gateway.charge(order: order, payment: payment, flow: :h5) }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end

    it "maps malformed platform PEM without exposing its content" do
      account.write_credentials(platform_public_key_pem: "private-secret-invalid")
      expect { gateway.verify_notification(headers: {}, body: "sign=x") }
        .to raise_error(Payments::Errors::CredentialsMissing) { |error| expect(error.message).not_to include("private-secret-invalid") }
    end
  end
end
