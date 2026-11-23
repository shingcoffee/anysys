# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Cipher do
  let(:key) { "test-secret-key-material" }

  describe ".encrypt_value / .decrypt_value" do
    it "round-trips through base64 encoding" do
      packed = described_class.encrypt_value("hello", key: key, encoding: :base64)
      expect(described_class.decrypt_value(packed, key: key, encoding: :base64)).to eq("hello")
    end

    it "round-trips a custom purpose string" do
      packed = described_class.encrypt_value("hello", key: key, encoding: :base64, purpose: "user_data")
      expect(described_class.decrypt_value(packed, key: key, encoding: :base64, purpose: "user_data")).to eq("hello")
    end
  end

  describe ".encrypt / .decrypt" do
    it "round-trips plaintext" do
      ciphertext = described_class.encrypt("hello world", key: key)
      expect(described_class.decrypt(ciphertext, key: key)).to eq("hello world")
    end

    it "returns a Base64-compatible ciphertext string" do
      ciphertext = described_class.encrypt("payload", key: key)
      expect(ciphertext).to be_a(String)
      expect(ciphertext).to match(/\A[A-Za-z0-9+\/=_-]+\z/)
    end

    it "produces stable encoding for the same inputs" do
      first = described_class.encrypt("stable", key: key)
      second = described_class.encrypt("stable", key: key)
      expect(first).not_to eq(second) # MessageEncryptor uses random IV
      expect(described_class.decrypt(first, key: key)).to eq(described_class.decrypt(second, key: key))
    end

    it "raises Error for tampered ciphertext" do
      ciphertext = described_class.encrypt("secret", key: key)
      tampered = ciphertext.succ
      expect { described_class.decrypt(tampered, key: key) }
        .to raise_error(FlowchartRuntime::Cipher::Error)
    end

    it "raises Error when decrypting with the wrong key" do
      ciphertext = described_class.encrypt("secret", key: key)
      expect { described_class.decrypt(ciphertext, key: "other-key") }
        .to raise_error(FlowchartRuntime::Cipher::Error)
    end

    it "raises Error for unsupported algorithms" do
      expect { described_class.encrypt("x", key: key, algorithm: "aes-128-cbc") }
        .to raise_error(FlowchartRuntime::Cipher::Error, /unsupported algorithm/)
      ciphertext = described_class.encrypt("x", key: key)
      expect { described_class.decrypt(ciphertext, key: key, algorithm: "chacha20-poly1305") }
        .to raise_error(FlowchartRuntime::Cipher::Error, /unsupported algorithm/)
    end

    it "rejects a blank key before calling MessageEncryptor" do
      expect { described_class.encrypt("x", key: "") }
        .to raise_error(FlowchartRuntime::Cipher::Error, "key is required")
    end

    it "accepts a custom purpose for round-trip" do
      ciphertext = described_class.encrypt("scoped", key: key, purpose: :custom_scope)
      expect(described_class.decrypt(ciphertext, key: key, purpose: :custom_scope)).to eq("scoped")
    end
  end

  describe ".key_from_passphrase" do
    it "derives a 32-byte key deterministically" do
      first = described_class.key_from_passphrase("pass", salt: "salt-a")
      second = described_class.key_from_passphrase("pass", salt: "salt-a")
      other = described_class.key_from_passphrase("pass", salt: "salt-b")
      expect(first).to eq(second)
      expect(first.bytesize).to eq(32)
      expect(first).not_to eq(other)
    end

    it "round-trips when used as key material for encrypt/decrypt" do
      derived = described_class.key_from_passphrase("master", salt: "tenant-1")
      ciphertext = described_class.encrypt("derived-key", key: derived)
      expect(described_class.decrypt(ciphertext, key: derived)).to eq("derived-key")
    end

    it "rejects non-positive iterations before calling OpenSSL" do
      expect { described_class.key_from_passphrase("secret", salt: "salt", iterations: 0) }
        .to raise_error(FlowchartRuntime::Cipher::Error, "iterations must be positive")
    end
  end

  describe ".encode / .decode" do
    let(:binary) { "\x00\xFFciphertext".b }

    it "strictly round-trips supported external encodings" do
      %i[base64 base64url hex raw binary].each do |encoding|
        encoded = described_class.encode(binary, encoding:)
        expect(described_class.decode(encoded, encoding:)).to eq(binary)
      end
    end

    it "uses strict Base64 rather than passing ciphertext through" do
      encoded = described_class.encode(binary, encoding: :base64)

      expect(encoded).to eq(Base64.strict_encode64(binary))
      expect(encoded).not_to eq(binary)
    end

    it "normalizes malformed Base64 and hex as Cipher::Error" do
      expect { described_class.decode("not base64!", encoding: :base64) }
        .to raise_error(described_class::Error, /invalid/)
      expect { described_class.decode("abc", encoding: :hex) }
        .to raise_error(described_class::Error, /invalid/)
    end
  end

  describe ".resolve_key" do
    it "normalizes missing key lookups as Cipher::Error" do
      expect { described_class.resolve_key { {}.fetch(:missing) } }
        .to raise_error(described_class::Error, /key/)
    end
  end
end
