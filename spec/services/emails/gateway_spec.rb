# frozen_string_literal: true

require "rails_helper"

# Delivery executes in the job specs; this suite isolates admission/handoff.
RSpec.describe Emails::Gateway do
  let_it_be(:customer) { create(:customer) }
  let!(:template) do
    create(
      :email_template,
      customer: customer,
      name: "welcome",
      subject: "Hi #{platform_token('first_name')}",
      body_html: "<p>Hello #{platform_token('first_name')}</p>"
    )
  end
  let!(:credential) { create(:email_credential, mode: "sandbox") }

  before { allow(Emails::DeliverMessageJob).to receive(:perform_later).and_return(instance_double(Emails::DeliverMessageJob)) }

  describe ".send" do
    it "delegates to Activities::Send" do
      expect(Emails::Activities::Send).to receive(:call).with(
        customer:        customer,
        to:              "user@example.com",
        template_id:     template.id,
        vars:            { name: "John" },
        cc:              nil,
        bcc:             nil,
        reply_to:        nil,
        idempotency_key: nil,
        mode:            nil
      ).and_call_original

      described_class.send(
        customer:    customer,
        to:          "user@example.com",
        template_id: template.id,
        vars:        { name: "John" }
      )
    end

    it "passes through optional parameters" do
      result = described_class.send(
        customer:        customer,
        to:              "user@example.com",
        template_id:     template.id,
        vars:            { name: "John" },
        cc:              "cc@example.com",
        idempotency_key: "key-123"
      )
      expect(result.cc).to eq("cc@example.com")
      expect(result.idempotency_key).to eq("key-123")
    end
  end

  describe ".send_raw" do
    def send_raw(**overrides)
      described_class.send_raw(
        **{ customer: customer, to: "user@example.com", subject: "Test", body_html: "<p>Test</p>" }.merge(overrides)
      )
    end

    it "creates message without template" do
      result = send_raw(subject: "Direct Subject", body_html: "<p>Direct body</p>")

      expect(result).to be_a(Emails::Message)
      expect(result.subject).to eq("Direct Subject")
      expect(result.email_template_id).to be_nil
      expect(result.status).to eq("queued")
    end

    it "sets provider from the resolved credential" do
      expect(send_raw.provider).to eq(credential.provider)
    end

    it "auto-generates body_text from body_html when not provided" do
      result = send_raw(body_html: "<p>Hello <strong>World</strong></p>")
      expect(result.body_text).to eq("Hello World")
    end

    it "uses provided body_text when given" do
      result = send_raw(body_html: "<p>HTML</p>", body_text: "Custom text")
      expect(result.body_text).to eq("Custom text")
    end

    it "uses credential username as default from address" do
      expect(send_raw.from).to eq(credential.username)
    end

    it "uses provided from when given" do
      expect(send_raw(from: "custom@example.com").from).to eq("custom@example.com")
    end

    it "enqueues Emails::DeliverMessageJob with the message id and mode" do
      result = send_raw(mode: "sandbox")
      expect(Emails::DeliverMessageJob).to have_received(:perform_later).with(result.id, "sandbox")
    end

    it "handles idempotency_key" do
      first  = send_raw(idempotency_key: "raw-key")
      second = send_raw(idempotency_key: "raw-key")
      expect(second.id).to eq(first.id)
      expect(Emails::Message.count).to eq(1)
    end

    it "is race-safe against a RecordNotUnique from a concurrent duplicate insert" do
      allow(Emails::Message).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      existing = create(:email_message, customer: customer, idempotency_key: "race-key")

      result = send_raw(idempotency_key: "race-key")
      expect(result).to eq(existing)
    end

    context "when the recipient is suppressed (E-ARCH-4)" do
      before do
        Emails::Suppression.record_for_customer!(
          customer_id: customer.id, email: "bounced@example.com", reason: "hard_bounce"
        )
      end

      it "records the message as suppressed and does not enqueue delivery" do
        result = send_raw(to: "bounced@example.com")
        expect(result.status).to eq("suppressed")
        expect(Emails::DeliverMessageJob).not_to have_received(:perform_later)
      end

      it "still delivers to a non-suppressed recipient" do
        result = send_raw(to: "clean@example.com")
        expect(result.status).to eq("queued")
        expect(Emails::DeliverMessageJob).to have_received(:perform_later).with(result.id, nil)
      end
    end

    context "with the Aliyun RPC transport selected" do
      let!(:credential) do
        create(:email_credential, provider: "aliyun", mode: "sandbox", username: "historical-smtp@example.com",
               config: { "access_key_id" => "AKID", "from_email" => "api@example.com" })
      end

      [{ bcc: "private@example.com" }, { cc: "copy@example.com" }, { reply_to: "reply@example.com" },
       { body_html: '<img src="cid:blob-123">' }, { attachment_blob_ids: [123] }].each do |features|
        it "rejects unsupported raw/test-send features #{features.keys.inspect} before reservation" do
          expect(Emails::Quota).not_to receive(:reserve)
          expect {
            expect { send_raw(**features) }.to raise_error(Email::Errors::UnsupportedMessage)
          }.not_to change(Emails::Message, :count)
          expect(Emails::DeliverMessageJob).not_to have_received(:perform_later)
        end
      end

      it "continues to admit plain transactional email with the API From address" do
        expect(send_raw.from).to eq("api@example.com")
      end

      it "preserves replay-before-mutable-capability-check semantics" do
        existing = send_raw(idempotency_key: "accepted")
        expect(send_raw(idempotency_key: "accepted", bcc: "private@example.com")).to eq(existing)
        expect(Emails::DeliverMessageJob).to have_received(:perform_later).once
      end
    end
  end

  describe ".queue_for_send_activity" do
    let(:campaign_template) do
      create(:email_template, customer: customer, name: "campaign_msg",
             subject: "Hi #{platform_token('first_name')}",
             body_html: "<p>Hello #{platform_token('first_name')}</p>")
    end
    let(:list)     { create(:email_list, customer: customer) }
    let(:campaign) { create(:email_send_activity, customer: customer, email_template: campaign_template, email_lists: [list]) }
    let(:user)     { create(:user, customer: customer, email: "user@example.com", first_name: "Jane", last_name: "Doe") }

    it "creates a campaign-type message addressed to the user" do
      result = described_class.queue_for_send_activity(send_activity: campaign, user: user)

      expect(result.message_type).to eq("campaign")
      expect(result.to).to eq("user@example.com")
    end

    it "sets provider from the resolved credential" do
      result = described_class.queue_for_send_activity(send_activity: campaign, user: user)
      expect(result.provider).to eq(credential.provider)
    end

    it "embeds send_activity_id and user_id in metadata" do
      result = described_class.queue_for_send_activity(send_activity: campaign, user: user)

      expect(result.metadata["send_activity_id"]).to eq(campaign.id)
      expect(result.metadata["user_id"]).to eq(user.id)
    end

    it "renders the template using the user's first_name via VariableContext" do
      result = described_class.queue_for_send_activity(send_activity: campaign, user: user)
      expect(result.subject).to eq("Hi Jane")
    end

    it "uses credential username as from address" do
      result = described_class.queue_for_send_activity(send_activity: campaign, user: user)
      expect(result.from).to eq(credential.username)
    end

    it "enqueues Emails::DeliverMessageJob" do
      result = described_class.queue_for_send_activity(send_activity: campaign, user: user)
      expect(Emails::DeliverMessageJob).to have_received(:perform_later).with(result.id, nil)
    end

    it "includes attachment_blob_ids in message metadata" do
      result = described_class.queue_for_send_activity(send_activity: campaign, user: user)
      expect(result.metadata).to have_key("attachment_blob_ids")
      expect(result.metadata["attachment_blob_ids"]).to be_an(Array)
    end

    it "sets attachment_blob_ids to empty array for code templates with no attachments" do
      # campaign_template is a code-type template (default); no rich_text body attachments
      result = described_class.queue_for_send_activity(send_activity: campaign, user: user)
      expect(result.metadata["attachment_blob_ids"]).to eq([])
    end

    context "when the recipient is on the suppression ledger" do
      before { Emails::Suppression.record_global!(email: "user@example.com", reason: "hard_bounce") }

      it "creates a suppressed message and does not enqueue delivery" do
        result = described_class.queue_for_send_activity(send_activity: campaign, user: user)

        expect(result.status).to eq("suppressed")
        expect(Emails::DeliverMessageJob).not_to have_received(:perform_later)
      end
    end

    it "is race-safe against a RecordNotUnique from a concurrent duplicate insert" do
      allow(Emails::Message).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      existing = create(:email_message, customer: customer, idempotency_key: "campaign-race", message_type: "campaign")

      result = described_class.queue_for_send_activity(send_activity: campaign, user: user, idempotency_key: "campaign-race")
      expect(result).to eq(existing)
    end

    it "rejects an Aliyun campaign before quota reservation or ledger acceptance" do
      aliyun = create(:email_credential, provider: "aliyun", mode: "sandbox", username: nil,
                      config: { "access_key_id" => "AKID", "from_email" => "api@example.com" })
      expect(Emails::Quota).not_to receive(:reserve)
      expect {
        expect { described_class.queue_for_send_activity(send_activity: campaign, user: user, credential: aliyun) }
          .to raise_error(Email::Errors::UnsupportedMessage)
      }.not_to change(Emails::Message, :count)
      expect(Emails::DeliverMessageJob).not_to have_received(:perform_later)
    end
  end
end
