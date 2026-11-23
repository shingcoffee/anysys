# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::DeviceType do
  describe ".call" do
    it "detects mobile" do
      expect(described_class.call("Mozilla/5.0 (iPhone; CPU iPhone OS) Mobile")).to eq("mobile")
    end

    it "detects Android as mobile" do
      expect(described_class.call("Mozilla/5.0 (Linux; Android 13)")).to eq("mobile")
    end

    it "detects tablet" do
      expect(described_class.call("Mozilla/5.0 (iPad; CPU OS 16_0)")).to eq("tablet")
    end

    it "defaults to desktop" do
      expect(described_class.call("Mozilla/5.0 (Macintosh; Intel Mac OS X)")).to eq("desktop")
    end

    it "handles nil user agent" do
      expect(described_class.call(nil)).to eq("desktop")
    end
  end
end
