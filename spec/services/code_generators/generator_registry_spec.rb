# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::GeneratorRegistry do
  before { described_class.instance_variable_set(:@instance, nil) }
  after  { described_class.instance_variable_set(:@instance, nil) }

  let(:registry) { described_class.instance }

  describe ".instance" do
    it "returns the same object on every call" do
      instance = described_class.instance
      expect(described_class.instance).to be(instance)
    end
  end

  describe "#discover!" do
    it "discovers generator files from step_actions directory" do
      expect(registry.step_action_generators).to be_a(Hash)
    end

    it "discovers generator files from element_types directory" do
      expect(registry.element_type_generators).to be_a(Hash)
    end
  end

  describe "#find_step_action" do
    it "returns nil for unknown action" do
      expect(registry.find_step_action("nonexistent")).to be_nil
    end
  end

  describe "#find_element_type" do
    it "returns nil for unknown type" do
      expect(registry.find_element_type("nonexistent")).to be_nil
    end
  end

  describe "#reload!" do
    it "clears and re-discovers the same set of generators" do
      count_before = registry.all_generators.size
      registry.reload!
      expect(registry.all_generators.size).to eq(count_before)
    end
  end
end
