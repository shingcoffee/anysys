# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Sources::Entities do
  let_it_be(:customer) { create(:customer) }

  describe "metadata" do
    it_behaves_like "member source metadata", key: :entities, editable: true, position: 20

    it { expect(described_class.name).to eq("Entities") }
    it { expect(described_class.description).to eq("Surfaces auto-generated from custom entity schemas.") }
  end

  describe "#surfaces" do
    let!(:entity_a) { Entity.create!(customer_id: customer.id, name: "Course") }
    let!(:entity_b) { Entity.create!(customer_id: customer.id, name: "Event") }

    it "yields one surface per Entity row owned by the customer" do
      keys = described_class.new(customer: customer).surfaces.map(&:key)
      expect(keys).to include(:"entity_#{entity_a.id}", :"entity_#{entity_b.id}")
    end

    it "ignores entities owned by other customers" do
      other = create(:customer)
      foreign = Entity.create!(customer_id: other.id, name: "Foreign")
      keys = described_class.new(customer: customer).surfaces.map(&:key)
      expect(keys).not_to include(:"entity_#{foreign.id}")
    end

    it "includes a shared entity visible to the tenant" do
      shared = create(:entity, :shared, name: "SharedCourse")
      keys = described_class.new(customer: customer).surfaces.map(&:key)
      expect(keys).to include(:"entity_#{shared.id}")
    end

    it "omits a trashed entity" do
      entity_a.soft_delete
      keys = described_class.new(customer: customer).surfaces.map(&:key)
      expect(keys).not_to include(:"entity_#{entity_a.id}")
      expect(keys).to include(:"entity_#{entity_b.id}")
    end

    it "omits private entities and non-owned bridges" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      student = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                       property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      teacher = create(:entity, customer: customer, name: "Teacher", extended_model: person_model,
                       property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      private_review = create(:entity, customer: customer, name: "Review",
                              property_schema: [
                                person_select("student", student),
                                person_select("teacher", teacher)
                              ].to_json)
      title_schema = [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json
      entity_a.update!(property_schema: title_schema)
      room = create(:entity, customer: customer, name: "Room", property_schema: title_schema)
      entity_a.associations_json = [association_to(room)]
      entity_a.save!
      entity_a.sync_bridge_entities!
      entity_a.reload
      open_bridge = Entity.find(entity_a.associations_list.first.fetch("bridge_entity_id"))

      student.associations_json = [association_to(entity_a)]
      student.save!
      student.sync_bridge_entities!
      student.reload
      owned_bridge = Entity.find(student.associations_list.first.fetch("bridge_entity_id"))

      keys = described_class.new(customer: customer).surfaces.map(&:key)
      expect(keys).not_to include(:"entity_#{private_review.id}")
      expect(keys).not_to include(:"entity_#{open_bridge.id}")
      expect(keys).to include(:"entity_#{owned_bridge.id}", :"entity_#{student.id}", :"entity_#{entity_a.id}")
    end
  end

  def association_to(target)
    {
      "target_entity_id" => target.id,
      "target_entity_name" => target.name,
      "display_field" => "title",
      "display_field_label" => "Title",
      "additional_attributes" => []
    }
  end

  def person_select(slug, target)
    {
      "name" => slug.capitalize,
      "name_slug" => slug,
      "html_type" => "select",
      "config" => {
        "options_source" => "entity_entries",
        "entity_id" => target.id.to_s,
        "label_field" => "name"
      }
    }
  end
end
