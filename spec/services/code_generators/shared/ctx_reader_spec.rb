# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::CtxReader do
  let(:dummy_class) { Class.new { include CodeGenerators::Shared::CtxReader } }
  let(:instance) { dummy_class.new }

  describe "#safe_read" do
    it "wraps with || [] for :array type" do
      expect(instance.safe_read("items", type: :array)).to eq("(ctx[:items] || [])")
    end

    it "wraps with || {} for :hash type" do
      expect(instance.safe_read("data", type: :hash)).to eq("(ctx[:data] || {})")
    end

    it "uses .to_s for :string type" do
      expect(instance.safe_read("name", type: :string)).to eq("ctx[:name].to_s")
    end

    it "falls back to bare read for :any" do
      expect(instance.safe_read("foo", type: :any)).to eq("ctx[:foo]")
    end

    it "reads a dotted path through Step.dig" do
      expect(instance.safe_read("order.lines", type: :array))
        .to eq("(FlowchartRuntime::Step.dig(ctx[:order], :lines) || [])")
    end

    it "refuses a path segment that is not an identifier" do
      expect(instance.safe_read("items]; system('id'); ctx[:foo", type: :any)).to eq("nil")
    end
  end

  describe "#ensure_array_expr" do
    it "wraps an arbitrary ruby expression" do
      expect(instance.ensure_array_expr("ctx[:items].first(10)")).to eq("Array(ctx[:items].first(10))")
    end
  end

  describe "#ensure_hash_expr" do
    it "wraps an arbitrary ruby expression" do
      expect(instance.ensure_hash_expr("ctx[:payload]")).to eq("((ctx[:payload]).is_a?(Hash) ? ctx[:payload] : {})")
    end
  end
end
