# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::PathPolicy do
  it "normalizes only an optional leading slash and one trailing slash, including root" do
    { "/" => "/", "join" => "/join", "/join/" => "/join",
      "campaign/spring-2026/" => "/campaign/spring-2026" }.each do |input, expected|
      expect(described_class.normalize(input)).to eq(expected)
    end
    expect(described_class.normalize("join", leading_slash: false)).to be_nil
  end

  it "accepts a 255-byte customer-relative nested path and rejects a longer stored path" do
    path = "/campaign/spring-#{'a' * 73}/launch-#{'b' * 73}/form-#{'c' * 78}"
    expect(path.bytesize).to eq(255)
    expect(described_class.normalize(path)).to eq(path)
    expect(described_class.normalize("#{path}d")).to be_nil
    expect(described_class.normalize("/12345678#{path}")).to be_nil
  end

  it "rejects unsafe URI spellings without decoding or normalizing them into aliases" do
    [nil, "", "//", "///", "//external.test/join", "https://external.test/join", "join?x=1",
     "/join#fragment", "/join?", "/join#", "/join//", "/campaign//spring", "/../join", "/./join",
      "/join..json", "/.join", "/join.", "/join-.html", "/%6aoin", "/join%2fadmin", "/%252e%252e", "/join\\admin", "/JOIN",
     " /join", "/join ", "/join\n", "/join\u0000", "/j oin", "/join_1", "/-join",
     "/join-", "/join--now", "/注册", "/#{'a' * 255}", "a" * 255, "/\xff".b].each do |input|
      expect(described_class.normalize(input)).to be_nil, input.inspect
    end
  end

  it "preserves interior dots on explicit aliases without enabling formatted automatic website slugs" do
    ["/join.html", "/join.json", "/campaign.v2/join.html"].each do |path|
      expect(described_class.normalize(path)).to eq(path)
      expect(described_class.automatic?(path)).to be(false)
    end
    %w[/auth.html/sign-in /admin.json /12345678.html/join].each do |path|
      expect(described_class.reserved?(path)).to be(true)
    end
  end

  it "reserves app namespaces and numeric tenant addressing with segment boundaries" do
    described_class::RESERVED_SEGMENTS.each do |segment|
      expect(described_class.reserved?("/#{segment}")).to be(true)
      expect(described_class.reserved?("/#{segment}/child")).to be(true)
      expect(described_class.reserved?("/#{segment}-guide")).to be(false)
    end
    expect(described_class.reserved?("/12345678/join")).to be(true)
    expect(described_class.reserved?("/123/join")).to be(true)
    expect(described_class.reserved?("/")).to be(false)
    expect(described_class.automatic?("/campaign/spring")).to be(false)
  end
end
