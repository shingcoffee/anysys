# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::MailAttachments do
  [nil, [], "invalid", { nil => "bytes" }, { "report.bin" => 123 },
   { "report.bin" => { content: 123 } }, { "report.bin" => {} },
   { "report.bin" => { filename: "/etc/passwd" } },
   { "report.bin" => { content: "bytes", encoding: "unsupported" } }].each do |input|
    it "rejects malformed public input #{input.inspect} with a localized facade error" do
      expect { described_class.encode(input) }
        .to raise_error(described_class::Error, I18n.t("code_generator_communication.invalid_attachments"))
    end
  end

  it "wraps expected Mail parsing errors with its namespaced boundary" do
    error = Mail::Field::ParseError.new("Content-Type", "invalid", "invalid field")
    allow(Mail).to receive(:new).and_raise(error)
    expect { described_class.encode("report.txt" => "bytes") }.to raise_error(described_class::Error) { |error|
      expect(error.cause).to be_a(Mail::Field::ParseError)
    }
  end

  it "localizes invalid public input in Simplified Chinese" do
    I18n.with_locale(:"zh-CN") do
      expect { described_class.encode(nil) }
        .to raise_error(described_class::Error, "附件必须以文件名为键，对应文件内容或有效的 Mail 附件选项")
    end
  end

  it "does not swallow unexpected programming errors in Mail" do
    allow(Mail).to receive(:new).and_raise(NoMethodError, "unexpected bug")
    expect { described_class.encode("report.txt" => "bytes") }.to raise_error(NoMethodError, "unexpected bug")
  end

  def reparse_attachment(filename, options)
    message = Mail.new
    message.attachments[filename] = options
    Mail.read_from_string(message.encoded).attachments.fetch(0)
  end

  it "encodes raw binary bytes as JSON-safe standard Mail options without mutating the source" do
    bytes = "report\x00\xFF\n".b.freeze
    encoded = described_class.encode("report.bin" => bytes)
    options = JSON.parse(JSON.dump(encoded)).fetch("report.bin").symbolize_keys
    attachment = reparse_attachment("report.bin", options)

    expect(attachment.body.decoded.b).to eq(bytes)
    expect(attachment.filename).to eq("report.bin")
    expect(attachment.content_transfer_encoding).to eq("base64")
    expect(bytes.encoding).to eq(Encoding::BINARY)
  end

  it "preserves descriptor metadata and decodes an existing transfer encoding before encoding" do
    bytes = "report\x00\xFF\n".b
    descriptor = { content: Base64.strict_encode64(bytes), encoding: "base64", mime_type: "application/pdf",
                   content_disposition: 'inline; filename="report.pdf"', content_id: "report@example.test",
                   "X-Attachment-Source" => "generated" }.freeze
    encoded = described_class.encode("report.pdf" => descriptor)
    options = JSON.parse(JSON.dump(encoded)).fetch("report.pdf").symbolize_keys
    attachment = reparse_attachment("report.pdf", options)

    expect(attachment.body.decoded.b).to eq(bytes)
    expect(attachment).to have_attributes(filename: "report.pdf", mime_type: "application/pdf", content_id: "<report@example.test>")
    expect(attachment).to be_inline
    expect(attachment["X-Attachment-Source"].value).to eq("generated")
    expect(descriptor[:content]).to eq(Base64.strict_encode64(bytes))
  end

  it "does not open a host path from a filename-only descriptor" do
    expect(File).not_to receive(:open)
    expect { described_class.encode("secret.txt" => { filename: "/etc/passwd" }) }
      .to raise_error(described_class::Error, I18n.t("code_generator_communication.invalid_attachments"))
  end

  it "ignores a descriptor filename when content bytes are supplied" do
    encoded = described_class.encode("report.bin" => { content: "bytes", filename: "/etc/passwd" })
    expect(encoded.fetch("report.bin").fetch(:content)).to eq(Base64.strict_encode64("bytes"))
  end

  it "preserves UTF-8 text attachments without changing their decoded content" do
    text = "Hello, 世界！"
    encoded = described_class.encode("notes.txt" => { "content" => text, "content_type" => "text/plain; charset=UTF-8" })
    options = JSON.parse(JSON.dump(encoded)).fetch("notes.txt").symbolize_keys
    attachment = reparse_attachment("notes.txt", options)

    expect(attachment.body.decoded.force_encoding(Encoding::UTF_8)).to eq(text)
    expect(attachment).to have_attributes(mime_type: "text/plain", charset: "UTF-8")
  end
end
