# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::BarcodeSvgLabel do
  let(:svg) do
    FlowchartRuntime::Barcode.generate("ABC123", format: :code128, output: :svg,
                                                 width: 2, height: 100, margin: 10)
  end

  describe ".apply" do
    it "adds a human-readable text node barby's SVG outputter never draws" do
      expect(svg).not_to include("<text")

      labelled = described_class.apply(svg, text: "ABC123")

      expect(labelled).to include("<text")
      expect(labelled).to include("ABC123")
    end

    it "honors the requested font" do
      expect(described_class.apply(svg, text: "ABC123", font: "Arial"))
        .to include('font-family="Arial"')
      expect(described_class.apply(svg, text: "ABC123", font: "DejaVuSans"))
        .to include('font-family="DejaVuSans"')
    end

    it "grows the document height to make room for the label" do
      original = Nokogiri::XML(svg).root["height"].to_f
      grown    = Nokogiri::XML(described_class.apply(svg, text: "ABC123")).root["height"].to_f

      expect(grown).to be > original
    end

    it "returns the document untouched when there is nothing to label" do
      expect(described_class.apply(svg, text: "")).to eq(svg)
    end

    it "escapes label content rather than injecting markup" do
      labelled = described_class.apply(svg, text: "<script>x</script>")

      expect(labelled).to include("&lt;script&gt;")
      expect(labelled).not_to include("<script>")
    end

    it "refuses a font the barcode runtime does not allow" do
      expect { described_class.apply(svg, text: "ABC", font: "ComicSans") }
        .to raise_error(described_class::Error, /unsupported text font/)
    end

    it "refuses input that is not an SVG document" do
      expect { described_class.apply("<html></html>", text: "ABC") }
        .to raise_error(described_class::Error, /not an SVG document/)
    end

    it "refuses malformed XML" do
      expect { described_class.apply("<svg", text: "ABC") }
        .to raise_error(described_class::Error)
    end

    it "refuses an SVG with no usable geometry" do
      expect { described_class.apply('<svg xmlns="http://www.w3.org/2000/svg"></svg>', text: "ABC") }
        .to raise_error(described_class::Error, /missing width\/height/)
    end
  end
end
