# frozen_string_literal: true

module FlowchartRuntime
  # Timeout-bounded regular expression extract / test / replace.
  module Regex
    class Error < StandardError; end

    TIMEOUT = 1.0
    MAX_PATTERN_BYTES = 4096
    OPERATIONS = %w[match scan test replace].freeze
    FLAGS = %w[i m x none].freeze
    RETURN_TYPES = %w[first all named_hash].freeze
    FLAG_MAP = {
      "i" => Regexp::IGNORECASE,
      "m" => Regexp::MULTILINE,
      "x" => Regexp::EXTENDED,
      "n" => Regexp::NOENCODING
    }.freeze

    module_function

    def apply(source, pattern:, operation: "match", flags: "none", regex_flags: "",
              return_type: "first", capture_group: 0, replacement: "", fallback: nil)
      name = operation.to_s
      raise Error, "unsupported operation" unless OPERATIONS.include?(name)

      regex = compile(pattern, flags: flags, regex_flags: regex_flags)
      text = source.to_s
      case name
      when "match" then match_value(text, regex, return_type, capture_group, fallback)
      when "scan" then text.scan(regex)
      when "test" then text.match?(regex)
      when "replace" then text.gsub(regex, replacement.to_s)
      end
    rescue Regexp::TimeoutError, RegexpError => error
      raise Error, error.message
    end

    def compile(pattern, flags: "none", regex_flags: "")
      source = pattern.to_s
      raise Error, "pattern too long" if source.bytesize > MAX_PATTERN_BYTES

      Regexp.new(source, flag_mask(flags, regex_flags), timeout: TIMEOUT)
    rescue RegexpError, TypeError, ArgumentError => error
      raise Error, error.message
    end

    def match_value(text, regex, return_type, capture_group, fallback)
      case return_type.to_s
      when "named_hash"
        match = text.match(regex)
        match ? match.named_captures : fallback
      when "all"
        text.scan(regex)
      else
        match = text.match(regex)
        return fallback unless match

        match[capture_group.to_i]
      end
    end

    def flag_mask(flags, regex_flags)
      chars = regex_flags.to_s.chars
      if chars.any? && chars.all? { |char| FLAG_MAP.key?(char) }
        return chars.uniq.sum { |char| FLAG_MAP[char] }
      end

      case flags.to_s
      when "i" then Regexp::IGNORECASE
      when "m" then Regexp::MULTILINE
      when "x" then Regexp::EXTENDED
      else 0
      end
    end
  end
end
