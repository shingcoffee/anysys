# frozen_string_literal: true

require "rails_helper"

# Delivery executes in the job specs; this suite isolates admission/handoff.
RSpec.describe Emails::Activities::Send do
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

  before do
    allow(Emails::DeliverMessageJob).to receive(:perform_later).and_return(instance_double(Emails::DeliverMessageJob))
    allow(Emails::DeliverMessageJob).to receive(:set).and_return(Emails::DeliverMessageJob)
  end

  describe ".call" do
    let(:valid_params) do
      {
        customer:    customer,
        to:          "user@example.com",
        template_id: template.id,
        vars:        { first_name: "John" }
      }
    end

    context "with valid inputs" do
      it "creates an Emails::Message" do
        expect { described_class.call(**valid_params) }
          .to change(Emails::Message, :count).by(1)
      end

      it "returns the created message" do
        result = described_class.call(**valid_params)
        expect(result).to be_a(Emails::Message)
        expect(result.to).to eq("user@example.com")
        expect(result.status).to eq("queued")
      end

      it "renders template variables" do
        result = described_class.call(**valid_params)
        expect(result.body_html).to include("John")
        expect(result.subject).to eq("Hi John")
      end

      it "enqueues Emails::DeliverMessageJob with the message id and mode" do
        result = described_class.call(**valid_params, mode: "sandbox")
        expect(Emails::DeliverMessageJob).to have_received(:perform_later).with(result.id, "sandbox")
      end

      it "sets message_type to transactional" do
        result = described_class.call(**valid_params)
        expect(result.message_type).to eq("transactional")
      end

      it "sets the provider from the resolved credential" do
        result = described_class.call(**valid_params)
        expect(result.provider).to eq(credential.provider)
      end

      it "uses credential username as from address" do
        result = described_class.call(**valid_params)
        expect(result.from).to eq(credential.username)
      end
    end

    context "with idempotency_key" do
      it "returns existing message on duplicate key" do
        first = described_class.call(**valid_params, idempotency_key: "unique-123")
        second = described_class.call(**valid_params, idempotency_key: "unique-123")

        expect(second.id).to eq(first.id)
        expect(Emails::Message.count).to eq(1)
      end

      it "creates new message for different key" do
        first = described_class.call(**valid_params, idempotency_key: "key-1")
        second = described_class.call(**valid_params, idempotency_key: "key-2")

        expect(second.id).not_to eq(first.id)
      end

      it "does not re-enqueue when returning the pre-existing idempotent message" do
        described_class.call(**valid_params, idempotency_key: "unique-123")
        described_class.call(**valid_params, idempotency_key: "unique-123")

        expect(Emails::DeliverMessageJob).to have_received(:perform_later).once
      end

      it "is race-safe against a RecordNotUnique from a concurrent duplicate insert" do
        allow(Emails::Message).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
        existing = create(:email_message, customer: customer, idempotency_key: "race-key", status: "queued")

        result = described_class.call(**valid_params, idempotency_key: "race-key")

        expect(result).to eq(existing)
        expect(Emails::DeliverMessageJob).not_to have_received(:perform_later)
      end
    end

    context "with invalid inputs" do
      it "raises TemplateVarsInvalid on contract failure" do
        expect {
          described_class.call(customer: customer, to: "", template_id: template.id, vars: {})
        }.to raise_error(Email::Errors::TemplateVarsInvalid)
      end

      it "raises TemplateVarsInvalid for non-existent template" do
        expect {
          described_class.call(customer: customer, to: "a@b.com", template_id: -1, vars: { name: "X" })
        }.to raise_error(Email::Errors::TemplateVarsInvalid)
      end

      it "does not persist a message or enqueue delivery on contract failure" do
        expect {
          described_class.call(customer: customer, to: "", template_id: template.id, vars: {}) rescue nil
        }.not_to change(Emails::Message, :count)
        expect(Emails::DeliverMessageJob).not_to have_received(:perform_later)
      end
    end

    context "suppression" do
      before { Emails::Suppression.record_global!(email: "suppressed@example.com", reason: "hard_bounce") }

      it "creates a message with status suppressed instead of dispatching" do
        result = described_class.call(**valid_params, to: "suppressed@example.com")
        expect(result.status).to eq("suppressed")
      end

      it "does not enqueue delivery for a suppressed address" do
        described_class.call(**valid_params, to: "suppressed@example.com")
        expect(Emails::DeliverMessageJob).not_to have_received(:perform_later)
      end
    end

    context "with a tenant-scoped (not global) suppression" do
      let!(:other_customer) { create(:customer) }

      before do
        Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "tenant-only@example.com", reason: "manual")
        create(:email_template, customer: other_customer, name: "welcome")
      end

      it "suppresses the send for the owning tenant" do
        result = described_class.call(**valid_params, to: "tenant-only@example.com")
        expect(result.status).to eq("suppressed")
      end

      it "does NOT suppress the same address for a different tenant" do
        other_template = Emails::Template.find_by!(customer: other_customer, name: "welcome")
        result = described_class.call(customer: other_customer, to: "tenant-only@example.com",
                                       template_id: other_template.id, vars: { name: "X" })
        expect(result.status).to eq("queued")
      end
    end

    context "when the transactional daily cap is exhausted" do
      before do
        allow(described_class).to receive(:daily_cap_for).with(customer).and_return(1)
        create(:email_message, customer: customer, message_type: "transactional", status: "queued")
      end

      it "raises DailyCapExceeded before persisting another message" do
        count_before = Emails::Message.count

        expect { described_class.call(**valid_params) }
          .to raise_error(Email::Errors::DailyCapExceeded)

        expect(Emails::Message.count).to eq(count_before)
      end

      it "does not count suppressed or failed transactional messages against the cap" do
        Emails::Message.where(customer: customer).update_all(status: "suppressed")

        expect { described_class.call(**valid_params) }
          .to change(Emails::Message, :count).by(1)
      end
    end

    context "when two sends race the transactional daily cap" do
      before do
        allow(described_class).to receive(:daily_cap_for).with(customer).and_return(1)
      end

      it "re-checks the cap under a customer lock so a concurrent send cannot slip past" do
        allow(customer).to receive(:with_lock).and_wrap_original do |method, &block|
          create(:email_message, customer: customer, message_type: "transactional", status: "queued")
          method.call(&block)
        end

        expect { described_class.call(**valid_params) }
          .to raise_error(Email::Errors::DailyCapExceeded)
      end
    end

    context "with optional fields" do
      it "schedules delivery when scheduled_at is provided in the future" do
        future_time = 1.hour.from_now.change(usec: 123456).utc
        result = described_class.call(
          **valid_params,
          scheduled_at: future_time
        )
        expect(Emails::DeliverMessageJob).to have_received(:set).with(wait_until: future_time)
        expect(result.reload.delivery_due_at.utc).to eq(future_time)
        expect(Emails::DeliverMessageJob).to have_received(:perform_later).with(result.id, nil)
      end

      it "sets cc, bcc, reply_to when provided" do
        result = described_class.call(
          **valid_params,
          cc:       "cc@example.com",
          bcc:      "bcc@example.com",
          reply_to: "reply@example.com"
        )
        expect(result.cc).to eq("cc@example.com")
        expect(result.bcc).to eq("bcc@example.com")
        expect(result.reply_to).to eq("reply@example.com")
      end
    end

    describe "provider selection" do
      let!(:ses_credential) do
        create(:email_credential, provider: "ses", mode: "sandbox", status: "active",
               host: nil, username: nil, password: "secret",
               config: { "access_key_id" => "AKID", "from_email" => "ses@example.com",
                         "sns_topic_arn" => "arn:aws:sns:us-east-1:1:receipts" })
      end

      it "honours an explicit provider argument" do
        result = described_class.call(**valid_params, provider: "ses")
        expect(result.provider).to eq("ses")
        expect(result.from).to eq("ses@example.com")
      end

      it "defaults to the default provider (smtp) when none is named" do
        result = described_class.call(**valid_params)
        expect(result.provider).to eq("smtp")
      end
    end

    context "Aliyun transactional admission" do
      let!(:aliyun) do
        create(:email_credential, provider: "aliyun", mode: "sandbox", username: "historical-smtp@example.com",
               config: { "access_key_id" => "AKID", "from_email" => "api@example.com" })
      end

      it "rejects unsupported envelope features before spending quota or persisting a row" do
        expect(Emails::Quota).not_to receive(:reserve)
        expect {
          expect { described_class.call(**valid_params, provider: "aliyun", bcc: "private@example.com") }
            .to raise_error(Email::Errors::UnsupportedMessage)
        }.not_to change(Emails::Message, :count)
        expect(Emails::DeliverMessageJob).not_to have_received(:perform_later)
      end

      it "rejects a template's CID image during admission" do
        template.update!(body_html: '<img src="cid:blob-123">')
        expect {
          expect { described_class.call(**valid_params, provider: "aliyun") }
            .to raise_error(Email::Errors::UnsupportedMessage)
        }.not_to change(Emails::Message, :count)
      end

      it "uses the API From address for a supported transactional message" do
        expect(described_class.call(**valid_params, provider: "aliyun").from).to eq("api@example.com")
      end
    end
  end
end
