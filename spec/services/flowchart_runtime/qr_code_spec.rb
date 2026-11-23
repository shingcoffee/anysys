# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::QrCode do
  describe ".generate" do
    it "returns PNG binary by default" do
      result = described_class.generate("hello")
      expect(result).to be_a(String)
      expect(result.bytesize).to be > 50
    end

    it "returns SVG when output is svg" do
      result = described_class.generate("hello", output: :svg, color_dark: "#000000", color_light: "#FFFFFF")
      expect(result).to include("<svg")
    end

    it "returns a data URL when output is base64" do
      result = described_class.generate("hello", output: :base64)
      expect(result).to start_with("data:image/png;base64,")
    end

    it "returns ascii art when output is ascii" do
      result = described_class.generate("hi", output: :ascii)
      expect(result).to include("█").or include(" ")
    end

    it "accepts error correction levels" do
      %i[l m q h].each do |level|
        expect { described_class.generate("hello", level: level) }.not_to raise_error
      end
    end

    it "treats size as rendered module pixels rather than QR version" do
      expect { described_class.generate("x" * 100, size: 1) }.not_to raise_error
    end

    it "scales rendered SVG modules using size" do
      result = described_class.generate("hello", size: 7, output: :svg)
      expect(result).to include('width="203"').or include('width="203px"')
    end

    it "raises Error for unsupported output" do
      expect { described_class.generate("hello", output: :bmp) }
        .to raise_error(FlowchartRuntime::QrCode::Error, /unsupported output/)
    end

    it "raises Error for unsupported level" do
      expect { described_class.generate("hello", level: :z) }
        .to raise_error(FlowchartRuntime::QrCode::Error, /unsupported level/)
    end

    it "raises Error for blank data" do
      expect { described_class.generate("") }
        .to raise_error(FlowchartRuntime::QrCode::Error)
    end

    it "normalizes invalid colors as QrCode::Error" do
      expect { described_class.generate("hello", color_dark: "not-a-color") }
        .to raise_error(described_class::Error, /color/)
    end

    it "rejects invalid colors for SVG before rendering" do
      expect { described_class.generate("hello", output: :svg, color_light: "not-a-color") }
        .to raise_error(described_class::Error, /color/)
    end
  end
end
