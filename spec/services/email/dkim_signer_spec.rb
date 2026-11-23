# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::DkimSigner do
  let(:key)  { OpenSSL::PKey::RSA.new(2048) }
  let(:mail) { Mail.new { to "a@b.com"; from "s@example.com"; subject :Hi; body "x" } }
  let(:credential) do
    build(:email_credential, dkim_enabled: true, dkim_domain: "example.com",
          dkim_selector: "mail", dkim_private_key: key.to_pem)
  end

  it "adds a real DKIM-Signature header (via the dkim gem)" do
    described_class.sign!(mail, credential)

    value = mail.header["DKIM-Signature"].value
    expect(value).to include("d=example.com").and include("s=mail")
    expect(value).to include("a=rsa-sha256")
    # Real signature + body hash present (not a stub).
    expect(value).to match(/(\A|;\s*)b=[^;]+/)
    expect(value).to match(/(\A|;\s*)bh=[^;]+/)
  end

  it "does not emit a duplicate signature when one already exists" do
    described_class.sign!(mail, credential)
    described_class.sign!(mail, credential)

    expect(mail.header.fields.count { |f| f.name == "DKIM-Signature" }).to eq(1)
  end

  it "covers both RFC 8058 headers in the actual signature's h= list" do
    mail["List-Unsubscribe"] = "<https://example.com/unsubscribe/signed>"
    mail["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    described_class.sign!(mail, credential)

    signed_headers = mail["DKIM-Signature"].value[/\bh=([^;]+)/, 1].delete("\r\n ").downcase.split(":")
    expect(signed_headers).to include("from", "list-unsubscribe", "list-unsubscribe-post")
  end

  it "is a no-op when DKIM is not configured" do
    described_class.sign!(mail, build(:email_credential, dkim_enabled: false))
    expect(mail.header["DKIM-Signature"]).to be_nil
  end

  it "is a no-op when the credential does not respond to dkim_configured?" do
    result = described_class.sign!(mail, double("credential"))
    expect(result).to eq(mail)
    expect(mail.header["DKIM-Signature"]).to be_nil
  end

  describe "unparseable private key (OpenSSL::PKey::PKeyError rescued)" do
    let(:broken_credential) do
      build(:email_credential, dkim_enabled: true, dkim_domain: "example.com",
            dkim_selector: "mail", dkim_private_key: key.to_pem)
    end

    it "leaves the mail unsigned and logs a warning instead of raising" do
      allow(broken_credential).to receive(:dkim_configured?).and_return(true)
      allow(OpenSSL::PKey::RSA).to receive(:new).with(broken_credential.dkim_private_key)
        .and_raise(OpenSSL::PKey::PKeyError, "bad key")
      expect(Rails.logger).to receive(:warn).with(/skipped signing.*unparseable key/)

      result = described_class.sign!(mail, broken_credential)

      expect(result).to eq(mail)
      expect(mail.header["DKIM-Signature"]).to be_nil
    end
  end
end
