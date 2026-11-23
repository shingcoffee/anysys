# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartMailer do
  it "preserves the plain fallback and attachment bytes after wire-format serialization" do
    bytes = "report\x00\xFF\n".b
    delivery = described_class.notification(to: "to@example.test", subject: "Report", body: "Plain report",
      attachments: { "report.bin" => bytes })
    message = Mail.read_from_string(delivery.message.encoded)

    expect(message.mime_type).to eq("multipart/mixed")
    expect(message).to be_multipart
    expect(message.text_part.body.decoded).to eq("Plain report")
    expect(message.html_part).to be_nil
    expect(message.attachments.size).to eq(1)
    expect(message.attachments["report.bin"].body.decoded.b).to eq(bytes)
  end

  it "keeps an attachment-free fallback as plain text after serialization" do
    delivery = described_class.notification(to: "to@example.test", subject: "Report", body: "Plain report")
    message = Mail.read_from_string(delivery.message.encoded)

    expect(message.mime_type).to eq("text/plain")
    expect(message).not_to be_multipart
    expect(message.body.decoded).to eq("Plain report")
    expect(message.attachments).to be_empty
  end

  it "rejects header injection in cc before the message is built" do
    expect {
      described_class.notification(to: "to@example.test", subject: "Report",
        cc: "cc@example.test\nBcc: attacker@evil.test").message
    }.to raise_error(FlowchartRuntime::MailHeaders::Error, I18n.t("code_generator_communication.invalid_recipients"))
  end

  it "collapses CR/LF in the subject so it cannot append headers" do
    message = described_class.notification(to: "to@example.test",
      subject: "Report\nBcc: attacker@evil.test").message
    expect(message.subject).to eq("Report Bcc: attacker@evil.test")
    expect(message.bcc).to be_blank
  end
end
