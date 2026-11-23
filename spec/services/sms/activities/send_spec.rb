# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Activities::Send do
  let_it_be(:customer) { create(:customer) }
  let!(:credential) { create(:sms_credential, provider: "aliyun", mode: "sandbox") }
  let!(:template)   { create(:sms_template, key: "verify_code", variables: %w[code minutes],
                             provider_template_codes: { "aliyun" => "SMS_1" }) }
  let(:vars)        { { "code" => "1234", "minutes" => "5" } }

  before do
    Current.customer = customer
    enable_module!("sms", customer, name: "SMS")
    allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).and_return(
      { vendor_message_id: "BIZ-1", raw: { "Code" => "OK", "BizId" => "BIZ-1" } }
    )
  end

  after { Current.customer = nil }

  def capture_events
    events = []
    sub = ActiveSupport::Notifications.subscribe("sms.send") { |*args| events << ActiveSupport::Notifications::Event.new(*args) }
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "durably admits a queued Sms::Message without calling the vendor" do
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
    msg = described_class.call(customer: customer, to: "+8613800138000",
                               template_key: "verify_code", vars: vars)
    expect(msg).to be_persisted
    expect(msg.status).to eq("queued")
    expect(msg.vendor_message_id).to be_nil
    expect(msg.provider).to eq("aliyun")
    expect(msg.sms_template).to eq(template)
  end

  it "normalizes the phone number to E.164 before persisting" do
    msg = described_class.call(customer: customer, to: "138-0013-8000",
                               template_key: "verify_code", vars: vars)
    expect(msg.to).to eq("+8613800138000")
  end

  it "rejects with TemplateVarsInvalid when vars miss required keys" do
    expect {
      described_class.call(customer: customer, to: "+8613800138000",
                           template_key: "verify_code", vars: { "code" => "x" })
    }.to raise_error(Sms::Errors::TemplateVarsInvalid, /missing required keys: minutes/)
  end

  it "rejects when the live vendor has no template code, before calling the adapter" do
    template.update!(provider_template_codes: { "twilio" => "HX1" })
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)

    expect {
      described_class.call(customer: customer, to: "+8613800138000",
                           template_key: "verify_code", vars: vars)
    }.to raise_error(Sms::Errors::TemplateVarsInvalid, /aliyun/)
    expect(Sms::Message.count).to eq(0)
  end

  it "rejects with TemplateVarsInvalid when template_key is unknown" do
    expect {
      described_class.call(customer: customer, to: "+8613800138000",
                           template_key: "does_not_exist", vars: {})
    }.to raise_error(Sms::Errors::TemplateVarsInvalid, /not a registered active template/)
  end

  it "rejects an invalid phone number via the contract" do
    expect {
      described_class.call(customer: customer, to: "nope", template_key: "verify_code", vars: vars)
    }.to raise_error(Sms::Errors::TemplateVarsInvalid, /To is invalid/)
  end

  it "is idempotent on (customer, idempotency_key)" do
    first  = described_class.call(customer: customer, to: "+8613800138000",
                                  template_key: "verify_code", vars: vars,
                                  idempotency_key: "k-1")
    second = described_class.call(customer: customer, to: "+8613800138000",
                                  template_key: "verify_code", vars: vars,
                                  idempotency_key: "k-1")
    expect(second.id).to eq(first.id)
    expect(Sms::Message.where(idempotency_key: "k-1").count).to eq(1)
  end

  it "returns the concurrently-inserted row (race-safe) instead of double-sending" do
    idempotency_key = "race-1"
    winner = described_class.call(customer: customer, to: "+8613800138000", template_key: "verify_code",
                                  vars: vars, idempotency_key: idempotency_key)
    winner.update_columns(status: "sent", vendor_message_id: "WINNER", created_at: 2.minutes.ago)
    # The initial and locked reads miss; the winner is visible on rescue and
    # lives outside the loser's savepoint, as a committed competing INSERT does.
    allow(Sms::MessageAdmission).to receive(:existing).and_return(nil, nil, winner)
    allow(Sms::Message).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, "duplicate")
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)

    msg = described_class.call(customer: customer, to: "+8613800138000", template_key: "verify_code",
                               vars: vars, idempotency_key: idempotency_key)

    expect(msg).to eq(winner)
    expect(msg.vendor_message_id).to eq("WINNER")
    expect(Sms::Message.where(idempotency_key: idempotency_key).count).to eq(1)
  end

  describe "opt-out suppression" do
    it "returns a suppressed message and never calls the vendor when the recipient opted out" do
      Sms::OptOut.record_global!(phone_e164: "+8613800138000", provider: "twilio", reason: "inbound:STOP")

      expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)

      msg = described_class.call(customer: customer, to: "+8613800138000",
                                 template_key: "verify_code", vars: vars)
      expect(msg.status).to eq("suppressed")
      expect(msg).to be_persisted
    end

    it "suppresses when only a tenant-scoped opt-out row matches this tenant" do
      Sms::OptOut.record_for_customer!(customer_id: customer.id, phone_e164: "+8613800138000")

      msg = described_class.call(customer: customer, to: "+8613800138000",
                                 template_key: "verify_code", vars: vars)
      expect(msg.status).to eq("suppressed")
    end

    it "does not suppress a different tenant's manual opt-out" do
      other = create(:customer)
      Sms::OptOut.record_for_customer!(customer_id: other.id, phone_e164: "+8613800138000")

      msg = described_class.call(customer: customer, to: "+8613800138000",
                                 template_key: "verify_code", vars: vars)
      expect(msg.status).to eq("queued")
    end

    it "emits sms.send with outcome=suppressed" do
      Sms::OptOut.record_global!(phone_e164: "+8613800138000")

      events = capture_events do
        described_class.call(customer: customer, to: "+8613800138000",
                             template_key: "verify_code", vars: vars)
      end
      expect(events.last.payload[:outcome]).to eq("suppressed")
    end
  end

  describe "per-phone rate limit" do
    it "rejects the 2nd send within a minute" do
      described_class.call(customer: customer, to: "+8613800138000",
                           template_key: "verify_code", vars: vars)
      expect {
        described_class.call(customer: customer, to: "+8613800138000",
                             template_key: "verify_code", vars: vars)
      }.to raise_error(Sms::Errors::RateLimited) { |e| expect(e.window).to eq(:minute) }
    end

    it "rejects the 6th send within an hour" do
      5.times do |i|
        create(:sms_message, customer: customer, to: "+8613800138000", template_key: "verify_code",
               status: "sent", created_at: (i * 2 + 2).minutes.ago)
      end
      expect {
        described_class.call(customer: customer, to: "+8613800138000",
                             template_key: "verify_code", vars: vars)
      }.to raise_error(Sms::Errors::RateLimited) { |e| expect(e.window).to eq(:hour) }
    end

    it "rejects the 11th send within a day" do
      10.times do |i|
        # spaced past the 1-min and 1-hour windows but within the 1-day window
        create(:sms_message, customer: customer, to: "+8613800138000", template_key: "verify_code",
               status: "sent", created_at: (i + 2).hours.ago)
      end
      expect {
        described_class.call(customer: customer, to: "+8613800138000",
                             template_key: "verify_code", vars: vars)
      }.to raise_error(Sms::Errors::RateLimited) { |e| expect(e.window).to eq(:day) }
    end
  end

  describe "per-adapter rate-limit window wider than the default 1-day lookback" do
    before do
      # Aliyun is the resolved adapter here; declare a single 2-day window so
      # only that window is enforced and the default lookback would miss it.
      allow(Sms::Adapters::Aliyun).to receive(:rate_limit_windows)
        .and_return([[:two_days, 2 * 86_400, 2]])
    end

    it "counts messages older than one day but inside the adapter's window" do
      2.times do
        create(:sms_message, customer: customer, to: "+8613800138000", template_key: "verify_code",
               status: "sent", created_at: 30.hours.ago)
      end

      expect {
        described_class.call(customer: customer, to: "+8613800138000",
                             template_key: "verify_code", vars: vars)
      }.to raise_error(Sms::Errors::RateLimited) { |e| expect(e.window).to eq(:two_days) }
    end
  end

  describe "per-tenant daily cap" do
    before do
      enable_module!("sms", customer, name: "SMS",
                     configuration: { daily_send_cap: 3 }.to_json, enabled_at: Time.current)
    end

    it "rejects when already at cap" do
      3.times do |i|
        create(:sms_message, customer: customer, to: "+86138001380#{i}#{i}", template_key: "verify_code",
               status: "sent", created_at: Time.zone.now.beginning_of_day + i.minutes)
      end
      expect {
        described_class.call(customer: customer, to: "+8613800139999",
                             template_key: "verify_code", vars: vars)
      }.to raise_error(Sms::Errors::DailyCapExceeded)
    end

    it "does not count suppressed or failed sends toward the cap" do
      create(:sms_message, customer: customer, to: "+8613800138001", template_key: "verify_code",
             status: "suppressed", created_at: Time.zone.now.beginning_of_day + 1.minute)
      create(:sms_message, customer: customer, to: "+8613800138002", template_key: "verify_code",
             status: "failed", created_at: Time.zone.now.beginning_of_day + 2.minutes)
      2.times do |i|
        create(:sms_message, customer: customer, to: "+86138001381#{i}#{i}", template_key: "verify_code",
               status: "sent", created_at: Time.zone.now.beginning_of_day + (3 + i).minutes)
      end
      expect {
        described_class.call(customer: customer, to: "+8613800139998",
                             template_key: "verify_code", vars: vars)
      }.not_to raise_error
    end

    it "re-checks the cap under a customer lock so a concurrent send cannot slip past" do
      2.times do |i|
        create(:sms_message, customer: customer, to: "+86138001382#{i}#{i}", template_key: "verify_code",
               status: "sent", created_at: Time.zone.now.beginning_of_day + i.minutes)
      end
      allow(customer).to receive(:with_lock).and_wrap_original do |method, &block|
        create(:sms_message, customer: customer, to: "+8613800138300", template_key: "verify_code",
               status: "sent", created_at: Time.zone.now.beginning_of_day + 2.minutes)
        method.call(&block)
      end

      expect {
        described_class.call(customer: customer, to: "+8613800139997",
                             template_key: "verify_code", vars: vars)
      }.to raise_error(Sms::Errors::DailyCapExceeded)
    end
  end

  describe "per-tenant daily cap — falls back to DEFAULT_DAILY_CAP when the module config has no daily_send_cap" do
    before do
      enable_module!("sms", customer, name: "SMS",
                     configuration: {}.to_json, enabled_at: Time.current)
    end

    it "does not reject a normal-volume send (default cap of 1000 applies)" do
      msg = described_class.call(customer: customer, to: "+8613800138000",
                                 template_key: "verify_code", vars: vars)
      expect(msg.status).to eq("queued")
    end
  end

  describe "per-tenant daily cap — malformed daily_send_cap config" do
    before do
      enable_module!("sms", customer, name: "SMS",
                     configuration: { daily_send_cap: "lots" }.to_json, enabled_at: Time.current)
    end

    it "logs a warning naming the customer and falls back to DEFAULT_DAILY_CAP" do
      allow(Rails.logger).to receive(:warn)

      msg = described_class.call(customer: customer, to: "+8613800138000",
                                 template_key: "verify_code", vars: vars)

      expect(msg.status).to eq("queued")
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/customer #{customer.id} has a malformed daily_send_cap/))
    end
  end

  describe "opt-out suppression — race safety" do
    it "returns the concurrently-suppressed row (race-safe) without double-processing" do
      Sms::OptOut.record_global!(phone_e164: "+8613800138000")
      idempotency_key = "opt-out-race-1"
      winner = described_class.call(customer: customer, to: "+8613800138000", template_key: "verify_code",
                                    vars: vars, idempotency_key: idempotency_key)
      allow(Sms::MessageAdmission).to receive(:existing).and_return(nil, nil, winner)
      allow(Sms::Message).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, "duplicate")
      expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)

      msg = described_class.call(customer: customer, to: "+8613800138000", template_key: "verify_code",
                                 vars: vars, idempotency_key: idempotency_key)

      expect(msg).to eq(winner)
    end
  end

  it "reloads the actual SMS winner after the database index rejects the loser" do
    request = Sms::MessageAdmission.new(to: "+8613800138000", template_key: "verify_code", vars: vars,
                                        idempotency_key: "actual-sms-index")
    winner, = request.persist(customer: customer, template: template, credential: credential)

    expect {
      message, created = request.persist(customer: customer, template: template, credential: credential)
      expect(message.id).to eq(winner.id)
      expect(created).to be(false)
    }.not_to change(Sms::Message, :count)
  end

  it "propagates an unrelated SMS uniqueness failure when there is no tenant/key winner" do
    create(:sms_message, customer: create(:customer), idempotency_key: "other-tenant-key")
    allow(Sms::Message).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, "unrelated index")

    expect {
      Sms::MessageAdmission.new(to: "+8613800138000", template_key: "verify_code", vars: vars,
                                idempotency_key: "other-tenant-key").persist(customer: customer, template: template, credential: credential)
    }.to raise_error(ActiveRecord::RecordNotUnique, "unrelated index")
  end

  describe "vendor failures" do
    it "marks the message failed on ApiError without raising" do
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message)
        .and_raise(Sms::Errors::ApiError.new("out of service", code: "isv.OUT_OF_SERVICE", payload: {}))

      msg = described_class.call(customer: customer, to: "+8613800138000",
                                 template_key: "verify_code", vars: vars)
      expect(msg.status).to eq("queued")
      Sms::DeliverMessageJob.new.perform(msg.id)
      expect(msg.reload.status).to eq("failed")
      expect(msg.failure_code).to eq("isv.OUT_OF_SERVICE")
    end

    it "emits sms.send with outcome=failed on ApiError" do
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message)
        .and_raise(Sms::Errors::ApiError.new("out of service", code: "isv.OUT_OF_SERVICE", payload: {}))

      events = capture_events do
        msg = described_class.call(customer: customer, to: "+8613800138000",
                                   template_key: "verify_code", vars: vars)
        Sms::DeliverMessageJob.new.perform(msg.id)
      end
      expect(events.last.payload[:outcome]).to eq("failed")
    end

    it "records ambiguous TransportError as unknown without retrying or raising" do
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message)
        .and_raise(Sms::Errors::TransportError, "timeout")

      msg = described_class.call(customer: customer, to: "+8613800138000",
                                 template_key: "verify_code", vars: vars)
      expect { Sms::DeliverMessageJob.new.perform(msg.id) }.not_to raise_error

      msg = Sms::Message.find_by(customer_id: customer.id, to: "+8613800138000")
      expect(msg.status).to eq("unknown")
      expect(msg.vendor_message_id).to be_nil
    end

    it "emits sms.send with outcome=unknown on TransportError" do
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message)
        .and_raise(Sms::Errors::TransportError, "timeout")

      events = capture_events do
        msg = described_class.call(customer: customer, to: "+8613800138000", template_key: "verify_code", vars: vars)
        Sms::DeliverMessageJob.new.perform(msg.id)
      end
      expect(events.last.payload[:outcome]).to eq("unknown")
    end
  end

  describe "instrumentation on the happy path" do
    it "emits sms.send with outcome=sent, the provider, and a duration" do
      events = capture_events do
        msg = described_class.call(customer: customer, to: "+8613800138000", template_key: "verify_code", vars: vars)
        Sms::DeliverMessageJob.new.perform(msg.id)
      end
      expect(events.size).to eq(1)
      expect(events.first.payload[:outcome]).to eq("sent")
      expect(events.first.payload[:provider]).to eq("aliyun")
      expect(events.first.payload[:duration]).to be_a(Numeric)
    end
  end
end
