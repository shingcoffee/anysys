# frozen_string_literal: true

require "rqrcode"

module FlowchartRuntime
  # FlowchartRuntime::QrCode
  #
  # Thin wrapper around rqrcode for flowchart qr_code_generate step generators.
  # Owns allowed outputs and a single error type (FlowchartRuntime::QrCode::Error)
  # so generated step code never rescues raw RQRCode exceptions.
  module QrCode
    class Error < StandardError; end

    OUTPUTS = %i[png svg base64 ascii].freeze
    LEVELS  = %i[l m q h].freeze
    COLOR_PATTERN = /\A#?(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})\z/i

    module_function

    # @param data        [String]
    # @param size        [Integer] module size (pixels per module for PNG)
    # @param level       [Symbol, String] error correction :l/:m/:q/:h
    # @param margin      [Integer] quiet-zone module count
    # @param color_dark  [String]
    # @param color_light [String]
    # @param output      [Symbol, String]
    # @return [String] rendered QR payload
    # @raise  [FlowchartRuntime::QrCode::Error]
    def generate(data, size: 4, level: :m, margin: 4, color_dark: "#000000",
                 color_light: "#FFFFFF", output: :png)
      out = output.to_s.downcase.to_sym
      ec  = normalize_level(level)
      raise Error, "unsupported output" unless OUTPUTS.include?(out)
      raise Error, "unsupported level" unless LEVELS.include?(ec)

      payload = data.to_s
      raise Error, "data cannot be blank" if payload.empty?
      raise Error, "size must be positive" unless size.to_i.positive?
      raise Error, "margin must be non-negative" if margin.to_i.negative?
      validate_color!(color_dark)
      validate_color!(color_light)

      qr = RQRCode::QRCode.new(payload, level: ec)
      render(qr, out, size: size.to_i, margin: margin.to_i,
                    color_dark: color_dark.to_s, color_light: color_light.to_s)
    rescue RQRCodeCore::QRCodeArgumentError, RQRCodeCore::QRCodeRunTimeError, ArgumentError => e
      raise Error, e.message
    end

    def normalize_level(level)
      level.to_s.downcase.to_sym
    end

    def validate_color!(color)
      raise Error, "invalid color" unless color.to_s.match?(COLOR_PATTERN)
    end

    def render(qr, output, size:, margin:, color_dark:, color_light:)
      pixel_size = (qr.modules.length + (margin * 2)) * size

      case output
      when :svg
        qr.as_svg(
          module_size: size,
          offset: margin * size,
          color: color_dark,
          fill: color_light,
          shape_rendering: "crispEdges",
          standalone: true
        )
      when :base64
        qr.as_png(
          size: pixel_size,
          border_modules: margin,
          color: color_dark,
          fill: color_light
        ).to_data_url
      when :ascii
        qr.to_s(dark: "██", light: "  ")
      else # :png
        qr.as_png(
          size: pixel_size,
          border_modules: margin,
          color: color_dark,
          fill: color_light
        ).to_s
      end
    end
  end
end
