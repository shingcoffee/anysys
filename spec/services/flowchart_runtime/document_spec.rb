# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Document do
  def pdf_text(payload)
    payload.to_s.scan(/BT(.*?)ET/m).flat_map do |(block)|
      hex = block.scan(/<([0-9A-Fa-f]+)>/).map { |pair| [pair.first].pack("H*") }
      literals = block.scan(/\((?:\\.|[^\\)])*\)/).map do |token|
        token[1..-2].gsub(/\\n/, "\n").gsub(/\\(.)/, '\\1')
      end
      hex + literals
    end.join
  end

  it "renders title, headings, table values and stores a tenant-tagged blob" do
    customer = create(:customer)
    result = described_class.pdf(
      title: "Invoice Ada",
      body: "Hello Ada\n\n## Items",
      rows: [{ "item" => "Widgets", "qty" => 2 }],
      columns: [{ "key" => "Item", "value" => "item" }],
      filename: "invoice.pdf",
      customer_id: customer.id
    )

    blob = ActiveStorage::Blob.find(result["blob_id"])
    expect(result["filename"]).to eq("invoice.pdf")
    expect(result["customer_id"]).to eq(customer.id)
    expect(blob.customer_id).to eq(customer.id)
    expect(blob.metadata["customer_id"].to_s).to eq(customer.id.to_s)
    payload = blob.download
    expect(payload).to start_with("%PDF")
    text = pdf_text(payload)
    expect(text).to include("Invoice Ada")
    expect(text).to include("Hello Ada")
    expect(text).to include("Items")
    expect(text).to include("Widgets")
  end

  it "uses a CJK-capable font when one is present and otherwise replaces CJK" do
    path = described_class.cjk_font_path
    result = described_class.pdf(title: "你好 Ada", body: "正文", filename: "cjk.pdf")
    payload = ActiveStorage::Blob.find(result["blob_id"]).download
    expect(payload).to start_with("%PDF")
    if path
      expect(payload).to include("DroidSansFallback")
    else
      expect(pdf_text(payload)).to include("Ada")
      expect(pdf_text(payload)).not_to include("你好")
    end
  end

  it "honors page size, orientation, header, footer and page numbers" do
    result = described_class.pdf(
      title: "Invoice Ada",
      body: "Hello Ada",
      filename: "letter.pdf",
      page_size: "letter",
      orientation: "landscape",
      header: "Acme Corp",
      footer: "Confidential",
      page_numbers: true
    )
    payload = ActiveStorage::Blob.find(result["blob_id"]).download
    expect(payload).to start_with("%PDF")
    expect(payload).to match(/\[0 0 792(\.0)? 612(\.0)?\]/)
    text = pdf_text(payload)
    expect(text).to include("Acme Corp")
    expect(text).to include("Confidential")
  end

  it "raises Document::Error when the filename cannot be stored" do
    allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_raise(ActiveRecord::ActiveRecordError, "disk full")
    expect { described_class.pdf(title: "x", body: "y") }.to raise_error(described_class::Error, /disk full/)
  end
end
