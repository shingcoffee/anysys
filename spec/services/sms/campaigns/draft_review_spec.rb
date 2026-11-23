# frozen_string_literal: true

require "rails_helper"
require_relative "helpers"

RSpec.describe "SMS campaign drafts and review" do
  include_context "SMS campaign engine"

  it "saves an incomplete draft without admission or enqueue and reports completion blockers" do
    expect(Sms::Gateway).not_to receive(:send_campaign)
    result = Sms::Campaigns::Save.call(customer: customer, actor: actor, attributes: { name: "Work in progress", send_timing: "scheduled" })
    expect(result).to be_success
    expect(result.value).to have_attributes(status: "draft", launched_at: nil)
    expect(enqueued_jobs).to be_empty
    preview = Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: result.value)
    expect(preview.value[:blockers]).to include(:template_required, :schedule_required)
    expect(preview.value[:review_token]).to be_nil
    expect(Sms::Message.count).to eq(0)
  end

  it "previews live consent, exclusions, personalized mirror and segments without writing any domain rows or jobs" do
    unknown = Sms::Contact.create!(customer: customer, phone_e164: "+8613800138001", name: "Unknown")
    Sms::Contact.create!(customer: customer, phone_e164: "+8613800138002", status: "archived", consent_status: "granted")
    campaign = save_campaign
    clear_enqueued_jobs
    counts = [Sms::Message.count, Sms::CampaignRecipient.count, Sms::ConsentEvent.count, Sms::OptOut.count]
    attributes = campaign.attributes
    preview = Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign, contact_id: unknown.id)
    expect(preview).to be_success
    expect(preview.value).to include(matched_count: 3, eligible_count: 1, excluded_counts: { consent_missing: 1, contact_archived: 1 })
    sample = preview.value[:samples].find { |item| item[:contact_id] == contact.id }
    expect(sample).to include(eligible: true, encoding: :gsm7)
    expect(sample[:rendered_body]).to start_with("Hello Alice. Unsubscribe: http://example.com/sms/unsubscribes/")
    expect(sample[:segments]).to be_positive
    expect(preview.value[:review_token]).to be_present
    expect([Sms::Message.count, Sms::CampaignRecipient.count, Sms::ConsentEvent.count, Sms::OptOut.count]).to eq(counts)
    expect(campaign.reload.attributes).to eq(attributes)
    expect(enqueued_jobs).to be_empty
  end

  it "previews unsaved changes but only mints a token for the exact saved draft" do
    campaign = save_campaign
    preview = Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign, attributes: { name: "Changed" })
    expect(preview).to be_success
    expect(preview.value[:review_token]).to be_nil
    expect(campaign.reload.name).to eq("Autumn offer")
  end

  it "uses variable-only previews when the provider mirror is absent" do
    template.update!(body_template: nil)
    preview = Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: save_campaign)
    expect(preview.value[:samples].first).to include(rendered_body: nil, encoding: nil, units: nil, segments: nil)
  end

  it "accepts partial maps for drafts and rejects unknown sources, fields, keys and over-limit settings" do
    expect(save_campaign(variable_map: { "name" => mapping.fetch("name") }).status).to eq("draft")
    [ { variable_map: { "name" => { "source" => "field", "field" => "customer_id" } } },
      { variable_map: { "extra" => { "source" => "literal", "value" => "x" } } },
      { variable_map: { "name" => { "source" => "eval", "value" => "contact.name" } } },
      { send_rate_per_minute: 61 }, { quiet_hours_end: 21 }, { status: "running" },
      { segment_id: 999_999 }, { template_id: "oops" } ].each do |change|
      result = Sms::Campaigns::Save.call(customer: customer, actor: actor,
        attributes: { name: "Invalid", template_id: template.id, variable_map: mapping }.merge(change))
      expect(result).not_to be_success
    end
  end

  it "rejects a stale edit, foreign references and a non-admin actor" do
    campaign = save_campaign
    stale = campaign.lock_version
    campaign.update!(name: "Concurrent")
    result = Sms::Campaigns::Save.call(customer: customer, actor: actor, campaign: campaign,
      attributes: { name: "Stale", lock_version: stale })
    expect(result.code).to eq(:stale_edit)
    other = create(:customer)
    segment = Sms::Audience::Segment.create!(customer: other, name: "Other", segment_rules: {})
    result = Sms::Campaigns::Save.call(customer: customer, actor: actor, attributes: { name: "Foreign", segment_id: segment.id })
    expect(result).not_to be_success
    member = create(:user, customer: customer)
    expect(Sms::Campaigns::Save.call(customer: customer, actor: member, attributes: { name: "Denied" }).code).to eq(:forbidden)
  end

  it "rejects malformed canonical inputs and duplicate normalized keys before inspecting a draft version" do
    campaign = save_campaign
    [nil, [], "settings", { name: "A", "name" => "B" }].each do |input|
      result = Sms::Campaigns::Save.call(customer: customer, actor: actor, campaign: campaign, attributes: input)
      expect(result.code).to eq(:invalid_input)
    end
    invalid = "\xff".b.dup.force_encoding(Encoding::ISO_8859_1)
    result = Sms::Campaigns::Save.call(customer: customer, actor: actor, attributes: { name: invalid })
    expect(result.errors).to have_key(:name)
  end

  it "pins content/provider/account and supports a same-launch replay despite worker bookkeeping" do
    campaign = save_campaign
    preview = Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign).value
    version = campaign.lock_version
    args = { customer: customer, actor: actor, campaign: campaign, lock_version: version, review_token: preview[:review_token] }
    expect(Sms::Campaigns::Launch.call(**args)).to be_success
    original = campaign.reload.settings_snapshot
    expect(original).to include("credential_id" => credential.id, "provider" => "aliyun", "draft_lock_version" => version)
    expect(campaign.expires_at).to eq(Time.current + 24.hours)
    campaign.update!(heartbeat_at: Time.current, run_token: "bookkeeping")
    template.update!(status: "retired", provider_template_codes: { "aliyun" => "CHANGED" })
    expect(Sms::Campaigns::Launch.call(**args)).to be_success
    expect(campaign.reload.settings_snapshot).to eq(original)
  end

  it "rejects a changed draft, rules, provider mapping, expired review and past schedule" do
    campaign = save_campaign
    token = Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign).value[:review_token]
    template.update!(provider_template_codes: { "aliyun" => "CHANGED" })
    args = { customer: customer, actor: actor, campaign: campaign, lock_version: campaign.lock_version, review_token: token }
    expect(Sms::Campaigns::Launch.call(**args).code).to eq(:review_changed)
    token = Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign).value[:review_token]
    travel 16.minutes
    expect(Sms::Campaigns::Launch.call(**args.merge(review_token: token)).code).to eq(:review_changed)
    past = save_campaign(send_timing: "scheduled", scheduled_at: 1.hour.ago)
    expect(Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: past).value[:blockers]).to include(:schedule_in_past)
  end

  it "rejects nonexistent/ambiguous DST schedule times rather than silently choosing an offset" do
    ["2026-03-08T02:30", "2026-11-01T01:30"].each do |local|
      result = Sms::Campaigns::Save.call(customer: customer, actor: actor,
        attributes: { name: "DST", timezone: "America/New_York", send_timing: "scheduled", scheduled_local: local })
      expect(result.code).to eq(:schedule_invalid)
    end
    expect(Sms::Campaigns::Schedule.parse(local: "2026-11-01T03:30", timezone: "America/New_York")).to eq(Time.utc(2026, 11, 1, 8, 30))
  end

  it "bounds previews to 10,000 matches without materializing all contacts" do
    campaign = save_campaign
    relation = Sms::Contact.where(customer_id: customer.id)
    allow(Sms::Audience::SegmentQuery).to receive(:call).and_return(relation)
    limited = relation.limit(10_001)
    allow(relation).to receive(:limit).with(10_001).and_return(limited)
    allow(limited).to receive(:count).and_return(10_001)
    expect(relation).not_to receive(:find_in_batches)
    expect(Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign).code).to eq(:audience_too_large)
  end
end
