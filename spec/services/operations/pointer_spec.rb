# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::Pointer do
  it "escapes RFC 6901 tokens and joins them onto a pointer" do
    expect(described_class.escape("a/b~c")).to eq("a~1b~0c")
    expect(described_class.join("", "name")).to eq("/name")
    expect(described_class.join("/entities/0", "attributes")).to eq("/entities/0/attributes")
  end
end
