# frozen_string_literal: true

require "nanoid"
require "ulid"

module FlowchartRuntime
  # Identifier generation for generate_id, including former generate_token
  # random types (hex, base58, urlsafe_base64, secure_random).
  module Id
    class Error < StandardError; end

    TYPES = %w[uuid ulid nanoid hash custom_pattern hex base58 urlsafe_base64 secure_random].freeze
    DEFAULT_NANOID_SIZE = 21
    DEFAULT_LENGTH = 21
    DEFAULT_TOKEN_LENGTH = 32

    module_function

    def generate(type:, size: nil, alphabet: nil, length: nil, pattern: nil,
                 prefix: nil, separator: nil, uppercase: false)
      raw = case type.to_s
            when "uuid" then SecureRandom.uuid
            when "ulid" then ULID.generate
            when "nanoid" then generate_nanoid(size: size, alphabet: alphabet)
            when "hash" then generate_hash(length: length)
            when "custom_pattern" then generate_custom_pattern(pattern: pattern)
            when "hex" then generate_hex(length: length)
            when "base58" then generate_base58(length: length)
            when "urlsafe_base64" then generate_urlsafe_base64(length: length)
            when "secure_random" then generate_secure_random(length: length)
            else raise Error, "unsupported id type: #{type}"
            end

      apply_decorations(raw.to_s, prefix: prefix, separator: separator, uppercase: uppercase)
    end

    def generate_nanoid(size:, alphabet:)
      resolved_size = size.to_i
      resolved_size = DEFAULT_NANOID_SIZE if resolved_size <= 0

      if !alphabet.nil?
        alpha = alphabet.to_s
        raise Error, "alphabet must be a non-empty string" if alpha.empty?
        raise Error, "alphabet must contain at least two characters" if alpha.length < 2

        ::Nanoid.generate(size: resolved_size, alphabet: alpha)
      else
        ::Nanoid.generate(size: resolved_size)
      end
    end

    def generate_hash(length:)
      resolved_length = length.to_i
      resolved_length = DEFAULT_LENGTH if resolved_length <= 0
      bytes = [((resolved_length + 1) / 2), 1].max
      SecureRandom.hex(bytes).first(resolved_length)
    end

    def generate_hex(length:)
      resolved = positive_length(length, DEFAULT_TOKEN_LENGTH)
      SecureRandom.hex([resolved / 2, 1].max)
    end

    def generate_base58(length:)
      resolved = positive_length(length, DEFAULT_TOKEN_LENGTH)
      Token.base58(bytes: [resolved / 2, 1].max)
    rescue Token::Error => error
      raise Error, error.message
    end

    def generate_urlsafe_base64(length:)
      SecureRandom.urlsafe_base64(positive_length(length, DEFAULT_TOKEN_LENGTH))
    end

    def generate_secure_random(length:)
      SecureRandom.hex(positive_length(length, DEFAULT_TOKEN_LENGTH))
    end

    def generate_custom_pattern(pattern:)
      Time.current.strftime(pattern.to_s) + SecureRandom.alphanumeric(6)
    end

    def positive_length(length, fallback)
      resolved = length.to_i
      resolved.positive? ? resolved : fallback
    end

    def apply_decorations(value, prefix:, separator:, uppercase:)
      id_part = uppercase ? value.upcase : value
      prefix_str = prefix.to_s
      return id_part if prefix_str.empty?

      "#{prefix_str}#{separator}#{id_part}"
    end
  end
end
