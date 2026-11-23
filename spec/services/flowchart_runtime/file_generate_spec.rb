# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::FileGenerate do
  describe ".apply" do
    it "generates a CSV file payload" do
      payload = described_class.apply(
        [{ "name" => "Ada" }],
        file_type: "csv",
        columns: [{ "key" => "Name", "value" => "name" }]
      )
      expect(payload["filename"]).to eq("export.csv")
      expect(payload["content_type"]).to eq("text/csv")
      expect(payload["content"].byteslice(0, 3)).to eq("\xEF\xBB\xBF".b)
      expect(CSV.parse(payload["content"].b.delete_prefix("\xEF\xBB\xBF".b).force_encoding("UTF-8"))).to eq([%w[Name], %w[Ada]])
    end

    it "exports a record's file field as its filenames" do
      customer = create(:customer)
      entity = create(:entity, customer: customer, property_schema: [
        { "name" => "Scans", "name_slug" => "scans", "html_type" => "file", "config" => { "multiple" => true } }
      ].to_json)
      record = EntityEntry.build_for(entity).create!(customer_id: customer.id, scans: [
        { io: StringIO.new("a"), filename: "a.pdf" }, { io: StringIO.new("b"), filename: "b.pdf" }
      ])

      payload = described_class.apply([EntityEntry.build_for(entity).find(record.id)], file_type: "csv", include_bom: false,
                                      columns: [{ "key" => "Scans", "value" => "scans" }])

      expect(CSV.parse(payload["content"])).to eq([%w[Scans], ["a.pdf, b.pdf"]])
    end

    it "rejects an unknown file type" do
      expect { described_class.apply([], file_type: "pdf") }
        .to raise_error(described_class::Error, /unknown file type/)
    end

    it "translates I18n column headers in the run locale" do
      payload = described_class.apply(
        [{ "name" => "Ada" }],
        file_type: "csv",
        columns: [{ "key" => "flowchart_actions.generate_file.fields.fileType.label", "value" => "name" }],
        include_bom: false,
        locale: "en"
      )
      expect(CSV.parse(payload["content"]).first).to eq(["File Type"])
    end
  end

  describe ".xlsx" do
    it "generates a workbook from hash rows" do
      payload = described_class.xlsx(
        data: [{ "name" => "Alice", "score" => 10 }, { "name" => "Bob", "score" => 8 }],
        sheet_name: "Report"
      )

      expect(payload).to be_a(String)
      expect(payload.byteslice(0, 2)).to eq("PK")
    end

    it "preserves false values from string and symbol keys" do
      expect(described_class.send(:fetch_row_value, { "enabled" => false }, "enabled")).to be(false)
      expect(described_class.send(:fetch_row_value, { enabled: false }, "enabled")).to be(false)
    end

    it "generates a workbook from configured columns" do
      payload = described_class.xlsx(
        data: [{ "name" => "Alice", "score" => 10 }],
        columns: [{ "key" => "Name", "value" => "name" }],
        auto_filter: true
      )

      expect(payload.byteslice(0, 2)).to eq("PK")
    end

    it "normalizes invalid worksheet names as FileGenerate::Error" do
      expect { described_class.xlsx(data: [], sheet_name: "bad/name") }
        .to raise_error(described_class::Error, /worksheet name/)
    end

    it "validates worksheet length using Excel UTF-16 code units" do
      expect { described_class.xlsx(data: [], sheet_name: "😀" * 16) }
        .to raise_error(described_class::Error, /worksheet name/)
    end
  end

  describe ".pdf" do
    it "generates a tabular pdf from hash rows" do
      payload = described_class.pdf(
        data: [{ "name" => "Alice" }, { "name" => "Bob" }],
        page_size: "a4"
      )

      expect(payload).to start_with("%PDF")
    end

    it "generates a text pdf from plain lines" do
      payload = described_class.pdf(data: %w[one two])

      expect(payload).to start_with("%PDF")
    end
  end

  describe ".xml" do
    it "generates xml with the configured root element" do
      payload = described_class.xml(
        data: [{ "id" => 1, "name" => "Alice" }],
        root_element: "orders"
      )

      expect(payload).to include('<?xml version="1.0"')
      expect(payload).to include("<orders>")
      expect(payload).to include("<item>")
      expect(payload).to include("<id>1</id>")
    end
  end

  describe ".attach_active_storage" do
    it "uploads content to Active Storage" do
      blob = described_class.attach_active_storage("hello", filename: "hello.txt")

      expect(blob).to be_a(ActiveStorage::Blob)
      expect(blob.filename.to_s).to eq("hello.txt")
    end
  end

  describe "error handling" do
    it "wraps Active Storage failures as FileGenerate::Error" do
      allow(ActiveStorage::Blob).to receive(:create_and_upload!)
        .and_raise(ActiveStorage::IntegrityError, "upload failed")

      expect { described_class.attach_active_storage("x", filename: "x.txt") }
        .to raise_error(FlowchartRuntime::FileGenerate::Error, "upload failed")
    end

    it "does not swallow unexpected attach failures" do
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_raise(StandardError, "upload failed")

      expect { described_class.attach_active_storage("x", filename: "x.txt") }
        .to raise_error(StandardError, "upload failed")
    end
  end
end
