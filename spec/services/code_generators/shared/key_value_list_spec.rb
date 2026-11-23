# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::KeyValueList do
  [false, nil, 0, "", true].each do |value|
    it "preserves #{value.inspect} in both string-keyed and symbol-keyed rows" do
      expect(described_class.pairs([{ "key" => "flag", "value" => value }])).to eq([["flag", value]])
      expect(described_class.to_hash([{ key: "flag", value: value }])).to eq("flag" => value)
      expect(described_class.to_hash("flag" => value)).to eq("flag" => value)
    end
  end

  it "uses key presence, not truthiness, when both value spellings exist" do
    expect(described_class.to_hash([{ "key" => "flag", "value" => false, value: true }])).to eq("flag" => false)
    expect(described_class.to_hash([{ "key" => "flag", "value" => nil, value: true }])).to eq("flag" => nil)
  end
end
