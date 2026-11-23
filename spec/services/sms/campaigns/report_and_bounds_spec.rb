# frozen_string_literal: true

require "rails_helper"
require_relative "helpers"

RSpec.describe "SMS campaign frozen audiences, reports and bounds" do
  include_context "SMS campaign engine"

  it "captures more than one worker batch atomically but admits only the specified bounded batch" do
    rows = 101.times.map do |index|
      { customer_id: customer.id, phone_e164: "+861390013#{index.to_s.rjust(4, '0')}", name: "Contact #{index}",
        consent_status: "granted", created_at: Time.current, updated_at: Time.current }
    end
    Sms::Contact.insert_all!(rows)
    campaign = launch_campaign
    expect(run_campaign(campaign, limit: 25)[:processed_count]).to eq(25)
    expect(campaign.recipients.count).to eq(102)
    expect(campaign.messages.count).to eq(25)
    expect(campaign.recipients.where(status: "pending").count).to eq(77)
    expect(run_campaign(campaign, limit: 200)[:processed_count]).to eq(77)
    expect(campaign.messages.count).to eq(60)
    expect(campaign.recipients.where(deferral_reason: "campaign_rate").count).to eq(42)
  end

  it "freezes segment rules/type specs at launch and evaluates contacts once at scheduled start" do
    contact.update!(custom_attributes: { "vip" => false })
    extra = Sms::Contact.create!(customer: customer, phone_e164: "+8613800138001", name: "VIP", consent_status: "granted", custom_attributes: { "vip" => true })
    rules = { "type" => "group", "conditions" => [{ "field" => "attributes.vip", "operator" => "equals", "value" => true }], "joins" => [] }
    segment = Sms::Audience::Segment.create!(customer: customer, name: "VIP", segment_rules: rules)
    campaign = launch_campaign(save_campaign(segment_id: segment.id, send_timing: "scheduled", scheduled_at: 1.hour.from_now))
    expect(campaign.audience_snapshot["field_specs"]).to eq("attributes.vip" => "boolean")
    contact.update!(custom_attributes: { "vip" => true })
    extra.update!(custom_attributes: { "vip" => "true" })
    segment.update!(segment_rules: {})
    travel 1.hour
    run_campaign(campaign)
    expect(campaign.recipients.pluck(:contact_id)).to eq([contact.id])
    expect(campaign.audience_snapshot["segment_rules"]).to eq(rules)
  end

  it "keeps selected samples outside the segment within five without changing audience counts" do
    segment = Sms::Audience::Segment.create!(customer: customer, name: "Nobody", segment_rules:
      { "conditions" => [{ "field" => "name", "operator" => "equals", "value" => "Nobody" }], "joins" => [] })
    campaign = save_campaign(segment_id: segment.id)
    preview = Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign, contact_id: contact.id).value
    expect(preview).to include(matched_count: 0, eligible_count: 0)
    expect(preview[:samples].first).to include(contact_id: contact.id, reason: :outside_audience, eligible: false)
    other_contact = Sms::Contact.create!(customer: create(:customer), phone_e164: contact.phone_e164)
    expect(Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign, contact_id: other_contact.id).code).to eq(:not_found)
  end

  it "defers determinable daily capacity without presenting it as a permanent skip" do
    transactional = create(:sms_template)
    Sms::Gateway.send(customer: customer, to: "+8613800138001", template_key: transactional.key, vars: { code: "1", minutes: 5 })
    campaign = launch_campaign(save_campaign(deadline_hours: 48))
    allow(Sms::Activities::Send).to receive(:daily_cap_for).and_return(1)
    run_campaign(campaign)
    recipient = campaign.recipients.first!
    expect(recipient).to have_attributes(status: "pending", skip_reason: nil, deferral_reason: "daily_cap", delivery_due_at: Time.current.next_day.beginning_of_day)
    report = Sms::Campaigns::Report.call(customer: customer, campaign: campaign).value
    expect(report).to include(pending_count: 1, skipped_count: 0, deferred_counts: { "daily_cap" => 1 }, skip_counts: {})
  end

  it "fails closed on invalid frozen rules before any recipient or admission exists" do
    campaign = launch_campaign
    campaign.update!(audience_snapshot: campaign.audience_snapshot.merge("segment_rules" => { "unexpected" => "all" }))
    run_campaign(campaign)
    expect(campaign.reload).to have_attributes(status: "failed", failure_code: "template_invalid", started_at: nil)
    expect(campaign.recipients.count).to eq(0)
    expect(campaign.messages.count).to eq(0)
  end

  it "reports historical milestones separately from current outcomes and never persists from GET-style reads" do
    campaign = launch_campaign
    run_campaign(campaign)
    message = campaign.messages.first!
    before = campaign.reload.attributes
    report = Sms::Campaigns::Report.call(customer: customer, campaign: campaign).value
    expect(report).to include(matched_count: 1, eligible_at_start_count: 1, admitted_count: 1, queued_count: 1,
      attempted_count: 0, delivery_rate: nil, provider_segments_missing_count: 1)
    expect(campaign.reload.attributes).to eq(before)
    Sms::DeliverMessageJob.new.perform(message.id)
    Sms::DeliveryProjection.apply!(message: message, event: { status: :delivered, segments: 2, raw: {} })
    Sms::Campaigns::RefreshStatsJob.new.perform(customer.id, campaign.id)
    expect(campaign.reload.status).to eq("completed")
    report = Sms::Campaigns::Report.call(customer: customer, campaign: campaign).value
    expect(report).to include(attempted_count: 1, api_accepted_count: 1, delivered_count: 1, queued_count: 0,
      provider_segments_total: 2, provider_segments_missing_count: 0, delivery_rate: 1.0)
    expect(campaign.stats).to include("delivered_count" => 1, "snapshot_at" => campaign.started_at.utc.iso8601(6))
    expect(Sms::Campaigns::Report.call(customer: create(:customer), campaign: campaign).code).to eq(:not_found)
    expect(Sms::Campaigns::Cancel.call(customer: customer, actor: actor, campaign: campaign).code).to eq(:cannot_cancel)
  end

  it "keeps transient queue failures recoverable by the one-minute scheduler with the current lease" do
    campaign = launch_campaign
    run_campaign(campaign)
    token = campaign.reload.run_token
    message = campaign.messages.first!
    clear_enqueued_jobs
    travel 61.seconds
    Sms::Campaigns::SchedulerJob.new.perform
    expect(campaign.reload.run_token).to eq(token)
    expect(enqueued_jobs.any? { |job| job[:job] == Sms::DeliverMessageJob && job[:args] == [message.id] }).to be(true)
    expect(enqueued_jobs.any? { |job| job[:job] == Sms::Campaigns::RunJob && job[:args] == [customer.id, campaign.id, token] }).to be(true)
  end

  it "has matching English/Chinese campaign validation keys and interpolation variables" do
    flatten = ->(hash, prefix = "") do
      hash.each_with_object({}) do |(key, value), result|
        value.is_a?(Hash) ? result.merge!(flatten.call(value, "#{prefix}#{key}.")) : result["#{prefix}#{key}"] = value
      end
    end
    en = flatten.call(YAML.load_file(Rails.root.join("config/locales/sms_campaigns.en.yml"))["en"])
    zh = flatten.call(YAML.load_file(Rails.root.join("config/locales/sms_campaigns.zh-CN.yml"))["zh-CN"])
    expect(en.keys.sort).to eq(zh.keys.sort)
    en.each { |key, value| expect(value.scan(/%\{([^}]+)\}/)).to eq(zh.fetch(key).scan(/%\{([^}]+)\}/)) }
  end
end
