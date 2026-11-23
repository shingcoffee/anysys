# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Translate do
  before do
    I18n.backend.store_translations(:en, items: { one: "1 item", other: "%{count} items" })
  end

  it "looks up a key with interpolations" do
    expect(described_class.call("items", locale: :en, interpolations: { count: 2 }, count: 2)).to eq("2 items")
  end

  it "raises Error when raise_on_missing and the key is absent" do
    expect { described_class.call("missing.none", raise_on_missing: true) }
      .to raise_error(described_class::Error, /missing translation/)
  end
end
