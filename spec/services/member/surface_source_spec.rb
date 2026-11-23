# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SurfaceSource do
  # A minimal concrete subclass that satisfies the required .key/.name interface.
  def concrete_subclass(key: :x, name: "X")
    Class.new(described_class) do
      define_singleton_method(:key)  { key }
      define_singleton_method(:name) { name }
    end
  end

  describe "subclass interface" do
    it "raises NotImplementedError when .key is not overridden" do
      klass = Class.new(described_class)
      expect { klass.key }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError when .name is not overridden" do
      klass = Class.new(described_class)
      expect { klass.name }.to raise_error(NotImplementedError)
    end

    it "defaults .editable? to true" do
      expect(concrete_subclass.editable?).to be(true)
    end

    it "defaults .position to 100" do
      expect(concrete_subclass.position).to eq(100)
    end

    it "defaults .description to ''" do
      expect(concrete_subclass.description).to eq("")
    end

    it "raises NotImplementedError when #surfaces is not overridden" do
      expect { concrete_subclass.new(customer: build(:customer)).surfaces }.to raise_error(NotImplementedError)
    end
  end

  describe "#surface_for(key:)" do
    let_it_be(:customer) { create(:customer) }

    it "returns the surface with the matching key" do
      surface = double("Surface", key: :alpha)
      instance = concrete_subclass.new(customer: customer)
      allow(instance).to receive(:surfaces).and_return([surface])

      expect(instance.surface_for(key: :alpha)).to eq(surface)
    end

    it "returns nil when no surface matches" do
      instance = concrete_subclass.new(customer: customer)
      allow(instance).to receive(:surfaces).and_return([])

      expect(instance.surface_for(key: :nope)).to be_nil
    end
  end

  describe ".register!" do
    after { Member::Surfaces::SourceRegistry.reset! }

    it "delegates to SourceRegistry.register(self)" do
      klass = concrete_subclass(key: :reg_test, name: "Reg")
      klass.register!
      expect(Member::Surfaces::SourceRegistry.find(:reg_test)).to eq(klass)
    end
  end
end
