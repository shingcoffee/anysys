# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::ChoiceList do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:course) { create(:entity, customer: customer, name: "Course") }
  let(:names) { described_class.names_by_id(customer.id) }

  describe ".names_by_id" do
    it "maps the tenant's entities and nobody else's" do
      foreign = create(:entity, customer: create(:customer), name: "Foreign")

      expect(names[course.id]).to eq("Course")
      expect(names).not_to have_key(foreign.id)
    end
  end

  describe ".to_prompt" do
    it "swaps a stored entity id for its name" do
      config = described_class.to_prompt(
        { "options_source" => "entity_entries", "entity_id" => course.id.to_s },
        names_by_id: names
      )

      expect(config).to eq("options_source" => "entity_entries", "options_entity_name" => "Course")
    end

    it "drops an id with no entity behind it rather than echoing the number" do
      config = described_class.to_prompt(
        { "options_source" => "entity_entries", "entity_id" => "999999" },
        names_by_id: names
      )

      expect(config).to eq("options_source" => "entity_entries")
    end

    it "leaves a self-contained list alone" do
      config = { "options" => [{ "value" => "low", "label" => "Low" }] }

      expect(described_class.to_prompt(config, names_by_id: names)).to eq(config)
    end
  end

  describe ".source_of" do
    def bound_to(name, **extra)
      described_class.source_of({ "options_source" => "entity_entries", "options_entity_name" => name, **extra })
    end

    it "is nil for a list that carries its own options" do
      expect(described_class.source_of({ "options" => %w[Low High] })).to be_nil
      expect(described_class.source_of(nil)).to be_nil
    end

    # The whole point of the value object: the stored shape and the shape the
    # model echoes back describe the same list, so they must compare equal.
    it "reads the same source from either shape" do
      stored = described_class.source_of(
        { "options_source" => "entity_entries", "entity_id" => course.id.to_s },
        names_by_id: names
      )

      expect(stored).to eq(bound_to("Course"))
      expect(stored.entity_name).to eq("Course")
    end

    it "ignores the label, which only changes what is displayed" do
      expect(bound_to("Course", "label_field" => "title")).to eq(bound_to("Course"))
    end

    it "distinguishes a different entity" do
      expect(bound_to("Course")).not_to eq(bound_to("Program"))
    end

    it "has no value field: the stored value is always the record id" do
      expect(EntityDefinitions::ChoiceList::Source.members).to eq(%i[options_source entity_name])
    end
  end
end
