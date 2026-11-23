# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Archive do
  let(:entries) do
    [
      { name: "hello.txt", content: "hello world" },
      { name: "data/readme.md", content: "# readme" }
    ]
  end

  describe ".pack / .unpack" do
    it "packs ctx sources and unpacks them" do
      payload = described_class.pack({ file_data: "hello" }, sources: { "data.txt" => "file_data" }, format: "zip")
      expect(payload).to include("filename" => "archive.zip", "content_type" => "application/zip")
      extracted = described_class.unpack(payload, format: "zip")
      expect(extracted).to contain_exactly(hash_including("filename" => "data.txt", "content" => "hello"))
    end

    it "rejects zip-slip names through SandboxPath" do
      allow(described_class).to receive(:decompress).and_return([{ name: "../x.txt", content: "nope" }])
      expect { described_class.unpack("PK", format: "zip") }
        .to raise_error(described_class::Error, /path traversal/)
    end
  end

  describe ".compress / .decompress" do
    it "round-trips zip archives" do
      payload = described_class.compress(entries, format: :zip)
      expect(payload).to be_a(String)
      expect(payload.byteslice(0, 2)).to eq("PK")

      extracted = described_class.decompress(payload, format: :zip)
      expect(extracted).to contain_exactly(
        { name: "hello.txt", content: "hello world" },
        { name: "data/readme.md", content: "# readme" }
      )
    end

    it "round-trips gzip archives" do
      payload = described_class.compress([{ name: "file.txt", content: "gzip me" }], format: :gzip)
      expect(payload.byteslice(0, 2).b).to eq("\x1F\x8B".b)

      extracted = described_class.decompress(payload, format: :gzip, gzip_name: "file.txt")
      expect(extracted).to eq([{ name: "file.txt", content: "gzip me" }])
    end

    it "rejects multiple entries for single-file gzip" do
      expect { described_class.compress(entries, format: :gzip) }
        .to raise_error(described_class::Error, /exactly one entry/)
    end

    it "rejects concatenated multi-member gzip payloads" do
      first = described_class.compress([{ name: "one.txt", content: "one" }], format: :gzip)
      second = described_class.compress([{ name: "two.txt", content: "two" }], format: :gzip)

      expect { described_class.decompress(first + second, format: :gzip) }
        .to raise_error(described_class::Error, /multiple gzip members/)
    end

    it "rejects concatenated multi-member tar_gz payloads" do
      first = described_class.compress([{ name: "one.txt", content: "one" }], format: :tar_gz)
      second = described_class.compress([{ name: "two.txt", content: "two" }], format: :tar_gz)

      expect { described_class.decompress(first + second, format: :tar_gz) }
        .to raise_error(described_class::Error, /multiple gzip members/)
    end

    it "round-trips tar_gz archives" do
      payload = described_class.compress(entries, format: :tar_gz)
      expect(payload.byteslice(0, 2).b).to eq("\x1F\x8B".b)

      extracted = described_class.decompress(payload, format: :tar_gz)
      expect(extracted).to contain_exactly(
        { name: "hello.txt", content: "hello world" },
        { name: "data/readme.md", content: "# readme" }
      )
    end

    it "round-trips plain tar archives" do
      payload = described_class.compress(entries, format: :tar)
      extracted = described_class.decompress(payload, format: :tar)
      expect(extracted).to contain_exactly(
        { name: "hello.txt", content: "hello world" },
        { name: "data/readme.md", content: "# readme" }
      )
    end

    it "accepts string format names" do
      payload = described_class.compress(entries, format: "zip")
      expect(described_class.decompress(payload, format: "zip")).to contain_exactly(
        { name: "hello.txt", content: "hello world" },
        { name: "data/readme.md", content: "# readme" }
      )
    end
  end

  describe "error handling" do
    it "rejects absolute, parent, null-byte, and platform-separator escapes as Archive::Error" do
      [
        "/etc/passwd",
        "C:\\Windows\\system.ini",
        "../secret.txt",
        "nested/../../secret.txt",
        "nested\\..\\secret.txt",
        "\\\\server\\share\\secret.txt",
        "bad\0name.txt"
      ].each do |name|
        expect {
          described_class.validate_entry_name!(name)
        }.to raise_error(described_class::Error, /path traversal/)
      end
    end

    it "accepts safe nested entry names" do
      expect(described_class.validate_entry_name!("nested/file.txt")).to eq("nested/file.txt")
    end

    it "raises Error for unsupported formats" do
      expect { described_class.compress(entries, format: :rar) }
        .to raise_error(FlowchartRuntime::Archive::Error, /unsupported format/)
      expect { described_class.decompress("PK\x03\x04", format: :rar) }
        .to raise_error(FlowchartRuntime::Archive::Error, /unsupported format/)
    end

    it "raises Error for corrupt zip payloads" do
      expect { described_class.decompress("not-a-zip", format: :zip) }
        .to raise_error(FlowchartRuntime::Archive::Error, /invalid zip archive/)
    end

    it "raises Error for corrupt gzip payloads" do
      expect { described_class.decompress("not-gzip", format: :gzip) }
        .to raise_error(FlowchartRuntime::Archive::Error)
    end

    it "normalizes invalid entry errors" do
      expect { described_class.compress(["bad"], format: :zip) }
        .to raise_error(described_class::Error, /entry must be a hash/)
    end

    it "honours a tighter max_entries cap on unpack" do
      payload = described_class.compress(entries, format: :zip)
      expect { described_class.unpack(payload, format: "zip", max_entries: 1) }
        .to raise_error(described_class::Error, /too many entries/)
    end

    it "rejects too many archive entries" do
      stub_const("#{described_class}::MAX_ENTRIES", 1)

      expect { described_class.compress(entries, format: :zip) }
        .to raise_error(described_class::Error, /too many entries/)
    end

    it "counts zip directories toward the extraction entry limit" do
      stub_const("#{described_class}::MAX_ENTRIES", 1)
      payload = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("data/")
        zip.put_next_entry("data/file.txt")
        zip.write("content")
      end.string

      expect { described_class.decompress(payload, format: :zip) }
        .to raise_error(described_class::Error, /too many entries/)
    end

    it "counts tar directories toward the extraction entry limit" do
      stub_const("#{described_class}::MAX_ENTRIES", 1)
      buffer = StringIO.new
      Gem::Package::TarWriter.new(buffer) do |tar|
        tar.mkdir("data", 0o755)
        tar.add_file_simple("data/file.txt", 0o644, 7) { |io| io.write("content") }
      end

      expect { described_class.decompress(buffer.string, format: :tar) }
        .to raise_error(described_class::Error, /too many entries/)
    end

    it "rejects oversized compressed input" do
      stub_const("#{described_class}::MAX_INPUT_BYTES", 4)

      expect { described_class.decompress("PK\x03\x04extra", format: :zip) }
        .to raise_error(described_class::Error, /input exceeds/)
    end

    it "rejects oversized expanded output" do
      payload = described_class.compress([{ name: "large.txt", content: "12345" }], format: :gzip)
      stub_const("#{described_class}::MAX_OUTPUT_BYTES", 4)
      stub_const("#{described_class}::MAX_ENTRY_BYTES", 4)

      expect { described_class.decompress(payload, format: :gzip) }
        .to raise_error(described_class::Error, /expanded data exceeds/)
    end
  end
end
