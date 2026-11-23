# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Surfaces::SourceRegistry do
  def source(key:, name: key.to_s, position: 99)
    Class.new(Member::SurfaceSource) do
      define_singleton_method(:key)      { key }
      define_singleton_method(:name)     { name }
      define_singleton_method(:position) { position }
      define_method(:surfaces)           { [] }
    end
  end

  let(:source_class) { source(key: :test_src, name: "Test") }

  before { described_class.reset! }

  describe ".register / .all / .find" do
    it "registers a source class and returns it" do
      described_class.register(source_class)
      expect(described_class.all).to include(source_class)
      expect(described_class.find(:test_src)).to eq(source_class)
    end

    it "looks up by string or symbol" do
      described_class.register(source_class)
      expect(described_class.find("test_src")).to eq(source_class)
    end

    it "returns nil for an unknown key" do
      expect(described_class.find(:nope)).to be_nil
    end

    it "sorts .all by position ascending" do
      first  = source(key: :a_first, name: "A", position: 1)
      second = source(key: :z_second, name: "Z", position: 10)
      described_class.register(second)
      described_class.register(first)
      expect(described_class.all).to eq([first, second])
    end

    it ".reset! empties the registry" do
      described_class.register(source_class)
      described_class.reset!
      expect(described_class.all).to eq([])
    end
  end
end
