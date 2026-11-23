# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Audience::DeleteSegment do
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }
  let(:segment) { create(:sms_segment, customer: customer) }

  def delete_segment(record = segment, customer: self.customer, actor: self.actor)
    described_class.call(customer: customer, actor: actor, segment: record)
  end

  it "deletes an unused segment and returns the destroyed record" do
    result = delete_segment
    expect(result).to be_success
    expect(result.value).to have_attributes(id: segment.id)
    expect(result.value).to be_destroyed
    expect(Sms::Audience::Segment.exists?(segment.id)).to be(false)
  end

  it "rejects draft dependencies with the existing localized error and no partial nullification" do
    draft = create(:sms_campaign, customer: customer, created_by: actor, segment: segment)
    historical = create(:sms_campaign, customer: customer, created_by: actor, segment: segment, status: "completed")
    %w[en zh-CN].each do |locale|
      I18n.with_locale(locale) do
        result = delete_segment
        expect(result.code).to eq(:segment_in_use)
        expect(result.errors).to eq(base: [I18n.t("sms_campaign_http.errors.segment_in_use")])
      end
    end
    expect(segment.reload).to be_persisted
    expect([draft.reload.segment_id, historical.reload.segment_id]).to eq([segment.id, segment.id])
  end

  it "nullifies only the historical segment reference and retains frozen rules, recipients, messages, contacts and evidence" do
    snapshot = { "kind" => "segment", "segment_id" => segment.id, "segment_name" => segment.name, "segment_rules" => {} }
    campaign = create(:sms_campaign, customer: customer, created_by: actor, segment: segment, status: "completed",
      launched_at: Time.current, audience_snapshot: snapshot)
    contact = create(:sms_contact, :granted, customer: customer)
    evidence = create(:sms_consent_event, contact: contact, customer: customer)
    message = create(:sms_message, customer: customer, campaign_id: campaign.id, contact_id: contact.id, status: "delivered")
    recipient = create(:sms_campaign_recipient, customer: customer, campaign: campaign, contact: contact, message: message, status: "admitted")
    retained = [contact, evidence, message, recipient].map(&:attributes)
    expect(delete_segment).to be_success
    expect(campaign.reload).to have_attributes(segment_id: nil, status: "completed", audience_snapshot: snapshot)
    expect([contact, evidence, message, recipient].map { |record| record.reload.attributes }).to eq(retained)
  end

  it "rejects anonymous, member, inactive and foreign-tenant admin actors" do
    inactive = create(:user, :admin, customer: customer)
    Authentication::User.where(id: inactive.id).update_all(status: Authentication::User.statuses.fetch("inactive"))
    [nil, create(:user, :member, customer: customer), inactive, create(:user, :admin)].each do |denied_actor|
      expect(delete_segment(actor: denied_actor).code).to eq(:forbidden)
    end
    expect(segment.reload).to be_persisted
  end

  it "allows the pinned owner for the supplied tenant but never deletes another URL tenant's record" do
    owner = find_or_create_platform_owner
    foreign = create(:sms_segment)
    expect(delete_segment(foreign, actor: owner).code).to eq(:not_found)
    expect(foreign.reload).to be_persisted
    expect(delete_segment(actor: owner)).to be_success
  end

  it "rejects wrong record types, unsaved records and forged in-memory tenant identities" do
    foreign = create(:sms_segment)
    foreign.customer_id = customer.id
    [nil, build(:sms_segment, customer: customer), create(:sms_contact, customer: customer), foreign].each do |record|
      expect(delete_segment(record).code).to eq(:not_found)
    end
    expect(segment.reload).to be_persisted
    expect(Sms::Audience::Segment.exists?(foreign.id)).to be(true)
  end

  it "returns not_found for a stale handle whose database row was removed" do
    Sms::Audience::Segment.where(id: segment.id).delete_all
    expect(delete_segment.code).to eq(:not_found)
  end

  it "checks fresh draft references instead of an already-loaded association" do
    segment.draft_campaigns.load
    create(:sms_campaign, customer: customer, created_by: actor, segment: segment)
    expect(delete_segment.code).to eq(:segment_in_use)
    expect(segment.reload).to be_persisted
  end
end
