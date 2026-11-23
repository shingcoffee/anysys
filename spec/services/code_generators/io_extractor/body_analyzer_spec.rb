# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::IoExtractor::BodyAnalyzer do
  describe ".call" do
    it "returns empty arrays for empty source" do
      expect(described_class.call("")).to eq(reads: [], writes: [])
    end

    it "detects a single ctx read" do
      src = "x = ctx[:user]"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(["user"])
      expect(result[:writes]).to be_empty
      read = result[:reads].first
      expect(src.byteslice(read[:start], read[:length])).to eq("ctx[:user]")
    end

    it "reports byte offsets when CJK text precedes a ctx read on the same line" do
      src = '"你好世界"; x = ctx[:v]'
      result = described_class.call(src)
      read = result[:reads].first
      expect(read[:pin]).to eq("v")
      expect(src.byteslice(read[:start], read[:length])).to eq("ctx[:v]")
    end

    it "reports byte offsets when CJK text is on a previous line" do
      src = "\"你好世界\"\nx = ctx[:v]"
      result = described_class.call(src)
      read = result[:reads].first
      expect(read[:pin]).to eq("v")
      expect(src.byteslice(read[:start], read[:length])).to eq("ctx[:v]")
    end

    it "detects a single ctx write" do
      src = "ctx[:model] = User.new"
      result = described_class.call(src)
      expect(result[:writes].map { |w| w[:pin] }).to eq(["model"])
      expect(result[:reads]).to be_empty
      w = result[:writes].first
      expect(src.byteslice(w[:start], w[:length])).to eq("ctx[:model]")
    end

    it "treats op-assign (||=) as both read and write" do
      src = "ctx[:count] ||= 0"
      result = described_class.call(src)
      expect(result[:writes].map { |w| w[:pin] }).to eq(["count"])
      expect(result[:reads].map { |r| r[:pin] }).to eq(["count"])
    end

    it "dedupes repeated reads but preserves first-seen order" do
      src = "a = ctx[:x]\nb = ctx[:y]\nc = ctx[:x]"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }.uniq).to eq(["x", "y"])
      expect(result[:reads].size).to eq(3)
    end

    it "skips dynamic access ctx[some_var]" do
      src = "ctx[some_var] = 1\nctx[config['k'].to_sym]"
      result = described_class.call(src)
      expect(result[:reads]).to be_empty
      expect(result[:writes]).to be_empty
    end

    it "detects only the outermost symbol in chained access ctx[:x][:y]" do
      src = "a = ctx[:x][:y]"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(["x"])
    end

    it "detects ctx[:x] inside string interpolation" do
      src = 'puts "value: #{ctx[:greeting]}"'
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(["greeting"])
    end

    it "ignores ctx[:x] inside comments" do
      src = "# ctx[:ignored]\nctx[:real] = 1"
      result = described_class.call(src)
      expect(result[:reads]).to be_empty
      expect(result[:writes].map { |w| w[:pin] }).to eq(["real"])
    end

    it "returns empty arrays when source is unparseable" do
      result = described_class.call("def broken")
      expect(result).to eq(reads: [], writes: [])
    end

    it "detects ctx[:CONSTANT_NAME] with a constant-style symbol" do
      src = "x = ctx[:USER_ID]\nctx[:MODEL_NAME] = 1"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(["USER_ID"])
      expect(result[:writes].map { |w| w[:pin] }).to eq(["MODEL_NAME"])
    end

    it "detects ctx[:<keyword>] symbols (e.g., :if, :class)" do
      src = "x = ctx[:if]\nctx[:class] = 1"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(["if"])
      expect(result[:writes].map { |w| w[:pin] }).to eq(["class"])
    end

    it "records massign LHS entries correctly" do
      src = "ctx[:a], ctx[:b] = 1, 2"
      result = described_class.call(src)
      expect(result[:writes].map { |w| w[:pin] }).to eq(["a", "b"])
      expect(result[:reads]).to be_empty
    end

    it "treats FlowchartRuntime::Entries.scope(ctx) as reads of bound_entity and customer_id" do
      src = "_scope = FlowchartRuntime::Entries.scope(ctx)"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(%w[bound_entity customer_id])
      expect(result[:writes]).to be_empty
      result[:reads].each do |read|
        expect(src.byteslice(read[:start], read[:length])).to eq("ctx")
        expect(read[:implied]).to be(true)
      end
    end

    it "does not tag explicit ctx[:pin] reads as implied" do
      result = described_class.call("x = ctx[:bound_entity]")
      expect(result[:reads]).to all(satisfy { |read| !read.key?(:implied) })
    end

    it "still records explicit ctx pins alongside Entries.scope(ctx)" do
      src = "FlowchartRuntime::Entries.scope(ctx)\nctx[:values] = 1"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(%w[bound_entity customer_id])
      expect(result[:writes].map { |w| w[:pin] }).to eq(["values"])
    end

    it "does not imply bound_entity reads for other Entries helpers" do
      src = "FlowchartRuntime::Entries.assign(record, attrs)\nFlowchartRuntime::Entries.where_attributes(rel, {}, ctx)"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to be_empty
      expect(result[:writes]).to be_empty
    end

    it "does not imply bound_entity reads when scope is not passed ctx" do
      src = "FlowchartRuntime::Entries.scope(ctx[:other])"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(["other"])
      expect(result[:reads].map { |r| r[:pin] }).not_to include("bound_entity", "customer_id")
    end

    it "does not imply bound_entity reads for a method merely named scope" do
      %w[foo.scope(ctx) scope(ctx)].each do |src|
        result = described_class.call(src)
        expect(result[:reads].map { |r| r[:pin] }).not_to include("bound_entity", "customer_id"), src
      end
    end
  end
end
