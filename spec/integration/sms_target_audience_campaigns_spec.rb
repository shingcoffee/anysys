# frozen_string_literal: true

require "rails_helper"
require "csv"
require "uri"

# Exercise the real domain, HTTP adapters, scheduler, outbox and receipt inbox.
# Only Twilio's external HTTP transport is replaced; its SDK and webhook
# signature verification/normalization run normally.
RSpec.describe "SMS target audience campaign integration", type: :request do
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }
  let!(:credential) do
    create(:sms_credential, provider: "twilio", access_key_id: "AC_QA_CAMPAIGNS",
      access_key_secret: "QA_AUTH_TOKEN", config: { "messaging_service_sid" => "MG_QA_CAMPAIGNS" })
  end
  let!(:template) do
    create(:sms_template, purpose: "marketing", variables: %w[name offer opt_out_url],
      provider_template_codes: { "twilio" => "HX_QA_APPROVED" },
      body_template: "Hello {{name}}. Offer: {{offer}}. Unsubscribe: {{opt_out_url}}")
  end
  let(:mapping) do
    { "name" => { "source" => "field", "field" => "name" },
      "offer" => { "source" => "field", "field" => "attributes.offer", "fallback" => "20%" },
      "opt_out_url" => { "source" => "field", "field" => "unsubscribe_url" } }
  end
  let(:base) { "/#{customer.id}/admin/modules/sms" }
  let(:messages_url) { "https://api.twilio.com/2010-04-01/Accounts/#{credential.access_key_id}/Messages.json" }
  let(:transport_calls) { [] }

  before do
    travel_to(Time.utc(2026, 10, 13, 2))
    enable_module!("sms", customer, name: "SMS")
    sign_in actor
    # Consume Devise's queued login before read-only assertions; its Trackable
    # hook legitimately writes the authentication record on the first request.
    get "#{base}/contacts.json"
    clear_enqueued_jobs
    stub_provider
  end

  after do
    clear_enqueued_jobs
    Current.reset
    travel_back
  end

  def value!(result)
    expect(result).to be_success, "#{result.code}: #{result.errors.inspect}"
    result.value
  end

  def new_contact(consented: true, customer: self.customer, actor: self.actor, **attributes)
    input = build(:sms_contact, customer: customer, custom_attributes: { "vip" => true, "offer" => "20%" }, **attributes)
    contact = value!(Sms::Contacts::Save.call(customer: customer, actor: actor, attributes:
      input.attributes.symbolize_keys.slice(:name, :country_code, :timezone, :custom_attributes).merge(phone: input.phone_e164)))
    record_consent(contact, customer: customer, actor: actor) if consented
    contact.reload
  end

  def record_consent(contact, action: "granted", customer: self.customer, actor: self.actor)
    value!(Sms::Contacts::RecordConsent.call(customer: customer, actor: actor, contact: contact, attributes:
      { action: action, event_key: SecureRandom.uuid, occurred_at: 1.minute.ago,
        reference: "signed-marketing-form", statement: "I agree to receive marketing SMS." }))
    contact.reload
  end

  def change_contact(contact, **attributes)
    value!(Sms::Contacts::Save.call(customer: customer, actor: actor, contact: contact,
      attributes: attributes.merge(lock_version: contact.reload.lock_version)))
  end

  def segment_for(rules)
    value!(Sms::Audience::SaveSegment.call(customer: customer, actor: actor,
      attributes: { name: "Dynamic offer audience", segment_rules: rules }))
  end

  def vip_rules
    { "type" => "group", "conditions" => [{ "field" => "attributes.vip", "operator" => "equals", "value" => true }], "joins" => [] }
  end

  def save_draft(**attributes)
    value!(Sms::Campaigns::Save.call(customer: customer, actor: actor, attributes:
      { name: "Audience offer", template_id: template.id, variable_map: mapping }.merge(attributes)))
  end

  def review_and_launch(campaign)
    preview = value!(Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign))
    expect(preview[:blockers]).to eq([])
    expect(preview[:review_token]).to be_present
    value!(Sms::Campaigns::Launch.call(customer: customer, actor: actor, campaign: campaign,
      lock_version: campaign.lock_version, review_token: preview[:review_token]))
  end

  def scheduler_and_worker(campaign)
    Sms::Campaigns::SchedulerJob.new.perform
    token = campaign.reload.run_token
    expect(token).to be_present
    Sms::Campaigns::RunJob.new.perform(campaign.customer_id, campaign.id, token)
    campaign.reload
  end

  def report(campaign)
    value!(Sms::Campaigns::Report.call(customer: customer, campaign: campaign))
  end

  def expect_read_only
    writes = []
    subscriber = lambda do |*args|
      sql = args.last.fetch(:sql)
      writes << sql if sql.match?(/\A\s*(?:INSERT|UPDATE|DELETE|REPLACE)\b/i)
    end
    jobs = enqueued_jobs.deep_dup
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    expect(writes).to eq([]), "Read-only operation issued writes: #{writes.inspect}"
    expect(enqueued_jobs).to eq(jobs)
  end

  def stub_provider(&during_transport)
    stub_request(:post, messages_url).to_return do |request|
      body = URI.decode_www_form(request.body).to_h
      call = { "sid" => "SMqa#{transport_calls.size + 1}", "to" => body.fetch("To"),
        "vars" => JSON.parse(body.fetch("ContentVariables")), "content_sid" => body.fetch("ContentSid"), "at" => Time.current }
      transport_calls << call
      during_transport&.call(call)
      { status: 201, headers: { "Content-Type" => "application/json" },
        body: { sid: call.fetch("sid"), status: "queued", to: call.fetch("to"), account_sid: credential.access_key_id }.to_json }
    end
  end

  def signed_callback(kind, parameters)
    path = "/sms/webhooks/twilio/#{kind}"
    parameters = { "AccountSid" => credential.access_key_id }.merge(parameters)
    signature = Twilio::Security::RequestValidator.new(credential.access_key_secret)
      .build_signature_for("http://www.example.com#{path}", parameters)
    # Provider callbacks have no administrator browser session/cookies.
    callback_session = ActionDispatch::Integration::Session.new(Rails.application)
    callback_session.post path, params: parameters, headers: { "X-Twilio-Signature" => signature }
    expect(callback_session.response).to have_http_status(:ok), callback_session.response.body
  end

  def receipt(message, status: "delivered", segments: "2", **extra)
    message.reload
    signed_callback("delivery", { "MessageSid" => message.vendor_message_id, "MessageStatus" => status,
      "To" => message.to, "NumSegments" => segments, "DateUpdated" => Time.current.iso8601 }.merge(extra.stringify_keys))
  end

  def browser_csrf
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  def confirmation_csrf
    form = Nokogiri::HTML(response.body).css("form").find { |node| node["action"].start_with?("/sms/unsubscribes/") }
    expect(form).to be_present
    form.at_css('input[name="authenticity_token"]')["value"]
  end

  it "takes consented dynamic contacts through preview, saved review, scheduling, paced transport and normalized reporting" do
    alice = new_contact(name: "Alice")
    bob = new_contact(name: "Bob")
    unknown = new_contact(name: "No evidence", consented: false)
    revoked = new_contact(name: "Revoked", custom_attributes: { "vip" => false })
    record_consent(revoked, action: "revoked")
    archived = new_contact(name: "Archived")
    value!(Sms::Contacts::Archive.call(customer: customer, actor: actor, contact: archived, lock_version: archived.lock_version))
    opted_out = new_contact(name: "Provider STOP")
    signed_callback("inbound", "From" => opted_out.phone_e164, "Body" => "STOP", "MessageSid" => "SMstop")
    outside = new_contact(name: "Outside", custom_attributes: { "vip" => false })
    foreign_customer = create(:customer)
    foreign_actor = create(:user, :admin, customer: foreign_customer)
    foreign = new_contact(customer: foreign_customer, actor: foreign_actor, phone_e164: alice.phone_e164)
    # The OR arm deliberately matches a revoked non-VIP. Audience membership
    # cannot OR its way around the independent positive-consent intersection.
    rules = vip_rules.merge("conditions" => vip_rules.fetch("conditions") +
      [{ "field" => "consent_status", "operator" => "equals", "value" => "revoked" }], "joins" => ["OR"])
    segment = segment_for(rules)
    form = { name: "Reviewed audience offer", template_id: template.id, segment_id: segment.id,
      variable_map_json: mapping.to_json, send_timing: "scheduled", scheduled_local: "2026-10-13T11:00", timezone: "Asia/Shanghai" }

    expect_read_only { post "#{base}/campaigns/preview.json", params: { sms_campaign: form }, as: :json }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.dig("data", "preview")).to include("matched_count" => 6, "eligible_count" => 2,
      "excluded_counts" => { "consent_missing" => 2, "contact_archived" => 1, "opted_out" => 1 }, "review_token" => nil)
    expect(Sms::Campaign.count).to eq(0)
    post "#{base}/campaigns.json", params: { sms_campaign: form }, as: :json
    expect(response).to have_http_status(:created), response.body
    campaign = Sms::Campaign.find(response.parsed_body.dig("data", "id"))
    expect(campaign).to have_attributes(status: "draft", created_by_id: actor.id, launched_at: nil)
    expect([Sms::CampaignRecipient.count, Sms::Message.count]).to eq([0, 0])
    expect(enqueued_jobs).to be_empty
    expect_read_only { get "#{base}/campaigns/#{campaign.id}.json" }
    token = response.parsed_body.dig("data", "preview", "review_token")
    expect(token).to be_present
    post "#{base}/campaigns/#{campaign.id}/launch.json", params: { lock_version: campaign.lock_version, review_token: token }, as: :json
    expect(response).to have_http_status(:accepted), response.body
    Sms::Campaigns::SchedulerJob.new.perform
    expect(campaign.reload).to have_attributes(status: "scheduled", started_at: nil, run_token: nil)
    expect(Sms::CampaignRecipient.count).to eq(0)

    travel_to(Time.utc(2026, 10, 13, 3))
    Current.set(customer: foreign_customer) { scheduler_and_worker(campaign) }
    expect(campaign.recipients.pluck(:contact_id)).to match_array([alice, bob, unknown, revoked, archived, opted_out].map(&:id))
    expect(campaign.recipients.where(contact_id: [foreign.id, outside.id])).not_to exist
    first, second = campaign.messages.order(:id).to_a
    expect(campaign.messages.pluck(:customer_id, :contact_id)).to contain_exactly([customer.id, alice.id], [customer.id, bob.id])
    Sms::DeliverMessageJob.new.perform(first.id)
    Sms::DeliverMessageJob.new.perform(second.id)
    expect(first.reload).to have_attributes(status: "sent", delivery_attempts: 1, dispatch_started_at: Time.current)
    expect(second.reload).to have_attributes(status: "queued", delivery_attempts: 0, dispatch_started_at: nil, delivery_due_at: 1.second.from_now)
    expect(report(campaign)).to include(attempted_count: 1, api_accepted_count: 1, delivered_count: 0, deferred_counts: { "account_rate" => 1 })
    travel 1.second
    Sms::DeliverMessageJob.new.perform(second.id)
    expect(transport_calls.map { |call| call.fetch("to") }).to eq([alice.phone_e164, bob.phone_e164])
    expect(transport_calls.map { |call| call.fetch("at") }).to eq([first.dispatch_started_at, second.reload.dispatch_started_at])
    2.times { receipt(first) }
    receipt(second, status: "undelivered", segments: "1", ErrorCode: "30003", ErrorMessage: "Unreachable handset")
    expect(Sms::BackendReceipt.where(vendor_message_id: first.vendor_message_id).count).to eq(1)
    expect(first.reload.metadata).to include("provider_status" => "delivered", "provider_segments" => 2)
    expect(second.reload).to have_attributes(status: "failed", failure_code: "30003")
    Sms::Campaigns::RefreshStatsJob.new.perform(customer.id, campaign.id)
    expect(campaign.reload.status).to eq("completed")
    # The scheduled hour exceeds the administrator's normal session timeout.
    reset!
    sign_in actor
    get "#{base}/contacts.json"
    expect(response).to have_http_status(:ok)
    expect_read_only { get "#{base}/campaigns/#{campaign.id}/report.json" }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.dig("data", "report")).to include("matched_count" => 6, "eligible_at_start_count" => 2,
      "admitted_count" => 2, "attempted_count" => 2, "api_accepted_count" => 2, "delivered_count" => 1,
      "failed_count" => 1, "skipped_count" => 4, "provider_segments_total" => 3, "delivery_rate" => 0.5,
      "skip_counts" => { "consent_missing" => 2, "contact_archived" => 1, "opted_out" => 1 }, "deferred_counts" => {})
    expect(WebMock).to have_requested(:post, messages_url).twice
  end

  it "freezes reviewed rules/content, start-time membership and personalization across later edits and continuation recovery" do
    alice = new_contact(name: "Alice at start")
    entrant = new_contact(name: "Before start", custom_attributes: { "vip" => false, "offer" => "30%" })
    excluded = new_contact(consented: false)
    outside = new_contact(custom_attributes: { "vip" => false })
    segment = segment_for(vip_rules)
    campaign = review_and_launch(save_draft(segment_id: segment.id, send_timing: "scheduled", scheduled_at: 1.hour.from_now, send_rate_per_minute: 1))
    value!(Sms::Audience::SaveSegment.call(customer: customer, actor: actor, segment: segment,
      attributes: { segment_rules: {}, lock_version: segment.lock_version }))
    template.update!(status: "retired", purpose: "transactional", variables: ["replacement"], body_template: nil,
      provider_template_codes: { "twilio" => "HX_REPLACEMENT" })
    change_contact(entrant, name: "Entrant at start", custom_attributes: { "vip" => true, "offer" => "30%" })
    travel 1.hour
    scheduler_and_worker(campaign)
    original_ids = campaign.recipients.order(:id).pluck(:contact_id)
    expect(original_ids).to contain_exactly(alice.id, entrant.id, excluded.id)
    expect(original_ids).not_to include(outside.id)
    recipient = campaign.recipients.find_by!(contact_id: entrant.id)
    expect(recipient).to have_attributes(status: "pending", deferral_reason: "campaign_rate")
    expect(recipient.vars).to include("name" => "Entrant at start", "offer" => "30%")
    frozen_vars = recipient.vars.deep_dup
    change_contact(entrant, name: "Later name", custom_attributes: { "vip" => false, "offer" => "90%" })
    record_consent(excluded)
    late = new_contact(name: "Added after snapshot")
    Sms::DeliverMessageJob.new.perform(campaign.messages.sole.id)
    clear_enqueued_jobs # Simulate a lost continuation accelerator, not DB state.
    travel 61.seconds
    scheduler_and_worker(campaign)
    Sms::DeliverMessageJob.new.perform(recipient.reload.message_id)
    Sms::Campaigns::RefreshStatsJob.new.perform(customer.id, campaign.id)
    expect(campaign.reload.status).to eq("completed")
    expect(campaign.recipients.order(:id).pluck(:contact_id)).to eq(original_ids)
    expect(campaign.recipients.where(contact_id: late.id)).not_to exist
    expect(campaign.recipients.find_by!(contact_id: excluded.id)).to have_attributes(status: "skipped", skip_reason: "consent_missing", message_id: nil)
    expect(recipient.reload.vars).to eq(frozen_vars)
    expect(recipient.message).to have_attributes(to: recipient.phone_e164, vars: frozen_vars, expires_at: campaign.expires_at)
    expect(transport_calls.last).to include("content_sid" => "HX_QA_APPROVED", "vars" => frozen_vars)
    expect(campaign.audience_snapshot).to include("segment_rules" => vip_rules, "field_specs" => { "attributes.vip" => "boolean" })
    expect(report(campaign)).to include(matched_count: 3, eligible_at_start_count: 2, admitted_count: 2, attempted_count: 2, skipped_count: 1)
  end

  it "cancels pending and account-deferred work while an attempted message continues through a late receipt" do
    3.times { |index| new_contact(name: "Cancel contact #{index}") }
    campaign = review_and_launch(save_draft(send_rate_per_minute: 2))
    scheduler_and_worker(campaign)
    first, queued = campaign.messages.order(:id).to_a
    Sms::DeliverMessageJob.new.perform(first.id)
    Sms::DeliverMessageJob.new.perform(queued.id)
    stale_token = campaign.reload.run_token
    expect(report(campaign)).to include(pending_count: 1, queued_count: 1,
      deferred_counts: { "account_rate" => 1, "campaign_rate" => 1 })
    2.times do
      post "#{base}/campaigns/#{campaign.id}/cancel.json", as: :json
      expect(response).to have_http_status(:ok), response.body
    end
    expect(campaign.reload).to have_attributes(status: "cancelled", run_token: nil)
    expect(queued.reload).to have_attributes(status: "suppressed", dispatch_started_at: nil, delivery_attempts: 0)
    expect(campaign.recipients.find_by!(message_id: first.id).status).to eq("admitted")
    travel 16.minutes
    Sms::Campaigns::RunJob.new.perform(customer.id, campaign.id, stale_token)
    Sms::Campaigns::SchedulerJob.new.perform
    Sms::Cron::RecoverMessages.call
    Sms::DeliverMessageJob.new.perform(queued.id)
    receipt(first)
    Sms::Campaigns::RefreshStatsJob.new.perform(customer.id, campaign.id)
    expect(campaign.reload.status).to eq("cancelled")
    expect(report(campaign)).to include(matched_count: 3, admitted_count: 2, attempted_count: 1, api_accepted_count: 1,
      delivered_count: 1, suppressed_count: 1, cancelled_count: 2, pending_count: 0,
      skip_counts: { "campaign_cancelled" => 2 }, deferred_counts: {}, delivery_rate: 1.0)
    expect(WebMock).to have_requested(:post, messages_url).once
  end

  it "defers eligible quiet-hour recipients, resumes at the boundary and expires lost queued work at the original deadline" do
    travel_to(Time.utc(2026, 10, 13, 0, 30)) # 08:30 in the recipient's zone.
    2.times { new_contact }
    campaign = review_and_launch(save_draft(deadline_hours: 1))
    expiry = Time.utc(2026, 10, 13, 1, 30)
    scheduler_and_worker(campaign)
    expect(campaign.expires_at).to eq(expiry)
    expect(campaign.recipients.pluck(:status, :deferral_reason, :delivery_due_at)).to eq([
      ["pending", "quiet_hours", Time.utc(2026, 10, 13, 1)], ["pending", "quiet_hours", Time.utc(2026, 10, 13, 1)]
    ])
    expect(report(campaign)).to include(eligible_at_start_count: 2, pending_count: 2, skipped_count: 0, deferred_counts: { "quiet_hours" => 2 })
    Sms::Campaigns::RunJob.new.perform(customer.id, campaign.id, campaign.run_token)
    Sms::Cron::RecoverMessages.call
    expect(campaign.messages.count).to eq(0)
    travel_to(Time.utc(2026, 10, 13, 1))
    scheduler_and_worker(campaign)
    first, lost = campaign.messages.order(:id).to_a
    expect(campaign.messages.pluck(:expires_at)).to eq([expiry, expiry])
    Sms::DeliverMessageJob.new.perform(first.id)
    clear_enqueued_jobs
    travel_to(expiry)
    Sms::Cron::RecoverMessages.call
    Sms::DeliverMessageJob.new.perform(lost.id)
    scheduler_and_worker(campaign)
    expect(lost.reload).to have_attributes(status: "expired", expires_at: expiry, dispatch_started_at: nil, delivery_attempts: 0)
    expect(campaign.reload).to have_attributes(status: "completed", expires_at: expiry)
    expect(report(campaign)).to include(admitted_count: 2, attempted_count: 1, expired_count: 1,
      pending_count: 0, skip_counts: { "campaign_expired" => 1 }, deferred_counts: {})
    expect(WebMock).to have_requested(:post, messages_url).once
  end

  it "quarantines an ambiguous SDK acceptance across lease recovery and repairs delivery without a duplicate external attempt" do
    new_contact
    campaign = review_and_launch(save_draft)
    scheduler_and_worker(campaign)
    message = campaign.messages.sole
    token = campaign.run_token
    stub_request(:post, messages_url).to_return(status: 201, body: { sid: "SMambiguous", status: [] }.to_json)
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload).to have_attributes(status: "unknown", vendor_message_id: "SMambiguous",
      dispatch_started_at: Time.current, delivery_attempts: 1, sent_at: nil)
    clear_enqueued_jobs
    travel 16.minutes
    Sms::Campaigns::RunJob.new.perform(customer.id, campaign.id, token)
    Sms::Cron::RecoverMessages.call
    scheduler_and_worker(campaign)
    2.times { Sms::DeliverMessageJob.new.perform(message.id) }
    expect(campaign.reload.status).to eq("completed")
    expect(report(campaign)).to include(attempted_count: 1, api_accepted_count: 0, unknown_count: 1, failed_count: 0, delivered_count: 0)
    original_ids = campaign.recipients.pluck(:id, :message_id)
    2.times { receipt(message, segments: "3") }
    Sms::Campaigns::RefreshStatsJob.new.perform(customer.id, campaign.id)
    expect(message.reload).to have_attributes(status: "delivered", delivery_attempts: 1, sent_at: nil)
    expect(campaign.recipients.pluck(:id, :message_id)).to eq(original_ids)
    expect(report(campaign)).to include(attempted_count: 1, api_accepted_count: 0, unknown_count: 0, delivered_count: 1,
      provider_segments_total: 3, provider_segments_missing_count: 0, delivery_rate: 1.0)
    expect(WebMock).to have_requested(:post, messages_url).once
  end

  it "reconciles an authenticated callback arriving before SDK acceptance onto the sole campaign message" do
    new_contact
    campaign = review_and_launch(save_draft)
    scheduler_and_worker(campaign)
    message = campaign.messages.sole
    stub_provider do |call|
      signed_callback("delivery", "MessageSid" => call.fetch("sid"), "MessageStatus" => "delivered",
        "To" => call.fetch("to"), "NumSegments" => "2", "DateUpdated" => Time.current.iso8601)
      expect(message.reload).to have_attributes(status: "queued", vendor_message_id: nil, delivery_attempts: 1)
      expect(Sms::BackendReceipt.sole.processed_at).to be_nil
    end
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload).to have_attributes(status: "delivered", sent_at: Time.current, delivered_at: Time.current, delivery_attempts: 1)
    expect(Sms::BackendReceipt.sole).to have_attributes(customer_id: customer.id, processed_at: Time.current)
    Sms::Campaigns::RefreshStatsJob.new.perform(customer.id, campaign.id)
    expect(report(campaign)).to include(admitted_count: 1, attempted_count: 1, api_accepted_count: 1,
      delivered_count: 1, provider_segments_total: 2, delivery_rate: 1.0)
    expect(campaign.messages.count).to eq(1)
    expect(WebMock).to have_requested(:post, messages_url).once
  end

  it "keeps a generated unsubscribe link read-only until a CSRF-protected POST and blocks its queued marketing dispatch" do
    contact = new_contact
    other = create(:customer)
    other_actor = create(:user, :admin, customer: other)
    foreign = new_contact(customer: other, actor: other_actor, phone_e164: contact.phone_e164)
    campaign = review_and_launch(save_draft)
    scheduler_and_worker(campaign)
    recipient = campaign.recipients.sole
    path = URI.parse(recipient.vars.fetch("opt_out_url")).path
    sign_out actor
    browser_csrf do
      expect_read_only { get path, params: { customer_id: other.id, contact_id: foreign.id } }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(contact.phone_e164)
      csrf = confirmation_csrf
      expect_read_only { head path }
      expect(response).to have_http_status(:ok)
      expect_read_only { post path }
      expect(response).to have_http_status(:unprocessable_content)
      expect(contact.reload.consent_status).to eq("granted")
      event_count = Sms::ConsentEvent.count
      2.times do
        post path, params: { authenticity_token: csrf, customer_id: other.id, contact_id: foreign.id, phone: foreign.phone_e164 }
        expect(response).to have_http_status(:ok), response.body
      end
      expect(Sms::ConsentEvent.count).to eq(event_count + 1)
    end
    expect(contact.reload.consent_status).to eq("revoked")
    expect(foreign.reload.consent_status).to eq("granted")
    expect(Sms::OptOut.where(phone_e164: contact.phone_e164).pluck(:customer_id)).to eq([customer.id])
    Sms::DeliverMessageJob.new.perform(recipient.message_id)
    expect(recipient.message.reload).to have_attributes(status: "suppressed", delivery_attempts: 0, dispatch_started_at: nil)
    expect(report(campaign)).to include(eligible_at_start_count: 1, admitted_count: 1, attempted_count: 0,
      suppressed_count: 1, skip_counts: { "consent_missing" => 1 })
    expect(WebMock).not_to have_requested(:post, messages_url)
  end

  it "uses the tenant-resolved Entity mapping and scopes an old campaign link after sync changes the phone and fresh consent is recorded" do
    schema = [{ "name" => "Mobile", "name_slug" => "mobile", "html_type" => "tel" },
      { "name" => "Name", "name_slug" => "full_name", "html_type" => "text" }]
    source = create(:entity, :shared, property_schema: schema.to_json)
    Current.set(customer: customer, shared_resources_mode: false) do
      source.property_schema_json = schema.map { |field| field["name_slug"] == "mobile" ? field.merge("name_slug" => "tenant_mobile") : field }
      source.commit_version!
    end
    original_phone = build(:sms_contact).phone_e164
    replacement_phone = build(:sms_contact).phone_e164
    entry = Current.set(customer: customer, shared_resources_mode: false) do
      create(:entity_entry, entity: source.reload, customer: customer, data: { "tenant_mobile" => original_phone, "full_name" => "Synced name" }.to_json)
    end
    other = create(:customer)
    other_actor = create(:user, :admin, customer: other)
    Current.set(customer: other, shared_resources_mode: false) do
      create(:entity_entry, entity: source.reload, customer: other, data: { "mobile" => original_phone, "full_name" => "Foreign entry" }.to_json)
    end
    foreign = new_contact(customer: other, actor: other_actor, phone_e164: original_phone)
    sync_input = { entity_id: source.id, phone_field: "tenant_mobile", name_field: "full_name", country_code: "CN", timezone: "Asia/Shanghai", attribute_map: {} }
    expect_read_only do
      preview = value!(Sms::Contacts::SyncEntity.call(customer: customer, actor: actor, attributes: sync_input, preview: true))
      expect(preview).to include(scanned: 1, created: 1)
    end
    value!(Sms::Contacts::SyncEntity.call(customer: customer, actor: actor, attributes: sync_input))
    contact = Sms::Contact.find_by!(customer_id: customer.id, source_entry_id: entry.id)
    expect(contact.consent_status).to eq("unknown")
    record_consent(contact)
    campaign = review_and_launch(save_draft(variable_map: mapping.merge("offer" => { "source" => "literal", "value" => "20%" })))
    scheduler_and_worker(campaign)
    recipient = campaign.recipients.sole
    path = URI.parse(recipient.vars.fetch("opt_out_url")).path
    Current.set(customer: customer, shared_resources_mode: false) do
      entry.reload.update!(data: { "tenant_mobile" => replacement_phone, "full_name" => "Changed source" }.to_json)
    end
    sync = value!(Sms::Contacts::SyncEntity.call(customer: customer, actor: actor, attributes: sync_input))
    expect(sync).to include(scanned: 1, updated: 1)
    expect(contact.reload).to have_attributes(phone_e164: replacement_phone, consent_status: "unknown", consent_changed_at: nil)
    record_consent(contact)
    projection = contact.attributes.slice("consent_status", "consent_changed_at", "lock_version")
    sign_out actor
    browser_csrf do
      expect_read_only { get path, params: { customer_id: other.id, phone: replacement_phone } }
      csrf = confirmation_csrf
      2.times do
        post path, params: { authenticity_token: csrf, customer_id: other.id, contact_id: foreign.id, phone: replacement_phone }
        expect(response).to have_http_status(:ok), response.body
      end
    end
    expect(contact.reload.attributes.slice(*projection.keys)).to eq(projection)
    event = contact.consent_events.find_by!(source: "recipient_unsubscribe")
    expect(event).to have_attributes(customer_id: customer.id, phone_e164: original_phone, action: "revoked", actor_user_id: nil)
    expect(Sms::OptOut.where(phone_e164: [original_phone, replacement_phone]).pluck(:customer_id, :phone_e164)).to eq([[customer.id, original_phone]])
    expect(foreign.reload.consent_status).to eq("granted")
    expect(recipient.reload.phone_e164).to eq(original_phone)
    expect(recipient.vars).to include("name" => "Synced name")
    Sms::DeliverMessageJob.new.perform(recipient.message_id)
    expect(recipient.message.reload).to have_attributes(to: original_phone, status: "suppressed", dispatch_started_at: nil, delivery_attempts: 0)
    expect(report(campaign)).to include(admitted_count: 1, attempted_count: 0, suppressed_count: 1, skip_counts: { "phone_changed" => 1 })
    expect(WebMock).not_to have_requested(:post, messages_url)
  end

  it "exports filtered historical ledger names with formula escaping and tenant isolation rather than mutable contact data" do
    names = ["=Offer%_", "+Offer%_", "-Offer%_", "@Offer%_", "\tOffer%_", "\uFEFF =Offer%_", "OfferXY"]
    contacts = names.map { |name| new_contact(name: name) }
    campaign = review_and_launch(save_draft)
    scheduler_and_worker(campaign)
    messages = campaign.messages.order(:id).to_a
    messages.each_with_index do |message, index|
      travel 1.second if index.positive?
      Sms::DeliverMessageJob.new.perform(message.id)
      receipt(message.reload, status: index == names.size - 1 ? "undelivered" : "delivered")
    end
    contacts.each { |contact| change_contact(contact, name: "Renamed safely") }
    other = create(:customer)
    other_actor = create(:user, :admin, customer: other)
    enable_module!("sms", other, name: "SMS")
    new_contact(customer: other, actor: other_actor, name: "=Offer%_ FOREIGN")
    foreign_campaign = value!(Sms::Campaigns::Save.call(customer: other, actor: other_actor,
      attributes: { name: "Foreign campaign", template_id: template.id, variable_map: mapping }))
    foreign_preview = value!(Sms::Campaigns::Preview.call(customer: other, actor: other_actor, campaign: foreign_campaign))
    value!(Sms::Campaigns::Launch.call(customer: other, actor: other_actor, campaign: foreign_campaign,
      lock_version: foreign_campaign.lock_version, review_token: foreign_preview[:review_token]))
    scheduler_and_worker(foreign_campaign)
    stats_before = campaign.reload.attributes.slice("stats", "stats_refreshed_at", "lock_version")
    expect_read_only do
      get "#{base}/campaigns/#{campaign.id}/report.csv", params: { q: "%_", status: "admitted", message_status: "delivered", page: 2, per_page: 1 }
    end
    expect(response).to have_http_status(:ok), response.body
    rows = CSV.parse(response.body, headers: true)
    expect(rows.size).to eq(6)
    expect(rows.map { |row| row.fetch("Name") }).to eq(names.first(6).map { |name| "'#{name}" })
    expect(rows.map { |row| row.fetch("Recipient ID").to_i }).to eq(campaign.recipients.order(:id).limit(6).pluck(:id))
    expect(rows.map { |row| row.fetch("Campaign ID").to_i }.uniq).to eq([campaign.id])
    expect(rows.map { |row| row.fetch("Phone") }).to eq(contacts.first(6).map { |contact| "'#{contact.phone_e164}" })
    expect(response.body).not_to include("FOREIGN", "Renamed safely", "/sms/unsubscribes/", "QA_AUTH_TOKEN", "HX_QA_APPROVED")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(campaign.reload.attributes.slice(*stats_before.keys)).to eq(stats_before)
    expect_read_only { get "#{base}/campaigns/#{foreign_campaign.id}/report.csv", params: { q: "%_", message_status: "queued" } }
    expect(response).to have_http_status(:not_found)
  end
end
