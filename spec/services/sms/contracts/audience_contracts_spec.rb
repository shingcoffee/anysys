# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS audience Reform contracts" do
  def contact_form(**attributes)
    form = Sms::Contracts::Contact.new(Sms::Contracts::Contact::Input.new)
    form.validate({ phone: "+8613800138000", country_code: "CN", status: "active", custom_attributes: {} }.merge(attributes))
    form
  end

  it "accepts bounded UTF-8 names, scalar custom keys and finite numbers" do
    form = contact_form(name: "名" * 66, custom_attributes: { "text" => "x" * 1024, "number" => 1.5,
      "integer" => 1, "bool" => false, "null" => nil })
    expect(form.errors).to be_empty
  end

  it "rejects byte overflow, invalid UTF-8, bad keys and nonscalar values" do
    ["名" * 67, "x" * 201, (+"\xff").force_encoding(Encoding::UTF_8)].each do |name|
      expect(contact_form(name: name).errors).to have_key(:name)
    end
    [{ "Upper" => 1 }, { "nested" => {} }, { "list" => [] }, { "value" => Float::NAN },
      { "value" => Float::INFINITY }, { "value" => "x" * 1025 }, { symbol: 1 },
      33.times.to_h { |index| ["key_#{index}", index] }, 8.times.to_h { |index| ["key_#{index}", "x" * 1024] }].each do |attrs|
      expect(contact_form(custom_attributes: attrs).errors).to have_key(:custom_attributes)
    end
  end

  it "rejects Rails-friendly labels in place of actual IANA zone identifiers" do
    expect(contact_form(timezone: "Eastern Time (US & Canada)").errors).to have_key(:timezone)
    expect(contact_form(timezone: "America/New_York").errors).to be_empty
    expect(contact_form(status: "deleted").errors).to have_key(:status)
  end

  it "bounds admin evidence including its escaped serialized size" do
    form = Sms::Contracts::ConsentEvent.new(Sms::Contracts::ConsentEvent::Input.new)
    values = { action: "granted", occurred_at: 1.hour.ago, reference: "form", statement: "yes", event_key: "one" }
    expect(form.validate(values)).to be(true)
    expect(form.validate(values.merge(event_key: "x" * 129))).to be(false)
    expect(form.validate(values.merge(notes: "x" * 1025))).to be(false)
    expect(form.validate(values.merge(reference: "\n" * 1024, statement: "\n" * 1024, notes: "\n" * 1024))).to be(false)
  end

  it "validates optional owner preview mirrors and marketing classification through the same model contract" do
    template = build(:sms_template, variables: ["name"], purpose: "marketing", body_template: "Hello {{name}}")
    expect(template).to be_valid
    expect(template).to be_marketing
    ["Hello {{missing}}", "Hello {{ name }}", "{{name.upcase}}", "x" * 4097].each do |body|
      template.body_template = body
      expect(template).not_to be_valid
      expect(template.errors).to have_key(:body_template)
    end
    template.body_template = nil
    expect(template).to be_valid
    template.purpose = "advertisement"
    expect(template).not_to be_valid
  end

  it "keeps existing platform templates transactional by default" do
    template = create(:sms_template)
    expect(template.purpose).to eq("transactional")
    expect(template.body_template).to be_nil
    expect(template).not_to be_marketing
  end

  it "returns frozen result APIs and error collections while keeping AR values usable" do
    contact = build(:sms_contact)
    result = Sms::Result.success(contact: contact, replayed: false)
    expect(result).to be_frozen
    expect(result.value).to be_frozen
    expect(result.value[:contact]).not_to be_frozen
    failures = { "phone" => [+"Invalid"] }
    failure = Sms::Result.failure(:invalid_input, errors: failures)
    failures["phone"].first.replace("Changed")
    expect(failure.errors).to eq(phone: ["Invalid"])
    expect(failure.errors[:phone]).to be_frozen
    expect(failure.errors[:phone].first).to be_frozen
    expect(failure).not_to be_success
    expect(failure.code).to eq(:invalid_input)
  end

  it "has complete English/Chinese locale and interpolation parity" do
    en = YAML.safe_load_file(Rails.root.join("config/locales/sms_audience.en.yml")).fetch("en")
    zh = YAML.safe_load_file(Rails.root.join("config/locales/sms_audience.zh-CN.yml")).fetch("zh-CN")
    flatten = lambda do |hash, prefix = ""|
      hash.flat_map { |key, value| value.is_a?(Hash) ? flatten.call(value, "#{prefix}#{key}.").to_a : [["#{prefix}#{key}", value]] }.to_h
    end
    expect(flatten.call(en).keys).to eq(flatten.call(zh).keys)
    flatten.call(en).each do |key, value|
      expect(value.scan(/%\{(\w+)\}/)).to eq(flatten.call(zh).fetch(key).scan(/%\{(\w+)\}/))
    end
    I18n.with_locale(:"zh-CN") do
      expect(contact_form(phone: "bad").errors[:phone]).to eq([I18n.t("sms_audience.errors.invalid_phone")])
    end
  end

  it "parses database IDs and optimistic versions strictly across the signed bigint range" do
    expect(Sms::DomainAccess.integer((2**63 - 1).to_s)).to eq(2**63 - 1)
    expect(Sms::DomainAccess.integer(0)).to eq(0)
    ["9223372036854775808", 2**63, "1e2", "1x", "-1", -1, 1.5, nil].each do |value|
      expect(Sms::DomainAccess.integer(value)).to be_nil
    end
  end
end
