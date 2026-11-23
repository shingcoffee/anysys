# frozen_string_literal: true

require "rails_helper"

RSpec.describe OutboundHttp::PublicAddress do
  BLOCKED = %w[
    169.254.169.254
    127.0.0.1
    ::1
    10.1.2.3
    172.16.0.1
    192.168.1.1
    100.64.0.1
    ::ffff:127.0.0.1
    ::127.0.0.1
    ::a9fe:a9fe
    fd00::1
    0.0.0.0
    255.255.255.255
    224.0.0.1
    240.0.0.1
    192.0.0.1
    198.18.0.1
    ::
    fc00::1
    ff02::1
    64:ff9b::1
    ::ffff:10.0.0.1
  ].freeze

  ALLOWED = %w[
    93.184.216.34
    2606:2800:220:1::1
    8.8.8.8
    ::ffff:93.184.216.34
  ].freeze

  BLOCKED.each do |address|
    it "rejects #{address}" do
      expect(described_class.public?(address)).to be(false)
    end
  end

  ALLOWED.each do |address|
    it "allows #{address}" do
      expect(described_class.public?(address)).to be(true)
    end
  end

  it "rejects an unparseable address" do
    expect(described_class.public?("not-an-ip")).to be(false)
  end
end
