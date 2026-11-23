# frozen_string_literal: true

require "rails_helper"
require_relative "helpers"

RSpec.describe Sms::Campaigns::Unsubscribe do
  include_context "SMS campaign engine"
  let(:token) { described_class.token_for(customer: customer, contact: contact, phone_e164: contact.phone_e164) }

  it "generates canonical request-independent links and read-only masked confirmations" do
    url = described_class.url_for(customer: customer, contact: contact, phone_e164: contact.phone_e164)
    expect(url).to start_with("http://example.com/sms/unsubscribes/")
    expect(Sms::Contacts::EvidenceWriter).not_to receive(:call)
    expect(Sms::OptOut).not_to receive(:record_for_customer!)
    2.times do
      result = described_class.preview(token: token)
      expect(result).to be_success
      expect(result.value).to include(already_unsubscribed: false)
      expect(result.value[:masked_phone]).not_to include(contact.phone_e164)
    end
    expect(Sms::ConsentEvent.count).to eq(0)
    expect(enqueued_jobs).to be_empty
  end

  it "records one signed revocation and suppression and succeeds on later POST replay" do
    expect { described_class.call(token: token) }.to change(Sms::ConsentEvent, :count).by(1)
    expect(contact.reload.consent_status).to eq("revoked")
    expect(Sms::OptOut.find_by!(customer_id: customer.id, phone_e164: contact.phone_e164).reason).to eq("recipient_unsubscribe")
    event = Sms::ConsentEvent.first!
    expect(event).to have_attributes(action: "revoked", source: "recipient_unsubscribe", actor_user_id: nil)
    expect(event.evidence.to_json).not_to include(token)
    travel 2.days
    expect { expect(described_class.call(token: token).value[:already_unsubscribed]).to be(true) }.not_to change(Sms::ConsentEvent, :count)
    expect(described_class.preview(token: token).value[:already_unsubscribed]).to be(true)
  end

  it "revokes only the signed old phone and preserves a different current phone projection" do
    signed = token
    contact.update!(phone_e164: "+8613800138001", consent_status: "granted")
    expect(described_class.call(token: signed)).to be_success
    expect(contact.reload.consent_status).to eq("granted")
    expect(Sms::ConsentEvent.first.phone_e164).to eq("+8613800138000")
    expect(Sms::OptOut.opted_out?(customer_id: customer.id, phone_e164: contact.phone_e164)).to be(false)
  end

  it "allows archived contacts to revoke and cannot affect another tenant with the same phone" do
    other = create(:customer)
    other_contact = Sms::Contact.create!(customer: other, phone_e164: contact.phone_e164, consent_status: "granted")
    contact.update!(status: "archived")
    expect(described_class.call(token: token)).to be_success
    expect(other_contact.reload.consent_status).to eq("granted")
    expect(Sms::OptOut.opted_out?(customer_id: other.id, phone_e164: other_contact.phone_e164)).to be(false)
  end

  it "rejects expired/tampered/wrong-purpose/wrong-tenant tokens without writes" do
    signed = token
    wrong = described_class.verifier.generate({ "contact_id" => contact.id, "customer_id" => create(:customer).id,
      "phone_e164" => contact.phone_e164, "expires_at" => 1.day.from_now.iso8601 }, purpose: described_class::PURPOSE)
    bad_purpose = described_class.verifier.generate({}, purpose: "other")
    [signed + "x", wrong, bad_purpose].each do |invalid|
      expect(described_class.preview(token: invalid).code).to eq(:not_found)
      expect(described_class.call(token: invalid).code).to eq(:not_found)
    end
    travel 366.days
    expect(described_class.call(token: signed).code).to eq(:not_found)
    expect(Sms::ConsentEvent.count).to eq(0)
    expect(Sms::OptOut.count).to eq(0)
  end
end
