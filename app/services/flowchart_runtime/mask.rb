# frozen_string_literal: true

module FlowchartRuntime
  # Format-aware masking for flowchart mask-data steps.
  #
  # Each masking convention lives here rather than being inlined into emitted
  # source so that (a) the rules are unit-testable on their own, and (b) the
  # implementation can be swapped for a library without touching any generator
  # or any already-generated step. Mirrors the facade shape used by
  # FlowchartRuntime::CacheKey.
  #
  # There is no well-maintained Ruby gem that covers PAN/SSN/phone display
  # masking (the credit-card gems validate and detect brands, they do not
  # mask), so the conventions are implemented here — in one place, behind one
  # interface — instead of being spread across generators.
  module Mask
    class Error < StandardError; end

    SIGNIFICANT = /[[:alnum:]]/
    DIGIT = /\d/

    # PCI-DSS 3.3: at most the first six (BIN/IIN) and the last four digits of
    # a PAN may be displayed. The BIN is only revealed when the PAN is long
    # enough that something is still masked between the two windows.
    PAN_BIN_LENGTH = 6
    PAN_TAIL_LENGTH = 4
    PAN_MIN_LENGTH_FOR_BIN = 12

    SSN_TAIL_LENGTH = 4
    PHONE_TAIL_LENGTH = 4

    TYPES = %w[last4 first1_last1 email phone mobile ssn credit_card id_number full custom name address].freeze
    # Presets keep their own windows; only custom honors visible_start/end.
    PRESET_TYPES = %w[last4 first1_last1 email phone mobile ssn credit_card id_number full name address].freeze

    module_function

    def apply(value, type:, mask_char: "*", visible_start: 0, visible_end: 0,
              preserve_format: true, regex_pattern: nil)
      type_name = type.to_s
      raise Error, "unsupported mask type" unless TYPES.include?(type_name)

      char = mask_char!(mask_char)
      windowed = positive_int?(visible_start) || positive_int?(visible_end)
      if windowed && !PRESET_TYPES.include?(type_name) && type_name != "custom"
        return window(value, mask_char: char, visible_start: visible_start,
                      visible_end: visible_end, preserve_format: preserve_format)
      end

      case type_name
      when "last4" then last4(value, mask_char: char)
      when "first1_last1" then first1_last1(value, mask_char: char)
      when "email" then email(value, mask_char: char)
      when "phone", "mobile", "ssn", "credit_card", "id_number"
        public_send(type_name, value, mask_char: char, preserve_format: preserve_format)
      when "full" then full(value, mask_char: char)
      when "name" then name(value, mask_char: char)
      when "address" then address(value, mask_char: char)
      else custom(value, mask_char: char, regex_pattern: regex_pattern,
                  visible_start: visible_start, visible_end: visible_end)
      end
    end

    def last4(value, mask_char: "*")
      char = mask_char!(mask_char)
      chars = value.to_s.chars
      len = chars.length
      tail = [len, 4].min
      (char * [len - tail, 0].max) + chars.last(tail).join
    end

    def first1_last1(value, mask_char: "*")
      char = mask_char!(mask_char)
      chars = value.to_s.chars
      len = chars.length
      return chars.join if len <= 1

      chars.first.to_s + (char * [len - 2, 0].max) + chars.last.to_s
    end

    def email(value, mask_char: "*")
      char = mask_char!(mask_char)
      email = value.to_s
      parts = email.split("@", 2)
      return email unless parts.length == 2 && !parts[0].empty? && !parts[1].empty?

      name_chars = parts[0].chars
      name_chars.first.to_s + (char * [name_chars.length - 1, 0].max) + "@" + parts[1]
    end

    def full(value, mask_char: "*")
      char = mask_char!(mask_char)
      char * value.to_s.chars.length
    end

    # Keep the first character of each whitespace-separated token.
    def name(value, mask_char: "*")
      char = mask_char!(mask_char)
      value.to_s.split(/(\s+)/).map do |part|
        next part if part.match?(/\A\s+\z/)

        chars = part.chars
        next part if chars.empty?

        chars.first.to_s + (char * [chars.length - 1, 0].max)
      end.join
    end

    # Mask street lines and keep the last comma-separated locality (city / region / postal).
    def address(value, mask_char: "*")
      char = mask_char!(mask_char)
      source = value.to_s
      parts = source.split(/,\s*/, -1)
      if parts.size > 1
        hidden = parts[0..-2].map do |part|
          window(part, mask_char: char, visible_start: 0, visible_end: 0, preserve_format: true)
        end
        (hidden + [parts.last]).join(", ")
      else
        window(source, mask_char: char, visible_start: 0, visible_end: 6, preserve_format: true)
      end
    end

    def custom(value, mask_char: "*", regex_pattern: nil, visible_start: 0, visible_end: 0)
      char = mask_char!(mask_char)
      pattern = regex_pattern.to_s
      if pattern.empty?
        window(value, mask_char: char, visible_start: visible_start, visible_end: visible_end,
               preserve_format: false)
      else
        value.to_s.gsub(Regexp.new(pattern), char)
      end
    rescue RegexpError => error
      raise Error, error.message
    end

    def positive_int?(value)
      value.to_s.match?(/\A\d+\z/) && value.to_i.positive?
    end

    # Generic significant-character window.
    #
    # @param visible_start [Integer] significant chars kept at the start
    # @param visible_end   [Integer] significant chars kept at the end
    # @param preserve_format [Boolean] when true, non-alphanumeric separators
    #   are passed through and are not counted towards the window
    def window(value, mask_char: "*", visible_start: 0, visible_end: 0, preserve_format: true)
      char = mask_char!(mask_char)
      head = non_negative!(visible_start, "visible_start")
      tail = non_negative!(visible_end, "visible_end")
      source = value.to_s

      if preserve_format
        total = source.chars.count { |c| c.match?(SIGNIFICANT) }
        head_n = [head, total].min
        tail_n = [tail, total - head_n].min

        mask_significant(source, char, pattern: SIGNIFICANT) do |index, _total|
          index < head_n || index >= total - tail_n
        end
      else
        chars = source.chars
        len = chars.length
        head = [head, len].min
        tail = [tail, len - head].min
        chars.first(head).join + (char * [len - head - tail, 0].max) + chars.last(tail).join
      end
    end

    # Credit card / PAN: reveal the BIN and the last four digits.
    def credit_card(value, mask_char: "*", preserve_format: true)
      char = mask_char!(mask_char)
      source = value.to_s
      digits = source.count("0-9")
      head = digits >= PAN_MIN_LENGTH_FOR_BIN ? PAN_BIN_LENGTH : 0

      mask_digits(source, char, preserve_format: preserve_format) do |index, total|
        index < head || index >= total - [PAN_TAIL_LENGTH, total].min
      end
    end

    # US SSN: reveal the last four digits only (***-**-1234).
    def ssn(value, mask_char: "*", preserve_format: true)
      char = mask_char!(mask_char)

      mask_digits(value.to_s, char, preserve_format: preserve_format) do |index, total|
        index >= total - [SSN_TAIL_LENGTH, total].min
      end
    end

    # Mainland mobile numbers: keep the first three digits (carrier prefix)
    # and the last four. Also used for other compact subscriber numbers of
    # length 7+.
    def mobile(value, mask_char: "*", preserve_format: true)
      char = mask_char!(mask_char)

      mask_digits(value.to_s, char, preserve_format: preserve_format) do |index, total|
        head = [3, total].min
        tail = [4, [total - head, 0].max].min
        index < head || index >= total - tail
      end
    end

    # Chinese resident ID (18-digit, last char may be X) and similar national
    # numbers: keep the first six (region) and the last four.
    def id_number(value, mask_char: "*", preserve_format: true)
      char = mask_char!(mask_char)
      source = value.to_s
      pattern = SIGNIFICANT
      total = source.chars.count { |c| c.match?(pattern) }
      head = total >= 15 ? 6 : 0
      tail = [4, total].min

      if preserve_format
        mask_significant(source, char, pattern: pattern) do |index, count|
          index < head || index >= count - tail
        end
      else
        compact = source.gsub(/[^[:alnum:]]/, "")
        mask_significant(compact, char, pattern: pattern) do |index, count|
          keep_head = count >= 15 ? 6 : 0
          index < keep_head || index >= count - [4, count].min
        end
      end
    end

    # Phone: reveal the last four digits, and keep an explicit international
    # dialling prefix (`+<country code>`) visible so the number stays
    # identifiable by region.
    def phone(value, mask_char: "*", preserve_format: true)
      char = mask_char!(mask_char)
      source = value.to_s
      prefix_digits = country_code_digits(source)

      mask_digits(source, char, preserve_format: preserve_format) do |index, total|
        index < prefix_digits || index >= total - [PHONE_TAIL_LENGTH, total].min
      end
    end

    # Number of leading digits that belong to an explicit `+NN` dialling
    # prefix. Only counted when the value starts with "+" AND the prefix is
    # delimited, because "+14155551234" gives no way to tell where the country
    # code ends.
    def country_code_digits(source)
      return 0 unless source.start_with?("+")

      prefix = source[1..].to_s[/\A\d+/]
      return 0 if prefix.nil?
      return 0 if source[1 + prefix.length].nil?
      return 0 if source[1 + prefix.length].match?(DIGIT)

      prefix.length
    end

    def mask_digits(source, char, preserve_format:, &keep)
      return mask_significant(source, char, pattern: DIGIT, &keep) if preserve_format

      mask_significant(source.gsub(/\D/, ""), char, pattern: DIGIT, &keep)
    end

    # Walks +source+, replacing every character matching +pattern+ with +char+
    # unless the block says that position is kept. Characters that do not match
    # +pattern+ are passed through untouched and are not counted.
    def mask_significant(source, char, pattern:)
      total = source.chars.count { |c| c.match?(pattern) }
      index = -1

      source.chars.map do |c|
        next c unless c.match?(pattern)

        index += 1
        yield(index, total) ? c : char
      end.join
    end

    def mask_char!(mask_char)
      char = mask_char.to_s
      raise Error, "mask character is required" if char.empty?

      char
    end

    def non_negative!(value, name)
      integer = Integer(value)
      raise Error, "#{name} must be non-negative" if integer.negative?

      integer
    rescue TypeError, ArgumentError
      raise Error, "#{name} must be an integer"
    end
  end
end
