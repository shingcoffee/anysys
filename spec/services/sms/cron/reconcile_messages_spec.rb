# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Cron::ReconcileMessages do
  let_it_be(:customer_a) { create(:customer) }
  let_it_be(:customer_b) { create(:customer) }
  let_it_be(:sms_module) do
    enable_module!("sms", customer_a, name: "SMS")
    enable_module!("sms", customer_b, name: "SMS")
  end

  let(:now) { Time.zone.parse("2026-07-14 12:00:00") }

  # Runs cross-tenant on purpose — no Current.customer set.
  before { Current.customer = nil }

  def message_at(customer:, created_at:, status: "sent", provider: "aliyun", vendor_message_id: "BIZ-1", **clocks)
    msg = create(:sms_message, customer: customer, status: status, provider: provider,
                 vendor_message_id: vendor_message_id, **clocks)
    msg.update_columns(created_at: created_at)
    msg
  end

  describe ".reconcile_pollable" do
    it "queries a non-terminal :poll message inside the [MAX_AGE, GRACE) window" do
      msg = message_at(customer: customer_a, created_at: now - 10.minutes)

      expect(Sms::Gateway).to receive(:query).with(message: msg)
      described_class.reconcile_pollable(now)
    end

    it "skips a message that is still within the GRACE settle period" do
      msg = message_at(customer: customer_a, created_at: now - 30.seconds)

      expect(Sms::Gateway).not_to receive(:query)
      described_class.reconcile_pollable(now)
    end

    it "skips a message older than MAX_AGE" do
      msg = message_at(customer: customer_a, created_at: now - 4.days)

      expect(Sms::Gateway).not_to receive(:query)
      described_class.reconcile_pollable(now)
    end

    it "waits for attempt grace even after four days queued with a five-day expiry" do
      message_at(customer: customer_a, created_at: now - 4.days, dispatch_started_at: now - 30.seconds,
                 sent_at: now - 20.seconds, expires_at: now + 1.day)
      expect(Sms::Gateway).not_to receive(:query)
      described_class.reconcile_pollable(now)
    end

    it "polls a fresh attempt after four days queued rather than expiring the reconciliation window" do
      msg = message_at(customer: customer_a, created_at: now - 4.days, dispatch_started_at: now - 5.minutes,
                       sent_at: now - 4.minutes, expires_at: now + 1.day)
      expect(Sms::Gateway).to receive(:query).with(message: msg)
      described_class.reconcile_pollable(now)
    end

    it "uses acceptance clock for historical rows without an attempted marker" do
      msg = message_at(customer: customer_a, created_at: now - 4.days, sent_at: now - 5.minutes)
      expect(Sms::Gateway).to receive(:query).with(message: msg)
      described_class.reconcile_pollable(now)
    end

    it "does not restart the max-age window when acceptance is recorded much later than dispatch" do
      message_at(customer: customer_a, created_at: now - 5.days, dispatch_started_at: now - 4.days, sent_at: now - 5.minutes)
      expect(Sms::Gateway).not_to receive(:query)
      described_class.reconcile_pollable(now)
    end

    it "skips a message with no vendor_message_id without ever resending" do
      msg = message_at(customer: customer_a, created_at: now - 10.minutes, vendor_message_id: nil)

      expect(Sms::Gateway).not_to receive(:query)
      described_class.reconcile_pollable(now)
    end

    it "skips an already-terminal message" do
      msg = message_at(customer: customer_a, created_at: now - 10.minutes, status: "delivered")

      expect(Sms::Gateway).not_to receive(:query)
      described_class.reconcile_pollable(now)
    end

    it "excludes queued rows even when they carry a stray provider ID" do
      message_at(customer: customer_a, created_at: now - 10.minutes, status: "queued")
      expect(Sms::Gateway).not_to receive(:query)
      described_class.reconcile_pollable(now)
    end

    it "continues reconciling outstanding sends when the SMS module is disabled" do
      msg = message_at(customer: customer_a, created_at: now - 10.minutes)
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer_a, feature_module: sms_module
      ).update!(status: :suspended)

      expect(Sms::Gateway).to receive(:query).with(message: msg)
      described_class.reconcile_pollable(now)
    end

    it "polls Twilio as a fallback for callback loss" do
      msg = message_at(customer: customer_a, created_at: now - 10.minutes, provider: "twilio")

      expect(Sms::Gateway).to receive(:query).with(message: msg)
      described_class.reconcile_pollable(now)
    end

    it "reconciles across multiple tenants in one sweep (cross-tenant by design)" do
      msg_a = message_at(customer: customer_a, created_at: now - 10.minutes, vendor_message_id: "A-1")
      msg_b = message_at(customer: customer_b, created_at: now - 20.minutes, vendor_message_id: "B-1")

      expect(Sms::Gateway).to receive(:query).with(message: msg_a)
      expect(Sms::Gateway).to receive(:query).with(message: msg_b)
      described_class.reconcile_pollable(now)
    end

    it "rescues an unregistered adapter (ArgumentError) for one message and continues" do
      bad  = message_at(customer: customer_a, created_at: now - 10.minutes, provider: "unregistered_vendor")
      good = message_at(customer: customer_b, created_at: now - 10.minutes, vendor_message_id: "GOOD-1")

      expect(Sms::Gateway).to receive(:query).with(message: good)
      expect { described_class.reconcile_pollable(now) }.not_to raise_error
    end

    it "rescues a Sms::Errors::Error raised by Gateway.query and continues" do
      msg = message_at(customer: customer_a, created_at: now - 10.minutes)
      allow(Sms::Gateway).to receive(:query).and_raise(Sms::Errors::CredentialsMissing, "no creds")

      expect { described_class.reconcile_pollable(now) }.not_to raise_error
    end

    it "rescues ActiveRecord::RecordInvalid raised while applying the query result and continues" do
      msg = message_at(customer: customer_a, created_at: now - 10.minutes)
      allow(Sms::Gateway).to receive(:query).and_raise(ActiveRecord::RecordInvalid.new(msg))

      expect { described_class.reconcile_pollable(now) }.not_to raise_error
    end
  end

  describe ".mark_unresolved_unknown" do
    it "marks unresolved sends beyond MAX_AGE unknown, not failed" do
      msg = message_at(customer: customer_a, created_at: now - 4.days, status: "pending", vendor_message_id: nil)
      expect(Sms::Gateway).not_to receive(:send)
      described_class.mark_unresolved_unknown(now)
      expect(msg.reload.status).to eq("unknown")
      expect(msg.failure_code).to be_nil
    end

    it "also marks accepted sends beyond MAX_AGE unknown without proving failure" do
      msg = message_at(customer: customer_a, created_at: now - 4.days)
      described_class.mark_unresolved_unknown(now)
      expect(msg.reload.status).to eq("unknown")
    end

    it "leaves recent pending attempts to outbox recovery" do
      msg = message_at(customer: customer_a, created_at: now - 2.hours, status: "pending", vendor_message_id: nil)
      described_class.mark_unresolved_unknown(now)
      expect(msg.reload.status).to eq("pending")
    end

    it "keeps freshly attempted/accepted sends unresolved after a long admission delay" do
      attempted = message_at(customer: customer_a, created_at: now - 4.days, dispatch_started_at: now - 5.minutes,
                             status: "pending", vendor_message_id: nil)
      accepted = message_at(customer: customer_b, created_at: now - 4.days, sent_at: now - 5.minutes)
      described_class.mark_unresolved_unknown(now)
      expect(attempted.reload.status).to eq("pending")
      expect(accepted.reload.status).to eq("sent")
    end

    it "marks genuinely stale dispatch unknown even with a later acceptance timestamp" do
      msg = message_at(customer: customer_a, created_at: now - 5.days, dispatch_started_at: now - 4.days, sent_at: now - 5.minutes)
      described_class.mark_unresolved_unknown(now)
      expect(msg.reload.status).to eq("unknown")
      expect(msg.failure_code).to be_nil
    end

    it "never queries or resends an attempted unknown row lacking vendor identity" do
      msg = message_at(customer: customer_a, created_at: now - 4.days, dispatch_started_at: now - 5.minutes,
                       status: "unknown", vendor_message_id: nil)
      expect(Sms::Gateway).not_to receive(:query)
      expect(Sms::Gateway).not_to receive(:send)
      described_class.call(now: now)
      expect(msg.reload.status).to eq("unknown")
    end

    %w[queued unknown delivered failed suppressed expired].each do |status|
      it "never dead-letters #{status} rows" do
        msg = message_at(customer: customer_a, created_at: now - 4.days, status: status, vendor_message_id: nil)
        described_class.mark_unresolved_unknown(now)
        expect(msg.reload.status).to eq(status)
      end
    end

    it "rescues a per-row projection failure and continues" do
      msg = message_at(customer: customer_a, created_at: now - 4.days, status: "pending", vendor_message_id: nil)
      allow_any_instance_of(Sms::Message).to receive(:mark_unknown!).and_raise(ActiveRecord::RecordInvalid.new(msg))
      expect { described_class.mark_unresolved_unknown(now) }.not_to raise_error
    end
  end

  describe ".call" do
    it "runs receipt reconciliation, query fallback and bounded unknown marking" do
      expect(Sms::ReceiptInbox).to receive(:reconcile)
      expect(described_class).to receive(:reconcile_pollable).with(now)
      expect(described_class).to receive(:mark_unresolved_unknown).with(now)
      described_class.call(now: now)
    end

    it "defaults now to the current time" do
      expect(described_class).to receive(:reconcile_pollable)
      expect(described_class).to receive(:mark_unresolved_unknown)
      described_class.call
    end
  end
end
