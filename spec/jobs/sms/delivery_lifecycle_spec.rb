# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::DeliverMessageJob, type: :job do
  let(:customer) { create(:customer) }
  let!(:credential) { create(:sms_credential) }
  let!(:template) { create(:sms_template) }

  before do
    enable_module!("sms", customer, name: "SMS")
    allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).and_return(vendor_message_id: "accepted-id", raw: {})
  end

  def admit(**options)
    Sms::Activities::Send.call(**{ customer: customer, to: "+8613800138000", template_key: template.key,
                                  vars: { "code" => "1234", "minutes" => "5" } }.merge(options))
  end

  it "persists the attempted marker before calling the vendor and accepts only once across duplicate workers" do
    message = admit
    calls = []
    allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message) do
      ledger = message.reload
      expect(ledger.dispatch_started_at).to be_present
      expect(ledger.delivery_attempts).to eq(1)
      calls << ledger.id
      described_class.new.perform(message.id)
      # Even a lease expiring during a slow external call grants no resend.
      ledger.update_columns(delivery_claimed_at: 1.hour.ago)
      described_class.new.perform(message.id)
      { vendor_message_id: "accepted-id", raw: {} }
    end

    described_class.new.perform(message.id)
    described_class.new.perform(message.id)
    expect(calls).to eq([message.id])
    expect(message.reload.status).to eq("sent")
    expect(message.delivered_at).to be_nil
    expect(message.delivery_attempts).to eq(1)
  end

  it "fences expired preparation owners and permits recovery before the attempted marker" do
    message = admit
    stale, token = Sms::DeliveryDispatch.claim(message.id)
    expect(Sms::DeliveryDispatch.claim(message.id)).to be_nil
    stale.update_columns(delivery_claimed_at: 1.hour.ago)
    _current, current_token = Sms::DeliveryDispatch.claim(message.id)
    expect(Sms::DeliveryDispatch.start(stale, token)).to be(false)
    stale.mark_failed!(code: "old", message: "old", raw: {}, claim_token: token)
    Sms::DeliveryDispatch.release(stale, token)
    expect(message.reload.delivery_claim_token).to eq(current_token)
    Sms::DeliveryDispatch.release(message, current_token)

    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("sent")
    expect(message.delivery_attempts).to eq(1)
  end

  it "recovers a safe preparation crash without charging another attempt" do
    message = admit
    allow(Sms::DeliveryCredential).to receive(:for_message).and_raise(Sms::Errors::CredentialsMissing)
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)

    expect { described_class.new.perform(message.id) }.not_to raise_error
    expect(message.reload.status).to eq("queued")
    expect(message.dispatch_started_at).to be_nil
    expect(message.delivery_claim_token).to be_nil
    expect(message.delivery_attempts).to eq(0)
    expect(Sms::DeliveryHandoff).to receive(:call).with(have_attributes(id: message.id), now: kind_of(ActiveSupport::TimeWithZone))
    Sms::RecoverMessagesJob.new.perform
  end

  it "quarantines a crashed attempt as unknown and never queues or calls another vendor send" do
    message = admit
    claimed, token = Sms::DeliveryDispatch.claim(message.id)
    expect(Sms::DeliveryDispatch.start(claimed, token)).to be(true)
    message.update_columns(delivery_claimed_at: 1.hour.ago)
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)

    expect { Sms::Cron::RecoverMessages.call }.not_to have_enqueued_job(described_class)
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("unknown")
    expect(message.delivery_attempts).to eq(1)
    expect(message.dispatch_started_at).to be_present
  end

  it "never labels a still-live attempted claim expired or suppressed" do
    message = admit(expires_at: 1.minute.from_now)
    claimed, token = Sms::DeliveryDispatch.claim(message.id)
    Sms::DeliveryDispatch.start(claimed, token)
    Sms::OptOut.record_for_customer!(customer_id: customer.id, phone_e164: message.to)
    message.update_columns(expires_at: 1.minute.ago)

    Sms::Cron::RecoverMessages.call
    expect(message.reload.status).to eq("queued")
    message.update_columns(delivery_claimed_at: 1.hour.ago)
    Sms::Cron::RecoverMessages.call
    expect(message.reload.status).to eq("unknown")
  end

  it "accepts a genuinely late response after recovery without allowing another attempt" do
    message = admit
    calls = 0
    allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message) do
      calls += 1
      message.update_columns(delivery_claimed_at: 1.hour.ago)
      Sms::Cron::RecoverMessages.call
      expect(message.reload.status).to eq("unknown")
      described_class.new.perform(message.id)
      { vendor_message_id: "late-id", raw: {} }
    end
    described_class.new.perform(message.id)
    expect(calls).to eq(1)
    expect(message.reload.status).to eq("sent")
    expect(message.vendor_message_id).to eq("late-id")
  end

  it "retains a recovered live attempt through early interim receipts and poll ingress until the late ID is stored" do
    message = admit
    receipt = nil
    calls = 0
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:query)
    allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message) do
      calls += 1
      receipt = Sms::ReceiptInbox.record!(credential: credential, event: {
        type: :delivery, vendor_message_id: "late-interim-id", status: :unknown, provider_status: "sending", raw: {}
      })
      message.update_columns(delivery_claimed_at: 1.hour.ago)
      Sms::Cron::RecoverMessages.call
      token = message.reload.delivery_claim_token
      expect(token).to be_present
      expect(message.status).to eq("unknown")
      expect(receipt.reload.processed_at).to be_nil
      Sms::Gateway.query(message: message.reload)
      Sms::ReceiptInbox.reconcile
      expect(message.reload.delivery_claim_token).to eq(token)
      Sms::DeliverMessageJob.new.perform(message.id)
      { vendor_message_id: "late-interim-id", raw: {} }
    end

    described_class.new.perform(message.id)
    expect(message.reload.vendor_message_id).to eq("late-interim-id")
    expect(message.sent_at).to be_present
    expect(receipt.reload.processed_at).to be_present
    expect(message.metadata["provider_status"]).to eq("sending")
    expect(message.status).to eq("unknown")
    Sms::ReceiptInbox.record!(credential: credential, event: {
      type: :delivery, vendor_message_id: "late-interim-id", status: :delivered, raw: {}
    })
    expect(message.reload.status).to eq("delivered")
    expect(message.delivery_attempts).to eq(1)
    expect(calls).to eq(1)
  end

  it "expires preparation atomically if expiry crosses between preparation and the final start gate" do
    message = admit(expires_at: 1.minute.from_now)
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
    allow(Sms::DispatchLimiter).to receive(:acquire).and_wrap_original do |method, **args|
      travel_to(message.expires_at + 1.second) { method.call(**args.merge(at: Time.current)) }
    end
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("expired")
    expect(message.delivery_claim_token).to be_nil
    expect(message.dispatch_started_at).to be_nil
    expect(message.delivery_attempts).to eq(0)
    travel_to(message.expires_at + 1.second) { Sms::Cron::RecoverMessages.call }
    expect(message.reload.status).to eq("expired")
  end

  it "leaves a process crash's attempted marker intact for recovery" do
    message = admit
    crash = Class.new(Exception)
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_raise(crash)
    expect { described_class.new.perform(message.id) }.to raise_error(crash)
    expect(message.reload.dispatch_started_at).to be_present
    message.update_columns(delivery_claimed_at: 1.hour.ago)
    Sms::Cron::RecoverMessages.call
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("unknown")
    expect(message.delivery_attempts).to eq(1)
  end

  it "records an ambiguous timeout without raising or blind retrying" do
    message = admit
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_raise(Sms::Errors::TransportError, "timeout")

    expect { described_class.new.perform(message.id) }.not_to raise_error
    described_class.new.perform(message.id)
    expect { Sms::Cron::RecoverMessages.call(now: 1.hour.from_now) }.not_to have_enqueued_job(described_class)
    expect(message.reload.status).to eq("unknown")
    expect(message.delivery_attempts).to eq(1)
  end

  it "retries a transient acceptance write without repeating the vendor call or losing its result" do
    message = admit
    raw = { "Code" => "OK", "BizId" => "known-id" }
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_return(vendor_message_id: "known-id", raw: raw)
    writes = 0
    allow_any_instance_of(Sms::Message).to receive(:mark_sent!).and_wrap_original do |method, **arguments|
      writes += 1
      raise ActiveRecord::StatementInvalid, "transient completion failure" if writes == 1
      method.call(**arguments)
    end

    expect { described_class.new.perform(message.id) }.not_to raise_error
    described_class.new.perform(message.id)
    Sms::Cron::RecoverMessages.call(now: 1.hour.from_now)
    expect(writes).to eq(2)
    expect(message.reload.status).to eq("sent")
    expect(message.vendor_message_id).to eq("known-id")
    expect(message.raw_response).to eq(raw)
    expect(message.delivery_attempts).to eq(1)
    expect(message.dispatch_started_at).to be_present
  end

  it "bounds failed acceptance writes, preserves result facts in quarantine and reconciles an early delivery" do
    message = admit
    raw = { "Code" => "OK", "BizId" => "known-id" }
    receipt = Sms::ReceiptInbox.record!(credential: credential,
                                       event: { type: :delivery, status: :delivered, vendor_message_id: "known-id", raw: { "dlr" => true } })
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_return(vendor_message_id: "known-id", raw: raw)
    sent_writes = 0
    unknown_writes = 0
    allow_any_instance_of(Sms::Message).to receive(:mark_sent!) do
      sent_writes += 1
      raise ActiveRecord::StatementInvalid, "acceptance write unavailable"
    end
    allow_any_instance_of(Sms::Message).to receive(:mark_unknown!).and_wrap_original do |method, **arguments|
      unknown_writes += 1
      raise ActiveRecord::StatementInvalid, "transient quarantine failure" if unknown_writes == 1
      method.call(**arguments)
    end
    allow(Sms::ReceiptInbox).to receive(:reconcile).and_wrap_original do |method, **arguments|
      recorded = Sms::Message.find(message.id)
      expect(recorded.status).to eq("unknown")
      expect(recorded.vendor_message_id).to eq("known-id")
      expect(recorded.raw_response).to eq(raw)
      method.call(**arguments)
    end

    expect { described_class.new.perform(message.id) }.not_to raise_error
    described_class.new.perform(message.id)
    expect(sent_writes).to eq(described_class::LEDGER_COMPLETION_ATTEMPTS)
    expect(unknown_writes).to eq(2)
    expect(message.reload.status).to eq("delivered")
    expect(message.vendor_message_id).to eq("known-id")
    expect(receipt.reload.processed_at).to be_present
    expect(message.delivery_attempts).to eq(1)
  end

  [ActiveRecord::StatementInvalid, IOError].each do |error_class|
    it "correlates an already-accepted database row after reload raises #{error_class}" do
      message = admit
      raw = { "Code" => "OK", "BizId" => "known-id" }
      receipt = Sms::ReceiptInbox.record!(credential: credential,
                                         event: { type: :delivery, status: :delivered, vendor_message_id: "known-id", raw: { "dlr" => true } })
      expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_return(vendor_message_id: "known-id", raw: raw)
      failed_reload = false
      allow_any_instance_of(Sms::Message).to receive(:reload).and_wrap_original do |method, *arguments|
        recorded = Sms::Message.find_by(id: message.id)
        if !failed_reload && recorded.vendor_message_id == "known-id" && recorded.sent_at
          expect(recorded.delivery_claim_token).to be_nil
          failed_reload = true
          raise error_class, "reload after successful completion"
        end
        method.call(*arguments)
      end

      expect { described_class.new.perform(message.id) }.not_to raise_error
      described_class.new.perform(message.id)
      expect(failed_reload).to be(true)
      expect(message.reload.status).to eq("delivered")
      expect(message.vendor_message_id).to eq("known-id")
      expect(message.sent_at).to be_present
      expect(message.raw_response).to eq("dlr" => true)
      expect(receipt.reload.processed_at).to be_present
      expect(message.delivery_attempts).to eq(1)
    end
  end

  it "preserves a transport error's known ID/raw, correlates early receipts and never logs response secrets" do
    message = admit
    raw = { "sid" => "SM_KNOWN", "status" => "malformed", "audit" => "private-provider-response" }
    receipt = Sms::ReceiptInbox.record!(credential: credential,
                                       event: { type: :delivery, status: :delivered, vendor_message_id: "SM_KNOWN", raw: {} })
    error = Sms::Errors::TransportError.new("private-exception-message", vendor_message_id: "SM_KNOWN", payload: raw)
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_raise(error)
    expect(Rails.logger).not_to receive(:warn).with(a_string_matching(/private-provider-response|private-exception-message/))
    allow(Sms::ReceiptInbox).to receive(:reconcile).and_wrap_original do |method, **arguments|
      recorded = Sms::Message.find(message.id)
      expect(recorded.vendor_message_id).to eq("SM_KNOWN")
      expect(recorded.raw_response).to eq(raw)
      expect(recorded.status).to eq("unknown")
      method.call(**arguments)
    end

    expect { described_class.new.perform(message.id) }.not_to raise_error
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("delivered")
    expect(message.vendor_message_id).to eq("SM_KNOWN")
    expect(receipt.reload.processed_at).to be_present
    expect(message.delivery_attempts).to eq(1)
  end

  it "does not regress interim receipt facts when a successful acceptance update's reload fails" do
    message = admit
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_return(vendor_message_id: "known-id", raw: { "accepted" => true })
    failed_reload = false
    allow_any_instance_of(Sms::Message).to receive(:reload).and_wrap_original do |method, *arguments|
      recorded = Sms::Message.find_by(id: message.id)
      if !failed_reload && recorded.vendor_message_id == "known-id" && recorded.sent_at
        failed_reload = true
        Sms::DeliveryProjection.apply!(message: recorded, event: { status: :unknown, raw: { "interim" => true } })
        raise ActiveRecord::StatementInvalid, "reload after interim receipt"
      end
      method.call(*arguments)
    end

    expect { described_class.new.perform(message.id) }.not_to raise_error
    expect(message.reload.status).to eq("unknown")
    expect(message.vendor_message_id).to eq("known-id")
    expect(message.sent_at).to be_present
    expect(message.raw_response).to eq("interim" => true)
    expect(message.delivery_attempts).to eq(1)
  end

  it "quarantines a malformed result with a usable ID and nil raw without losing receipt correlation" do
    message = admit
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_return(vendor_message_id: "known-id", raw: nil)
    described_class.new.perform(message.id)
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("unknown")
    expect(message.vendor_message_id).to eq("known-id")
    expect(message.raw_response).to eq({})
    Sms::ReceiptInbox.record!(credential: credential, event: { type: :delivery, status: :delivered, vendor_message_id: "known-id" })
    expect(message.reload.status).to eq("delivered")
    expect(message.delivery_attempts).to eq(1)
  end

  it "keeps a malformed success code's raw facts when its vendor ID is missing" do
    message = admit
    raw = { "Code" => "OK", "BizId" => nil }
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_return(vendor_message_id: nil, raw: raw)
    described_class.new.perform(message.id)
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("unknown")
    expect(message.raw_response).to eq(raw)
    expect(message.vendor_message_id).to be_nil
    expect(message.delivery_attempts).to eq(1)
  end

  it "finishes the sole attempted payload after an interim projection clears a recovered token" do
    message = admit
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once do
      message.update_columns(delivery_claimed_at: 1.hour.ago)
      Sms::Cron::RecoverMessages.call
      expect(message.reload.delivery_claim_token).to be_present
      Sms::DeliveryProjection.apply!(message: message, event: { status: :unknown, raw: { "interim" => true } })
      expect(message.delivery_claim_token).to be_nil
      { vendor_message_id: "late-id", raw: { "accepted" => true } }
    end
    described_class.new.perform(message.id)
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("sent")
    expect(message.vendor_message_id).to eq("late-id")
    expect(message.sent_at).to be_present
    expect(message.delivery_attempts).to eq(1)
  end

  it "treats malformed success, unclassified API errors and server errors as unknown" do
    [nil, {}, { vendor_message_id: "", raw: {} }, { vendor_message_id: "id", raw: nil },
     Sms::Errors::ApiError.new("bad response"), Sms::Errors::ApiError.new("server error", code: 500)].each_with_index do |response, i|
      message = admit(to: "+86138001380#{i.to_s.rjust(2, '0')}")
      credential.reload
      travel_to(credential.dispatch_next_at, with_usec: true) if credential.dispatch_next_at && credential.dispatch_next_at > Time.current
      if response.is_a?(Exception)
        allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).and_raise(response)
      else
        allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).and_return(response)
      end
      expect { described_class.new.perform(message.id) }.not_to raise_error
      expect(message.reload.status).to eq("unknown")
      expect(message.delivery_attempts).to eq(1)
    end
  end

  it "records proven rejection as failed, releases daily quota and still never retries the attempted payload" do
    allow(Sms::Activities::Send).to receive(:daily_cap_for).and_return(1)
    message = admit
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).once.and_raise(
      Sms::Errors::ApiError.new("rejected", code: "isv.BUSINESS_LIMIT_CONTROL", payload: { "Code" => "isv.BUSINESS_LIMIT_CONTROL" })
    )
    described_class.new.perform(message.id)
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("failed")
    expect(message.failure_code).to eq("isv.BUSINESS_LIMIT_CONTROL")
    expect(admit(to: "+8613800138001").status).to eq("queued")
  end

  it "expires old queued messages before calling the vendor, including recovery" do
    message = admit(expires_at: 1.second.ago)
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("expired")
    expect(message.dispatch_started_at).to be_nil
    expect(message.delivery_attempts).to eq(0)
    other = admit(to: "+8613800138001", expires_at: 1.second.ago)
    Sms::Cron::RecoverMessages.call
    expect(other.reload.status).to eq("expired")
  end

  it "suppresses new opt-outs and a disabled module after admission" do
    message = admit
    Sms::OptOut.record_for_customer!(customer_id: customer.id, phone_e164: message.to)
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("suppressed")
    other = admit(to: "+8613800138001")
    FeatureModules::CustomerAssignment.where(customer_id: customer.id).update_all(status: 1)
    described_class.new.perform(other.id)
    expect(other.reload.status).to eq("suppressed")
    expect(other.dispatch_started_at).to be_nil
  end

  it "rechecks opt-out/module/expiry after preparation immediately before the external call" do
    [:opt_out, :module_disable, :expiry].each_with_index do |blocker, i|
      enable_module!("sms", customer, name: "SMS")
      message = admit(to: "+86138001381#{i.to_s.rjust(2, '0')}")
      allow(Sms::DeliveryDispatch).to receive(:template_for).and_wrap_original do |method, record|
        case blocker
        when :opt_out then Sms::OptOut.record_for_customer!(customer_id: customer.id, phone_e164: message.to)
        when :module_disable then FeatureModules::CustomerAssignment.where(customer_id: customer.id).update_all(status: 1)
        when :expiry then travel_to(2.hours.from_now)
        end
        method.call(record)
      end
      expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
      described_class.new.perform(message.id)
      expect(message.reload.status).to eq(blocker == :expiry ? "expired" : "suppressed")
      expect(message.dispatch_started_at).to be_nil
      travel_back
    end
  end

  it "ignores another customer's opt-out and pins template content, provider and mode through changes" do
    message = admit
    Sms::OptOut.record_for_customer!(customer_id: create(:customer).id, phone_e164: message.to)
    template.update!(status: "retired", variables: ["changed"], provider_template_codes: { "twilio" => "HX_NEW" })
    credential.update!(status: "disabled")
    create(:sms_credential, provider: "twilio", config: { from: "+15551234567" })
    message.update_columns(vars: { "changed" => "not the admitted payload" })
    expect(Sms::CredentialResolver).not_to receive(:call)
    expect(Sms::DeliveryCredential.for_message(message, mode: "production")).to eq(credential)
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message) do |_adapter, to:, template:, template_params:|
      expect(to).to eq(message.to)
      expect(template.provider_code("aliyun")).to eq("SMS_12345678")
      expect(template.required_vars).to eq(%w[code minutes])
      expect(template_params).to eq("code" => "1234", "minutes" => "5")
      { vendor_message_id: "accepted-id", raw: {} }
    end

    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("sent")
    expect(message.provider).to eq("aliyun")
  end

  it "keeps a message queued if its recorded credential is no longer configured instead of switching accounts" do
    message = admit
    credential.update_columns(access_key_id: "")
    create(:sms_credential, provider: "twilio", config: { from: "+15551234567" })
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
    expect_any_instance_of(Sms::Adapters::Twilio).not_to receive(:send_message)
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("queued")
    expect(message.delivery_attempts).to eq(0)
  end

  it "reconciles retained early receipts immediately after storing the accepted vendor ID" do
    message = admit
    receipt = Sms::ReceiptInbox.record!(credential: credential,
                                       event: { type: :delivery, status: :delivered, vendor_message_id: "accepted-id", raw: {} })
    expect(receipt.processed_at).to be_nil
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("delivered")
    expect(message.vendor_message_id).to eq("accepted-id")
    expect(receipt.reload.processed_at).to be_present
    expect(receipt.customer_id).to eq(customer.id)
  end

  it "creates global opt-out after a confirmed Twilio 21610 send rejection" do
    credential.update!(status: "disabled")
    create(:sms_credential, provider: "twilio", config: { from: "+15551234567" })
    template.update!(provider_template_codes: { twilio: "HX_PINNED" })
    message = admit(provider: "twilio")
    allow_any_instance_of(Sms::Adapters::Twilio).to receive(:send_message).and_raise(Sms::Errors::ApiError.new("STOP", code: 21610))
    described_class.new.perform(message.id)
    expect(message.reload.status).to eq("failed")
    expect(Sms::OptOut.find_by(customer_id: nil, phone_e164: message.to)).to be_present
  end
end
