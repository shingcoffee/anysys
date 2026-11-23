# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Barcode do
  describe ".generate" do
    it "returns PNG binary for code128" do
      result = described_class.generate("TEST123", format: :code128, output: :png)
      expect(result).to be_a(String)
      expect(result.bytesize).to be > 50
      expect(result.b.start_with?("\x89PNG".b)).to be true
    end

    it "returns SVG string when output is svg" do
      result = described_class.generate("TEST123", format: :code128, output: :svg, include_text: true)
      expect(result).to include("<svg")
      expect(result).to include("TEST123")
    end

    it "returns base64-encoded PNG when output is base64" do
      png = described_class.generate("TEST123", format: :code128, output: :png)
      b64 = described_class.generate("TEST123", format: :code128, output: :base64)
      expect(b64).to eq(Base64.strict_encode64(png))
    end

    it "supports every declared format" do
      samples = {
        code128: "TEST123",
        code39:  "TEST",
        ean13:   "978020137962",
        ean8:    "5512345",
        upca:    "72527273070",
        itf:     "12345670",
        codabar: "A40156A"
      }

      samples.each do |format, data|
        expect { described_class.generate(data, format: format, output: :png) }.not_to raise_error
      end
    end

    it "maps legacy upc_a format to upca" do
      upca_png = described_class.generate("72527273070", format: :upca, output: :png)
      legacy_png = described_class.generate("72527273070", format: "upc_a", output: :png)
      expect(legacy_png).to eq(upca_png)
    end

    it "raises Error for unsupported format" do
      expect { described_class.generate("X", format: :qr, output: :png) }
        .to raise_error(FlowchartRuntime::Barcode::Error, /unsupported format/)
    end

    it "raises Error for unsupported output" do
      expect { described_class.generate("TEST", format: :code128, output: :bmp) }
        .to raise_error(FlowchartRuntime::Barcode::Error, /unsupported output/)
    end

    it "raises Error for invalid barcode data" do
      expect { described_class.generate("not-a-number", format: :ean13, output: :png) }
        .to raise_error(FlowchartRuntime::Barcode::Error)
    end

    it "returns JPG bytes when MiniMagick succeeds" do
      png = described_class.generate("TEST123", format: :code128, output: :png)
      blob = "jpeg-bytes"
      image = instance_double(MiniMagick::Image, format: image)
      allow(image).to receive(:format).with("jpg").and_return(image)
      allow(image).to receive(:to_blob).and_return(blob)
      allow(MiniMagick::Image).to receive(:read).with(png).and_return(image)

      expect(described_class.generate("TEST123", format: :code128, output: :jpg)).to eq(blob)
    end

    it "wraps MiniMagick failures for jpg output" do
      allow(MiniMagick::Image).to receive(:read).and_raise(MiniMagick::Error, "conversion failed")

      expect { described_class.generate("TEST123", format: :code128, output: :jpg) }
        .to raise_error(FlowchartRuntime::Barcode::Error, "conversion failed")
    end
  end

  it "supports include_text for svg output" do
    svg = described_class.generate("HELLO123", format: :code128, output: :svg, include_text: true)
    expect(svg).to include("HELLO123")
  end

  it "rejects include_text for raster outputs" do
    expect {
      described_class.generate("HELLO123", format: :code128, output: :png, include_text: true)
    }.to raise_error(FlowchartRuntime::Barcode::Error, /include_text is only supported for svg/)
  end

  describe ".artifact" do
    it "wraps a PNG barcode with a data_uri later steps can embed" do
      artifact = described_class.artifact("TEST123")
      expect(artifact["bytes"].b).to start_with("\x89PNG".b)
      expect(artifact["content_type"]).to eq("image/png")
      expect(artifact["filename"]).to eq("barcode.png")
      expect(artifact["data_uri"]).to start_with("data:image/png;base64,")
    end

    it "wraps a QR payload" do
      artifact = described_class.artifact("https://example.test", format: :qr)
      expect(artifact["filename"]).to eq("qr.png")
      expect(artifact["bytes"].b).to start_with("\x89PNG".b)
    end
  end
end
