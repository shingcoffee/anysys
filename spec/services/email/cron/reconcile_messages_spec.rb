# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Cron::ReconcileMessages do
  let_it_be(:customer_a) { create(:customer) }
  let_it_be(:customer_b) { create(:customer) }
  let_it_be(:email_module_a) { enable_module!("email", customer_a, name: "Email") }

  before { enable_module!("email", customer_b, name: "Email") }

  let(:now) { Time.zone.parse("2026-07-14 12:00:00") }

  def message_at(customer:, created_at:, status: "queued", metadata: { "dispatched_at" => created_at.iso8601 })
    msg = create(:email_message, customer: customer, status: status, metadata: metadata)
    msg.update_columns(created_at: created_at, delivery_attempts: metadata["dispatched_at"] ? Emails::DeliveryDispatch::MAX_ATTEMPTS : 0)
    msg
  end

  it "dead-letters a message stuck in queued past DEAD_LETTER_AFTER" do
    msg = message_at(customer: customer_a, created_at: now - 2.hours)

    described_class.call(now: now)

    expect(msg.reload.status).to eq("failed")
    expect(msg.failure_code).to eq("UNDELIVERED")
  end

  it "leaves a queued message alone while still within the grace window" do
    msg = message_at(customer: customer_a, created_at: now - 10.minutes)

    described_class.call(now: now)

    expect(msg.reload.status).to eq("queued")
  end

  it "does not touch a non-queued message" do
    msg = message_at(customer: customer_a, created_at: now - 2.hours, status: "sent")

    described_class.call(now: now)

    expect(msg.reload.status).to eq("sent")
  end

  it "runs cross-tenant in one sweep (no Current.customer tenant filter)" do
    Current.customer = nil
    msg_a = message_at(customer: customer_a, created_at: now - 2.hours)
    msg_b = message_at(customer: customer_b, created_at: now - 3.hours)

    described_class.call(now: now)

    expect(msg_a.reload.status).to eq("failed")
    expect(msg_b.reload.status).to eq("failed")
  end

  it "rescues ActiveRecord::RecordInvalid raised while dead-lettering one row and continues with the rest" do
    bad  = message_at(customer: customer_a, created_at: now - 2.hours)
    good = message_at(customer: customer_b, created_at: now - 2.hours)

    allow_any_instance_of(Emails::Message).to receive(:mark_failed!) do |instance, **|
      raise ActiveRecord::RecordInvalid.new(instance) if instance.id == bad.id

      instance.update!(status: "failed", failure_code: "UNDELIVERED")
    end

    expect { described_class.call(now: now) }.not_to raise_error
    expect(good.reload.status).to eq("failed")
  end

  it "defaults now to the current time" do
    Time.use_zone("UTC") do
      msg = message_at(customer: customer_a, created_at: Time.current - 2.hours)
      described_class.call
      expect(msg.reload.status).to eq("failed")
    end
  end

  it "does not dead-letter queued mail while the Email module is off" do
    FeatureModules::CustomerAssignment.find_by!(
      customer: customer_a, feature_module: email_module_a
    ).update!(status: :suspended)
    msg = message_at(customer: customer_a, created_at: now - 2.hours)

    described_class.call(now: now)

    expect(msg.reload.status).to eq("queued")
  end

  it "does not deliver or fail old mail scheduled for a future due time" do
    msg = message_at(customer: customer_a, created_at: now - 2.days,
                     metadata: { "scheduled_at" => (now + 1.day).iso8601 })

    expect { described_class.call(now: now) }.not_to have_enqueued_job(Emails::DeliverMessageJob)
    expect(msg.reload.status).to eq("queued")
  end

  it "starts the grace window at due time instead of creation time" do
    msg = message_at(customer: customer_a, created_at: now - 2.days,
                     metadata: { "scheduled_at" => (now - 10.minutes).iso8601 })

    expect { described_class.call(now: now) }.not_to have_enqueued_job(Emails::DeliverMessageJob)
    expect(msg.reload.status).to eq("queued")
  end

  it "re-enqueues an overdue orphan using its recorded mode and throttles repeated recovery" do
    msg = message_at(customer: customer_a, created_at: now - 2.hours,
                     metadata: { "scheduled_at" => (now - 90.minutes).iso8601, "mode" => "production" })

    expect { described_class.call(now: now) }.to have_enqueued_job(Emails::DeliverMessageJob).with(msg.id, "production")
    expect(msg.reload.status).to eq("queued")
    expect(msg.delivery_enqueued_at).to eq(now)
    expect { described_class.call(now: now + 4.minutes) }.not_to have_enqueued_job(Emails::DeliverMessageJob)
  end

  it "recovers an orphan with no scheduling metadata" do
    msg = message_at(customer: customer_a, created_at: now - 2.hours, metadata: {})
    expect { described_class.call(now: now) }.to have_enqueued_job(Emails::DeliverMessageJob).with(msg.id, nil)
    expect(msg.reload.status).to eq("queued")
  end

  it "leaves a recently dispatched old message in its delivery grace window" do
    msg = message_at(customer: customer_a, created_at: now - 2.days,
                     metadata: { "dispatched_at" => (now - 10.minutes).iso8601 })
    described_class.call(now: now)
    expect(msg.reload.status).to eq("queued")
  end

  it "does not race a live delivery claim" do
    msg = message_at(customer: customer_a, created_at: now - 2.hours, metadata: {})
    msg.update_columns(delivery_claimed_at: now - 5.minutes, delivery_claim_token: "worker-claim")
    expect { described_class.call(now: now) }.not_to have_enqueued_job(Emails::DeliverMessageJob)
    expect(msg.reload.status).to eq("queued")
  end

  it "does not guess the due time of malformed scheduling metadata" do
    msg = message_at(customer: customer_a, created_at: now - 2.hours, metadata: { "scheduled_at" => ["bad"] })
    expect { described_class.call(now: now) }.not_to have_enqueued_job(Emails::DeliverMessageJob)
    expect(msg.reload.status).to eq("queued")
  end

  it "honors the campaign lane's dedicated due-time and recorded credential-mode fields" do
    msg = message_at(customer: customer_a, created_at: now - 2.days, metadata: { "credential_mode" => "production" })
    msg.update_columns(delivery_due_at: now + 1.day)
    expect { described_class.call(now: now) }.not_to have_enqueued_job(Emails::DeliverMessageJob)
    expect(msg.reload.status).to eq("queued")

    msg.update_columns(delivery_due_at: now - 2.hours)
    expect { described_class.call(now: now) }.to have_enqueued_job(Emails::DeliverMessageJob).with(msg.id, "production")
  end
end
