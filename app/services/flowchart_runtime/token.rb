# frozen_string_literal: true

require "base58"
require "securerandom"
require "digest"
require "json"

module FlowchartRuntime
  # Random tokens and Rails MessageVerifier signed payloads for flowchart
  # generate_token / verify_token steps. JWT stays on FlowchartRuntime::Jwt.
  module Token
    class Error < StandardError; end
    class InvalidToken < Error; end

    DEFAULT_PURPOSE = "flowchart_token"

    module_function

    def base58(bytes:)
      byte_count = Integer(bytes, exception: false)
      raise Error, "bytes must be positive" unless byte_count&.positive?

      Base58.binary_to_base58(SecureRandom.random_bytes(byte_count))
    end

    def sign(payload, key:, purpose: DEFAULT_PURPOSE, expires_in: nil)
      raise Error, "key is required" if key.to_s.empty?

      options = { purpose: purpose.to_s }
      if expires_in.to_s.present?
        options[:expires_in] = Jwt.duration_seconds(expires_in)
      end
      verifier(key).generate(payload, **options)
    rescue JSON::GeneratorError => error
      raise Error, error.message
    end

    def verify(token, key:, purpose: DEFAULT_PURPOSE)
      raise Error, "key is required" if key.to_s.empty?
      raise InvalidToken, "token is required" if token.to_s.empty?

      verifier(key).verify(token.to_s, purpose: purpose.to_s)
    rescue ActiveSupport::MessageVerifier::InvalidSignature => error
      raise InvalidToken, error.message
    end

    def verify_or_nil(token, key:, purpose: DEFAULT_PURPOSE)
      verify(token, key: key, purpose: purpose)
    rescue InvalidToken
      nil
    end

    def verifier(key)
      ActiveSupport::MessageVerifier.new(
        Digest::SHA256.digest(key.to_s),
        digest: "SHA256",
        serializer: JSON
      )
    end
    private_class_method :verifier
  end
end
