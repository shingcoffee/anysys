# frozen_string_literal: true

require "rails_helper"
require_relative "helpers"

RSpec.describe "SMS campaign execution" do
  include_context "SMS campaign engine"

  it "captures the complete audience once, excludes unknown consent forever and freezes destinations/vars" do
    unknown = Sms::Contact.create!(customer: customer, phone_e164: "+8613800138001", name: "Unknown")
    campaign = launch_campaign
    outcome = run_campaign(campaign, limit: 1)
    expect(outcome).to include(processed_count: 1, has_more: true)
    expect(campaign.reload).to have_attributes(status: "running", started_at: Time.current)
    expect(campaign.recipients.count).to eq(2)
    recipient = campaign.recipients.find_by!(contact_id: contact.id)
    excluded = campaign.recipients.find_by!(contact_id: unknown.id)
    expect(excluded).to have_attributes(status: "skipped", skip_reason: "consent_missing", message_id: nil)
    expect(recipient).to have_attributes(status: "admitted", admitted_at: Time.current)
    expect(recipient.message).to have_attributes(campaign_id: campaign.id, contact_id: contact.id, expires_at: campaign.expires_at)
    expect(recipient.message.idempotency_key).to eq("sms-campaign:#{campaign.id}:recipient:#{recipient.id}")
    unknown.update!(consent_status: "granted")
    contact.update!(name: "Later name")
    Sms::Contact.create!(customer: customer, phone_e164: "+8613800138002", name: "New", consent_status: "granted")
    run_campaign(campaign)
    expect(campaign.recipients.count).to eq(2)
    expect(recipient.reload.vars["name"]).to eq("Alice")
    expect(excluded.reload.message_id).to be_nil
    expect(Sms::Gateway.send_campaign(customer: customer, recipient: recipient).id).to eq(recipient.message_id)
    expect(Sms::Message.count).to eq(1)
  end

  it "uses launch-pinned remote content after owner retirement and provider reassignment" do
    campaign = launch_campaign
    template.update!(status: "retired", purpose: "transactional", variables: ["changed"], body_template: nil, provider_template_codes: { "twilio" => "NEW" })
    credential.update!(status: "disabled")
    create(:sms_credential, provider: "twilio", config: { "from" => "+14155550000" })
    run_campaign(campaign)
    message = campaign.messages.first!
    expect(message.metadata["template_snapshot"]).to include("purpose" => "marketing", "provider_code" => "SMS_12345678", "required_vars" => %w[name opt_out_url])
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message) do |_adapter, template:, **_args|
      expect(template.provider_code("aliyun")).to eq("SMS_12345678")
      { vendor_message_id: "pinned", raw: {} }
    end
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload.status).to eq("sent")
  end

  it "fences stale run tokens and duplicates without a second audience or message" do
    campaign = launch_campaign
    token = claim_campaign(campaign)
    expect(run_campaign(campaign, token: "stale")).to eq(processed_count: 0, has_more: false, next_run_at: nil)
    expect(campaign.recipients.count).to eq(0)
    run_campaign(campaign, token: token)
    run_campaign(campaign, token: token)
    expect(campaign.recipients.count).to eq(1)
    expect(campaign.messages.count).to eq(1)
  end

  it "rolls back the entire audience snapshot and started_at on an insertion failure then recovers" do
    campaign = launch_campaign
    claim_campaign(campaign)
    allow(Sms::CampaignRecipient).to receive(:insert_all!).and_wrap_original do |method, rows|
      method.call(rows)
      raise ActiveRecord::StatementInvalid, "interrupted"
    end
    expect { run_campaign(campaign) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(campaign.reload.started_at).to be_nil
    expect(campaign.recipients.count).to eq(0)
    allow(Sms::CampaignRecipient).to receive(:insert_all!).and_call_original
    expect(run_campaign(campaign)[:processed_count]).to eq(1)
  end

  it "serializes rolling campaign admissions, clears delay separately and does not slide expiry" do
    Sms::Contact.create!(customer: customer, phone_e164: "+8613800138001", name: "Bob", consent_status: "granted")
    campaign = launch_campaign(save_campaign(send_rate_per_minute: 1))
    expiry = campaign.expires_at
    run_campaign(campaign)
    deferred = campaign.recipients.find_by!(status: "pending")
    expect(deferred).to have_attributes(deferral_reason: "campaign_rate", skip_reason: nil)
    expect(campaign.messages.count).to eq(1)
    travel_to(Time.current + 61.seconds)
    run_campaign(campaign)
    expect(deferred.reload).to have_attributes(status: "admitted", deferral_reason: nil)
    expect(campaign.messages.count).to eq(2)
    expect(campaign.reload.expires_at).to eq(expiry)
  end

  it "enforces one rolling admission per minute for three contacts with the real advancing clock" do
    travel_back
    2.times do |index|
      Sms::Contact.create!(customer: customer, phone_e164: "+861380013800#{index + 1}", name: "Contact #{index}", consent_status: "granted")
    end
    quiet_start = (Time.current.utc.hour + 12) % 24
    campaign = launch_campaign(save_campaign(send_rate_per_minute: 1, timezone: "Etc/UTC",
      quiet_hours_start: quiet_start, quiet_hours_end: (quiet_start + 1) % 24))
    token = claim_campaign(campaign)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    outcome = Sms::Campaigns::Run.call(customer: customer, campaign: campaign, run_token: token)

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 60
    expect(outcome[:processed_count]).to eq(3)
    expect(campaign.messages.count).to eq(1)
    admitted = campaign.recipients.find_by!(status: "admitted")
    deferred = campaign.recipients.where(status: "pending").order(:id).to_a
    expect(deferred.size).to eq(2)
    deferred.each do |recipient|
      expect(recipient).to have_attributes(deferral_reason: "campaign_rate", skip_reason: nil, message_id: nil)
      expect(recipient.delivery_due_at).to be_within(0.000002.seconds).of(admitted.admitted_at + 60.seconds)
    end
  end

  it "keeps a supplied future clock consistent with admission reservations and rolling capacity" do
    Sms::Contact.create!(customer: customer, phone_e164: "+8613800138001", name: "Bob", consent_status: "granted")
    campaign = launch_campaign(save_campaign(send_rate_per_minute: 1))
    token = claim_campaign(campaign)
    later = Time.current + 1.minute

    outcome = Sms::Campaigns::Run.call(customer: customer, campaign: campaign, run_token: token, at: later)

    expect(outcome[:processed_count]).to eq(2)
    expect(campaign.messages.count).to eq(1)
    expect(campaign.recipients.find_by!(status: "admitted").admitted_at).to eq(later)
    expect(campaign.recipients.find_by!(status: "pending")).to have_attributes(deferral_reason: "campaign_rate", skip_reason: nil)
    expect(campaign.reload.run_lease_expires_at).to eq(later + Sms::Campaigns::Support::LEASE)
  end

  it "does not write an audience, heartbeat or message when the lease expires while acquiring the initial campaign lock" do
    campaign = launch_campaign
    token = claim_campaign(campaign)
    before = campaign.attributes
    clear_enqueued_jobs
    allow(campaign).to receive(:lock!).and_wrap_original do |method|
      method.call
      travel 16.minutes
    end

    outcome = Sms::Campaigns::Run.call(customer: customer, campaign: campaign, run_token: token)

    expect(outcome).to eq(processed_count: 0, has_more: false, next_run_at: nil)
    expect(campaign.reload.attributes).to eq(before)
    expect(campaign.recipients.count).to eq(0)
    expect(campaign.messages.count).to eq(0)
    expect(enqueued_jobs).to be_empty
  end

  it "renews a still-valid lease from the time the campaign lock was acquired" do
    campaign = launch_campaign
    token = claim_campaign(campaign)
    entered_at = Time.current
    waited = false
    allow(campaign).to receive(:lock!).and_wrap_original do |method|
      method.call
      unless waited
        waited = true
        travel 4.minutes
      end
    end

    Sms::Campaigns::Run.call(customer: customer, campaign: campaign, run_token: token)

    expect(campaign.reload.started_at).to eq(entered_at + 4.minutes)
    expect(campaign.heartbeat_at).to eq(Time.current)
    expect(campaign.run_lease_expires_at).to eq(Time.current + Sms::Campaigns::Support::LEASE)
  end

  it "rechecks the lease after acquiring contact and recipient locks before any recipient write" do
    2.times do |index|
      Sms::Contact.create!(customer: customer, phone_e164: "+861380013800#{index + 1}", name: "Contact #{index}", consent_status: "granted")
    end
    campaign = launch_campaign
    run_campaign(campaign, limit: 1)
    token = campaign.reload.run_token
    before = campaign.recipients.order(:id).map(&:attributes)
    before_stats = campaign.attributes.slice("stats", "stats_refreshed_at")
    waited = false
    allow_any_instance_of(Sms::CampaignRecipient).to receive(:lock!).and_wrap_original do |method|
      method.call
      unless waited
        waited = true
        travel 16.minutes
      end
    end

    outcome = Sms::Campaigns::Run.call(customer: customer, campaign: campaign, run_token: token)

    expect(outcome).to eq(processed_count: 0, has_more: false, next_run_at: nil)
    expect(campaign.recipients.order(:id).map(&:attributes)).to eq(before)
    expect(campaign.messages.count).to eq(1)
    expect(campaign.reload.attributes.slice("stats", "stats_refreshed_at")).to eq(before_stats)
  end

  it "does not complete or refresh stats after the lease expires while acquiring the completion lock" do
    campaign = launch_campaign
    run_campaign(campaign)
    token = campaign.reload.run_token
    message = campaign.messages.first!
    Sms::DeliverMessageJob.new.perform(message.id)
    before = campaign.attributes.slice("status", "stats", "stats_refreshed_at", "finished_at")
    locks = 0
    allow(campaign).to receive(:lock!).and_wrap_original do |method|
      method.call
      locks += 1
      travel 16.minutes if locks == 2
    end

    outcome = Sms::Campaigns::Run.call(customer: customer, campaign: campaign, run_token: token)

    expect(outcome).to eq(processed_count: 0, has_more: false, next_run_at: nil)
    expect(campaign.reload.attributes.slice("status", "stats", "stats_refreshed_at", "finished_at")).to eq(before)
    expect(message.reload.delivery_attempts).to eq(1)
  end

  it "rejects an expired job lease even when its supplied clock predates that expiry" do
    campaign = launch_campaign
    token = claim_campaign(campaign)
    campaign.update!(run_lease_expires_at: Time.current - 1.second)
    before = campaign.attributes

    outcome = Sms::Campaigns::Run.call(customer: customer, campaign: campaign, run_token: token, at: Time.current - 2.minutes)

    expect(outcome).to eq(processed_count: 0, has_more: false, next_run_at: nil)
    expect(campaign.reload.attributes).to eq(before)
    expect(campaign.recipients.count).to eq(0)
    expect(campaign.messages.count).to eq(0)
  end

  it "defers quiet hours to the recipient's IANA zone and expires delay beyond the absolute deadline" do
    contact.update!(timezone: "America/New_York")
    campaign = launch_campaign(save_campaign(deadline_hours: 1))
    run_campaign(campaign)
    expect(campaign.recipients.first).to have_attributes(status: "skipped", skip_reason: "campaign_expired", deferral_reason: nil)
    expect(campaign.messages.count).to eq(0)
    expect(campaign.reload.status).to eq("completed")
  end

  it "distinguishes zero daily allowance from a determinable next-day delay" do
    campaign = launch_campaign
    allow(Sms::Activities::Send).to receive(:daily_cap_for).and_return(0)
    run_campaign(campaign)
    expect(campaign.recipients.first.skip_reason).to eq("daily_cap_exceeded")
    expect(campaign.messages.count).to eq(0)
  end

  it "keeps orchestration running until queued messages are attempted, allowing cancellation before core start" do
    campaign = launch_campaign
    run_campaign(campaign)
    expect(campaign.reload.status).to eq("running")
    recipient = campaign.recipients.first!
    message = recipient.message
    expect(Sms::Campaigns::Cancel.call(customer: customer, actor: actor, campaign: campaign)).to be_success
    expect(message.reload).to have_attributes(status: "suppressed", dispatch_started_at: nil)
    expect(recipient.reload).to have_attributes(status: "cancelled", skip_reason: "campaign_cancelled", message_id: message.id)
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload.delivery_attempts).to eq(0)
    expect(Sms::Campaigns::Cancel.call(customer: customer, actor: actor, campaign: campaign)).to be_success
  end

  it "does not recall a durable attempt, and late delivery changes report counts after cancellation" do
    campaign = launch_campaign
    run_campaign(campaign)
    message = campaign.messages.first!
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(Sms::Campaigns::Cancel.call(customer: customer, actor: actor, campaign: campaign)).to be_success
    expect(campaign.recipients.first.status).to eq("admitted")
    Sms::DeliveryProjection.apply!(message: message, event: { status: :delivered, raw: {} })
    report = Sms::Campaigns::Report.call(customer: customer, campaign: campaign).value
    expect(report).to include(attempted_count: 1, api_accepted_count: 1, delivered_count: 1, cancelled_count: 0, delivery_rate: 1.0)
    expect(campaign.reload.status).to eq("cancelled")
  end

  it "expires a campaign before snapshot without sending or capturing membership" do
    campaign = launch_campaign(save_campaign(deadline_hours: 1))
    travel 2.hours
    run_campaign(campaign)
    expect(campaign.reload).to have_attributes(status: "failed", failure_code: "campaign_expired", started_at: nil)
    expect(campaign.recipients.count).to eq(0)
  end

  it "repairs a lost continuation enqueue with the current token and rotates only expired leases" do
    campaign = launch_campaign
    token = claim_campaign(campaign)
    clear_enqueued_jobs
    Sms::Campaigns::SchedulerJob.new.perform
    expect(campaign.reload.run_token).to eq(token)
    expect(enqueued_jobs.any? { |job| job[:job] == Sms::Campaigns::RunJob && job[:args] == [customer.id, campaign.id, token] }).to be(true)
    travel 16.minutes
    Sms::Campaigns::SchedulerJob.new.perform
    expect(campaign.reload.run_token).not_to eq(token)
  end

  it "runs the worker in the ledger tenant and restores an unrelated ambient tenant after a bounded continuation" do
    campaign = launch_campaign
    token = claim_campaign(campaign)
    unrelated = create(:customer)
    Current.customer = unrelated
    clear_enqueued_jobs
    Sms::Campaigns::RunJob.new.perform(customer.id, campaign.id, token)
    expect(campaign.recipients.count).to eq(1)
    expect(campaign.messages.first.customer_id).to eq(customer.id)
    expect(Current.customer).to eq(unrelated)
    expect(enqueued_jobs.any? { |job| job[:job] == Sms::Campaigns::RunJob && job[:args] == [customer.id, campaign.id, token] }).to be(true)
  end
end
