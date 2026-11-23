# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::PasswordHash do
  describe ".create" do
    it "hashes with bcrypt" do
      hash = described_class.create("bcrypt", "secret", cost: 4)
      expect(hash).to be_a(String)
      expect(BCrypt::Password.new(hash)).to eq("secret")
    end

    it "hashes with scrypt" do
      hash = described_class.create("scrypt", "secret", max_time: 0.05)
      expect(hash).to be_a(String)
      expect(SCrypt::Password.new(hash)).to eq("secret")
    end

    it "maps scrypt iterations to max_time" do
      hash = described_class.create("scrypt", "secret", iterations: 100_000)
      expect(hash).to be_a(String)
      expect(SCrypt::Password.new(hash)).to eq("secret")
    end

    it "hashes with argon2" do
      hash = described_class.create("argon2", "secret")
      expect(hash).to be_a(String)
      expect(Argon2::Password.verify_password("secret", hash)).to be true
    end

    it "honors argon2 time and memory costs" do
      hash = described_class.create("argon2", "secret", t_cost: 1, m_cost: 10)
      expect(Argon2::Password.verify_password("secret", hash)).to be true
    end

    it "rejects argon2 costs outside the worker-safe bounds" do
      expect { described_class.create("argon2", "secret", m_cost: 20) }
        .to raise_error(described_class::Error, "invalid argon2 memory cost")
      expect { described_class.create("argon2", "secret", t_cost: 0) }
        .to raise_error(described_class::Error, "invalid argon2 time cost")
    end

    it "raises Error for unsupported algorithms" do
      expect { described_class.create("sha256", "secret") }
        .to raise_error(described_class::Error, /unsupported password algorithm/)
    end

    it "wraps invalid bcrypt cost as Error" do
      expect { described_class.create("bcrypt", "secret", cost: 0) }
        .to raise_error(described_class::Error)
    end

    it "does not swallow unexpected argument errors from a password library" do
      allow(BCrypt::Password).to receive(:create).and_raise(ArgumentError, "unexpected")

      expect { described_class.create("bcrypt", "secret", cost: 4) }
        .to raise_error(ArgumentError, "unexpected")
    end
  end
end
