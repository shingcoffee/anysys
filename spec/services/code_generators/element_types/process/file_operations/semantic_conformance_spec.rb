# frozen_string_literal: true

require "rails_helper"
require "ripper"

# Deep semantic conformance for the file_operations step actions.
#
# The structural audits prove a property-editor field is *referenced*. These
# examples prove each field actually *changes the emitted source*, so a user
# who picks CSV does not silently get JSON and a user who picks S3/ActiveStorage
# does not silently get local disk.
RSpec.describe "file_operations semantic conformance" do
  def body(klass, config)
    CodeGenerators::TestRunner.run(klass, config: config)[:body]
  end

  def sample(klass, overrides = {})
    klass.sample_input.merge(overrides)
  end

  describe CodeGenerators::ElementTypes::Process::FileOperations::GenerateDocumentGenerator do
    it "honors pageSize, orientation, header, footer and pageNumbers" do
      base = sample(described_class)
      expect(body(described_class, base.merge("pageSize" => "letter")))
        .not_to eq(body(described_class, base.merge("pageSize" => "a4")))
      expect(body(described_class, base.merge("orientation" => "landscape")))
        .not_to eq(body(described_class, base.merge("orientation" => "portrait")))
      expect(body(described_class, base.merge("header" => "Acme")))
        .not_to eq(body(described_class, base.merge("header" => "Beta")))
      expect(body(described_class, base.merge("footer" => "Confidential")))
        .not_to eq(body(described_class, base.merge("footer" => "Internal")))
      expect(body(described_class, base.merge("pageNumbers" => true)))
        .not_to eq(body(described_class, base.merge("pageNumbers" => false)))
    end
  end

  describe CodeGenerators::ElementTypes::Process::FileOperations::DownloadFileGenerator do
    it "honors urlVariable even when a static url is also configured" do
      base = sample(described_class)
      expect(body(described_class, base.merge("urlVariable" => "a")))
        .not_to eq(body(described_class, base.merge("urlVariable" => "b")))
    end

    it "prefers the runtime url variable over the static url" do
      src = body(described_class, sample(described_class, "url" => "https://static.example.com/f.csv",
                                                          "urlVariable" => "download_url"))
      expect(src).to include("ctx[:download_url]")
      expect(src).to include("https://static.example.com/f.csv")
    end

    it "refuses to emit a ctx read for an unsafe urlVariable identifier" do
      src = body(described_class, sample(described_class, "url" => nil, "urlVariable" => "evil]; system('x'); ctx[:x"))
      expect(src.to_s).not_to include("system('x')")
    end

    it "writes a file payload through FileDownload.fetch without a destination field" do
      src = body(described_class, sample(described_class))
      expect(src).to include("FlowchartRuntime::FileDownload.fetch")
      expect(src).not_to include("destination:")
      expect(src).not_to include('Rails.root.join("tmp", "flowchart_downloads")')
    end

    it "honors followRedirects" do
      base = sample(described_class)
      expect(body(described_class, base.merge("followRedirects" => true)))
        .not_to eq(body(described_class, base.merge("followRedirects" => false)))
    end
  end

  describe CodeGenerators::ElementTypes::Process::FileOperations::GenerateFileGenerator do
    it "emits a distinct body for every fileType" do
      bodies = %w[csv xlsx json txt].map do |ft|
        body(described_class, sample(described_class, "fileType" => ft))
      end
      expect(bodies.uniq.size).to eq(4)
    end

    it "honors lineEnding for txt" do
      base = sample(described_class, "fileType" => "txt")
      expect(body(described_class, base.merge("lineEnding" => "lf")))
        .not_to eq(body(described_class, base.merge("lineEnding" => "crlf")))
    end

    it "always writes a file payload through FileGenerate.apply" do
      src = body(described_class, sample(described_class))
      expect(src).to include("FlowchartRuntime::FileGenerate.apply")
      expect(src).to include("locale: ctx[:locale]")
      expect(src).not_to include("output_destination:")
    end

    it "ignores xlsx sheetName when the fileType is json" do
      base = sample(described_class, "fileType" => "json")
      expect(body(described_class, base.merge("sheetName" => "A")))
        .to eq(body(described_class, base.merge("sheetName" => "B")))
    end

    it "honors nestedSeparator against csv columns" do
      base = sample(described_class, "fileType" => "csv")
      expect(body(described_class, base.merge("nestedSeparator" => ".")))
        .not_to eq(body(described_class, base.merge("nestedSeparator" => "/")))
    end

    it "honors headerRow" do
      base = sample(described_class, "fileType" => "csv")
      expect(body(described_class, base.merge("headerRow" => true)))
        .not_to eq(body(described_class, base.merge("headerRow" => false)))
    end

    it "does not expose deleted generate_csv header aliases" do
      keys = CodeGenerators::Shared::SchemaReader.read("generate_file").map { |f| f[:key].to_s }
      expect(keys).to include("headerRow")
      expect(keys).not_to include("headers", "includeHeaders")
    end
  end

  describe CodeGenerators::ElementTypes::Process::DataOperations::ParseDataGenerator do
    it "honors csvHeaders" do
      base = sample(described_class, "format" => "csv")
      expect(body(described_class, base.merge("csvHeaders" => true)))
        .not_to eq(body(described_class, base.merge("csvHeaders" => false)))
    end

    it "does not expose a deleted parse_csv headers alias" do
      keys = CodeGenerators::Shared::SchemaReader.read("parse_data").map { |f| f[:key].to_s }
      expect(keys).to include("csvHeaders")
      expect(keys).not_to include("headers")
    end

    it "refuses to emit a ctx read for an unsafe sourceVariable" do
      src = body(described_class, sample(described_class, "sourceVariable" => "a]; system('x'); ctx[:b"))
      expect(src.to_s).not_to include("system('x')")
    end
  end

  describe CodeGenerators::ElementTypes::Process::FileOperations::UploadFileGenerator do
    it "honors sourceVariable even when a filename is configured" do
      base = sample(described_class)
      expect(body(described_class, base.merge("sourceVariable" => "a")))
        .not_to eq(body(described_class, base.merge("sourceVariable" => "b")))
    end

    it "attaches to the configured field and renders the filename from ctx" do
      src = body(described_class, sample(described_class, "fileField" => "photo", "filename" => "{{ model.title }}.png"))
      expect(src).to include('ctx[:model], "photo",')
      expect(src).to include('filename: FlowchartRuntime::Template.render("{{ model.title }}.png", ctx)')
    end

    it "saves the record unless saveRecord is off" do
      expect(body(described_class, sample(described_class))).not_to include("save: false")
      expect(body(described_class, sample(described_class, "saveRecord" => false))).to include("save: false")
    end

    it "refuses an unsafe fileField" do
      src = body(described_class, sample(described_class, "fileField" => "doc; system('x') #"))
      expect(Ripper.sexp(src.to_s)).not_to be_nil
      kinds = Ripper.lex(src.to_s)
                    .select { |(_, _type, tok, _)| tok.to_s.include?("system") }
                    .map { |(_, type, _, _)| type }.uniq
      expect(kinds - %i[on_tstring_content on_comment]).to(
        be_empty, "system('x') reached code position (#{kinds.inspect}) in:\n#{src}"
      )
    end
  end
end
