# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Campaigns::DeleteDraft do
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }
  let(:campaign) { create(:sms_campaign, customer: customer, created_by: actor) }

  def delete_draft(record = campaign, customer: self.customer, actor: self.actor)
    described_class.call(customer: customer, actor: actor, campaign: record)
  end

  it "removes an unlaunched empty draft without changing its segment, contact or evidence" do
    segment = create(:sms_segment, customer: customer)
    campaign.update!(segment: segment)
    contact = create(:sms_contact, :granted, customer: customer)
    evidence = create(:sms_consent_event, customer: customer, contact: contact)
    retained = [segment, contact, evidence].map(&:attributes)
    result = delete_draft
    expect(result).to be_success
    expect(result.value).to have_attributes(id: campaign.id)
    expect(result.value).to be_destroyed
    expect(Sms::Campaign.exists?(campaign.id)).to be(false)
    expect([segment, contact, evidence].map { |record| record.reload.attributes }).to eq(retained)
  end

  it "retains every non-draft state with the existing translated conflict" do
    %w[scheduled running completed cancelled failed].each do |status|
      record = create(:sms_campaign, customer: customer, created_by: actor, status: status)
      %w[en zh-CN].each do |locale|
        I18n.with_locale(locale) do
          result = delete_draft(record)
          expect(result.code).to eq(:not_draft)
          expect(result.errors).to eq(base: [I18n.t("sms_campaign_http.errors.not_draft")])
        end
      end
      expect(record.reload.status).to eq(status)
    end
  end

  it "retains a draft with recipient rows and their contact evidence" do
    contact = create(:sms_contact, customer: customer)
    evidence = create(:sms_consent_event, customer: customer, contact: contact)
    recipient = create(:sms_campaign_recipient, customer: customer, campaign: campaign, contact: contact)
    expect(delete_draft.code).to eq(:not_draft)
    expect([campaign, recipient, contact, evidence].map { |record| record.reload.persisted? }).to all(be(true))
  end

  it "respects the model's retained-launch and linked-message restrictions without partial deletion" do
    launched = create(:sms_campaign, customer: customer, created_by: actor, launched_at: Time.current)
    expect(delete_draft(launched).code).to eq(:not_draft)
    message = create(:sms_message, customer: customer, campaign_id: campaign.id)
    expect(delete_draft.code).to eq(:not_draft)
    expect([launched, campaign, message].map { |record| record.reload.persisted? }).to all(be(true))
  end

  it "rejects anonymous, member, inactive and foreign-tenant admin actors" do
    inactive = create(:user, :admin, customer: customer)
    Authentication::User.where(id: inactive.id).update_all(status: Authentication::User.statuses.fetch("inactive"))
    [nil, create(:user, :member, customer: customer), inactive, create(:user, :admin)].each do |denied_actor|
      expect(delete_draft(actor: denied_actor).code).to eq(:forbidden)
    end
    expect(campaign.reload).to be_persisted
  end

  it "allows the pinned owner under the record's tenant and rejects a foreign record under that URL customer" do
    owner = find_or_create_platform_owner
    foreign = create(:sms_campaign)
    expect(delete_draft(foreign, actor: owner).code).to eq(:not_found)
    expect(foreign.reload).to be_persisted
    expect(delete_draft(actor: owner)).to be_success
  end

  it "rejects wrong record types, unsaved records and a forged in-memory customer" do
    foreign = create(:sms_campaign)
    foreign.customer_id = customer.id
    [nil, build(:sms_campaign, customer: customer, created_by: actor), create(:sms_segment, customer: customer), foreign].each do |record|
      expect(delete_draft(record).code).to eq(:not_found)
    end
    expect(campaign.reload).to be_persisted
    expect(Sms::Campaign.exists?(foreign.id)).to be(true)
  end

  it "checks the persisted state after locking instead of trusting a stale draft object" do
    Sms::Campaign.where(id: campaign.id).update_all(status: "scheduled", launched_at: Time.current)
    expect(campaign.status).to eq("draft")
    expect(delete_draft.code).to eq(:not_draft)
    expect(campaign.reload.status).to eq("scheduled")
  end

  it "returns not_found when a stale draft handle no longer has a database row" do
    Sms::Campaign.where(id: campaign.id).delete_all
    expect(delete_draft.code).to eq(:not_found)
  end
end
