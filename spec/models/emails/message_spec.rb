# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Message do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "is valid with required attributes" do
    expect(build(:email_message, customer: customer)).to be_valid
  end

  it "requires customer_id" do
    Current.customer = nil
    message = build(:email_message, customer_id: nil)
    expect(message).not_to be_valid
    expect(message.errors[:customer_id]).to include("can't be blank")
    Current.customer = customer
  end

  it "requires to" do
    message = build(:email_message, to: nil)
    expect(message).not_to be_valid
    expect(message.errors[:to]).to include("can't be blank")
  end

  it "requires from" do
    message = build(:email_message, from: nil)
    expect(message).not_to be_valid
    expect(message.errors[:from]).to include("can't be blank")
  end

  it "requires subject" do
    message = build(:email_message, subject: nil)
    expect(message).not_to be_valid
    expect(message.errors[:subject]).to include("can't be blank")
  end

  it "requires body_html" do
    message = build(:email_message, body_html: nil)
    expect(message).not_to be_valid
    expect(message.errors[:body_html]).to include("can't be blank")
  end

  it "validates status inclusion" do
    message = build(:email_message, status: "invalid")
    expect(message).not_to be_valid
    expect(message.errors[:status]).to include("is not included in the list")
  end

  %w[complained suppressed].each do |status|
    it "accepts the new #{status} status" do
      expect(build(:email_message, status: status)).to be_valid
    end
  end

  it "validates message_type inclusion" do
    message = build(:email_message, message_type: "invalid")
    expect(message).not_to be_valid
    expect(message.errors[:message_type]).to include("is not included in the list")
  end

  it "accepts a provider and provider_message_id" do
    message = build(:email_message, provider: "ses", provider_message_id: "ses-123")
    expect(message).to be_valid
  end

  it "enforces [customer_id, idempotency_key] uniqueness when idempotency_key present" do
    create(:email_message, customer: customer, idempotency_key: "unique-key")
    dup = build(:email_message, customer: customer, idempotency_key: "unique-key")
    expect(dup).not_to be_valid
    expect(dup.errors[:idempotency_key]).to include("has already been taken")
  end

  it "allows multiple rows with NULL idempotency_key" do
    create(:email_message, customer: customer, idempotency_key: nil)
    another = build(:email_message, customer: customer, idempotency_key: nil)
    expect(another).to be_valid
  end

  it "allows same idempotency_key for different customers" do
    customer2 = create(:customer)
    create(:email_message, customer: customer, idempotency_key: "unique-key")
    another = build(:email_message, customer: customer2, idempotency_key: "unique-key")
    expect(another).to be_valid
  end

  describe "#terminal?" do
    %w[delivered bounced complained failed suppressed].each do |status|
      it "is true for #{status}" do
        expect(build(:email_message, status: status).terminal?).to be true
      end
    end

    %w[pending queued sent].each do |status|
      it "is false for #{status}" do
        expect(build(:email_message, status: status).terminal?).to be false
      end
    end
  end

  describe ".non_terminal scope" do
    it "excludes terminal-status rows" do
      queued    = create(:email_message, customer: customer, status: "queued")
      delivered = create(:email_message, customer: customer, status: "delivered")
      expect(described_class.non_terminal).to include(queued)
      expect(described_class.non_terminal).not_to include(delivered)
    end
  end

  describe "state transitions" do
    let(:message) { create(:email_message, customer: customer, status: "queued") }

    describe "#mark_sent!" do
      it "transitions to sent and records the provider_message_id" do
        message.mark_sent!(provider_message_id: "pm-1")
        message.reload
        expect(message.status).to eq("sent")
        expect(message.sent_at).to be_present
        expect(message.provider_message_id).to eq("pm-1")
      end

      it "defaults provider_message_id to nil (SMTP has none)" do
        message.mark_sent!
        expect(message.reload.provider_message_id).to be_nil
      end

      it "is a no-op once already sent (idempotent)" do
        message.update!(status: "sent", sent_at: 1.hour.ago)
        original_sent_at = message.sent_at
        message.mark_sent!(provider_message_id: "new-id")
        expect(message.reload.sent_at).to be_within(1.second).of(original_sent_at)
        expect(message.provider_message_id).to be_nil
      end

      it "is a no-op once terminal (e.g. already delivered)" do
        message.update!(status: "delivered", delivered_at: Time.current)
        message.mark_sent!(provider_message_id: "late")
        expect(message.reload.status).to eq("delivered")
      end
    end

    describe "#mark_delivered!" do
      it "transitions sent -> delivered" do
        message.update!(status: "sent")
        message.mark_delivered!
        expect(message.reload.status).to eq("delivered")
        expect(message.delivered_at).to be_present
      end

      it "is the success floor — does not regress once delivered" do
        message.update!(status: "delivered", delivered_at: 1.hour.ago)
        original = message.delivered_at
        message.mark_delivered!
        expect(message.reload.delivered_at).to be_within(1.second).of(original)
      end

      %w[bounced complained suppressed].each do |terminal_status|
        it "is a no-op once #{terminal_status} (delivered never overwrites another terminal status)" do
          message.update!(status: terminal_status)
          message.mark_delivered!
          expect(message.reload.status).to eq(terminal_status)
        end
      end
    end

    describe "#mark_bounced!" do
      it "records bounce code + message and transitions to bounced" do
        message.mark_bounced!(code: "HardBounce", message: "Mailbox not found")
        message.reload
        expect(message.status).to eq("bounced")
        expect(message.failure_code).to eq("HardBounce")
        expect(message.failure_message).to eq("Mailbox not found")
      end

      it "truncates a vendor diagnostic longer than 255 characters" do
        long = "x" * 300
        message.mark_bounced!(code: "HardBounce", message: long)
        expect(message.reload.failure_message.length).to eq(255)
      end

      it "is a no-op once delivered — a late bounce never un-delivers" do
        message.update!(status: "delivered", delivered_at: Time.current)
        message.mark_bounced!(code: "HardBounce", message: "late")
        expect(message.reload.status).to eq("delivered")
      end

      %w[bounced complained suppressed].each do |terminal_status|
        it "is a no-op once already #{terminal_status}" do
          message.update!(status: terminal_status)
          message.mark_bounced!(code: "X", message: "x")
          expect(message.reload.status).to eq(terminal_status)
        end
      end
    end

    describe "#mark_complained!" do
      it "transitions to complained with a default code" do
        message.mark_complained!
        message.reload
        expect(message.status).to eq("complained")
        expect(message.failure_code).to eq("complaint")
      end

      it "accepts an explicit code and message" do
        message.mark_complained!(code: "SpamComplaint", message: "reported as spam")
        message.reload
        expect(message.failure_code).to eq("SpamComplaint")
        expect(message.failure_message).to eq("reported as spam")
      end

      it "is a no-op once already complained" do
        message.update!(status: "complained")
        message.mark_complained!(code: "again")
        expect(message.reload.failure_code).not_to eq("again")
      end

      it "is a no-op once suppressed" do
        message.update!(status: "suppressed")
        message.mark_complained!
        expect(message.reload.status).to eq("suppressed")
      end

      it "DOES overwrite a merely-delivered/bounced message (complaint is not blocked by delivered)" do
        message.update!(status: "delivered", delivered_at: Time.current)
        message.mark_complained!(code: "SpamComplaint")
        expect(message.reload.status).to eq("complained")
      end
    end

    describe "#mark_failed!" do
      it "records failure code + message" do
        message.mark_failed!(code: "SMTP_ERROR", message: "Connection refused")
        message.reload
        expect(message.status).to eq("failed")
        expect(message.failure_code).to eq("SMTP_ERROR")
        expect(message.failure_message).to eq("Connection refused")
      end

      %w[sent delivered bounced complained suppressed].each do |protected_status|
        it "is a no-op once #{protected_status} — a late failure never clobbers it" do
          message.update!(status: protected_status)
          message.mark_failed!(code: "LATE", message: "late failure")
          expect(message.reload.status).to eq(protected_status)
        end
      end
    end

    describe "#mark_suppressed!" do
      it "transitions to suppressed" do
        message.mark_suppressed!
        expect(message.reload.status).to eq("suppressed")
      end
    end
  end
end
