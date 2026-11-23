# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Providers do
  describe ".ensure_loaded!" do
    it "loads every provider file under app/services/email/providers/*.rb (except base)" do
      expect { described_class.ensure_loaded! }.not_to raise_error
      expect(described_class.keys).not_to be_empty
    end
  end

  describe ".keys" do
    it "returns the registered provider keys as symbols" do
      expect(described_class.keys).to all(be_a(Symbol))
      expect(described_class.keys).to include(:smtp, :ses, :aliyun)
      expect(described_class.keys).not_to include(:postmark)
    end
  end

  describe ".all" do
    it "returns the registered provider classes" do
      expect(described_class.all).to include(Email::Providers::Smtp,
                                            Email::Providers::Ses, Email::Providers::Aliyun)
    end
  end

  describe ".for" do
    it "resolves a registered provider by string key" do
      expect(described_class.for("smtp")).to eq(Email::Providers::Smtp)
      expect(described_class.for("aliyun")).to eq(Email::Providers::Aliyun)
    end

    it "resolves a registered provider by symbol key" do
      expect(described_class.for(:ses)).to eq(Email::Providers::Ses)
    end

    it "raises ArgumentError for an unknown key" do
      expect { described_class.for("sendgrid") }.to raise_error(ArgumentError, /unknown email provider/)
    end
  end

  describe ".default_key" do
    it "returns the provider that declared default! (smtp)" do
      expect(described_class.default_key).to eq(:smtp)
    end
  end
end
