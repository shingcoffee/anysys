# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ValueValidator do
  def check(value, **opts)
    described_class.check(value, rule: "email", **opts)
  end

  it "normalises a valid email and rejects an invalid one" do
    expect(check("Ada@Example.COM")).to eq(valid: true, normalized: "ada@example.com")
    expect(check("not-an-email")[:valid]).to be(false)
  end

  it "parses an international phone to E.164" do
    result = described_class.check("+1 415 555 2671", rule: "phone")
    expect(result).to eq(valid: true, normalized: "+14155552671")
  end

  it "accepts a national phone when a country is given" do
    result = described_class.check("13812345678", rule: "phone", phone_country: "CN")
    expect(result[:normalized]).to eq("+8613812345678")
  end

  it "validates url, uuid, regex, length, range and in_list" do
    expect(described_class.check("https://example.test/a", rule: "url")[:valid]).to be(true)
    expect(described_class.check("javascript:alert(1)", rule: "url")[:valid]).to be(false)
    expect(described_class.check("550e8400-e29b-41d4-a716-446655440000", rule: "uuid")[:normalized])
      .to eq("550e8400-e29b-41d4-a716-446655440000")
    expect(described_class.check("12345", rule: "regex", pattern: "\\A\\d+\\z")[:valid]).to be(true)
    expect(described_class.check("ab", rule: "length", min_length: 1, max_length: 3)[:valid]).to be(true)
    expect(described_class.check("abcd", rule: "length", min_length: 1, max_length: 3)[:valid]).to be(false)
    expect(described_class.check("12.5", rule: "range", min_value: 0, max_value: 20)[:normalized]).to eq(12.5)
    expect(described_class.check("Active", rule: "in_list", allowed_values: %w[active pending], case_sensitive: false)[:valid])
      .to be(true)
  end

  it "checks luhn, iban, Chinese resident ID, postal code, IP and date" do
    expect(described_class.check("4111111111111111", rule: "luhn")[:valid]).to be(true)
    expect(described_class.check("GB82 WEST 1234 5698 7654 32", rule: "iban")[:normalized]).to eq("GB82WEST12345698765432")
    expect(described_class.check("de89 3704 0044 0532 0130 00", rule: "iban")[:normalized]).to eq("DE89370400440532013000")
    expect(described_class.check("110101199003078275", rule: "cn_resident_id")[:valid]).to be(true)
    expect(described_class.check("110101199003078274", rule: "cn_resident_id")[:valid]).to be(false)
    expect(described_class.check("94105", rule: "postal_code", postal_country: "US")[:valid]).to be(true)
    expect(described_class.check("100000", rule: "postal_code", postal_country: "CN")[:valid]).to be(true)
    expect(described_class.check("127.0.0.1", rule: "ip_address", ip_version: "v4")[:valid]).to be(true)
    expect(described_class.check("::1", rule: "ip_address", ip_version: "v4")[:valid]).to be(false)
    expect(described_class.check("2026-04-19", rule: "date", date_format: "%Y-%m-%d")[:normalized]).to eq("2026-04-19")
  end

  it "rejects an IBAN whose length does not match its country" do
    expect(described_class.check("DE8937040044053201300", rule: "iban")[:valid]).to be(false)
    expect(described_class.check("GB82WEST1234569876543X", rule: "iban")[:valid]).to be(false)
  end

  it "validates required, China mobile, and a date range" do
    expect(described_class.check("x", rule: "required")[:valid]).to be(true)
    expect(described_class.check("", rule: "required")[:valid]).to be(false)
    expect(described_class.check("13812345678", rule: "cn_mobile")[:normalized]).to eq("+8613812345678")
    expect(described_class.check("2026-04-19", rule: "date_range", min_date: "2026-01-01", max_date: "2026-12-31")[:valid])
      .to be(true)
    expect(described_class.check("2025-12-31", rule: "date_range", min_date: "2026-01-01")[:valid]).to be(false)
  end

  it "treats blank as valid when allow_blank is true" do
    expect(check("", allow_blank: true)).to eq(valid: true, normalized: "")
    expect(check("", allow_blank: false)[:valid]).to be(false)
  end

  it "raises Error for an unknown rule" do
    expect { described_class.check("x", rule: "nope") }.to raise_error(described_class::Error)
  end
end
