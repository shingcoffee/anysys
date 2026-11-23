# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityIndexSettings::Contract::Update do
  let(:model) { OpenStruct.new(visible_column_keys: nil) }
  let(:form)  { described_class.new(model) }

  it "accepts an empty array" do
    expect(form.validate(visible_column_keys: [])).to be(true)
  end

  it "accepts up to MAX_VISIBLE_KEYS entries" do
    keys = Array.new(described_class::MAX_VISIBLE_KEYS) { |i| "k#{i}" }
    expect(form.validate(visible_column_keys: keys)).to be(true)
  end

  it "rejects more than MAX_VISIBLE_KEYS entries" do
    keys = Array.new(described_class::MAX_VISIBLE_KEYS + 1) { |i| "k#{i}" }
    expect(form.validate(visible_column_keys: keys)).to be(false)
    expect(form.errors[:base]).to include(
      I18n.t("admin_misc.entities.index_setting.errors.too_many")
    )
  end

  it "ignores blank entries when counting toward the max" do
    keys = Array.new(described_class::MAX_VISIBLE_KEYS) { |i| "k#{i}" } + [""]
    expect(form.validate(visible_column_keys: keys)).to be(true)
  end

  it "rejects unknown slugs against allowed_slugs" do
    form.allowed_slugs = %w[name status]
    expect(form.validate(visible_column_keys: %w[name nope])).to be(false)
    expect(form.errors[:base]).to include(
      I18n.t("admin_misc.entities.index_setting.errors.invalid_keys")
    )
  end
end
