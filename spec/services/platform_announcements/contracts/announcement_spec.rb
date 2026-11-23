# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAnnouncements::Contracts::Announcement do
  def id_rules(customer_id)
    {
      "type" => "group",
      "joins" => [],
      "conditions" => [
        { "field" => "id", "operator" => "equals", "value" => customer_id.to_s }
      ]
    }
  end

  def validate_with(overrides = {})
    defaults = {
      title: "Notice",
      body_en: "English body",
      body_zh: "中文正文",
      severity: "info",
      status: "draft",
      audience: "all",
      link_url: nil,
      starts_at: nil,
      ends_at: nil,
      target_rules: {}
    }
    form = described_class.new(PlatformAnnouncement.new)
    form.validate(defaults.merge(overrides))
    form
  end

  it "is valid with required fields" do
    expect(validate_with).to be_valid
  end

  it "requires title, body_en, and body_zh" do
    form = validate_with(title: "", body_en: "", body_zh: "")
    expect(form).not_to be_valid
    expect(form.errors[:title]).to be_present
    expect(form.errors[:body_en]).to be_present
    expect(form.errors[:body_zh]).to be_present
  end

  it "limits title to 120 and bodies to 500" do
    form = validate_with(title: "x" * 121, body_en: "e" * 501, body_zh: "z" * 501)
    expect(form).not_to be_valid
    expect(form.errors[:title]).to be_present
    expect(form.errors[:body_en]).to be_present
    expect(form.errors[:body_zh]).to be_present
  end

  it "requires severity, status, and audience inclusion" do
    form = validate_with(severity: "loud", status: "archived", audience: "everyone")
    expect(form).not_to be_valid
    expect(form.errors[:severity]).to be_present
    expect(form.errors[:status]).to be_present
    expect(form.errors[:audience]).to be_present
  end

  it "accepts an optional https URL" do
    expect(validate_with(link_url: "https://example.com/more")).to be_valid
    expect(validate_with(link_url: "http://example.com/more")).to be_valid
    expect(validate_with(link_url: "")).to be_valid
  end

  it "rejects a non-http(s) URL" do
    form = validate_with(link_url: "javascript:alert(1)")
    expect(form).not_to be_valid
    expect(form.errors[:link_url]).to be_present
  end

  it "rejects an http(s) prefix that continues into javascript or whitespace" do
    [
      "https://example.com\njavascript:alert(1)",
      "https://example.com javascript:alert(1)",
      "https://user:pass@example.com/more"
    ].each do |url|
      form = validate_with(link_url: url)
      expect(form).not_to be_valid, "expected to reject #{url.inspect}"
      expect(form.errors[:link_url]).to be_present
    end
  end

  it "requires ends_at after starts_at when both are present" do
    now = Time.zone.parse("2026-08-29 12:00:00")
    form = validate_with(starts_at: now, ends_at: now)
    expect(form).not_to be_valid
    expect(form.errors[:ends_at]).to be_present
  end

  it "accepts a window where ends_at is after starts_at" do
    now = Time.zone.parse("2026-08-29 12:00:00")
    expect(validate_with(starts_at: now, ends_at: now + 1.hour)).to be_valid
  end

  it "requires at least one usable customer condition when audience is selected" do
    form = validate_with(audience: "selected", target_rules: {})
    expect(form).not_to be_valid
    expect(form.errors[:base]).to include(I18n.t("maint_platform.announcements.form.errors.target_rules_blank"))
  end

  it "rejects selected audience rules whose fields are not in the catalog" do
    form = validate_with(
      audience: "selected",
      target_rules: {
        "type" => "group",
        "joins" => [],
        "conditions" => [ { "field" => "password", "operator" => "equals", "value" => "x" } ]
      }
    )
    expect(form).not_to be_valid
    expect(form.errors[:base]).to include(I18n.t("maint_platform.announcements.form.errors.target_rules_invalid"))
  end

  it "rejects malformed audience JSON" do
    form = validate_with(audience: "selected", target_rules: {}, target_rules_malformed: true)
    expect(form).not_to be_valid
    expect(form.errors[:base]).to include(I18n.t("maint_platform.announcements.form.errors.target_rules_invalid"))
  end

  it "accepts selected audience with a catalog field condition" do
    customer = create(:customer)
    expect(validate_with(audience: "selected", target_rules: id_rules(customer.id))).to be_valid
  end
end
