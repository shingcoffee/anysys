# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS audience domain records", type: :model do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }

  it "publishes exactly five tenant-scoped domain models and frozen state enums" do
    [Sms::Contact, Sms::ConsentEvent, Sms::Audience::Segment, Sms::Campaign, Sms::CampaignRecipient].each do |klass|
      expect(klass.tenant_scoped?).to be(true)
      expect(klass.columns_hash.fetch("customer_id").null).to be(false)
    end
    expect(Sms::Contact::CONSENT_STATUSES).to eq(%w[unknown granted revoked])
    expect(Sms::Campaign::STATUSES).to eq(%w[draft scheduled running completed cancelled failed])
    expect(Sms::CampaignRecipient::STATUSES).to eq(%w[pending admitted skipped cancelled])
    expect(Sms::CampaignRecipient::DEFERRAL_REASONS).to be_frozen
  end

  it "uses explicit tenant helpers independent of ambient Current" do
    first = create(:sms_contact, customer: customer)
    create(:sms_contact, customer: other)
    Current.with_customer(other) do
      expect(Sms::Contact.for_customer(customer.id).pluck(:id)).to eq([first.id])
    end
  end

  it "retains tenant phone identity across archive and permits another tenant's same phone" do
    first = create(:sms_contact, :archived, customer: customer)
    expect(build(:sms_contact, customer: customer, phone_e164: first.phone_e164)).not_to be_valid
    expect(create(:sms_contact, customer: other, phone_e164: first.phone_e164)).to be_persisted
    expect { Sms::Contact.insert_all!([first.attributes.except("id")]) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects cross-tenant contact, campaign, segment, and source links" do
    foreign_contact = create(:sms_contact, customer: other)
    campaign = create(:sms_campaign, customer: customer)
    expect(build(:sms_consent_event, customer: customer, contact: foreign_contact)).not_to be_valid
    expect(build(:sms_campaign_recipient, campaign: campaign, customer: customer, contact: foreign_contact)).not_to be_valid
    campaign.segment = create(:sms_segment, customer: other)
    expect(campaign).not_to be_valid
    expect(build(:sms_contact, customer: customer, source_entry: create(:entity_entry, customer: other))).not_to be_valid
    campaign.segment = nil
    campaign.created_by = create(:user, :admin, customer: other)
    expect(campaign).not_to be_valid
    entry = create(:entity_entry, customer: customer)
    expect(build(:sms_contact, customer: customer, source_entity: create(:entity, customer: customer), source_entry: entry)).not_to be_valid
  end

  it "retains contacts with consent and recipient history" do
    contact = create(:sms_contact, customer: customer)
    create(:sms_consent_event, contact: contact)
    expect { contact.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect { Sms::Contact.where(id: contact.id).delete_all }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "makes persisted evidence read-only for all ordinary AR mutation paths" do
    event = create(:sms_consent_event)
    expect(event).to be_readonly
    expect { event.update!(action: "granted") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.update_columns(action: "granted") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.touch }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(event.reload.action).to eq("revoked")
  end

  it "protects segments referenced by drafts, nullifies launched history, and retains launched campaigns" do
    segment = create(:sms_segment, customer: customer)
    campaign = create(:sms_campaign, customer: customer, segment: segment)
    expect { segment.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    campaign.update!(status: "scheduled", launched_at: Time.current)
    segment.reload.destroy!
    expect(campaign.reload.segment_id).to be_nil
    expect(campaign.destroy).to be(false)
    expect(campaign.errors[:base]).to include(I18n.t("sms_audience.errors.campaign_retained"))
  end

  it "allows deleting only an unlaunched empty draft" do
    campaign = create(:sms_campaign)
    expect(campaign.destroy!).to be_destroyed
    recipient = create(:sms_campaign_recipient)
    expect { recipient.campaign.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end

  it "enforces unique campaign contact, phone, source identity and message linkage in the database" do
    recipient = create(:sms_campaign_recipient)
    expect { Sms::CampaignRecipient.insert_all!([recipient.attributes.except("id")]) }.to raise_error(ActiveRecord::RecordNotUnique)
    indexes = Sms::CampaignRecipient.connection.indexes("sms_campaign_recipients")
    expect(indexes.find { |index| index.columns == ["message_id"] }.unique).to be(true)
    expect(indexes.find { |index| index.columns == ["message_id"] }.where).to eq("message_id IS NOT NULL")
    expect(Sms::Contact.connection.indexes("sms_contacts").find { |index| index.name == "idx_sms_contacts_source" }.unique).to be(true)
  end

  it "nullifies actual source foreign keys while retaining the contact and evidence" do
    source = create(:entity, customer: customer)
    entry = create(:entity_entry, entity: source, customer: customer)
    contact = create(:sms_contact, customer: customer, source_kind: "entity", source_entity: source, source_entry: entry)
    event = create(:sms_consent_event, contact: contact)
    EntityEntry.where(id: entry.id).delete_all
    expect(contact.reload.source_entry_id).to be_nil
    source.destroy!
    expect(contact.reload.source_entity_id).to be_nil
    expect(event.reload.contact_id).to eq(contact.id)
  end
end
