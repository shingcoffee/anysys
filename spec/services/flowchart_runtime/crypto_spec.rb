# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FlowchartRuntime::Crypto" do
  let(:crypto) { FlowchartRuntime.const_get(:Crypto) }

  it "computes HMAC hex digests" do
    expect(crypto.hmac("sha256", key: "secret", data: "payload"))
      .to eq(OpenSSL::HMAC.hexdigest("sha256", "secret", "payload"))
  end

  it "derives PBKDF2 bytes" do
    result = crypto.pbkdf2("secret", salt: "salt", iterations: 1_000, length: 32, digest: "sha256")
    expect(result.bytesize).to eq(32)
  end

  it "hashes with salt, pepper and encodings" do
    hex = crypto.digest("sha256", "secret", salt: "s", pepper: "p")
    expect(hex).to eq(Digest::SHA256.hexdigest("ssecretp"))
    expect(crypto.digest("sha256", "secret", encoding: "base64")).to eq([Digest::SHA256.digest("secret")].pack("m0"))
  end

  it "compares secrets in constant time and rejects blanks" do
    expect(crypto.secure_compare("abc", "abc")).to be(true)
    expect(crypto.secure_compare("abc", "abd")).to be(false)
    expect(crypto.secure_compare("", "")).to be(false)
  end

  it "normalizes invalid algorithms and arguments as Error" do
    expect { crypto.hmac("md5", key: "secret", data: "payload") }
      .to raise_error(crypto::Error, /unsupported digest/)
    expect { crypto.digest("md5", "secret") }
      .to raise_error(crypto::Error, /unsupported digest/)
    expect { crypto.pbkdf2("secret", salt: "", iterations: 1_000) }
      .to raise_error(crypto::Error, /salt is required/)
  end
end
