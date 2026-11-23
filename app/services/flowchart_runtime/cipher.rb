# frozen_string_literal: true

require "openssl"
require "digest"
require "base64"

module FlowchartRuntime
  # FlowchartRuntime::Cipher
  #
  # Thin wrapper around ActiveSupport::MessageEncryptor for flowchart
  # encrypt/decrypt step generators. Owns allowed algorithms and a single
  # error type (FlowchartRuntime::Cipher::Error) so generated step code
  # never rescues raw OpenSSL or MessageEncryptor exceptions.
  module Cipher
    class Error < StandardError; end

    MAX_ITERATIONS = 1_000_000

    ALLOWED_ALGORITHMS = %w[aes-256-gcm].freeze
    DEFAULT_ALGORITHM = "aes-256-gcm"
    DEFAULT_ITERATIONS = 20_000
    DEFAULT_PURPOSE = :flowchart_data
    ENCODINGS = %i[base64 base64url hex raw binary].freeze

    module_function

    # @param plaintext [String]
    # @param key       [String]
    # @param purpose   [Symbol]
    # @param algorithm [String]
    # @return [String] encrypted message (Base64-compatible)
    # @raise  [FlowchartRuntime::Cipher::Error]
    def encrypt(plaintext, key:, purpose: DEFAULT_PURPOSE, algorithm: DEFAULT_ALGORITHM)
      raise Error, "unsupported algorithm" unless ALLOWED_ALGORITHMS.include?(algorithm.to_s)
      raise Error, "key is required" if key.to_s.empty?

      build_encryptor(key, algorithm: algorithm).encrypt_and_sign(plaintext.to_s, purpose: purpose.to_s)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, OpenSSL::Cipher::CipherError => e
      raise Error, e.message
    end

    # @param ciphertext [String]
    # @param key        [String]
    # @param purpose    [Symbol]
    # @param algorithm  [String]
    # @return [String] decrypted plaintext
    # @raise  [FlowchartRuntime::Cipher::Error]
    def decrypt(ciphertext, key:, purpose: DEFAULT_PURPOSE, algorithm: DEFAULT_ALGORITHM)
      raise Error, "unsupported algorithm" unless ALLOWED_ALGORITHMS.include?(algorithm.to_s)
      raise Error, "key is required" if key.to_s.empty?

      build_encryptor(key, algorithm: algorithm).decrypt_and_verify(ciphertext.to_s, purpose: purpose.to_s)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, OpenSSL::Cipher::CipherError => e
      raise Error, e.message
    end

    # Derives a 32-byte key via PBKDF2. Generators pass Ruby expressions for
    # passphrase and salt; this method performs the OpenSSL work at runtime.
    #
    # @param passphrase [String]
    # @param salt       [String]
    # @param iterations [Integer]
    # @return [String] 32-byte binary key
    def key_from_passphrase(passphrase, salt:, iterations: DEFAULT_ITERATIONS)
      raise Error, "passphrase is required" if passphrase.to_s.empty?
      raise Error, "salt is required" if salt.to_s.empty?

      iteration_count = Integer(iterations, exception: false)
      raise Error, "iterations must be positive" unless iteration_count&.positive?
      raise Error, "iterations exceed maximum of #{MAX_ITERATIONS}" if iteration_count > MAX_ITERATIONS

      FlowchartRuntime::Crypto.pbkdf2(
        passphrase.to_s,
        salt: salt.to_s,
        iterations: iteration_count,
        length: 32,
        digest: "sha256"
      )
    rescue FlowchartRuntime::Crypto::Error => e
      raise Error, e.message
    end

    def encrypt_value(plaintext, key:, encoding:, purpose: DEFAULT_PURPOSE, algorithm: DEFAULT_ALGORITHM)
      encode(encrypt(plaintext, key: key, purpose: purpose, algorithm: algorithm), encoding: encoding)
    end

    def decrypt_value(ciphertext, key:, encoding:, purpose: DEFAULT_PURPOSE, algorithm: DEFAULT_ALGORITHM)
      decrypt(decode(ciphertext, encoding: encoding), key: key, purpose: purpose, algorithm: algorithm)
    end

    def encode(ciphertext, encoding:)
      case normalize_encoding(encoding)
      when :base64
        Base64.strict_encode64(ciphertext.to_s.b)
      when :base64url
        Base64.urlsafe_encode64(ciphertext.to_s.b, padding: false)
      when :hex
        ciphertext.to_s.b.unpack1("H*")
      else
        ciphertext.to_s.b
      end
    end

    def decode(ciphertext, encoding:)
      value = ciphertext.to_s
      case normalize_encoding(encoding)
      when :base64
        Base64.strict_decode64(value)
      when :base64url
        Base64.urlsafe_decode64(value)
      when :hex
        raise ArgumentError, "invalid hex ciphertext" unless value.match?(/\A(?:[0-9a-fA-F]{2})*\z/)

        [value].pack("H*")
      else
        value.b
      end
    rescue ArgumentError => e
      raise Error, "invalid #{encoding} ciphertext: #{e.message}"
    end

    def resolve_key
      key = yield
      raise Error, "key is required" if key.to_s.empty?

      key.to_s
    rescue KeyError, TypeError => e
      raise Error, "key resolution failed: #{e.message}"
    end

    # Normalizes arbitrary key material to the 32-byte secret MessageEncryptor expects.
    def normalize_key(key)
      Digest::SHA256.digest(key.to_s)
    end

    def build_encryptor(key, algorithm:)
      ActiveSupport::MessageEncryptor.new(normalize_key(key), cipher: algorithm.to_s)
    end

    def normalize_encoding(encoding)
      normalized = encoding.to_s.downcase.to_sym
      raise Error, "unsupported encoding" unless ENCODINGS.include?(normalized)

      normalized
    end
    private_class_method :normalize_encoding
  end
end
