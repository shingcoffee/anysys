# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator::SubflowResolver do
  let(:customer) { create(:customer) }
  let(:parent) { create(:flowchart, :simple, customer: customer, name: "Parent Flow") }

  def subflow_element(flowchart_id, id: "sf1")
    { "id" => id, "type" => "subflow", "label" => "Child", "properties" => { "flowchartId" => flowchart_id } }
  end

  def referencing(*ids, **attrs)
    elements = ids.each_with_index.map { |id, index| subflow_element(id, id: "sf#{index}") }
    instance_double(Flowchart, elements: elements, **attrs)
  end

  describe ".visible_to" do
    it "finds the parent customer's own flowcharts" do
      own = create(:flowchart, :simple, customer: customer)
      expect(described_class.visible_to(parent, own.id)).to eq(own)
    end

    it "finds shared flowcharts" do
      shared = create(:flowchart, :simple, :shared_type)
      expect(described_class.visible_to(parent, shared.id)).to eq(shared)
    end

    it "does not find another customer's flowcharts" do
      foreign = create(:flowchart, :simple, customer: create(:customer))
      expect(described_class.visible_to(parent, foreign.id)).to be_nil
    end

    it "gives a shared parent only shared flowcharts" do
      shared_parent = create(:flowchart, :simple, :shared_type)
      expect(described_class.visible_to(shared_parent, create(:flowchart, :simple, customer: customer).id)).to be_nil
    end
  end

  describe "#find" do
    it "looks each id up once" do
      finder = instance_double(Proc)
      allow(finder).to receive(:call).with(7).and_return(:child)
      resolver = described_class.new(parent, finder: finder)

      expect([resolver.find(7), resolver.find("7"), resolver.find(7)]).to eq(%i[child child child])
      expect(finder).to have_received(:call).once
    end

    it "remembers misses too" do
      calls = 0
      resolver = described_class.new(parent, finder: ->(_id) { (calls += 1) && nil })
      2.times { resolver.find(9) }
      expect(calls).to eq(1)
    end

    it "ignores blank ids" do
      expect(described_class.new(parent).find("")).to be_nil
    end
  end

  describe "#cycle?" do
    it "detects a chain that leads back to the parent" do
      children = { "2" => referencing(3), "3" => referencing(parent.id) }
      resolver = described_class.new(parent, finder: ->(id) { children[id.to_s] })
      expect(resolver.cycle?(2)).to be(true)
    end

    it "accepts a chain that ends" do
      children = { "2" => referencing(3), "3" => referencing }
      resolver = described_class.new(parent, finder: ->(id) { children[id.to_s] })
      expect(resolver.cycle?(2)).to be(false)
    end

    it "detects a loop between two children that excludes the parent" do
      children = { "2" => referencing(3), "3" => referencing(2) }
      resolver = described_class.new(parent, finder: ->(id) { children[id.to_s] })
      expect(resolver.cycle?(2)).to be(true)
    end

    it "accepts a child reached along two paths" do
      children = { "2" => referencing(3, 4), "3" => referencing(5), "4" => referencing(5), "5" => referencing }
      resolver = described_class.new(parent, finder: ->(id) { children[id.to_s] })
      expect(resolver.cycle?(2)).to be(false)
    end

    it "walks each acyclic child once" do
      lookups = Hash.new(0)
      layers = (2..40).to_h { |id| [id.to_s, id.even? ? referencing(id + 1, id + 2) : referencing(id + 1)] }
      finder = lambda do |id|
        lookups[id.to_s] += 1
        layers[id.to_s]
      end
      resolver = described_class.new(parent, finder: finder)

      resolver.cycle?(2)
      expect(lookups.values).to all(eq(1))
    end

    it "treats a chain deeper than MAX_DEPTH as a cycle" do
      resolver = described_class.new(parent, finder: ->(id) { referencing(id.to_i + 1) })
      expect(resolver.cycle?(1000)).to be(true)
    end
  end

  describe "#resolve!" do
    it "returns the Subprocess target named after the child's own name" do
      child = create(:flowchart, :simple, customer: customer, name: "学生档案")
      info = described_class.new(parent).resolve!(subflow_element(child.id))

      expect(info).to eq(
        flowchart_id: child.id,
        activity_class_name: ActivityGenerator::NameDeriver.new.derive_activity_class_name("学生档案"),
        subflow_name: "学生档案"
      )
      expect(info[:activity_class_name]).not_to eq(ActivityGenerator::NameDeriver.new.derive_activity_class_name(parent.name))
    end

    it "skips an element without a target" do
      expect(described_class.new(parent).resolve!(subflow_element(""))).to be_nil
    end

    it "rejects another customer's flowchart as an inaccessible reference" do
      foreign = create(:flowchart, :simple, customer: create(:customer))

      expect { described_class.new(parent).resolve!(subflow_element(foreign.id)) }.to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:invalid_subflow_reference)
        expect(error.element_id).to eq("sf1")
        expect(error.details).to eq(["flowchartId=#{foreign.id}"])
        expect(error.message).to eq(I18n.t("maint_core.flowcharts.structure_errors.subflow_inaccessible"))
      }
    end

    it "rejects a reference that cycles back to the parent" do
      child = create(:flowchart, :simple, customer: customer)
      resolver = described_class.new(parent, finder: ->(id) { id.to_s == child.id.to_s ? referencing(parent.id, id: child.id, name: "C") : nil })

      expect { resolver.resolve!(subflow_element(child.id)) }
        .to raise_error(ActivityGenerator::Error) { |error| expect(error.code).to eq(:subflow_cycle) }
    end
  end
end
