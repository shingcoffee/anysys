# frozen_string_literal: true

require "base64"
require "barby"
require "barby/barcode/code_128"
require "barby/barcode/code_39"
require "barby/barcode/ean_13"
require "barby/barcode/ean_8"
require "barby/barcode/code_25_interleaved"
require "barby/barcode/codabar"
require "barby/outputter/png_outputter"
require "barby/outputter/svg_outputter"
require "mini_magick"

module FlowchartRuntime
  # FlowchartRuntime::Barcode
  #
  # Thin wrapper around barby (+ chunky_png, optional MiniMagick) for flowchart
  # barcode_generate step generators. Owns allowed formats/outputs and a single
  # error type (FlowchartRuntime::Barcode::Error) so generated step code never
  # rescues raw Barby/MiniMagick exceptions.
  module Barcode
    class Error < StandardError; end

    FORMATS = %i[code128 code39 ean13 ean8 upca itf codabar].freeze
    OUTPUTS = %i[png svg jpg base64].freeze
    ALLOWED_FONTS = %w[Helvetica Arial DejaVuSans FreeSans].freeze
    CONTENT_TYPES = {
      png: "image/png",
      svg: "image/svg+xml",
      jpg: "image/jpeg",
      base64: "image/png",
      ascii: "text/plain"
    }.freeze
    EXTENSIONS = {
      png: "png",
      svg: "svg",
      jpg: "jpg",
      base64: "png",
      ascii: "txt"
    }.freeze

    BARCODE_CLASSES = {
      code128: Barby::Code128,
      code39:  Barby::Code39,
      ean13:   Barby::EAN13,
      ean8:    Barby::EAN8,
      upca:    Barby::UPCA,
      itf:     Barby::Code25Interleaved,
      codabar: Barby::Codabar
    }.freeze

    module_function

    # @param data          [String]
    # @param format        [Symbol, String]
    # @param output        [Symbol, String]
    # @param width         [Integer] module width (xdim)
    # @param height        [Integer] bar height in pixels
    # @param margin        [Integer] quiet zone in pixels
    # @param include_text  [Boolean]
    # @param text_font     [String]
    # @return [String] rendered barcode payload
    # @raise  [FlowchartRuntime::Barcode::Error]
    def generate(data, format: :code128, output: :png, width: 2, height: 100, margin: 10,
                 include_text: false, text_font: "Helvetica")
      fmt = normalize_format(format)
      out = normalize_output(output)
      raise Error, "unsupported format" unless FORMATS.include?(fmt)
      raise Error, "unsupported output" unless OUTPUTS.include?(out)
      raise Error, "data is required" if data.to_s.empty?
      raise Error, "width must be positive" unless width.to_i.positive?
      raise Error, "height must be positive" unless height.to_i.positive?
      raise Error, "margin must be non-negative" if margin.to_i.negative?

      barcode = build_barcode(data.to_s, fmt)
      render(barcode, out, data: data.to_s, width: width, height: height, margin: margin,
                          include_text: include_text, text_font: text_font)
    rescue ArgumentError, ChunkyPNG::Exception, MiniMagick::Error, BarcodeSvgLabel::Error => e
      raise Error, e.message
    end

    # Hash later steps (template_render, send_email HTML, generate_document
    # body) can read: bytes, content_type, filename, and a data_uri for img src.
    def artifact(data, format: :code128, output: :png, width: 2, height: 100, margin: 10,
                 include_text: false, text_font: "Helvetica", size: 4, level: :m,
                 color_dark: "#000000", color_light: "#FFFFFF")
      fmt = format.to_s == "qr" ? :qr : normalize_format(format)
      out = normalize_output(output)
      payload = if fmt == :qr
        QrCode.generate(
          data, size: size, level: level, margin: margin,
                color_dark: color_dark, color_light: color_light, output: out
        )
      else
        generate(
          data, format: fmt, output: out, width: width, height: height,
                margin: margin, include_text: include_text, text_font: text_font
        )
      end
      wrap_artifact(payload, format: fmt, output: out)
    rescue QrCode::Error => error
      raise Error, error.message
    end

    def normalize_format(format)
      token = format.to_s
      token = "upca" if token == "upc_a"
      token.to_sym
    end

    def normalize_output(output)
      output.to_s.downcase.to_sym
    end

    def build_barcode(data, format)
      klass = BARCODE_CLASSES.fetch(format)
      klass.new(data)
    end

    def render(barcode, output, data:, width:, height:, margin:, include_text:, text_font:)
      font = normalize_font(text_font) if include_text || output == :svg
      if include_text && output != :svg
        raise Error, "include_text is only supported for svg output"
      end

      case output
      when :svg
        svg = barcode.to_svg(
          margin: margin,
          xdim: width,
          height: height,
          show_text: include_text,
          font: font || "Helvetica"
        )
        return svg unless include_text

        BarcodeSvgLabel.apply(svg, text: data.to_s, font: font || "Helvetica")
      when :jpg
        png = barcode.to_png(margin: margin, xdim: width, height: height).to_s
        render_jpg(png)
      when :base64
        Base64.strict_encode64(barcode.to_png(margin: margin, xdim: width, height: height).to_s)
      else # :png
        barcode.to_png(margin: margin, xdim: width, height: height).to_s
      end
    end

    def normalize_font(text_font)
      font = text_font.to_s
      return "Helvetica" if font.empty?
      return font if ALLOWED_FONTS.include?(font)

      raise Error, "unsupported text font"
    end

    def render_jpg(png_bytes)
      MiniMagick::Image.read(png_bytes).format("jpg").to_blob
    end

    def wrap_artifact(payload, format:, output:)
      {
        "bytes" => payload,
        "content_type" => CONTENT_TYPES.fetch(output, "application/octet-stream"),
        "filename" => "#{format == :qr ? 'qr' : 'barcode'}.#{EXTENSIONS.fetch(output, 'bin')}",
        "data_uri" => data_uri_for(payload, output)
      }
    end

    def data_uri_for(payload, output)
      text = payload.to_s
      return text if text.start_with?("data:")
      return nil if output == :ascii

      case output
      when :svg
        "data:image/svg+xml;base64,#{Base64.strict_encode64(text)}"
      when :jpg
        "data:image/jpeg;base64,#{Base64.strict_encode64(text)}"
      when :base64
        "data:image/png;base64,#{text}"
      else
        "data:image/png;base64,#{Base64.strict_encode64(text)}"
      end
    end
    private_class_method :wrap_artifact, :data_uri_for
  end
end
