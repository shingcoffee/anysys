# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Message do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "is valid with required attributes" do
    expect(build(:sms_message, customer: customer)).to be_valid
  end

  it "enforces [customer_id, idempotency_key] uniqueness when idempotency_key present" do
    create(:sms_message, customer: customer, idempotency_key: "k1")
    dup = build(:sms_message, customer: customer, idempotency_key: "k1")
    expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows multiple rows with NULL idempotency_key" do
    create(:sms_message, customer: customer, idempotency_key: nil)
    another = build(:sms_message, customer: customer, idempotency_key: nil)
    expect { another.save! }.not_to raise_error
  end

  describe ".rate_limit_window" do
    it "returns created_at values for the same tenant phone within the window" do
      create(:sms_message, customer: customer, to: "+8613800138000", template_key: "verify_code", created_at: 30.minutes.ago)
      create(:sms_message, customer: customer, to: "+8613800138000", template_key: "verify_code", created_at: 2.days.ago)
      result = described_class.rate_limit_window(customer_id: customer.id, to: "+8613800138000")
      expect(result.size).to eq(1)
    end
  end

  describe "STATUSES / TERMINAL_STATUSES" do
    it "includes suppressed as a status" do
      expect(described_class::STATUSES).to include("suppressed")
    end

    it "treats delivered, failed, suppressed and expired as terminal" do
      expect(described_class::TERMINAL_STATUSES).to contain_exactly("delivered", "failed", "suppressed", "expired")
    end
  end

  describe "#terminal?" do
    it "is true for each terminal status" do
      described_class::TERMINAL_STATUSES.each do |status|
        expect(build(:sms_message, customer: customer, status: status)).to be_terminal
      end
    end

    it "is false for pending/sent/unknown" do
      %w[queued pending sent unknown].each do |status|
        expect(build(:sms_message, customer: customer, status: status)).not_to be_terminal
      end
    end
  end

  describe ".non_terminal scope" do
    it "excludes terminal-status rows" do
      pending   = create(:sms_message, customer: customer, status: "pending")
      sent      = create(:sms_message, customer: customer, status: "sent")
      delivered = create(:sms_message, customer: customer, status: "delivered")
      failed    = create(:sms_message, customer: customer, status: "failed")
      suppressed = create(:sms_message, customer: customer, status: "suppressed")

      result = described_class.non_terminal
      expect(result).to include(pending, sent)
      expect(result).not_to include(delivered, failed, suppressed)
    end
  end

  describe "monotonic state transitions" do
    it "accepts queued and expired states with locale parity" do
      %w[queued expired].each do |status|
        expect(build(:sms_message, customer: customer, status: status)).to be_valid
        %i[en zh-CN].each { |locale| expect(I18n.exists?("sms.statuses.#{status}", locale)).to be(true) }
      end
    end

    it "expires only an unattempted queued payload" do
      msg = create(:sms_message, customer: customer, status: "queued")
      msg.mark_expired!
      expect(msg.status).to eq("expired")
      msg.mark_delivered!(at: Time.current, raw: {})
      expect(msg.status).to eq("expired")

      attempted = create(:sms_message, customer: customer, status: "queued", dispatch_started_at: Time.current)
      attempted.mark_expired!
      attempted.mark_suppressed!
      expect(attempted.status).to eq("queued")
    end

    it "does not let a query mutate an unattempted queued message" do
      msg = create(:sms_message, customer: customer, status: "queued")
      msg.mark_unknown!(raw: {})
      msg.mark_failed!(code: "late", message: "late", raw: {})
      msg.mark_sent!(vendor_message_id: "late", raw: {})
      expect(msg.status).to eq("queued")
    end

    it "#mark_sent! transitions pending → sent" do
      msg = create(:sms_message, customer: customer, status: "pending")
      msg.mark_sent!(vendor_message_id: "BIZ-1", raw: { "Code" => "OK" })
      expect(msg.reload.status).to eq("sent")
      expect(msg.vendor_message_id).to eq("BIZ-1")
      expect(msg.sent_at).to be_present
    end

    it "#mark_sent! no-ops on an already-terminal message" do
      msg = create(:sms_message, customer: customer, status: "delivered", delivered_at: Time.zone.now)
      msg.mark_sent!(vendor_message_id: "LATE", raw: {})
      expect(msg.reload.status).to eq("delivered")
      expect(msg.vendor_message_id).to be_nil
    end

    it "#mark_failed! records failure code + message" do
      msg = create(:sms_message, customer: customer, status: "sent")
      msg.mark_failed!(code: "isv.OUT_OF_SERVICE", message: "out of service", raw: {})
      expect(msg.reload.status).to eq("failed")
      expect(msg.failure_code).to eq("isv.OUT_OF_SERVICE")
    end

    it "#mark_failed! no-ops when the message is already delivered (delivered is the success floor)" do
      msg = create(:sms_message, customer: customer, status: "delivered", delivered_at: Time.zone.now)
      msg.mark_failed!(code: "LATE_DLR", message: "late failure", raw: {})
      expect(msg.reload.status).to eq("delivered")
      expect(msg.failure_code).to be_nil
    end

    it "#mark_failed! no-ops when already failed" do
      msg = create(:sms_message, customer: customer, status: "failed", failure_code: "FIRST")
      msg.mark_failed!(code: "SECOND", message: "later", raw: {})
      expect(msg.reload.failure_code).to eq("FIRST")
    end

    it "#mark_delivered! flips sent → delivered" do
      msg = create(:sms_message, customer: customer, status: "sent")
      msg.mark_delivered!(at: Time.zone.now, raw: {})
      expect(msg.reload.status).to eq("delivered")
      expect(msg.delivered_at).to be_present
    end

    it "#mark_delivered! repairs a transient failed status" do
      msg = create(:sms_message, customer: customer, status: "failed", failure_code: "TRANSIENT")
      msg.mark_delivered!(at: Time.zone.now, raw: {})
      expect(msg.reload.status).to eq("delivered")
    end

    it "#mark_delivered! is a no-op (idempotent) when already delivered" do
      at  = 1.hour.ago
      msg = create(:sms_message, customer: customer, status: "delivered", delivered_at: at)
      msg.mark_delivered!(at: Time.zone.now, raw: {})
      expect(msg.reload.delivered_at).to be_within(1.second).of(at)
    end

    it "#mark_unknown! transitions a non-terminal message" do
      msg = create(:sms_message, customer: customer, status: "sent")
      msg.mark_unknown!(raw: { "x" => 1 })
      expect(msg.reload.status).to eq("unknown")
    end

    it "#mark_unknown! no-ops when already terminal" do
      msg = create(:sms_message, customer: customer, status: "failed")
      msg.mark_unknown!(raw: {})
      expect(msg.reload.status).to eq("failed")
    end

    it "#mark_suppressed! sets the terminal suppressed status" do
      msg = create(:sms_message, customer: customer, status: "pending")
      msg.mark_suppressed!
      expect(msg.reload.status).to eq("suppressed")
    end

    it "fences late completions by dispatch identity after the token is cleared" do
      at = Time.current.change(usec: 0)
      msg = create(:sms_message, customer: customer, status: "unknown", dispatch_started_at: at)
      msg.mark_sent!(vendor_message_id: "stale-id", raw: {}, claim_token: "stale", attempt_started_at: at - 1.second)
      expect(msg.status).to eq("unknown")
      expect(msg.vendor_message_id).to be_nil
      msg.mark_sent!(vendor_message_id: "actual-id", raw: {}, claim_token: "owner", attempt_started_at: at)
      expect(msg.status).to eq("sent")
      expect(msg.vendor_message_id).to eq("actual-id")
    end

    it "does not let completion steal a different owner's claim even with the same dispatch timestamp" do
      at = Time.current.change(usec: 0)
      msg = create(:sms_message, customer: customer, status: "queued", dispatch_started_at: at, delivery_claim_token: "actual-owner")
      msg.mark_sent!(vendor_message_id: "stale-id", raw: {}, claim_token: "stale-owner", attempt_started_at: at)
      expect(msg.status).to eq("queued")
      expect(msg.vendor_message_id).to be_nil
      expect(msg.delivery_claim_token).to eq("actual-owner")
    end

    it "preserves recorded acceptance when a completion error tries to quarantine it" do
      at = Time.current.change(usec: 0)
      sent_at = at - 1.minute
      msg = create(:sms_message, customer: customer, status: "sent", dispatch_started_at: at, sent_at: sent_at,
                    vendor_message_id: "actual-id", raw_response: { "accepted" => true })
      msg.mark_unknown!(raw: {}, vendor_message_id: "actual-id", claim_token: "owner", attempt_started_at: at)
      expect(msg.status).to eq("sent")
      expect(msg.sent_at).to eq(sent_at)
      expect(msg.raw_response).to eq("accepted" => true)
    end

    it "fills late API acceptance facts without regressing delivered or failed receipt facts" do
      at = Time.current.change(usec: 0)
      %w[delivered failed].each do |status|
        msg = create(:sms_message, customer: customer, status: status, dispatch_started_at: at, vendor_message_id: "actual-id",
                      delivered_at: status == "delivered" ? at : nil, failure_code: status == "failed" ? "DLR" : nil,
                      raw_response: { "receipt" => status })
        msg.mark_sent!(vendor_message_id: "actual-id", raw: { "accepted" => true }, claim_token: "owner", attempt_started_at: at)
        expect(msg.status).to eq(status)
        expect(msg.sent_at).to be_present
        expect(msg.raw_response).to eq("receipt" => status)
        expect(msg.failure_code).to eq(status == "failed" ? "DLR" : nil)
      end
    end
  end

  describe "#displayed_failure_message" do
    it "translates a canned I18n key" do
      msg = build(:sms_message, customer: customer, failure_message: described_class::FAILURE_DELIVERY)
      expect(msg.displayed_failure_message).to eq("delivery failed")
    end

    it "returns vendor text that is not an I18n key" do
      msg = build(:sms_message, customer: customer, failure_message: "invalid To")
      expect(msg.displayed_failure_message).to eq("invalid To")
    end

    it "returns nil when blank" do
      msg = build(:sms_message, customer: customer, failure_message: nil)
      expect(msg.displayed_failure_message).to be_nil
    end
  end
end
