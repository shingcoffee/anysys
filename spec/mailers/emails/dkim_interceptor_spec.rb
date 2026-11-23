# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::DkimInterceptor do
  def mail_for(mode:)
    Mail.new do
      to "a@b.com"
      from "s@example.com"
      subject :Hi
      body "x"
    end.tap { |m| m["X-Anysys-Mode"] = mode }
  end

  context "when the mode's credential has DKIM configured" do
    let!(:credential) do
      create(:email_credential, mode: "sandbox",
        dkim_enabled: true, dkim_domain: "example.com",
        dkim_selector: "mail", dkim_private_key: OpenSSL::PKey::RSA.new(2048).to_pem)
    end

    it "adds a DKIM-Signature header" do
      mail = mail_for(mode: "sandbox")
      described_class.delivering_email(mail)
      expect(mail.header["DKIM-Signature"]).to be_present
      expect(mail.header["DKIM-Signature"].value).to include("d=example.com")
    end

    it "strips the X-Anysys-Mode header after signing" do
      mail = mail_for(mode: "sandbox")
      described_class.delivering_email(mail)
      expect(mail["X-Anysys-Mode"]).to be_nil
    end

    it "strips the internal X-Anysys-Message-Id header so it never ships to recipients (E-SEC-3)" do
      mail = mail_for(mode: "sandbox").tap { |m| m["X-Anysys-Message-Id"] = "12345" }
      described_class.delivering_email(mail)
      expect(mail["X-Anysys-Message-Id"]).to be_nil
    end

    it "signs with the transport's original credential even if its active status changed" do
      mail = mail_for(mode: "sandbox")
      mail["X-Anysys-Credential-Id"] = credential.id.to_s
      credential.update!(status: "disabled")

      described_class.delivering_email(mail)

      expect(mail["DKIM-Signature"].value).to include("d=example.com")
      expect(mail["X-Anysys-Credential-Id"]).to be_nil
    end
  end

  context "when the mode's credential has no DKIM configured" do
    let!(:credential) { create(:email_credential, mode: "sandbox") }

    it "does not add a DKIM-Signature header but still strips the mode header" do
      mail = mail_for(mode: "sandbox")
      described_class.delivering_email(mail)
      expect(mail.header["DKIM-Signature"]).to be_nil
      expect(mail["X-Anysys-Mode"]).to be_nil
    end
  end

  context "when no active credential exists for the mode" do
    it "does not raise, leaves the mail unsigned, and strips the mode header" do
      allow(Email::CredentialResolver).to receive(:call).and_raise(Email::Errors::CredentialsMissing)
      mail = mail_for(mode: "sandbox")
      expect { described_class.delivering_email(mail) }.not_to raise_error
      expect(mail.header["DKIM-Signature"]).to be_nil
      expect(mail["X-Anysys-Mode"]).to be_nil
    end
  end

  context "when no mode header is present (foreign mail)" do
    it "is a no-op and does not raise" do
      mail = Mail.new { to "a@b.com"; from "s@x.com"; subject :Hi; body "x" }
      expect { described_class.delivering_email(mail) }.not_to raise_error
      expect(mail.header["DKIM-Signature"]).to be_nil
    end
  end
end
