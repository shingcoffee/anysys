# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::QrCode do
  describe ".svg" do
    it "renders a standalone SVG for a provisioning URI" do
      svg = described_class.svg("otpauth://totp/Anysys:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Anysys")

      expect(svg).to include("<svg")
      expect(svg).to include("<path")
    end

    it "returns nil when there is no secret yet" do
      expect(described_class.svg(nil)).to be_nil
      expect(described_class.svg("")).to be_nil
    end
  end
end
