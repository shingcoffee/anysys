# frozen_string_literal: true

module Sms
  # Advisory counting for *rendered text*, not an estimate from provider template
  # codes/variables. Actual carrier segments are separately recorded as
  # metadata.provider_segments by DeliveryProjection.
  #
  # 3GPP TS 23.038 §6.2.1 default/extension alphabets; TS 23.040 §9.2.3.24 UDH.
  # https://www.etsi.org/deliver/etsi_ts/123000_123099/123038/18.00.00_60/ts_123038v180000p.pdf
  # Evaluated smstools 0.2.2: its ceiling(total/capacity) calculation cannot pack
  # indivisible escape sequences/surrogate pairs at boundaries, and lacks
  # provider-specific capacity overrides. This small pure packing algorithm
  # covers those requirements; it is not a provider billing quote or encoder.
  class SegmentCalculator
    GSM_DEFAULT = ("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ" \
      " !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà").chars.freeze
    GSM_EXTENSION = "\f^{}\\[~]|€".chars.freeze
    DEFAULT_LIMITS = { gsm_single: 160, gsm_multipart: 153, unicode_single: 70, unicode_multipart: 67 }.freeze

    # @return [Hash] { encoding: :gsm7|:utf16, units:, segments:, segment_units: }
    def self.call(text:, **limits)
      new(text: text, **limits).call
    end

    def initialize(text:, **limits)
      unless text.is_a?(String) && text.valid_encoding? && (text.encoding == Encoding::UTF_8 || text.ascii_only?)
        raise ArgumentError, I18n.t("sms_standards.errors.invalid_text")
      end
      unless (limits.keys - DEFAULT_LIMITS.keys).empty? && limits.values.all? { |v| v.is_a?(Integer) && v >= 2 }
        raise ArgumentError, I18n.t("sms_standards.errors.invalid_segment_limits")
      end
      @text = text
      @limits = DEFAULT_LIMITS.merge(limits)
    end

    def call
      chars = @text.each_char.to_a
      gsm = chars.all? { |char| GSM_DEFAULT.include?(char) || GSM_EXTENSION.include?(char) }
      weights = chars.map { |char| gsm ? (GSM_EXTENSION.include?(char) ? 2 : 1) : (char.ord > 0xFFFF ? 2 : 1) }
      units = weights.sum
      single = @limits.fetch(gsm ? :gsm_single : :unicode_single)
      multipart = @limits.fetch(gsm ? :gsm_multipart : :unicode_multipart)
      parts = units.zero? ? [] : (units <= single ? [units] : pack(weights, multipart))
      { encoding: gsm ? :gsm7 : :utf16, units: units, segments: parts.size, segment_units: parts }
    end

    private

    def pack(weights, capacity)
      parts = [0]
      weights.each do |weight|
        parts << 0 if parts.last + weight > capacity
        parts[-1] += weight
      end
      parts
    end
  end
end
