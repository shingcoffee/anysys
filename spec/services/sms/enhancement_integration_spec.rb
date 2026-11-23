# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe "SMS enhancement integration", type: :request do
  let(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let!(:sms_module) { enable_module!("sms", customer, name: "SMS") }
  let!(:credential) do
    create(:sms_credential, provider: "twilio", access_key_id: "AC_QA", access_key_secret: "QA_AUTH_TOKEN",
           config: { "messaging_service_sid" => "MG_QA" })
  end
  let!(:template) do
    create(:sms_template, variables: %w[code minutes], provider_template_codes: { "twilio" => "HX_QA" })
  end
  let(:phone) { "+14155552671" }
  let(:vars) { { "code" => "1234", "minutes" => 5 } }
  let(:messages_url) { "https://api.twilio.com/2010-04-01/Accounts/AC_QA/Messages.json" }
  let(:receipt_time) { Time.current.change(usec: 0) - 30.seconds }

  before { clear_enqueued_jobs }

  after do
    clear_enqueued_jobs
    Current.reset
  end

  def admit(**options)
    Sms::Gateway.send(**{ customer: customer, to: phone, template_key: template.key, vars: vars,
                          idempotency_key: "qa-request" }.merge(options))
  end

  def accept_vendor(sid: "SM_QA")
    stub_request(:post, messages_url).with do |request|
      payload = URI.decode_www_form(request.body).to_h
      payload["To"] == phone && payload["ContentSid"] == "HX_QA" &&
        JSON.parse(payload.fetch("ContentVariables")) == vars && payload["MessagingServiceSid"] == "MG_QA"
    end.to_return(status: 201, headers: { "Content-Type" => "application/json" },
                  body: { sid: sid, status: "queued", account_sid: "AC_QA", to: phone }.to_json)
  end

  def signed_callback(kind, params)
    path = "/sms/webhooks/twilio/#{kind}"
    signature = Twilio::Security::RequestValidator.new(credential.access_key_secret)
                .build_signature_for("http://www.example.com#{path}", params)
    post path, params: params, headers: { "X-Twilio-Signature" => signature }
  end

  def delivered_callback(sid: "SM_QA", **extra)
    signed_callback("delivery", {
      "AccountSid" => "AC_QA", "MessageSid" => sid, "MessageStatus" => "delivered",
      "To" => "+1 (415) 555-2671", "NumSegments" => "2", "DateUpdated" => receipt_time.iso8601
    }.merge(extra.stringify_keys))
  end

  def query_resource(sid: "SM_QA", **attributes)
    stub_request(:get, "https://api.twilio.com/2010-04-01/Accounts/AC_QA/Messages/#{sid}.json")
      .with(basic_auth: ["AC_QA", "QA_AUTH_TOKEN"])
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        sid: sid, status: "undelivered", account_sid: "AC_QA", to: phone,
        error_code: 30003, error_message: "Destination unavailable", num_segments: "3",
        date_updated: receipt_time.rfc2822
      }.merge(attributes).to_json)
  end

  def suspend_sms!
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: sms_module).update!(status: :suspended)
  end

  it "hands HTTP admission to one worker attempt, projects a signed receipt and exposes status only to its tenant" do
    sign_in admin
    post "/#{customer.id}/admin/modules/sms/sends", params: {
      to: phone, template_key: template.key, vars: vars, idempotency_key: "qa-request"
    }, as: :json
    expect(response).to have_http_status(:accepted)
    message = Sms::Message.find(response.parsed_body.fetch("message_id"))
    expect(message).to have_attributes(status: "queued", customer_id: customer.id, delivery_attempts: 0)
    expect(message.expires_at).to be_within(2.seconds).of(1.hour.from_now)
    expect(message.dispatch_started_at).to be_nil
    expect(WebMock).not_to have_requested(:post, messages_url)

    enable_module!("sms", other_customer, name: "SMS")
    other_message = admit(customer: other_customer, to: "+14155552672")
    expect(other_message.id).not_to eq(message.id)
    # Both content and account identity must survive mutable platform settings.
    template.update!(status: "retired", variables: ["replacement"], provider_template_codes: { "twilio" => "HX_CHANGED" })
    credential.update!(status: "disabled")
    accept_vendor
    2.times { Sms::DeliverMessageJob.new.perform(message.id) }
    expect(message.reload).to have_attributes(status: "sent", vendor_message_id: "SM_QA", delivery_attempts: 1)
    expect(message.dispatch_started_at).to be_present
    expect(message.delivered_at).to be_nil
    expect(WebMock).to have_requested(:post, messages_url).once

    delivered_callback
    expect(response).to have_http_status(:ok)
    expect(message.reload).to have_attributes(status: "delivered", delivered_at: receipt_time, failure_code: nil)
    expect(message.metadata).to include("credential_id" => credential.id, "provider_status" => "delivered",
                                        "provider_segments" => 2, "provider_occurred_at" => receipt_time.iso8601)
    receipt = Sms::BackendReceipt.find_by!(vendor_message_id: "SM_QA")
    expect(receipt).to have_attributes(customer_id: customer.id, credential_id: credential.id)
    expect(receipt.processed_at).to be_present
    expect(other_message.reload).to have_attributes(status: "queued", delivery_attempts: 0, vendor_message_id: nil)

    get "/#{customer.id}/admin/modules/sms/messages/#{message.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("common.status.delivered"))
    sign_in create(:user, :admin, customer: other_customer)
    get "/#{other_customer.id}/admin/modules/sms/messages/#{other_message.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("common.status.queued"))
    get "/#{other_customer.id}/admin/modules/sms/messages/#{message.id}"
    expect(response).to have_http_status(:not_found)
    get "/#{customer.id}/admin/modules/sms/messages/#{message.id}", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:forbidden)
  end

  it "retains and deduplicates a genuinely signed early receipt until the worker records its vendor ID" do
    message = admit
    delivered_callback
    expect(response).to have_http_status(:ok)
    receipt = Sms::BackendReceipt.find_by!(vendor_message_id: "SM_QA")
    expect(receipt).to have_attributes(customer_id: nil, processed_at: nil)
    expect(message.reload.status).to eq("queued")
    expect { delivered_callback }.not_to change(Sms::BackendReceipt, :count)

    accept_vendor
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload).to have_attributes(status: "delivered", delivery_attempts: 1, delivered_at: receipt_time)
    expect(receipt.reload.customer_id).to eq(customer.id)
    expect(receipt.processed_at).to be_present
    expect(WebMock).to have_requested(:post, messages_url).once
  end

  it "uses the real REST fallback on the retained disabled account and preserves failure code, time and actual segments" do
    message = admit
    accept_vendor
    Sms::DeliverMessageJob.new.perform(message.id)
    # Reconciliation grace is measured from the external attempt, rather than
    # admission. Keep all fixture clocks coherent with an elapsed send.
    message.update!(created_at: 4.minutes.ago, dispatch_started_at: 3.minutes.ago, sent_at: 3.minutes.ago)
    credential.update!(status: "disabled")
    template.update!(status: "retired")
    suspend_sms!
    query_resource(error_code: 21610, error_message: "Recipient opted out")

    Sms::Cron::ReconcileMessages.call
    expect(message.reload).to have_attributes(status: "failed", failure_code: "21610", failure_message: "Recipient opted out",
                                              delivered_at: nil, delivery_attempts: 1)
    expect(message.metadata).to include("provider_status" => "undelivered", "provider_segments" => 3, "credential_id" => credential.id)
    expect(Time.iso8601(message.metadata.fetch("provider_occurred_at"))).to eq(receipt_time)
    expect(message.raw_response).to include("error_code" => 21610, "num_segments" => "3")
    expect(Sms::OptOut.find_by!(phone_e164: phone)).to have_attributes(customer_id: nil, reason: "provider:21610")
    expect(WebMock).to have_requested(:get, %r{/Accounts/AC_QA/Messages/SM_QA\.json}).once
    expect(WebMock).to have_requested(:post, messages_url).once

    # A later authenticated success repairs the failure without another attempt.
    delivered_callback
    expect(response).to have_http_status(:ok)
    expect(message.reload).to have_attributes(status: "delivered", failure_code: nil, failure_message: nil, delivery_attempts: 1)
  end

  it "protects delivered facts from a stale query object and a genuinely signed late failed receipt" do
    message = admit
    accept_vendor
    Sms::DeliverMessageJob.new.perform(message.id)
    stale = Sms::Message.find(message.id)
    delivered_callback
    expect(response).to have_http_status(:ok)
    protected_facts = message.reload.attributes.slice("status", "delivered_at", "failure_code", "failure_message", "metadata", "raw_response")

    query_resource
    Sms::Gateway.query(message: stale)
    signed_callback("delivery", {
      "AccountSid" => "AC_QA", "MessageSid" => "SM_QA", "MessageStatus" => "failed", "To" => phone,
      "ErrorCode" => "30003", "ErrorMessage" => "Late failure", "NumSegments" => "9",
      "DateUpdated" => (receipt_time + 10.seconds).iso8601
    })
    expect(response).to have_http_status(:ok)
    expect(message.reload.attributes.slice(*protected_facts.keys)).to eq(protected_facts)
    expect(message.delivery_attempts).to eq(1)
  end

  it "does not apply an authenticated receipt or REST result for a different recipient" do
    message = admit
    accept_vendor
    Sms::DeliverMessageJob.new.perform(message.id)
    delivered_callback(To: "+14155552672", ErrorCode: "21610")
    expect(response).to have_http_status(:ok)
    query_resource(to: "+14155552672", error_code: 21610)
    Sms::Gateway.query(message: message)

    expect(message.reload).to have_attributes(status: "sent", failure_code: nil, delivered_at: nil)
    expect(Sms::BackendReceipt.find_by!(vendor_message_id: "SM_QA").processed_at).to be_nil
    expect(Sms::OptOut.where(phone_e164: [phone, "+14155552672"])).to be_empty
  end

  it "honors signed localized STOP classification after admission and before any dispatch in either tenant" do
    # A prior actual contact binds the account when sandbox/production retain
    # the same key. Inbound To is our sender, not the recipient being blocked.
    contacted = admit(idempotency_key: "prior-contact")
    accept_vendor(sid: "SM_CONTACT")
    Sms::DeliverMessageJob.new.perform(contacted.id)
    contacted.update!(created_at: 3.minutes.ago)
    create(:sms_credential, provider: "twilio", mode: "production", access_key_id: "AC_QA",
           access_key_secret: "QA_AUTH_TOKEN", config: { "messaging_service_sid" => "MG_QA" })
    first = admit
    enable_module!("sms", other_customer, name: "SMS")
    second = admit(customer: other_customer)
    params = { "AccountSid" => "AC_QA", "MessageSid" => "SM_IN_QA", "From" => phone,
               "To" => "+14155550000", "Body" => "退订", "OptOutType" => "STOP" }
    signature = Twilio::Security::RequestValidator.new(credential.access_key_secret)
                .build_signature_for("http://www.example.com/sms/webhooks/twilio/inbound", params)
    post "/sms/webhooks/twilio/inbound", params: params.merge("OptOutType" => "HELP"),
         headers: { "X-Twilio-Signature" => signature }
    expect(response).to have_http_status(:forbidden)
    expect(Sms::OptOut.where(phone_e164: phone)).to be_empty

    signed_callback("inbound", params)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/xml")
    expect(response.body).to eq("<Response/>")
    opt_out = Sms::OptOut.find_by!(phone_e164: phone)
    expect(opt_out).to have_attributes(customer_id: nil, reason: "inbound:STOP")
    expect { signed_callback("inbound", params) }.not_to change(Sms::BackendReceipt, :count)
    [first, second].each do |message|
      Sms::DeliverMessageJob.new.perform(message.id)
      expect(message.reload).to have_attributes(status: "suppressed", delivery_attempts: 0, dispatch_started_at: nil, vendor_message_id: nil)
    end
    %w[START HELP].each do |classification|
      signed_callback("inbound", params.merge("MessageSid" => "SM_IN_#{classification}", "OptOutType" => classification, "Body" => "STOP"))
      expect(response).to have_http_status(:ok)
    end
    expect(opt_out.reload.reason).to eq("inbound:STOP")
    expect(WebMock).to have_requested(:post, messages_url).once
  end

  it "replays the canonical request over HTTP after delivery, retirement and disablement, but rejects changed content" do
    message = admit(to: "0014155552671", vars: { minutes: 5, code: "1234" })
    accept_vendor
    Sms::DeliverMessageJob.new.perform(message.id)
    delivered_callback
    credential.update!(status: "disabled")
    template.update!(status: "retired", variables: ["changed"])
    suspend_sms!
    sign_in admin
    params = { to: "+1 (415) 555-2671", template_key: template.key, vars: vars, idempotency_key: "qa-request" }

    expect { post "/#{customer.id}/admin/modules/sms/sends", params: params, as: :json }.not_to change(Sms::Message, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("message_id" => message.id, "status" => "delivered", "vendor_message_id" => "SM_QA")
    expect { post "/#{customer.id}/admin/modules/sms/sends", params: params.merge(vars: vars.merge("code" => "5678")), as: :json }
      .not_to change(Sms::Message, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["error"]).to eq("idempotency_conflict")
    post "/#{customer.id}/admin/modules/sms/sends", params: params.merge(idempotency_key: "new-request"), as: :json
    expect(response).to have_http_status(:not_found)
    expect(WebMock).to have_requested(:post, messages_url).once
  end

  it "accepts real module input and completes both a queued handoff and a delivered idempotency replay" do
    sms_module.update!(handoff_enabled: true)
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: sms_module).update!(configuration_json: {})
    Current.customer = customer
    input = { to: phone, template_key: template.key, vars: vars, idempotency_key: "qa-request", expires_at: 20.minutes.from_now }
    session = {}
    start = lambda do
      FeatureModules::Invocation.begin!(session: session, customer: customer, module_key: "sms", triggering_page: nil,
                                       entity_entry: nil, input: input, exit_target: { kind: "route", name: "customer_home" })
    end
    expect(start.call).to eq("/#{customer.id}/admin/modules/sms/campaigns")
    invocation = FeatureModules::Invocation.current(session)
    message = Sms::Gateway.send(customer: customer, **invocation.fetch(:input).symbolize_keys)
    expect(message.status).to eq("queued")
    expect(message.expires_at).to be_within(0.001.seconds).of(input[:expires_at])
    queued_output = { message_id: message.id, status: message.status }
    result = FeatureModules::Complete.call(session: session, customer: customer, module_key: "sms", output: queued_output)
    expect(result).to include(redirect_to: "/#{customer.id}/admin/dashboard", flash: { feature_module_result: { module_key: "sms", output: queued_output } })
    expect(session).to be_empty

    accept_vendor
    Sms::DeliverMessageJob.new.perform(message.id)
    delivered_callback
    Current.customer = customer
    start.call
    template.update!(status: "retired")
    credential.update!(status: "disabled")
    suspend_sms!
    replay = Sms::Gateway.send(customer: customer, **FeatureModules::Invocation.current(session).fetch(:input).symbolize_keys)
    expect(replay).to have_attributes(id: message.id, status: "delivered")
    result = FeatureModules::Complete.call(session: session, customer: customer, module_key: "sms",
                                          output: { message_id: replay.id, status: replay.status })
    expect(result.dig(:flash, :feature_module_result, :output)).to eq(message_id: message.id, status: "delivered")
    expect(session).to be_empty
    logs = FeatureModules::Log.where(customer_id: customer.id, action: "invocation.complete")
    expect(logs.count).to eq(2)
    expect(logs).to all(have_attributes(status: "success"))
    expect(WebMock).to have_requested(:post, messages_url).once
  end

  it "completes a queued SMS handoff without requiring customer settings to have been saved first" do
    sms_module.update!(handoff_enabled: true)
    Current.customer = customer
    session = {}
    FeatureModules::Invocation.begin!(session: session, customer: customer, module_key: "sms", triggering_page: nil,
                                     entity_entry: nil, input: { to: phone, template_key: template.key, vars: vars }, exit_target: nil)
    message = Sms::Gateway.send(customer: customer, **FeatureModules::Invocation.current(session).fetch(:input).symbolize_keys)
    result = FeatureModules::Complete.call(session: session, customer: customer, module_key: "sms",
                                          output: { message_id: message.id, status: message.status })
    expect(result[:redirect_to]).to eq("/#{customer.id}/admin/dashboard")
    expect(session).to be_empty
  end

  it "runs a validated send_sms step through the core ledger and rejects arbitrary Twilio credentials" do
    config = { "templateKey" => template.key, "to" => "recipient",
               "vars" => [{ "key" => "code", "value" => "ctx[:payload][\"code\"]" },
                          { "key" => "minutes", "value" => "ctx[:payload][\"minutes\"]" }],
               "idempotencyKey" => "ctx[:request_key]", "resultVar" => "sms_message_id" }
    generator = CodeGenerators::ElementTypes::Process::Communication::SendSmsGenerator.new({ "config" => config }, {})
    expect(generator.validate_config(config)).to be_empty
    code = generator.generate_body
    runnable = eval("->(ctx) { #{code} }", binding, "(sms_enhancement_integration)") # rubocop:disable Security/Eval
    ctx = { customer_id: customer.id, recipient: phone, payload: vars, request_key: "qa-request" }
    expect { expect(runnable.call(ctx)).to be_present }.to change(Sms::Message, :count).by(1)
    message = Sms::Message.find(ctx.fetch(:sms_message_id))
    expect(message).to have_attributes(status: "queued", customer_id: customer.id, vars: vars)
    accept_vendor
    Sms::DeliverMessageJob.new.perform(message.id)
    delivered_callback
    template.update!(status: "retired")
    credential.update!(status: "disabled")
    suspend_sms!
    expect(Emails::Gateway).not_to receive(:send_raw)
    expect { expect(runnable.call(ctx)).to eq(message.id) }.not_to change(Sms::Message, :count)
    expect(message.reload.status).to eq("delivered")
    ctx[:request_key] = "new-request"
    expect { expect(runnable.call(ctx)).to be(false) }.not_to change(Sms::Message, :count)
    expect(ctx[:errors].last).to eq(I18n.t("flowchart_runtime.errors.send_sms.module_disabled"))

    untrusted = config.merge("twilioSid" => "AC_ARBITRARY", "twilioToken" => "UNTRUSTED_TOKEN", "fromNumber" => "+14155550000")
    untrusted_code = CodeGenerators::ElementTypes::Process::Communication::SendSmsGenerator
      .new({ "config" => untrusted }, {}).generate_body
    expect(untrusted_code).to eq(code)
    expect(code).not_to include("Twilio::REST", "send_twilio_message", "twilio")
    expect(WebMock).to have_requested(:post, messages_url).once
  end

  it "counts fully rendered variable substitutions without presenting the estimate as provider segment facts" do
    message = admit(vars: { "code" => "^", "minutes" => "a" * 152 })
    rendered = format("%{prefix}%{code}%{minutes}", prefix: "a" * 152, **message.vars.symbolize_keys)
    expect(Sms::SegmentCalculator.call(text: rendered)).to eq(encoding: :gsm7, units: 306, segments: 3, segment_units: [152, 153, 1])
    rendered_unicode = format("%{recipient}：%{body}", recipient: "客户", body: "😀" * 34)
    expect(Sms::SegmentCalculator.call(text: rendered_unicode)).to eq(encoding: :utf16, units: 71, segments: 2, segment_units: [67, 4])
    expect(message.metadata).not_to have_key("provider_segments")
    expect(message.metadata.fetch("template_snapshot").fetch("provider_code")).to eq("HX_QA")
  end
