# spec/services/code_generators/shared/config_field_reader_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::Shared::ConfigFieldReader do
  let(:dummy_class) do
    Class.new do
      include CodeGenerators::Shared::ConfigFieldReader
      attr_accessor :config
      def initialize(cfg); @config = cfg.with_indifferent_access; end
    end
  end

  describe "#fetch_with_default" do
    it "returns config value when present" do
      expect(dummy_class.new("foo" => "bar").fetch_with_default(:foo, "fallback")).to eq("bar")
    end

    it "returns default when blank" do
      expect(dummy_class.new("foo" => "").fetch_with_default(:foo, "fallback")).to eq("fallback")
    end
  end

  describe "#fetch_enum" do
    it "returns the value when in allowed list" do
      expect(dummy_class.new("mode" => "fast").fetch_enum(:mode, %w[fast slow], default: "slow")).to eq("fast")
    end

    it "returns default when value not in allowed list" do
      expect(dummy_class.new("mode" => "x").fetch_enum(:mode, %w[fast slow], default: "slow")).to eq("slow")
    end
  end

  describe "#fetch_int_positive" do
    it "returns the int when > 0" do
      expect(dummy_class.new("n" => "42").fetch_int_positive(:n, default: 10)).to eq(42)
    end

    it "returns default when 0 or negative" do
      expect(dummy_class.new("n" => "-5").fetch_int_positive(:n, default: 10)).to eq(10)
    end
  end
end
