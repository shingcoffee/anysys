# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Contracts::Site do
  let_it_be(:customer) { create(:customer) }

  def validate_with(overrides = {})
    site = build(:website, customer: customer)
    defaults = {
      "name" => "Studio",
      "skeleton_key" => "presence",
      "theme" => Website::DEFAULT_THEME.dup,
      "seo" => {},
      "footer" => {}
    }
    form = described_class.new(site)
    form.validate(defaults.merge(overrides.stringify_keys))
    form
  end

  it "is valid with a known skeleton and default theme" do
    expect(validate_with).to be_valid
  end

  it "requires a name" do
    form = validate_with(name: "")
    expect(form).not_to be_valid
    expect(form.errors[:name]).to be_present
  end

  it "rejects an unknown skeleton" do
    form = validate_with(skeleton_key: "not-a-skeleton")
    expect(form).not_to be_valid
    expect(form.errors[:skeleton_key]).to include(I18n.t("website.errors.unknown_skeleton"))
  end

  it "rejects a theme token outside the allowed sets" do
    form = validate_with(theme: Website::DEFAULT_THEME.merge("accent" => "neon"))
    expect(form).not_to be_valid
    expect(form.errors[:theme]).to be_present
  end

  it "rejects a javascript: footer href" do
    form = validate_with(
      footer: {
        "columns" => [
          { "heading" => "Visit", "links" => [ { "label" => "Hack", "url" => "javascript:alert(1)" } ] }
        ]
      }
    )
    expect(form).not_to be_valid
    expect(form.errors[:footer]).to include(I18n.t("website.errors.javascript_href"))
  end

  it "rejects an http:// footer href" do
    form = validate_with(
      footer: {
        "columns" => [
          { "heading" => "Visit", "links" => [ { "label" => "Insecure", "url" => "http://example.com" } ] }
        ]
      }
    )
    expect(form).not_to be_valid
    expect(form.errors[:footer]).to include(I18n.t("website.errors.invalid_href"))
  end
end
