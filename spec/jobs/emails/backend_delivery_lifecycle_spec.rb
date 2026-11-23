# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::DeliverMessageJob, "backend lifecycle", type: :job do
  let(:customer) { create(:customer) }
  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let!(:credential) { create(:email_credential) }

  def queue_mail(**options)
    Emails::Gateway.send_raw(**{
      customer: customer, to: "recipient@example.com", subject: "Notice", body_html: "<p>Notice</p>"
    }.merge(options))
  end

  it "blocks suppression added after queueing, including unsubscribe" do
    message = queue_mail
    Emails::Suppression.record_for_customer!(customer_id: customer.id, email: message.to, reason: "unsubscribe")
    expect_any_instance_of(Email::Providers::Smtp).not_to receive(:deliver)

    described_class.new.perform(message.id)

    expect(message.reload.status).to eq("suppressed")
    expect(message.delivery_claim_token).to be_nil
  end

  it "does not apply another tenant's suppression" do
    message = queue_mail
    Emails::Suppression.record_for_customer!(customer_id: create(:customer).id, email: message.to, reason: "manual")
    expect_any_instance_of(Email::Providers::Smtp).to receive(:deliver).and_return(provider_message_id: nil)

    described_class.new.perform(message.id)

    expect(message.reload.status).to eq("sent")
  end

  it "blocks already-queued recipients when their campaign is cancelled" do
    campaign = create(:email_send_activity, :processing, customer: customer)
    user = create(:user, customer: customer)
    message = Emails::Gateway.queue_for_send_activity(send_activity: campaign, user: user)
    campaign.cancel!
    expect_any_instance_of(Email::Providers::Smtp).not_to receive(:deliver)

    described_class.new.perform(message.id)

    expect(message.reload.status).to eq("suppressed")
  end

  it "permits only one execution while another worker is inside the vendor call" do
    message = queue_mail
    calls = []
    allow_any_instance_of(Email::Providers::Smtp).to receive(:deliver) do |_provider, **arguments|
      calls << arguments.fetch(:message).id
      described_class.new.perform(message.id)
      { provider_message_id: nil }
    end

    described_class.new.perform(message.id)

    expect(calls).to eq([message.id])
    expect(message.reload.delivery_attempts).to eq(1)
    expect(message.status).to eq("sent")
  end

  it "honors a future due time even when an old message is picked up prematurely" do
    message = queue_mail
    message.update_columns(created_at: 2.days.ago, delivery_due_at: 1.day.from_now)
    expect_any_instance_of(Email::Providers::Smtp).not_to receive(:deliver)

    described_class.new.perform(message.id)
    Emails::Cron::RecoverMessages.call

    expect(message.reload.status).to eq("queued")
    expect(message.delivery_attempts).to eq(0)
  end

  it "pins the account and mode after provider reassignment" do
    message = queue_mail
    credential.update!(status: "disabled")
    expect(Emails::DeliveryCredential.for_message(message)).to eq(credential)
    expect_any_instance_of(Email::Providers::Smtp).to receive(:deliver).and_return(provider_message_id: nil)

    described_class.new.perform(message.id)

    expect(message.reload.status).to eq("sent")
    expect(message.metadata).to include("credential_id" => credential.id, "credential_mode" => credential.mode)
  end

  it "recovers committed mail after enqueue failure without creating another ledger row" do
    allow(described_class).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue unavailable")
    message = queue_mail(idempotency_key: "outbox")
    expect(message.reload.delivery_enqueued_at).to be_nil
    expect(message.status).to eq("queued")
    allow(described_class).to receive(:perform_later).and_call_original

    expect { Emails::Cron::RecoverMessages.call }.to have_enqueued_job(described_class).with(message.id, nil)
    expect(Emails::Message.where(customer_id: customer.id, idempotency_key: "outbox").count).to eq(1)
  end

  it "preserves complaints and deliveries across stale model instances" do
    message = queue_mail
    message.mark_sent!(provider_message_id: "receipt-id")
    stale = Emails::Message.find(message.id)
    message.mark_complained!(code: "Complaint")
    stale.mark_delivered!
    stale.mark_sent!(provider_message_id: "late-id")

    expect(message.reload.status).to eq("complained")
    expect(message.provider_message_id).to eq("receipt-id")
  end

  it "does not let an expired owner's result finish a newer claim" do
    message = queue_mail
    first, token = Emails::DeliveryDispatch.claim(message.id)
    first.update_columns(delivery_claimed_at: 1.hour.ago)
    _new_owner, new_token = Emails::DeliveryDispatch.claim(message.id)

    first.mark_sent!(provider_message_id: "old-response", claim_token: token)

    expect(message.reload.status).to eq("queued")
    expect(message.delivery_claim_token).to eq(new_token)
  end
end
