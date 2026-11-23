# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::DeliveryMailer, type: :mailer do
  let(:customer)    { create(:customer) }
  let!(:credential) { create(:email_credential, mode: "sandbox", host: "smtp.test", username: "smtp@example.com") }
  let(:message) do
    create(:email_message, :queued, customer: customer,
      to: "r@example.com", from: "s@example.com", cc: "c@example.com",
      subject: "Hello {{name}}", body_html: "<p>Hi body</p>", body_text: "Hi text")
  end

  def build = described_class.with(message_id: message.id, mode: "sandbox").deliver_email

  it "pulls the envelope from the ledger row" do
    m = build
    expect(m.to).to eq(["r@example.com"])
    expect(m.from).to eq(["s@example.com"])
    expect(m.cc).to eq(["c@example.com"])
    expect(m.subject).to eq("Hello {{name}}") # already-rendered; mailer does not interpolate
  end

  it "emits the stored body as multipart text + html (no layout wrapping)" do
    m = build
    expect(m.text_part.body.decoded).to include("Hi text")
    expect(m.html_part.body.decoded).to include("<p>Hi body</p>")
    expect(m.html_part.body.decoded).not_to include("<html") # layout false
  end

  it "stamps correlation headers and native SMTP options" do
    m = build
    expect(m["X-Anysys-Message-Id"].value).to eq(message.id.to_s)
    expect(m["X-Anysys-Mode"].value).to eq("sandbox")
    expect(m["X-Anysys-Credential-Id"].value).to eq(credential.id.to_s)
    expect(m.delivery_method.settings[:address]).to eq("smtp.test")
    expect(m.delivery_method.settings[:user_name]).to eq("smtp@example.com")
  end

  describe "RFC 8058 one-click unsubscribe headers" do
    let(:recipient) { create(:user, customer: customer) }
    let(:campaign_message) do
      create(:email_message, :queued, customer: customer, to: recipient.email,
             from: "s@example.com", subject: "Campaign", body_html: "<p>c</p>", body_text: "c",
             message_type: "campaign", metadata: { "user_id" => recipient.id })
    end

    it "stamps List-Unsubscribe + List-Unsubscribe-Post on campaign mail" do
      m = described_class.with(message_id: campaign_message.id, mode: "sandbox").deliver_email
      expect(m["List-Unsubscribe"].value).to match(%r{\A<https?://.+/unsubscribe/.+>\z})
      expect(m["List-Unsubscribe-Post"].value).to eq("List-Unsubscribe=One-Click")

      # The embedded token must resolve back to the recipient.
      token = m["List-Unsubscribe"].value[%r{/unsubscribe/([^>]+)>}, 1]
      expect(Emails::SendActivities::SendActivityUnsubscribe.find_user(CGI.unescape(token))&.id).to eq(recipient.id)
    end

    it "does not stamp unsubscribe headers on transactional mail" do
      m = build
      expect(m["List-Unsubscribe"]).to be_nil
      expect(m["List-Unsubscribe-Post"]).to be_nil
    end

    it "omits the headers when the campaign message has no recipient identity" do
      campaign_message.update!(metadata: {})
      m = described_class.with(message_id: campaign_message.id, mode: "sandbox").deliver_email
      expect(m["List-Unsubscribe"]).to be_nil
    end

    it "signs the queued address and customer after the user's email and tenant change" do
      queued = campaign_message
      original_email = queued.to
      recipient.update!(email: "changed@example.com", customer: create(:customer))

      m = described_class.with(message_id: queued.id, mode: "sandbox").deliver_email
      token = CGI.unescape(m["List-Unsubscribe"].value[%r{/unsubscribe/([^>]+)>}, 1])
      Emails::SendActivities::SendActivityUnsubscribe.unsubscribe(token)

      expect(Emails::Suppression.suppressed?(customer_id: customer.id, email: original_email)).to be(true)
      expect(Emails::Suppression.suppressed?(customer_id: recipient.customer_id, email: recipient.email)).to be(false)
    end
  end

  it "no-ops (delivers nothing) when the ledger row is missing" do
    expect { described_class.with(message_id: -1, mode: "sandbox").deliver_email.deliver_now }
      .not_to change { ActionMailer::Base.deliveries.size }
  end

  it "inlines only same-tenant blobs" do
    own = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("a"), filename: "a.png", content_type: "image/png")
    own.update!(customer_id: customer.id)
    other = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("b"), filename: "b.png", content_type: "image/png")
    other.update!(customer_id: create(:customer).id)
    message.update!(metadata: { "attachment_blob_ids" => [own.id, other.id] })

    cids = build.attachments.select(&:inline?).map { |p| p.content_id.to_s }
    expect(cids.join).to include("blob-#{own.id}")
    expect(cids.join).not_to include("blob-#{other.id}")
  end

  # Pure transport: the mailer's rescue_from was removed by design — status
  # (sent/failed) is owned exclusively by Emails::DeliverMessageJob, which
  # invokes this mailer via deliver_now and catches/records outcomes itself.
  # A transport-level raise here must propagate unmodified and must NOT touch
  # the ledger row.
  it "propagates a transport failure without touching the ledger row (status ownership moved to the job)" do
    allow_any_instance_of(described_class).to receive(:smtp_settings).and_return(address: "smtp.test", port: 587)
    mailer = described_class.with(message_id: message.id, mode: "sandbox").deliver_email
    allow(mailer.message).to receive(:deliver).and_raise(Net::SMTPServerBusy.new("busy"))
    expect { mailer.deliver_now }.to raise_error(Net::SMTPServerBusy)
    expect(message.reload.status).to eq("queued")
  end

  it "propagates CredentialsMissing without touching the ledger row when no credential exists for the mode" do
    allow(Email::CredentialResolver).to receive(:call).and_raise(Email::Errors::CredentialsMissing.new("none"))
    mailer = described_class.with(message_id: message.id, mode: "sandbox").deliver_email
    expect { mailer.deliver_now }.to raise_error(Email::Errors::CredentialsMissing)
    expect(message.reload.status).to eq("queued")
  end

  it "rejects a nonexistent pinned credential identity" do
    mailer = described_class.with(message_id: message.id, mode: "sandbox", credential_id: credential.id + 1).deliver_email
    expect { mailer.message }.to raise_error(Email::Errors::CredentialsMissing)
  end

  it "uses the original SMTP account for queued delivery after it is unassigned" do
    credential.update!(status: "disabled")
    m = described_class.with(message_id: message.id, mode: "sandbox", credential_id: credential.id).deliver_email
    expect(m.delivery_method.settings[:address]).to eq("smtp.test")
    expect { described_class.with(message_id: message.id, mode: "sandbox").deliver_email.message }
      .to raise_error(Email::Errors::CredentialsMissing)
  end
end
