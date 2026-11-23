# frozen_string_literal: true

module FlowchartRuntime
  # HMAC verification for inbound webhook / callback signatures.
  module Signature
    class Error < StandardError; end

    DIGESTS = Crypto::DIGESTS
    ENCODINGS = %w[hex base64].freeze
    SIGNED_PAYLOADS = %w[body timestamp_body].freeze

    module_function

    def verify(ctx, payload:, signature:, secret:, algorithm: "sha256", encoding: "hex",
               prefix: "", signed_payload: "body", timestamp: nil, separator: ".",
               tolerance: 300, on_invalid: "fail")
      return Step.fail(ctx, :"verify_signature.missing_secret") if secret.to_s.empty?

      data = signed_bytes(payload, signed_payload, timestamp, separator)
      flag = on_invalid.to_s == "flag"
      if signed_payload.to_s == "timestamp_body" && timestamp_expired?(timestamp, tolerance)
        return flag ? false : Step.fail(ctx, :"verify_signature.expired")
      end

      raise Error, "unsupported encoding" unless ENCODINGS.include?(encoding.to_s)

      expected = Crypto.hmac(algorithm, key: secret, data: data, encoding: encoding)
      return true if candidate_match?(signature, prefix, expected, encoding)

      flag ? false : Step.fail(ctx, :"verify_signature.invalid")
    rescue Crypto::Error, Error
      Step.fail(ctx, :"verify_signature.invalid")
    end

    def signed_bytes(payload, mode, timestamp, separator)
      body = payload.is_a?(String) ? payload : payload.to_s
      return body unless mode.to_s == "timestamp_body"

      "#{timestamp}#{separator}#{body}"
    end

    def timestamp_expired?(timestamp, tolerance)
      seconds = Integer(tolerance, exception: false) || 0
      return false if seconds <= 0

      ts = parse_timestamp(timestamp)
      return true if ts.nil?

      (Time.now.to_i - ts).abs > seconds
    end

    def parse_timestamp(value)
      number = case value
               when Integer then value
               when Float then value.to_i
               when Time then value.to_i
               else Integer(value.to_s, exception: false)
               end
      return nil unless number

      number > 10_000_000_000 ? number / 1000 : number
    end

    def candidate_match?(header, prefix, expected, encoding)
      wanted = normalize(expected, encoding)
      candidates_from(header, prefix).any? do |candidate|
        Crypto.secure_compare(normalize(candidate, encoding), wanted)
      end
    end

    def candidates_from(header, prefix)
      text = header.to_s.strip
      pref = prefix.to_s
      text = text.delete_prefix(pref) if pref.present? && text.start_with?(pref)
      tokens = text.split(/[,\s]+/).reject(&:empty?)
      tokens.filter_map do |token|
        if token.match?(/\A(?:t|v0|v1|sha1|sha256|sha512)=/i)
          key, value = token.split("=", 2)
          next if key.to_s.downcase == "t"
          next if value.to_s.empty?

          value
        else
          token
        end
      end
    end

    def normalize(value, encoding)
      text = value.to_s
      encoding.to_s == "hex" ? text.downcase : text
    end
    private_class_method :signed_bytes, :timestamp_expired?, :parse_timestamp,
                         :candidate_match?, :candidates_from, :normalize
  end
end
