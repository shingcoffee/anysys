# frozen_string_literal: true

require "jwt"
require "openssl"
require "fugit"

module FlowchartRuntime
  # FlowchartRuntime::Jwt
  #
  # Thin wrapper around the jwt gem for flowchart token step generators.
  # Owns the app-level contract: allowed algorithms and a single error type
  # (FlowchartRuntime::Jwt::Error) so generated step code never rescues raw
  # ::JWT::* exceptions.
  module Jwt
    class Error < StandardError; end
    # A token that fails decoding or claim checks; setup problems stay plain Error.
    class InvalidToken < Error; end

    ALLOWED_ALGS = %w[HS256 HS384 HS512 RS256].freeze

    module_function

    # @param payload   [Hash]
    # @param secret    [String]
    # @param algorithm [String]
    # @param headers   [Hash]
    # @return [String] signed JWT
    # @raise  [FlowchartRuntime::Jwt::Error]
    def encode(payload, secret, algorithm: "HS256", headers: {})
      raise Error, "unsupported algorithm" unless ALLOWED_ALGS.include?(algorithm.to_s)
      raise Error, "payload must be a hash" unless payload.is_a?(Hash)
      raise Error, "secret is required" if secret.to_s.empty?
      raise Error, "headers must be a hash" unless headers.is_a?(Hash)

      ::JWT.encode(payload, normalize_key(secret, algorithm.to_s), algorithm.to_s, headers)
    rescue ::JWT::EncodeError, OpenSSL::PKey::PKeyError => e
      raise Error, e.message
    end

    # @param token           [String]
    # @param secret          [String]
    # @param algorithms      [Array<String>]
    # @param verify          [Boolean]
    # @param required_claims [Array<String>]
    # @param options         [Hash] additional options forwarded to ::JWT.decode
    # @return [Hash] decoded payload
    # @raise  [FlowchartRuntime::Jwt::Error]
    def decode(token, secret, algorithms: ["HS256"], verify: true, required_claims: [], **options)
      algs = Array(algorithms).map(&:to_s)
      raise InvalidToken, "token is required" if token.to_s.empty?
      raise Error, "secret is required" if secret.to_s.empty?
      raise Error, "algorithms are required" if algs.empty?
      raise Error, "unsupported algorithm" unless algs.all? { |a| ALLOWED_ALGS.include?(a) }

      decode_opts = { algorithms: algs, required_claims: Array(required_claims) }.merge(options)
      key = algs.any? { |algorithm| algorithm.start_with?("RS") } ? normalize_rsa_key(secret) : secret
      payload, = ::JWT.decode(token, key, verify, decode_opts)
      payload
    rescue ::JWT::DecodeError => e
      raise InvalidToken, e.message
    rescue OpenSSL::PKey::PKeyError => e
      raise Error, e.message
    end

    def issue(payload, secret, algorithm: "HS256", expires_in: nil, issuer: nil,
              audience: nil, not_before: nil, claims: {}, key_id: nil, subject: nil,
              issued_at: false)
      base = case payload
             when nil then {}
             when Hash then payload
             else raise Error, "payload must be a hash"
             end
      extra = stringify_keys(claims)
      extra["iss"] = issuer if issuer.to_s.present?
      extra["aud"] = audience if audience.to_s.present?
      extra["sub"] = subject if subject.to_s.present?
      extra["nbf"] = not_before if not_before
      extra["iat"] = Time.current.to_i if issued_at
      extra["exp"] = Time.current.to_i + duration_seconds(expires_in) if expires_in.to_s.present?
      headers = key_id.to_s.present? ? { kid: key_id.to_s } : {}
      encode(stringify_keys(base).merge(extra), secret, algorithm: algorithm, headers: headers)
    end

    def verify(token, secret, algorithms:, iss: nil, aud: nil, leeway: 0, required_claims: {})
      algs = Array(algorithms).map(&:to_s)
      algs = ["HS256"] if algs.empty?
      options = { algorithms: algs, leeway: Integer(leeway || 0), verify_expiration: true }
      if iss.to_s.present?
        options[:iss] = iss.to_s
        options[:verify_iss] = true
      end
      if aud.to_s.present?
        options[:aud] = aud.to_s
        options[:verify_aud] = true
      end
      payload = decode(token, secret, **options)
      assert_required_claims!(payload, required_claims)
      payload
    end

    def verify_or_nil(token, secret, **options)
      verify(token, secret, **options)
    rescue InvalidToken
      nil
    end

    def duration_seconds(value)
      return 0 if value.nil? || value.to_s.strip.empty?
      return value.to_i if value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)

      if value.to_s.start_with?("P")
        ActiveSupport::Duration.parse(value.to_s).to_i
      else
        parsed = Fugit::Duration.parse(value.to_s)
        raise Error, "invalid expiry" unless parsed

        parsed.to_sec
      end
    rescue ActiveSupport::Duration::ISO8601Parser::ParsingError
      raise Error, "invalid expiry"
    end

    def stringify_keys(hash)
      (hash || {}).to_h.transform_keys(&:to_s)
    end

    def assert_required_claims!(payload, required_claims)
      return unless required_claims.respond_to?(:each)

      required_claims.each do |claim, expected|
        name = claim.to_s
        present, value = claim_lookup(payload, name)
        raise InvalidToken, "missing claim #{name}" unless present
        next if expected.nil? || expected.to_s.strip.empty?

        raise InvalidToken, "invalid claim #{name}" unless values_equal?(value, expected)
      end
    end

    def claim_lookup(payload, claim)
      parts = claim.to_s.split(".", -1)
      current = payload
      parts.each do |segment|
        return [false, nil] unless current.is_a?(Hash) && current.key?(segment)

        current = current[segment]
      end
      [true, current]
    end

    def values_equal?(actual, expected)
      actual == expected || actual.to_s == expected.to_s
    end

    def normalize_key(secret, algorithm)
      algorithm.start_with?("RS") ? normalize_rsa_key(secret) : secret
    end

    def normalize_rsa_key(key)
      parsed = key.is_a?(OpenSSL::PKey::RSA) ? key : OpenSSL::PKey.read(key.to_s)
      raise Error, "RS256 key must be an RSA key" unless parsed.is_a?(OpenSSL::PKey::RSA)

      parsed
    end
    private_class_method :stringify_keys, :assert_required_claims!, :claim_lookup, :values_equal?
  end
end
