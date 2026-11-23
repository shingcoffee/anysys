# frozen_string_literal: true

require "openssl"
require "digest"

module FlowchartRuntime
  module Crypto
    class Error < StandardError; end

    MAX_ITERATIONS = 1_000_000

    DIGESTS = %w[sha1 sha256 sha512].freeze
    HASH_ALGORITHMS = %w[sha256 sha512].freeze
    HASH_ENCODINGS = %w[hex base64 base64url].freeze

    module_function

    def hmac(digest, key:, data:, encoding: "hex")
      algorithm = normalize_digest(digest)
      raise Error, "key is required" if key.to_s.empty?

      encode_digest(OpenSSL::HMAC.digest(algorithm, key.to_s, data.to_s), encoding)
    rescue OpenSSL::OpenSSLError => e
      raise Error, e.message
    end

    def pbkdf2(passphrase, salt:, iterations:, length: 32, digest: "sha256")
      algorithm = normalize_digest(digest)
      raise Error, "passphrase is required" if passphrase.to_s.empty?
      raise Error, "salt is required" if salt.to_s.empty?

      iteration_count = Integer(iterations, exception: false)
      output_length = Integer(length, exception: false)
      raise Error, "iterations must be positive" unless iteration_count&.positive?
      raise Error, "iterations exceed maximum of #{MAX_ITERATIONS}" if iteration_count > MAX_ITERATIONS
      raise Error, "length must be positive" unless output_length&.positive?

      OpenSSL::KDF.pbkdf2_hmac(
        passphrase.to_s,
        salt: salt.to_s,
        iterations: iteration_count,
        length: output_length,
        hash: algorithm
      )
    rescue OpenSSL::OpenSSLError => e
      raise Error, e.message
    end

    def digest(algorithm, data, encoding: "hex", salt: nil, pepper: nil)
      algo = algorithm.to_s.downcase
      raise Error, "unsupported digest" unless HASH_ALGORITHMS.include?(algo)

      input = [salt, data, pepper].compact.map(&:to_s).join
      encode_digest(Digest.const_get(algo.upcase).digest(input), encoding)
    end

    def encoded_pbkdf2(passphrase, salt:, iterations:, encoding: "hex", length: 32, digest: "sha256")
      encode_digest(pbkdf2(passphrase, salt: salt, iterations: iterations, length: length, digest: digest), encoding)
    end

    def secure_compare(given, expected)
      left = given.to_s
      right = expected.to_s
      return false if left.empty? || right.empty? || left.bytesize != right.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def encode_digest(raw, encoding)
      case encoding.to_s
      when "hex" then raw.to_s.unpack1("H*")
      when "base64" then [raw.to_s].pack("m0")
      when "base64url" then [raw.to_s].pack("m0").tr("+/", "-_").tr("=", "")
      else raise Error, "unsupported encoding"
      end
    end

    def normalize_digest(digest)
      algorithm = digest.to_s.downcase
      raise Error, "unsupported digest" unless DIGESTS.include?(algorithm)

      algorithm
    end
    private_class_method :normalize_digest, :encode_digest
  end
end
