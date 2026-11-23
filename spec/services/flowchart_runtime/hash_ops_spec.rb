# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::HashOps do
  describe ".apply" do
    let(:source) { { "name" => "Ada", "email" => "a@example.test", "secret" => 9 } }

    it "picks listed keys" do
      expect(described_class.apply("pick", source, keys: %w[name email]))
        .to eq("name" => "Ada", "email" => "a@example.test")
    end

    it "omits listed keys" do
      expect(described_class.apply("omit", source, keys: %w[secret])).not_to have_key("secret")
    end

    it "renames keys without mutating the source" do
      original = source.dup
      result = described_class.apply("rename_keys", source, rename_map: { "name" => "full_name" })
      expect(result).to include("full_name" => "Ada")
      expect(source).to eq(original)
    end

    it "picks a nested path via Step.dig" do
      nested = { "profile" => { "city" => "Paris" } }
      expect(described_class.apply("pick", nested, keys: ["profile.city"]))
        .to eq("city" => "Paris")
    end

    it "sets computed keys" do
      expect(described_class.apply("set_keys", { count: 1 }, computed: { total: 2 }))
        .to include(count: 1, total: 2)
    end

    it "shallow-merges with last-write wins" do
      expect(described_class.apply("merge", { keep: 1, changed: 2 }, other: { changed: 3 },
                                   merge_strategy: "shallow", on_conflict: "last"))
        .to eq(keep: 1, changed: 3)
    end

    it "deep-merges arrays by concat" do
      left = { items: [1] }
      right = { items: [2] }
      expect(described_class.apply("merge", left, other: right, merge_strategy: "deep",
                                   array_merge_mode: "concat", on_conflict: "last"))
        .to eq(items: [1, 2])
    end

    it "replaces with the other hash" do
      expect(described_class.apply("merge", { a: 1 }, other: { b: 2 }, merge_strategy: "replace"))
        .to eq(b: 2)
    end

    it "raises Error for an unknown operation" do
      expect { described_class.apply("nope", {}) }
        .to raise_error(described_class::Error, /unsupported operation/)
    end
  end
end