end

RSpec.describe "SMS concurrent admission integration", type: :job do
  self.use_transactional_tests = false

  before do
    @customer = create(:customer)
    @module_created = !FeatureModules::Module.exists?(key: "sms")
    @sms_module = enable_module!("sms", @customer, name: "SMS")
    @credential = create(:sms_credential)
    @template = create(:sms_template)
    clear_enqueued_jobs
  end

  after do
    Sms::Message.where(customer_id: @customer.id).delete_all if @customer
    @template&.destroy!
    @credential&.destroy!
    @customer&.destroy!
    @sms_module&.destroy! if @module_created
    clear_enqueued_jobs
    Current.reset
  end

  # Both callers hold independent real connections before the start barrier.
  # Rails SQLite uses BEGIN IMMEDIATE and a Ruby busy handler (PRAGMA
  # busy_timeout remains zero); no DB stub, sleep, retry or journal override.
  def race_admissions(*payloads)
    ready = Queue.new
    start = Queue.new
    workers = payloads.map do |payload|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          local_customer = Customer.find(@customer.id)
          ready << connection.object_id
          start.pop
          begin
            Sms::Gateway.send(customer: local_customer, template_key: @template.key, **payload)
          rescue Sms::Errors::Error => error
            error
          end
        end
      end
    end
    Timeout.timeout(15) do
      connections = payloads.map { ready.pop }
      expect(connections.uniq.size).to eq(payloads.size)
      payloads.size.times { start << true }
      workers.map(&:value)
    end
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  it "reserves the last tenant daily slot exactly once across independent connections" do
    assignment = FeatureModules::CustomerAssignment.find_by!(customer: @customer, feature_module: @sms_module)
    assignment.update!(configuration_json: assignment.configuration_json.merge("daily_send_cap" => 1))
    results = race_admissions(
      { to: "+8613800138000", vars: { code: "1234", minutes: 5 }, idempotency_key: "quota-a" },
      { to: "+8613800138001", vars: { code: "1234", minutes: 5 }, idempotency_key: "quota-b" }
    )
    expect(results.count { |result| result.is_a?(Sms::Message) }).to eq(1)
    expect(results.count { |result| result.is_a?(Sms::Errors::DailyCapExceeded) }).to eq(1)
    expect(Sms::Message.where(customer_id: @customer.id).count).to eq(1)
  end

  it "reserves a phone window exactly once for different concurrent idempotency keys" do
    results = race_admissions(*%w[phone-a phone-b].map do |key|
      { to: "+8613800138000", vars: { code: "1234", minutes: 5 }, idempotency_key: key }
    end)
    expect(results.count { |result| result.is_a?(Sms::Message) }).to eq(1)
    error = results.find { |result| result.is_a?(Sms::Errors::RateLimited) }
    expect(error).to be_present
    expect(error.window).to eq(:minute)
    expect(Sms::Message.where(customer_id: @customer.id).count).to eq(1)
  end

  it "returns one canonical winner to concurrent same-key callers without a second reservation" do
    results = race_admissions(
      { to: "13800138000", vars: { code: "1234", minutes: 5 }, idempotency_key: "same-key" },
      { to: "+86 (138) 0013-8000", vars: { "minutes" => 5, "code" => "1234" }, idempotency_key: "same-key" }
    )
    expect(results).to all(be_a(Sms::Message))
    expect(results.map(&:id).uniq.size).to eq(1)
    expect(Sms::Message.where(customer_id: @customer.id).count).to eq(1)
    expect(Sms::Message.find(results.first.id)).to have_attributes(status: "queued", delivery_attempts: 0)
  end

  it "rejects the real conflicting same-key loser rather than replaying the winner's different payload" do
    results = race_admissions(
      { to: "+8613800138000", vars: { code: "1234", minutes: 5 }, idempotency_key: "conflict-key" },
      { to: "+8613800138001", vars: { code: "5678", minutes: 5 }, idempotency_key: "conflict-key" }
    )
    expect(results.count { |result| result.is_a?(Sms::Message) }).to eq(1)
    expect(results.count { |result| result.is_a?(Sms::Errors::IdempotencyConflict) }).to eq(1)
    expect(Sms::Message.where(customer_id: @customer.id).count).to eq(1)
  end
end
