# frozen_string_literal: true

require "nokogiri"

module FlowchartRuntime
  # FlowchartRuntime::BarcodeSvgLabel
  #
  # Draws the human-readable line under an SVG barcode.
  #
  # barby's Barby::SvgOutputter renders bars only — it accepts no text options,
  # so the barcode_generate step's "Include Text" / "Text Font" settings had no
  # effect on the produced image. Rather than drop the feature this facade adds
  # the label as a real SVG <text> node with Nokogiri (the XML library already
  # in the bundle), so nothing hand-parses or string-splices XML.
  #
  # Single public interface: .apply.
  module BarcodeSvgLabel
    class Error < StandardError; end

    # Mirrors FlowchartRuntime::Barcode::ALLOWED_FONTS.
    ALLOWED_FONTS = %w[Helvetica Arial DejaVuSans FreeSans].freeze
    DEFAULT_FONT  = "Helvetica"
    FONT_SIZE     = 12
    # Vertical room reserved for the label, in user units.
    LABEL_BAND    = 16

    module_function

    # @param svg  [String] SVG document produced by FlowchartRuntime::Barcode
    # @param text [String] human-readable value to draw under the bars
    # @param font [String] one of ALLOWED_FONTS
    # @return [String] SVG document with the label appended
    # @raise  [FlowchartRuntime::BarcodeSvgLabel::Error]
    def apply(svg, text:, font: DEFAULT_FONT)
      label = text.to_s
      return svg.to_s if label.empty?

      raise Error, "unsupported text font" unless ALLOWED_FONTS.include?(font.to_s)

      doc = Nokogiri::XML(svg.to_s) { |cfg| cfg.strict }
      root = doc.root
      raise Error, "not an SVG document" if root.nil? || root.name != "svg"

      height = numeric(root["height"])
      width  = numeric(root["width"])
      raise Error, "SVG is missing width/height" if height.nil? || width.nil?

      root["height"] = (height + LABEL_BAND).to_s
      root["viewBox"] = "0 0 #{width} #{height + LABEL_BAND}" if root["viewBox"]

      root.add_child(text_node(doc, label, width, height, font.to_s))
      doc.to_xml
    rescue Nokogiri::XML::SyntaxError => e
      raise Error, e.message
    end

    def text_node(doc, label, width, height, font)
      node = Nokogiri::XML::Node.new("text", doc)
      node["x"] = (width / 2.0).round(2).to_s
      node["y"] = (height + FONT_SIZE).to_s
      node["text-anchor"] = "middle"
      node["font-family"] = font
      node["font-size"]   = FONT_SIZE.to_s
      node.content = label
      node
    end

    def numeric(value)
      Float(value.to_s[/-?\d+(\.\d+)?/].to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
