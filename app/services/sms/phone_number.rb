# frozen_string_literal: true

require "phonelib"

module Sms
  # Strict lexical gate over maintained libphonenumber data. Validity describes
  # a numbering plan, not assignment, reachability, or SMS capability. Display
  # separators are accepted; prose, vanity numbers and extensions are not.
  # International input requires + or 00; national input uses explicit CN
  # context by default. Never mutate Phonelib's process-global configuration.
  class PhoneNumber
    DEFAULT_COUNTRY = "CN"
    MAX_INPUT_BYTES = 64
    DISPLAY_FORMAT = /\A\+?[0-9(][0-9 .()\-]*\z/

    def self.normalize(raw, country: DEFAULT_COUNTRY)
      new(raw, country: country).e164
    end

    def initialize(raw, country: DEFAULT_COUNTRY)
      @raw = raw
      @country = country
    end

    def e164
      return @e164 if defined?(@e164)

      @e164 = parse_e164
    end

    def valid? = !e164.nil?

    private

    def parse_e164
      return unless @raw.is_a?(String) && @raw.valid_encoding? && @raw.bytesize <= MAX_INPUT_BYTES
      return unless @raw.encoding == Encoding::UTF_8 || @raw.ascii_only?
      return if @raw.match?(/[\r\n\t]/)

      text = @raw.strip
      return unless text.match?(DISPLAY_FORMAT) && balanced_parentheses?(text)

      compact = text.delete(" .()-")
      international = compact.start_with?("+", "00")
      compact = "+#{compact.delete_prefix('00')}" if compact.start_with?("00")
      parsed = Phonelib.parse(compact, @country)
      return unless parsed.valid? && parsed.extension.to_s.empty?
      return unless parsed.e164.match?(/\A\+[1-9][0-9]{6,14}\z/)

      if international
        return unless parsed.e164 == compact
      else
        # Reject a bare country-code prefix that the permissive library would
        # otherwise reinterpret as international despite the national context.
        return unless parsed.valid_for_country?(@country)
        return unless [parsed.national_number, parsed.national(false)].include?(compact)
      end
      parsed.e164
    end

    def balanced_parentheses?(text)
      depth = 0
      text.each_char do |char|
        depth += 1 if char == "("
        depth -= 1 if char == ")"
        return false unless (0..1).cover?(depth)
      end
      depth.zero? && !text.include?("()")
    end
  end
end
