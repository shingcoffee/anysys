# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::ReceiptInbox do
  let(:customer) { create(:customer) }
  let!(:credential) { create(:email_credential) }

  it "keeps an early authenticated receipt pending and applies it after correlation" do
    receipt = described_class.record!(credential: credential, event: { type: :delivered, provider_message_id: "early" })
    expect(receipt.reload.processed_at).to be_nil
    message = create(:email_message, customer: customer, provider: credential.provider, status: "sent",
                     provider_message_id: "early", metadata: { credential_id: credential.id, credential_mode: credential.mode })

    described_class.reconcile

    expect(message.reload.status).to eq("delivered")
    expect(receipt.reload.customer_id).to eq(customer.id)
    expect(receipt.processed_at).to be_present
  end

  it "never correlates a different account's otherwise identical vendor ID" do
    other = create(:email_credential, mode: "production")
    message = create(:email_message, customer: customer, provider: credential.provider, status: "sent",
                     provider_message_id: "collision", metadata: { credential_id: other.id, credential_mode: other.mode })

    receipt = described_class.record!(credential: credential, event: { type: :delivered, provider_message_id: "collision" })

    expect(message.reload.status).to eq("sent")
    expect(receipt.reload.processed_at).to be_nil
  end

  it "deduplicates replayed events while retaining suppression for unmatched messages" do
    event = { type: :bounced, provider_message_id: "unknown", email: "bad@example.com", suppress: true }
    first = described_class.record!(credential: credential, event: event)
    second = described_class.record!(credential: credential, event: event)

    expect(second.id).to eq(first.id)
    expect(Emails::BackendReceipt.count).to eq(1)
    expect(Emails::Suppression.suppressed?(customer_id: customer.id, email: "bad@example.com")).to be(true)
  end

  it "does not collapse multiple recipients inside one vendor envelope ID" do
    %w[first@example.com second@example.com].each do |email|
      described_class.record!(credential: credential, event_key: "same-envelope",
                              event: { type: :bounced, provider_message_id: "same-message", email: email, suppress: true })
    end

    expect(Emails::BackendReceipt.count).to eq(2)
    expect(Emails::Suppression.where(customer_id: nil).pluck(:email)).to include("first@example.com", "second@example.com")
  end
end
