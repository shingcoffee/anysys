# frozen_string_literal: true

require "base64"
require "cgi"
require "erb"

module FlowchartRuntime
  # String operations for string_manipulate (including Base64 encode/decode).
  module Text
    class Error < StandardError; end

    OPERATIONS = %w[
      strip squish upcase downcase capitalize titleize parameterize
      truncate pad_left pad_right split join replace gsub mask_middle
      html_escape html_unescape base64_encode base64_decode
    ].freeze

    module_function

    def apply(source, operation:, delimiter: ",", length: 10, pad_char: " ",
              pattern: "", replacement: "", regex_escape: false,
              url_safe: false, strip_padding: false, input_encoding: "utf8",
              line_width: 0, encoding: "utf8", operations: nil)
      name = operation.to_s
      raise Error, "unsupported operation" unless OPERATIONS.include?(name)

      case name
      when "base64_encode"
        encode64(source, url_safe: url_safe, strip_padding: strip_padding,
                         input_encoding: input_encoding, line_width: line_width)
      when "base64_decode"
        decode64(source, url_safe: url_safe)
      else
        single(source.to_s, name, delimiter: delimiter, length: length,
               pad_char: pad_char, pattern: pattern, replacement: replacement,
               regex_escape: regex_escape, source: source)
      end
    rescue ArgumentError, Encoding::CompatibilityError => error
      raise Error, error.message
    end

    def single(text, operation, delimiter:, length:, pad_char:, pattern:, replacement:, regex_escape:, source:)
      case operation
      when "split" then text.split(delimiter.presence || ",")
      when "join" then Array(source).join(delimiter.presence || ", ")
      when "strip" then text.strip
      when "squish" then text.squish
      when "pad_left" then text.rjust(positive_length(length, 10), pad_char.to_s.presence || " ")
      when "pad_right" then text.ljust(positive_length(length, 10), pad_char.to_s.presence || " ")
      when "truncate" then text.truncate(positive_length(length, 100))
      when "upcase" then text.upcase
      when "downcase" then text.downcase
      when "capitalize" then text.capitalize
      when "titleize" then text.titleize
      when "parameterize" then text.parameterize
      when "replace" then text.sub(pattern.to_s, replacement.to_s)
      when "gsub"
        text.gsub(gsub_pattern(pattern, regex_escape), replacement.to_s)
      when "html_escape" then ERB::Util.html_escape(text)
      when "html_unescape" then CGI.unescapeHTML(text)
      when "mask_middle" then mask_middle(text, length, pad_char)
      end
    end

    def gsub_pattern(pattern, regex_escape)
      source = pattern.to_s
      regex_escape ? Regexp.escape(source) : Regexp.new(source)
    rescue RegexpError => error
      raise Error, error.message
    end

    def encode64(source, url_safe:, strip_padding:, input_encoding:, line_width:)
      raw = source.to_s
      raw = input_encoding.to_s == "binary" ? raw.b : raw.encode("UTF-8")
      encoded = url_safe ? Base64.urlsafe_encode64(raw) : Base64.strict_encode64(raw)
      encoded = encoded.delete("=") if strip_padding
      width = line_width.to_i
      encoded = encoded.scan(/.{1,#{width}}/).join("\n") if width.positive?
      encoded
    end

    def decode64(source, url_safe:)
      raw = source.to_s
      url_safe ? Base64.urlsafe_decode64(raw) : Base64.strict_decode64(raw)
    rescue ArgumentError => error
      raise Error, error.message
    end

    def positive_length(length, fallback)
      n = length.to_i
      n.positive? ? n : fallback
    end

    def mask_middle(text, length, pad_char)
      window = positive_length(length, 1)
      char = pad_char.to_s
      char = "*" if char.empty?
      chars = text.to_s.chars
      return text.to_s if chars.length <= window * 2

      chars.first(window).join + (char * (chars.length - window * 2)) + chars.last(window).join
    end
    private_class_method :mask_middle
  end
end
