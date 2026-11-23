# frozen_string_literal: true

require "rails_helper"

# The job's private helper is named `log_send_outcome` (NOT `instrument`) so it
# no longer shadows ActiveJob::Instrumentation#instrument — so ActiveJob entry
# points (`perform_now`, `perform_later`) run cleanly, and the `retry_on
# StandardError` dead-letter path is reachable end-to-end (exercised below).
# Business-logic examples call `#perform` directly for isolation; the
# dead-letter example drives the real ActiveJob retry machinery.
RSpec.describe Emails::DeliverMessageJob do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:email_module) { enable_module!("email", customer, name: "Email") }

  describe "ActiveJob entry points (no longer shadowed by a private #instrument)" do
    let!(:credential) { create(:email_credential, mode: "sandbox") }

    it "delivers via perform_now and marks the message sent" do
      message = create(:email_message, :queued, customer: customer)
      allow_any_instance_of(Email::Providers::Smtp).to receive(:deliver).and_return(provider_message_id: "pm-1", raw: {})

      described_class.new(message.id, "sandbox").perform_now

      expect(message.reload.status).to eq("sent")
    end

    it "enqueues via perform_later without raising" do
      message = create(:email_message, :queued, customer: customer)

      expect { described_class.perform_later(message.id, "sandbox") }.not_to raise_error
    end
  end

  describe "#perform (business logic, called directly to bypass the collision above)" do
    let!(:credential) { create(:email_credential, mode: "sandbox") }
    let(:message) { create(:email_message, :queued, customer: customer) }

    it "delivers via the resolved provider and marks the message sent with the provider_message_id" do
      allow_any_instance_of(Email::Providers::Smtp).to receive(:deliver)
        .and_return(provider_message_id: "pm-1", raw: {})

      described_class.new.perform(message.id, "sandbox")

      expect(message.reload.status).to eq("sent")
      expect(message.provider_message_id).to eq("pm-1")
    end

    it "resolves the credential using the message's own provider and the given mode" do
      expect(Email::CredentialResolver).to receive(:call)
        .with(provider: message.provider, mode: "sandbox").and_call_original
      allow_any_instance_of(Email::Providers::Smtp).to receive(:deliver).and_return(provider_message_id: nil, raw: {})

      described_class.new.perform(message.id, "sandbox")
    end

    it "defaults mode to CredentialResolver.default_mode when mode is nil" do
      expect(Email::CredentialResolver).to receive(:call)
        .with(provider: message.provider, mode: Email::CredentialResolver.default_mode).and_call_original
      allow_any_instance_of(Email::Providers::Smtp).to receive(:deliver).and_return(provider_message_id: nil, raw: {})

      described_class.new.perform(message.id, nil)
    end

    it "marks the message failed (no retry) on Email::Errors::ApiError" do
      allow_any_instance_of(Email::Providers::Smtp).to receive(:deliver)
        .and_raise(Email::Errors::ApiError.new("rejected", code: "500"))

      described_class.new.perform(message.id, "sandbox")

      expect(message.reload.status).to eq("failed")
      expect(message.failure_code).to eq("500")
      expect(message.failure_message).to eq("rejected")
    end

    it "is a no-op when the message no longer exists" do
      expect { described_class.new.perform(-1, "sandbox") }.not_to raise_error
    end

    it "is a no-op when the message is not in the queued status (already handled/terminal)" do
      sent_message = create(:email_message, :sent, customer: customer)
      expect(Email::CredentialResolver).not_to receive(:call)

      described_class.new.perform(sent_message.id, "sandbox")
    end

    it "leaves the message queued when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)
      expect(Email::CredentialResolver).not_to receive(:call)

      described_class.new.perform(message.id, "sandbox")
      expect(message.reload.status).to eq("queued")
    end

    it "propagates a non-ApiError StandardError (transport failure) — the caller (ActiveJob retry) owns recovery" do
      allow_any_instance_of(Email::Providers::Smtp).to receive(:deliver)
        .and_raise(Email::Errors::TransportError, "timeout")

      expect { described_class.new.perform(message.id, "sandbox") }.to raise_error(Email::Errors::TransportError)
      expect(message.reload.status).to eq("queued") # unchanged — perform doesn't rescue non-ApiError itself
    end
  end

  describe "dead-letter after exhausting retries (E-TEST-1)" do
    let!(:credential) { create(:email_credential, mode: "sandbox") }
    let(:message) { create(:email_message, :queued, customer: customer) }

    it "marks the message failed with the error class once transient retries are exhausted" do
      allow_any_instance_of(Email::Providers::Smtp).to receive(:deliver)
        .and_raise(Email::Errors::TransportError, "timeout")

      perform_enqueued_jobs do
        described_class.perform_later(message.id, "sandbox")
      end

      expect(message.reload.status).to eq("failed")
      expect(message.failure_code).to eq("Email::Errors::TransportError")
      expect(message.failure_message).to eq("timeout")
    end
  end

  it "is enqueued on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  describe "tracking injection" do
    let(:provider_instance) { instance_double("Email::Providers::Base", deliver: { provider_message_id: "pi_789" }) }
    let(:credential) { create(:email_credential) }
    let(:customer) { create(:customer) }

    before do
      enable_module!("email", customer, name: "Email")
      allow(Email::Providers).to receive(:for).and_return(double(new: provider_instance, configured?: true))
      allow(Email::CredentialResolver).to receive(:call).and_return(credential)
    end

    it "injects tracking into raw emails when metadata[:tracking_enabled] is true" do
      message = create(:email_message,
        customer: customer,
        status: "queued",
        body_html: "<body><a href='https://example.com'>Link</a></body>",
        metadata: { "tracking_enabled" => true }
      )

      described_class.new.perform(message.id)

      message.reload
      expect(message.body_html).to include("open.gif?sig=")
      expect(message.body_html).to include("/email/track/#{message.id}/click")
    end

    it "injects tracking into emails when metadata[:tracking_enabled] is true" do
      template = create(:email_template, customer: customer, body_html: "<body><a href='{{link}}'>Link</a></body>")
      message = create(:email_message,
        customer: customer,
        email_template: template,
        status: "queued",
        body_html: "<body><a href='https://example.com'>Link</a></body>",
        metadata: { "tracking_enabled" => true, "vars" => { "link" => "https://example.com" } }
      )

      described_class.new.perform(message.id)

      message.reload
      expect(message.body_html).to include("open.gif?sig=")
      expect(message.body_html).to include("/email/track/#{message.id}/click")
    end
  end
end
