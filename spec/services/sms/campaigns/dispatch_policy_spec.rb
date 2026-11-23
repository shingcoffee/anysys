# frozen_string_literal: true

require "rails_helper"
require_relative "helpers"

RSpec.describe "SMS marketing dispatch and shared account clock" do
  include_context "SMS campaign engine"

  def direct_send(**options)
    Sms::Gateway.send(**{ customer: customer, to: contact.phone_e164, template_key: template.key,
      vars: { "name" => "Alice", "opt_out_url" => "https://example.com/unsubscribe" } }.merge(options))
  end

  it "requires positive consent on the exact active tenant contact for all direct marketing admission" do
    contact.update!(consent_status: "unknown")
    expect { direct_send }.to raise_error(Sms::Errors::MarketingIneligible) { |error| expect(error.reason).to eq(:consent_missing) }
    other = create(:customer)
    Sms::Contact.create!(customer: other, phone_e164: contact.phone_e164, consent_status: "granted")
    expect { direct_send }.to raise_error(Sms::Errors::MarketingIneligible)
    contact.update!(consent_status: "granted", status: "archived")
    expect { direct_send }.to raise_error(Sms::Errors::MarketingIneligible) { |error| expect(error.reason).to eq(:contact_archived) }
    contact.update!(status: "active")
    expect(direct_send).to have_attributes(contact_id: contact.id, campaign_id: nil, status: "queued")
  end

  it "cannot bypass permission by passing a modified template to the lower-level persistence helper" do
    contact.update!(consent_status: "unknown")
    template.purpose = "transactional"
    request = Sms::MessageAdmission.new(to: contact.phone_e164, template_key: template.key,
      vars: { "name" => "Alice", "opt_out_url" => "https://example.com/unsubscribe" })
    expect { request.persist(customer: customer, template: template, credential: credential) }.to raise_error(Sms::Errors::MarketingIneligible)
    expect(Sms::Message.count).to eq(0)
  end

  %i[revoke archive change_phone].each do |action|
    it "blocks direct marketing #{action} after preparation at the synchronized final-start gate" do
      message = direct_send
      allow(Sms::DeliveryDispatch).to receive(:template_for).and_wrap_original do |method, record|
        case action
        when :revoke
          Sms::Contacts::EvidenceWriter.call(customer: customer, contact: contact, phone_e164: contact.phone_e164,
            action: "revoked", source: "recipient_unsubscribe", occurred_at: Time.current, evidence: {}, event_key: "revoke")
        when :archive then contact.update!(status: "archived")
        when :change_phone then contact.update!(phone_e164: "+8613800138001")
        end
        method.call(record)
      end
      expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
      Sms::DeliverMessageJob.new.perform(message.id)
      expect(message.reload).to have_attributes(status: "suppressed", dispatch_started_at: nil, delivery_attempts: 0)
      expect(credential.reload.dispatch_next_at).to be_nil
    end
  end

  it "paces direct transactional and campaign starts through one shared account clock across tenants" do
    campaign = launch_campaign
    run_campaign(campaign)
    marketing = campaign.messages.first!
    transactional = create(:sms_template)
    other = create(:customer)
    enable_module!("sms", other, name: "SMS")
    direct = Sms::Gateway.send(customer: other, to: "+8613800138001", template_key: transactional.key, vars: { code: "1", minutes: 5 })
    Sms::DeliverMessageJob.new.perform(direct.id)
    expect(direct.reload.status).to eq("sent")
    first_clock = credential.reload.dispatch_next_at
    expect(first_clock).to eq(1.second.from_now)
    Sms::DeliverMessageJob.new.perform(marketing.id)
    expect(marketing.reload).to have_attributes(status: "queued", dispatch_started_at: nil, delivery_due_at: first_clock, delivery_attempts: 0)
    expect(campaign.recipients.first).to have_attributes(deferral_reason: "account_rate", skip_reason: nil)
    expect(credential.reload.dispatch_next_at).to eq(first_clock)
    expect(Sms::DeliveryDispatch.claim(marketing.id)).to be_nil
    expect(enqueued_jobs.any? { |job| job[:job] == Sms::DeliverMessageJob && job[:args] == [marketing.id] && job[:at] == first_clock.to_f }).to be(true)
    travel_to(first_clock)
    Sms::DeliverMessageJob.new.perform(marketing.id)
    expect(marketing.reload).to have_attributes(status: "sent", delivery_attempts: 1)
    expect(campaign.recipients.first.deferral_reason).to be_nil
    expect(credential.reload.dispatch_next_at).to eq(1.second.from_now)
  end

  it "uses the live lower account ceiling and never advances it for a lost preparation owner" do
    credential.write_config("sender_rate_per_second" => 0.5)
    credential.save!
    message = direct_send
    claimed, token = Sms::DeliveryDispatch.claim(message.id)
    decision = Sms::DispatchLimiter.acquire(credential: credential, message: claimed, claim_token: "lost", at: Time.current)
    expect(decision[:action]).to eq(:lost_claim)
    expect(credential.reload.dispatch_next_at).to be_nil
    decision = Sms::DispatchLimiter.acquire(credential: credential, message: claimed, claim_token: token, at: Time.current)
    expect(decision).to include(action: :started, attempt_started_at: Time.current)
    expect(credential.reload.dispatch_next_at).to eq(2.seconds.from_now)
  end

  it "does not backdate an authorization after waiting for a lock" do
    message = direct_send(expires_at: 2.minutes.from_now)
    claimed, token = Sms::DeliveryDispatch.claim(message.id)
    earlier = Time.current
    travel 10.seconds
    decision = Sms::DispatchLimiter.acquire(credential: credential, message: claimed, claim_token: token, at: earlier)
    expect(decision).to include(action: :started, attempt_started_at: Time.current)
    expect(credential.reload.dispatch_next_at).to eq(1.second.from_now)
  end

  it "expires an account-delayed message beyond its fixed TTL without reserving a future slot" do
    message = direct_send(expires_at: 1.minute.from_now)
    credential.update!(dispatch_next_at: 2.minutes.from_now)
    existing_clock = credential.dispatch_next_at
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload).to have_attributes(status: "expired", dispatch_started_at: nil, delivery_attempts: 0)
    expect(credential.reload.dispatch_next_at).to eq(existing_clock)
  end

  it "rechecks cancellation after preparation and retains the typed ledger reason" do
    campaign = launch_campaign
    run_campaign(campaign)
    message = campaign.messages.first!
    allow(Sms::DeliveryDispatch).to receive(:template_for).and_wrap_original do |method, record|
      Sms::Campaigns::Cancel.call(customer: customer, actor: actor, campaign: campaign)
      method.call(record)
    end
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload).to have_attributes(status: "suppressed", dispatch_started_at: nil)
    expect(campaign.recipients.first.skip_reason).to eq("campaign_cancelled")
  end

  it "uses attempts rather than API acceptance/delivery for another campaign's frequency cap" do
    first = launch_campaign
    run_campaign(first)
    second = launch_campaign
    run_campaign(second)
    attempted = first.messages.first!
    claimed, token = Sms::DeliveryDispatch.claim(attempted.id)
    expect(Sms::DeliveryDispatch.start(claimed, token)).to be(true)
    expect(attempted.reload.sent_at).to be_nil
    other = second.messages.first
    # Foundation phone-window quota may have deferred this second admission.
    if other.nil?
      travel 61.seconds
      run_campaign(second)
      expect(second.recipients.first.skip_reason).to eq("frequency_capped")
    else
      Sms::DeliverMessageJob.new.perform(other.id)
      expect(other.reload.status).to eq("suppressed")
      expect(second.recipients.first.skip_reason).to eq("frequency_capped")
    end
  end

  it "keeps future due rows out of claims and recovery without moving their fixed expiry" do
    message = direct_send(expires_at: 20.minutes.from_now)
    expiry = message.expires_at
    message.reload.update!(delivery_due_at: 5.minutes.from_now, delivery_enqueued_at: nil)
    expect(Sms::DeliveryDispatch.claim(message.id)).to be_nil
    clear_enqueued_jobs
    Sms::Cron::RecoverMessages.call
    expect(enqueued_jobs).to be_empty
    Sms::DeliveryHandoff.call(message)
    expect(enqueued_jobs.last[:at]).to eq(message.delivery_due_at.to_f)
    expect(message.reload.expires_at).to eq(expiry)
  end

  it "handles overnight and same-day quiet windows at exact boundaries and DST transitions" do
    window = Sms::Campaigns::QuietWindow
    expect(window.next_allowed(at: Time.utc(2026, 10, 13, 1), timezone: "Asia/Shanghai", start_hour: 21, end_hour: 9)).to eq(Time.utc(2026, 10, 13, 1))
    expect(window.next_allowed(at: Time.utc(2026, 10, 13, 13), timezone: "Asia/Shanghai", start_hour: 21, end_hour: 9)).to eq(Time.utc(2026, 10, 14, 1))
    expect(window.next_allowed(at: Time.utc(2026, 10, 13, 3), timezone: "Asia/Shanghai", start_hour: 10, end_hour: 12)).to eq(Time.utc(2026, 10, 13, 4))
    # Quiet hours ending in the spring gap advance to 03:00, not 03:30.
    expect(window.next_allowed(at: Time.utc(2026, 3, 8, 6), timezone: "America/New_York", start_hour: 21, end_hour: 2)).to eq(Time.utc(2026, 3, 8, 7))
    # Repeated fall hour: choose the earliest future occurrence of the end.
    expect(window.next_allowed(at: Time.utc(2026, 11, 1, 4, 30), timezone: "America/New_York", start_hour: 21, end_hour: 1)).to eq(Time.utc(2026, 11, 1, 5))
  end
end
