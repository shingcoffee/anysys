# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS ambiguous provider identity retention" do
  let(:customer) { create(:customer) }
  let(:template) { create(:sms_template, variables: [], provider_template_codes: { twilio: "HX_PINNED", aliyun: "SMS_PINNED" }) }
  let(:credential) do
    create(:sms_credential, provider: "twilio", access_key_id: "AC_TEST", access_key_secret: "AUTH_TOKEN",
           config: { messaging_service_sid: "MG_TEST" })
  end
  let(:phone) { "+14155552671" }
  let(:endpoint) { "https://api.twilio.com/2010-04-01/Accounts/AC_TEST/Messages.json" }

  before { enable_module!("sms", customer, name: "SMS") }

  def admit
    credential
    Sms::Gateway.send(customer: customer, to: phone, template_key: template.key, vars: {}, provider: credential.provider)
  end

  [{ status: [] }, { date_updated: "not-a-date" }, { date_created: "not-a-date" }, { date_sent: [] },
   { error_code: [21610] }, { error_code: "not-a-number" }].each do |malformed|
    context "malformed original SDK response #{malformed.inspect}" do
      def stub_malformed_create(attributes)
        stub_request(:post, endpoint).to_return(status: 201, body: {
          sid: "SM_VALID", status: "queued", to: phone, account_sid: "AC_TEST", body: "PRIVATE_TEXT", auth_token: "SECRET_ECHO"
        }.merge(attributes).to_json)
      end

      it "quarantines as unknown with the SID when no receipt exists and never resends" do
        message = admit
        stub_malformed_create(malformed)
        Sms::DeliverMessageJob.new.perform(message.id)
        expect(message.reload).to have_attributes(status: "unknown", vendor_message_id: "SM_VALID", delivery_attempts: 1,
                                                  sent_at: nil, failure_code: nil, failure_message: nil)
        expect(message.raw_response).to include(malformed.stringify_keys)
        expect(message.raw_response).not_to have_key("body")
        expect(message.raw_response).not_to have_key("auth_token")
        expect(Sms::OptOut.where(phone_e164: phone)).to be_empty
        Sms::DeliverMessageJob.new.perform(message.id)
        expect { Sms::Cron::RecoverMessages.call }.not_to have_enqueued_job(Sms::DeliverMessageJob)
        expect(WebMock).to have_requested(:post, endpoint).once
      end

      it "stores unknown with the SID before consuming an early genuine receipt, without resending" do
        message = admit
        params = { "MessageSid" => "SM_VALID", "MessageStatus" => "delivered", "To" => phone, "AccountSid" => "AC_TEST" }
        event = Sms::Adapters::Twilio.new(credential: credential)
                                    .parse_delivery_receipt(double(request_parameters: params)).first.merge(type: :delivery)
        receipt = Sms::ReceiptInbox.record!(credential: credential, event: event)
        expect(receipt.processed_at).to be_nil
        before_projection = nil
        allow(Sms::ReceiptInbox).to receive(:reconcile).and_wrap_original do |method, **options|
          before_projection = message.reload.attributes.slice("status", "vendor_message_id", "raw_response")
          method.call(**options)
        end
        stub_malformed_create(malformed)

        Sms::DeliverMessageJob.new.perform(message.id)
        expect(before_projection).to include("status" => "unknown", "vendor_message_id" => "SM_VALID")
        expect(before_projection.fetch("raw_response")).to include("sid" => "SM_VALID", **malformed.stringify_keys)
        expect(before_projection.fetch("raw_response")).not_to have_key("body")
        expect(before_projection.fetch("raw_response")).not_to have_key("auth_token")
        expect(message.reload).to have_attributes(status: "delivered", vendor_message_id: "SM_VALID", delivery_attempts: 1, failure_code: nil)
        expect(receipt.reload).to have_attributes(customer_id: customer.id)
        expect(receipt.processed_at).to be_present
        Sms::DeliverMessageJob.new.perform(message.id)
        expect(WebMock).to have_requested(:post, endpoint).once
      end

      it "does not turn a quarantined attempt into false failure when query data is malformed" do
        message = admit
        stub_malformed_create(status: [])
        Sms::DeliverMessageJob.new.perform(message.id)
        query_endpoint = "https://api.twilio.com/2010-04-01/Accounts/AC_TEST/Messages/SM_VALID.json"
        stub_request(:get, query_endpoint).to_return(status: 200, body: {
          sid: "SM_VALID", status: "failed", to: phone, account_sid: "AC_TEST"
        }.merge(malformed).to_json)
        travel 3.minutes do
          Sms::Cron::ReconcileMessages.call
          Sms::DeliverMessageJob.new.perform(message.id)
        end
        expect(message.reload).to have_attributes(status: "unknown", vendor_message_id: "SM_VALID", delivery_attempts: 1,
                                                  failure_code: nil, failure_message: nil)
        expect(Sms::OptOut.where(phone_e164: phone)).to be_empty
        expect(WebMock).to have_requested(:get, query_endpoint).once
        expect(WebMock).to have_requested(:post, endpoint).once
      end
    end
  end

  it "queries a known quarantined SID through the real SDK when the callback was lost" do
    message = admit
    stub_request(:post, endpoint).to_return(status: 201, body: { sid: "SM_VALID", status: [], to: phone }.to_json)
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload).to have_attributes(status: "unknown", vendor_message_id: "SM_VALID", delivery_attempts: 1)
    expect(message.raw_response).to include("sid" => "SM_VALID", "status" => [])
    query_endpoint = "https://api.twilio.com/2010-04-01/Accounts/AC_TEST/Messages/SM_VALID.json"
    stub_request(:get, query_endpoint).to_return(status: 200, body: {
      sid: "SM_VALID", status: "delivered", to: phone, account_sid: "AC_TEST", num_segments: "2"
    }.to_json)

    travel 3.minutes do
      Sms::Cron::ReconcileMessages.call
      Sms::Cron::RecoverMessages.call
    end
    expect(message.reload).to have_attributes(status: "delivered", delivery_attempts: 1, failure_code: nil)
    expect(message.metadata).to include("provider_segments" => 2, "credential_id" => credential.id)
    expect(WebMock).to have_requested(:get, query_endpoint).once
    expect(WebMock).to have_requested(:post, endpoint).once
  end

  context "documented REST exception envelopes" do
    [21610, 21211].each do |code|
      it "records proven HTTP 400/#{code} rejection with correct suppression and one external call" do
        message = admit
        body = { status: 400, code: code, message: "Documented rejection", more_info: "https://www.twilio.com/docs/api/errors/#{code}" }
        stub_request(:post, endpoint).to_return(status: 400, body: body.to_json)
        Sms::DeliverMessageJob.new.perform(message.id)
        expect(message.reload).to have_attributes(status: "failed", failure_code: code.to_s, delivery_attempts: 1)
        if code == 21610
          expect(Sms::OptOut.find_by!(customer_id: nil, phone_e164: phone)).to have_attributes(provider: "twilio", reason: "vendor:21610")
          expect(Sms::OptOut.opted_out?(customer_id: create(:customer).id, phone_e164: phone)).to be(true)
        else
          expect(Sms::OptOut.where(phone_e164: phone)).to be_empty
        end
        expect(message.raw_response).not_to have_key("more_info")
        Sms::DeliverMessageJob.new.perform(message.id)
        expect { Sms::Cron::RecoverMessages.call }.not_to have_enqueued_job(Sms::DeliverMessageJob)
        expect(WebMock).to have_requested(:post, endpoint).once
      end
    end

    [{ code: [21610] }, { code: "not-a-number" }, { error_code: [21610] }, { error_code: "not-a-number" }].each do |malformed|
      it "quarantines malformed rejection #{malformed.inspect}, retaining a safe SID without suppression" do
        message = admit
        stub_request(:post, endpoint).to_return(status: 400, body: {
          status: 400, message: "Unconfirmed", sid: "SM_AMBIGUOUS", auth_token: "SECRET_ECHO"
        }.merge(malformed).to_json)
        Sms::DeliverMessageJob.new.perform(message.id)
        expect(message.reload).to have_attributes(status: "unknown", vendor_message_id: "SM_AMBIGUOUS", failure_code: nil, delivery_attempts: 1)
        expect(Sms::OptOut.where(phone_e164: phone)).to be_empty
        expect(message.raw_response).not_to have_key("auth_token")
        Sms::DeliverMessageJob.new.perform(message.id)
        expect(WebMock).to have_requested(:post, endpoint).once
      end
    end

    it "keeps an unclassified HTTP 400 exception unknown instead of manufacturing a rejection code" do
      message = admit
      stub_request(:post, endpoint).to_return(status: 400, body: { message: "Unclassified error" }.to_json)
      Sms::DeliverMessageJob.new.perform(message.id)
      expect(message.reload).to have_attributes(status: "unknown", failure_code: nil, delivery_attempts: 1)
      expect(Sms::OptOut.where(phone_e164: phone)).to be_empty
      Sms::DeliverMessageJob.new.perform(message.id)
      expect(WebMock).to have_requested(:post, endpoint).once
    end

    it "keeps a legitimate HTTP 500 server exception unknown without opt-out or resend" do
      message = admit
      stub_request(:post, endpoint).to_return(status: 500, body: {
        status: 500, code: 20500, message: "Server error", more_info: "https://www.twilio.com/docs/api/errors/20500"
      }.to_json)
      Sms::DeliverMessageJob.new.perform(message.id)
      expect(message.reload).to have_attributes(status: "unknown", failure_code: nil, delivery_attempts: 1)
      expect(Sms::OptOut.where(phone_e164: phone)).to be_empty
      Sms::DeliverMessageJob.new.perform(message.id)
      expect(WebMock).to have_requested(:post, endpoint).once
    end

    it "still quarantines numeric status on a successful Message resource even with opt-out error_code" do
      message = admit
      stub_request(:post, endpoint).to_return(status: 201, body: {
        sid: "SM_AMBIGUOUS", status: 400, error_code: 21610, error_message: "Not a valid Message status"
      }.to_json)
      Sms::DeliverMessageJob.new.perform(message.id)
      expect(message.reload).to have_attributes(status: "unknown", vendor_message_id: "SM_AMBIGUOUS", failure_code: nil, delivery_attempts: 1)
      expect(Sms::OptOut.where(phone_e164: phone)).to be_empty
      Sms::DeliverMessageJob.new.perform(message.id)
      expect(WebMock).to have_requested(:post, endpoint).once
    end
  end

  context "Aliyun HTTP/JSON mismatch" do
    let(:phone) { "+8613800138000" }
    let(:credential) { create(:sms_credential, provider: "aliyun") }
    let(:endpoint) { "https://dysmsapi.aliyuncs.com/" }

    it "retains the BizId in worker quarantine and consumes an early receipt without another attempt" do
      message = admit
      receipt = Sms::ReceiptInbox.record!(credential: credential, event: {
        type: :delivery, vendor_message_id: "12345^67890", status: :delivered, phone: phone, raw: {}
      })
      before_projection = nil
      allow(Sms::ReceiptInbox).to receive(:reconcile).and_wrap_original do |method, **options|
        before_projection = message.reload.attributes.slice("status", "vendor_message_id", "raw_response")
        method.call(**options)
      end
      stub_request(:post, endpoint).to_return(status: 502, body: {
        Code: "OK", BizId: "12345^67890", RequestId: "request-1", AccessKeySecret: "SECRET_ECHO"
      }.to_json)

      Sms::DeliverMessageJob.new.perform(message.id)
      expect(before_projection).to include("status" => "unknown", "vendor_message_id" => "12345^67890")
      expect(before_projection.fetch("raw_response")).to eq("Code" => "OK", "BizId" => "12345^67890", "RequestId" => "request-1")
      expect(message.reload).to have_attributes(status: "delivered", vendor_message_id: "12345^67890", delivery_attempts: 1, failure_code: nil)
      expect(receipt.reload.processed_at).to be_present
      Sms::DeliverMessageJob.new.perform(message.id)
      expect(WebMock).to have_requested(:post, endpoint).once
    end
  end
end
