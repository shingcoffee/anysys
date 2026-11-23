# frozen_string_literal: true

require "rails_helper"
require_relative "../audience_domain_helpers"

RSpec.describe "SMS contact and consent operations" do
  include SmsAudienceDomainHelpers
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }

  it "normalizes national and international phones without inferring a timezone or consent" do
    result = save_contact(phone: "138 0013 8000", timezone: nil)
    expect(result).to be_success
    expect(result.value).to have_attributes(phone_e164: "+8613800138000", consent_status: "unknown", timezone: nil, source_kind: "manual")
    expect(Sms::ConsentEvent.count).to eq(0)
  end

  it "uses explicit country context and rejects a bad phone" do
    expect(save_contact(phone: "4155552671", country_code: "US").value.phone_e164).to eq("+14155552671")
    expect(save_contact(phone: "not a phone").errors).to have_key(:phone)
    expect(save_contact(country_code: "ZZ").errors).to have_key(:country_code)
  end

  it "never accepts protected fields from a contact form" do
    %i[consent_status consent_changed_at customer_id source_kind source_entry_id source_mapping synced_at phone_e164].each do |field|
      expect(save_contact(field => "forged").code).to eq(:invalid_input)
    end
    expect(Sms::Contact.count).to eq(0)
  end

  it "checks actual actor roles and URL tenant ownership, including platform owner cross-tenant writes" do
    other_actor = create(:user, :admin)
    member = create(:user, :member, customer: customer)
    expect(save_contact(actor: other_actor).code).to eq(:forbidden)
    expect(save_contact(actor: member).code).to eq(:forbidden)
    expect(save_contact(actor: nil).code).to eq(:forbidden)
    owner = find_or_create_platform_owner
    expect(save_contact(actor: owner)).to be_success
    foreign = create(:sms_contact)
    expect(save_contact(contact: foreign, lock_version: 0).code).to eq(:not_found)
    other_actor.customer_id = customer.id
    expect(save_contact(actor: other_actor).code).to eq(:forbidden)
  end

  it "rejects duplicate phones without merging contacts or evidence" do
    first = save_contact.value
    result = save_contact
    expect(result).not_to be_success
    expect(Sms::Contact.count).to eq(1)
    expect(first.reload.name).to eq("Alice")
  end

  it "resets current-phone consent on a phone change and preserves old evidence" do
    contact = save_contact.value
    expect(consent(contact)).to be_success
    updated = save_contact({ phone: "+8613900139000", lock_version: contact.reload.lock_version }, contact: contact)
    expect(updated).to be_success
    expect(updated.value).to have_attributes(consent_status: "unknown", consent_changed_at: nil)
    expect(contact.consent_events.pluck(:phone_e164)).to eq(["+8613800138000"])
    restored = save_contact({ phone: "+8613800138000", lock_version: updated.value.lock_version }, contact: updated.value)
    expect(restored.value.consent_status).to eq("unknown")
  end

  it "guards optimistic edits and does not lose saved data" do
    contact = save_contact.value
    first = save_contact({ name: "First", lock_version: 0 }, contact: contact)
    expect(first).to be_success
    expect(save_contact({ name: "Lost", lock_version: 0 }, contact: contact).code).to eq(:stale_edit)
    expect(contact.reload.name).to eq("First")
    expect(save_contact({ lock_version: "0junk" }, contact: contact).code).to eq(:stale_edit)
  end

  it "archives/restores while retaining evidence and consent" do
    contact = save_contact.value
    consent(contact)
    contact.reload
    archived = Sms::Contacts::Archive.call(customer: customer, actor: actor, contact: contact, lock_version: contact.lock_version)
    expect(archived.value).to have_attributes(status: "archived", consent_status: "granted")
    expect(Sms::Contacts::Eligibility.call(customer: customer, contact: archived.value)).to eq(eligible: false, reason: :contact_archived)
    restored = save_contact({ status: "active", lock_version: archived.value.lock_version }, contact: archived.value)
    expect(restored.value.consent_status).to eq("granted")
    expect(Sms::ConsentEvent.count).to eq(1)
  end

  it "requires grant evidence and fixes source/phone/actor on the server" do
    contact = save_contact.value
    expect(consent(contact, statement: "")).not_to be_success
    expect(consent(contact, reference: "")).not_to be_success
    expect(consent(contact, source: "provider_opt_out").code).to eq(:invalid_input)
    result = consent(contact)
    expect(result.value[:event]).to have_attributes(source: "admin", actor_user_id: actor.id, phone_e164: contact.phone_e164)
  end

  it "deduplicates identical evidence and conflicts on any reused-key content change" do
    contact = save_contact.value
    at = 1.hour.ago
    first = consent(contact, occurred_at: at)
    replay = consent(contact, occurred_at: at)
    expect(first.value[:replayed]).to be(false)
    expect(replay.value[:replayed]).to be(true)
    expect(replay.value[:event].id).to eq(first.value[:event].id)
    expect(consent(contact, occurred_at: at, notes: "Changed").code).to eq(:event_key_conflict)
    expect(Sms::ConsentEvent.count).to eq(1)
  end

  it "orders projections by insertion instead of historical occurrence time" do
    contact = save_contact.value
    consent(contact, event_key: "new", occurred_at: 1.hour.ago)
    revoked = consent(contact, action: "revoked", statement: nil, event_key: "older", occurred_at: 2.days.ago)
    expect(revoked.value[:contact].consent_status).to eq("revoked")
    expect(revoked.value[:contact].consent_changed_at).to eq(revoked.value[:event].created_at)
    expect(Sms::OptOut.opted_out?(customer_id: customer.id, phone_e164: contact.phone_e164)).to be(true)
  end

  it "never clears suppression when a later grant is recorded" do
    contact = save_contact.value
    consent(contact, action: "revoked", event_key: "revoke")
    granted = consent(contact, event_key: "grant").value[:contact]
    expect(granted.consent_status).to eq("granted")
    expect(Sms::Contacts::Eligibility.call(customer: customer, contact: granted)).to eq(eligible: false, reason: :opted_out)
  end

  it "stores internal old-phone revocation without changing a replacement phone's projection" do
    contact = save_contact.value
    original = contact.phone_e164
    contact = save_contact({ phone: "+8613900139000", lock_version: 0 }, contact: contact).value
    consent(contact)
    result = Sms::Contacts::EvidenceWriter.call(customer: customer, contact: contact, phone_e164: original,
      action: "revoked", source: "recipient_unsubscribe", occurred_at: Time.current,
      evidence: { "token_digest" => "signed" }, event_key: "unsubscribe-signed")
    expect(result).to be_success
    expect(result.value[:contact].consent_status).to eq("granted")
    expect(Sms::OptOut.opted_out?(customer_id: customer.id, phone_e164: original)).to be(true)
    expect(Sms::OptOut.opted_out?(customer_id: customer.id, phone_e164: contact.phone_e164)).to be(false)
  end

  it "rejects internal grants and malformed evidence before writes" do
    contact = save_contact.value
    common = { customer: customer, contact: contact, phone_e164: contact.phone_e164, source: "provider_opt_out",
      occurred_at: Time.current, evidence: {}, event_key: "provider" }
    expect(Sms::Contacts::EvidenceWriter.call(**common, action: "granted").code).to eq(:invalid_evidence)
    expect(Sms::Contacts::EvidenceWriter.call(**common.merge(evidence: { "raw" => "x" * 4096 }), action: "revoked").code).to eq(:invalid_evidence)
    expect(Sms::ConsentEvent.count).to eq(0)
  end

  it "rejects future, missing-offset and invalid calendar evidence times" do
    contact = save_contact.value
    [1.day.from_now, "2026-10-13T09:00:00", "2026-02-30T09:00:00Z", nil].each do |time|
      expect(consent(contact, occurred_at: time).errors).to have_key(:occurred_at)
    end
    expect(Sms::ConsentEvent.count).to eq(0)
  end

  it "uses archived, changed-phone, consent, then opt-out reason precedence" do
    contact = create(:sms_contact, customer: customer)
    expect(Sms::Contacts::Eligibility.call(customer: customer, contact: contact)[:reason]).to eq(:consent_missing)
    expect(Sms::Contacts::Eligibility.call(customer: customer, contact: contact, phone_e164: "+14155552671")[:reason]).to eq(:phone_changed)
    consent(contact)
    Sms::OptOut.record_global!(phone_e164: contact.phone_e164, provider: "twilio", reason: "STOP")
    contact.reload
    expect(Sms::Contacts::Eligibility.call(customer: customer, contact: contact)[:reason]).to eq(:opted_out)
    contact.update!(status: "archived")
    expect(Sms::Contacts::Eligibility.call(customer: customer, contact: contact, phone_e164: "+14155552671")[:reason]).to eq(:contact_archived)
  end

  it "rolls evidence and projection back together on an outer transaction rollback" do
    contact = save_contact.value
    Sms::Contact.transaction do
      consent(contact)
      raise ActiveRecord::Rollback
    end
    expect(contact.reload.consent_status).to eq("unknown")
    expect(Sms::ConsentEvent.count).to eq(0)
  end
end
