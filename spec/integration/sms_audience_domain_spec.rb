# frozen_string_literal: true

require "rails_helper"
require_relative "../services/sms/audience_domain_helpers"

RSpec.describe "SMS audience data integration" do
  include SmsAudienceDomainHelpers
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }

  it "composes explicit synchronization, consent, dynamic targeting and suppression without admitting messages" do
    source = create(:entity, customer: customer, property_schema: [
      { "name" => "Mobile", "name_slug" => "mobile", "html_type" => "tel" },
      { "name" => "City", "name_slug" => "city", "html_type" => "text" }
    ].to_json)
    create(:entity_entry, entity: source, customer: customer,
      data: { "mobile" => "13800138000", "city" => "Shanghai" }.to_json)
    mapping = { entity_id: source.id, phone_field: "mobile", country_code: "CN", attribute_map: { "city" => "city" } }
    sync = Sms::Contacts::SyncEntity.call(customer: customer, actor: actor, attributes: mapping)
    expect(sync).to be_success
    rules = group(condition("attributes.city", "Shanghai"))
    segment = Sms::Audience::SaveSegment.call(customer: customer, actor: actor, attributes: { name: "Shanghai", segment_rules: rules }).value
    preview = -> { Sms::Audience::Preview.call(customer: customer, rules: segment.reload.segment_rules).value }
    expect(preview.call).to include(matched_count: 1, eligible_count: 0)
    contact = Sms::Contact.sole
    expect(consent(contact)).to be_success
    expect(preview.call).to include(matched_count: 1, eligible_count: 1)
    expect(consent(contact, action: "revoked", event_key: "revoke")).to be_success
    expect(preview.call).to include(matched_count: 1, eligible_count: 0, excluded_counts: { consent_missing: 1 })
    expect(consent(contact, event_key: "new-grant")).to be_success
    expect(preview.call).to include(eligible_count: 0, excluded_counts: { opted_out: 1 })
    expect(Sms::Message.count).to eq(0)
    expect(Sms::CampaignRecipient.count).to eq(0)
  end

  it "publishes every frozen campaign/template/core field for dependent fixtures" do
    expected = {
      Sms::Contact => %w[customer_id phone_e164 name country_code timezone status consent_status consent_changed_at
        custom_attributes source_kind source_entity_id source_entry_id source_mapping synced_at lock_version],
      Sms::ConsentEvent => %w[customer_id contact_id phone_e164 action source occurred_at actor_user_id evidence event_key],
      Sms::Audience::Segment => %w[customer_id name description segment_rules lock_version],
      Sms::Campaign => %w[customer_id name template_id segment_id variable_map send_timing scheduled_at timezone quiet_hours_start
        quiet_hours_end frequency_window_hours send_rate_per_minute deadline_hours status created_by_id launched_by_id launched_at
        started_at expires_at finished_at cancelled_at settings_snapshot audience_snapshot stats stats_refreshed_at run_token
        run_lease_expires_at heartbeat_at failure_code lock_version],
      Sms::CampaignRecipient => %w[customer_id campaign_id contact_id phone_e164 contact_snapshot vars status skip_reason
        deferral_reason message_id delivery_due_at admitted_at processed_at]
    }
    expected.each do |klass, columns|
      expect(klass.column_names.sort).to eq((columns + %w[id created_at updated_at]).sort)
    end
    expect(Sms::Template.column_names).to include("purpose", "body_template")
    expect(Sms::Message.column_names).to include("campaign_id", "contact_id", "delivery_due_at")
    expect(Sms::Credential.column_names).to include("dispatch_next_at")
    campaign = build(:sms_campaign)
    expect(campaign).to have_attributes(send_timing: "immediate", timezone: "Asia/Shanghai", quiet_hours_start: 21,
      quiet_hours_end: 9, frequency_window_hours: 24, send_rate_per_minute: 60, deadline_hours: 24,
      status: "draft", settings_snapshot: {}, audience_snapshot: {}, stats: {})
  end
end
