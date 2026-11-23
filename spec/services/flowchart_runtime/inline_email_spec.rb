# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::InlineEmail do
  let(:customer) { create(:customer) }
  let(:ctx) { { customer_id: customer.id, errors: [] } }

  before { allow(Emails::DeliverMessageJob).to receive(:perform_later) }

  it "sends one message per recipient and records bcc plus attachments" do
    create(:email_credential, mode: "sandbox")
    document = FlowchartRuntime::Document.pdf(title: "Invoice", body: "Thanks", filename: "invoice.pdf",
                                              customer_id: customer.id)

    ids = described_class.deliver(
      ctx,
      to: ["sales@example.com", "ops@example.com"],
      subject: "Hello",
      body: "Hi",
      bcc: "audit@example.com",
      attachments: document
    )

    expect(ids.size).to eq(2)
    messages = Emails::Message.where(id: ids)
    expect(messages.map(&:to)).to match_array(%w[sales@example.com ops@example.com])
    expect(messages.map(&:bcc).uniq).to eq(["audit@example.com"])
    expect(messages.map { |message| message.metadata["attachment_blob_ids"] }.uniq).to eq([[document["blob_id"]]])
  end

  it "attaches an in-memory file as a blob of the run's customer" do
    create(:email_credential, mode: "sandbox")
    file = FlowchartRuntime::FilePayload.wrap("id,total\n1,9.50\n", filename: "orders.csv", content_type: "text/csv")

    ids = described_class.deliver(ctx, to: "sales@example.com", subject: "Orders", body: "Attached",
                                       attachments: [file, { "filename" => "empty.txt", "content" => "" }])

    blob_ids = Emails::Message.find(ids.first).metadata["attachment_blob_ids"]
    expect(blob_ids.size).to eq(1)
    blob = ActiveStorage::Blob.find(blob_ids.first)
    expect([blob.filename.to_s, blob.content_type, blob.customer_id, blob.download])
      .to eq(["orders.csv", "text/csv", customer.id, "id,total\n1,9.50\n"])
  end

  it "attaches the files a record's File or Image field holds" do
    create(:email_credential, mode: "sandbox")
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Contract", "name_slug" => "contract", "html_type" => "file" },
      { "name" => "Scans", "name_slug" => "scans", "html_type" => "file", "config" => { "multiple" => true } }
    ].to_json)
    file = ->(name) { { io: StringIO.new("%PDF-1.4\n"), filename: name } }
    record = EntityEntry.build_for(entity).create!(customer_id: customer.id, contract: file.call("terms.pdf"),
                                                   scans: [file.call("a.pdf"), file.call("b.pdf")])
    record = EntityEntry.build_for(entity).find(record.id)

    ids = described_class.deliver(ctx, to: "sales@example.com", subject: "Contract", body: "Attached",
                                       attachments: [record.contract, record.scans, record.scans.first])

    expect(Emails::Message.find(ids.first).metadata["attachment_blob_ids"])
      .to eq([record.contract.blob.id, *record.scans.blobs.map(&:id), record.scans.first.blob_id])
  end

  it "returns [] and keeps the run when on_error is continue" do
    allow(Email::CredentialResolver).to receive(:call).and_raise(Email::Errors::CredentialsMissing, "none")

    expect(described_class.deliver(ctx, to: "sales@example.com", subject: "Hi", body: "Hi")).to eq([])
    expect(ctx[:errors]).to eq([])
  end

  it "fails the run when on_error is fail" do
    allow(Email::CredentialResolver).to receive(:call).and_raise(Email::Errors::CredentialsMissing, "none")

    expect(described_class.deliver(ctx, to: "sales@example.com", subject: "Hi", body: "Hi", on_error: "fail")).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.send_email.failed"))
  end
end
