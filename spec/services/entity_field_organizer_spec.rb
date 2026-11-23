# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityFieldOrganizer do
  let_it_be(:customer) { create(:customer) }

  describe ".call" do
    it "returns empty sections for nil entity" do
      result = described_class.call(nil)

      expect(result[:base_fields]).to eq({})
      expect(result[:own_fields]).to eq([])
      expect(result[:associated_entities]).to eq([])
    end

    context "with entity having own fields" do
      let(:entity) do
        create(:entity, name: "User", customer: customer, property_schema: [
          { 'name' => 'Name', 'name_slug' => 'name', 'html_type' => 'text' },
          { 'name' => 'Age', 'name_slug' => 'age', 'html_type' => 'number' }
        ].to_json)
      end

      it "returns own fields" do
        result = described_class.call(entity)

        expect(result[:own_fields].length).to eq(2)
        expect(result[:own_fields].first['name_slug']).to eq('name')
      end
    end

    context "with associated entities" do
      let!(:source_entity) do
        create(:entity, name: "Student", customer: customer, property_schema: [
          { 'name' => 'Name', 'name_slug' => 'name', 'html_type' => 'text' }
        ].to_json)
      end

      let!(:target_entity) do
        create(:entity, name: "Course", customer: customer, property_schema: [
          { 'name' => 'Title', 'name_slug' => 'title', 'html_type' => 'text' }
        ].to_json)
      end

      it "skips associations without bridge entity" do
        source_entity.associations_json = [{
          'target_entity_id' => target_entity.id,
          'target_entity_name' => target_entity.name,
          'association_type' => 'has_many',
          'display_field' => 'title',
          'display_field_label' => 'Title'
        }]
        source_entity.save!

        result = described_class.call(source_entity)

        expect(result[:associated_entities]).to be_empty
      end

      context "with bridge entity" do
        let!(:bridge_entity) do
          create(:entity, name: "assoc_student_course", customer: customer,
                 category: :bridge, property_schema: [
                   { 'name' => 'Student', 'name_slug' => 'student', 'type' => 'EntityReference', 'entity_id' => source_entity.id },
                   { 'name' => 'Course', 'name_slug' => 'course', 'type' => 'EntityReference', 'entity_id' => target_entity.id },
                   { 'name' => 'Enrolled At', 'name_slug' => 'enrolled_at', 'html_type' => 'date' }
                 ].to_json)
        end

        it "includes bridge entity metadata and bridge fields" do
          source_entity.associations_json = [{
            'target_entity_id' => target_entity.id,
            'target_entity_name' => target_entity.name,
            'association_type' => 'many_to_many',
            'bridge_entity_id' => bridge_entity.id,
            'bridge_entity_name' => bridge_entity.name,
            'display_field' => 'title',
            'display_field_label' => 'Title'
          }]
          source_entity.save!

          result = described_class.call(source_entity)

          expect(result[:associated_entities].length).to eq(1)
          assoc = result[:associated_entities].first
          expect(assoc[:entity_name]).to eq('Course')
          expect(assoc[:entity_id]).to eq(target_entity.id)
          expect(assoc[:bridge_entity_id]).to eq(bridge_entity.id)
          expect(assoc[:bridge_entity_name]).to eq('assoc_student_course')
          # Bridge fields include EntityReference ref to target + own fields,
          # but exclude EntityReference ref to source (auto-populated)
          expect(assoc[:bridge_fields].length).to eq(2)
          slugs = assoc[:bridge_fields].map { |f| f['name_slug'] }
          expect(slugs).to include('course', 'enrolled_at')
          expect(slugs).not_to include('student')
        end

        it ".primary returns the own sections without looking up the associations" do
          source_entity.associations_json = [{
            'target_entity_id' => target_entity.id,
            'bridge_entity_id' => bridge_entity.id,
            'association_type' => 'many_to_many'
          }]
          expect(Entity).not_to receive(:find_by)

          result = described_class.primary(source_entity)

          expect(result.keys).to eq(%i[base_fields own_fields])
          expect(result[:own_fields].map { |f| f['name_slug'] }).to eq(['name'])
        end
      end
    end

    it ".primary returns empty own sections for a nil entity" do
      expect(described_class.primary(nil)).to eq(base_fields: {}, own_fields: [])
    end

    context "with an extended base model" do
      before do
        enable_module!("payment", customer)
        FeatureModules::Module.find_by!(key: "payment").set_extendable_model!("Payments::Order", true)
      end

      it "includes columns of the selected base model in base_fields" do
        entity = create(:entity, name: "CustomOrder", customer: customer,
                        extended_model: "Payments::Order")
        result = described_class.call(entity)

        expect(result[:base_fields]).to have_key("Payments::Order")
        fields = result[:base_fields]["Payments::Order"]
        expect(fields).to be_an(Array)
        expect(fields).not_to be_empty
        # Verify system columns are excluded
        field_keys = fields.map { |f| f["key"] }
        expect(field_keys).not_to include("id", "customer_id", "created_at", "updated_at")
        # Verify expected columns are present
        expect(field_keys).to include("external_ref", "subject", "amount")
      end

      it "returns empty base_fields for a non-existent class" do
        entity = build(:entity, name: "Test", customer: customer,
                        extended_model: "NonExistent::Class")
        result = described_class.call(entity)

        expect(result[:base_fields]).to eq({})
      end

      it "returns empty base_fields for a non-ApplicationRecord class" do
        entity = build(:entity, name: "Test", customer: customer,
                        extended_model: "String")
        result = described_class.call(entity)

        expect(result[:base_fields]).to eq({})
      end
    end

    it "returns empty base_fields for a person entity" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      entity = create(:entity, name: "Student", customer: customer, extended_model: person_model)

      expect(described_class.call(entity)[:base_fields]).to eq({})
    end
  end

  describe "#grouped_organized_fields" do
    let(:customer) { create(:customer) }

    it "returns [] when initialized with nil" do
      expect(described_class.new(nil).grouped_organized_fields).to eq([])
    end

    it "returns named groups first and the ungrouped section last" do
      entity = create(:entity, customer: customer)
      entity.attribute_groups_json = [{ "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }]
      entity.property_schema_json  = [
        { "name" => "email", "name_slug" => "email", "group_id" => "g_1" },
        { "name" => "notes", "name_slug" => "notes" }
      ]
      entity.save(validate: false)
      sections = described_class.new(Entity.find(entity.id)).grouped_organized_fields
      expect(sections.size).to eq(2)
      expect(sections[0][:group]["name"]).to eq("Contact")
      expect(sections[0][:fields].map { |f| f["name"] }).to eq(["email"])
      expect(sections[1][:group]).to be_nil
      expect(sections[1][:fields].map { |f| f["name"] }).to eq(["notes"])
    end

    it "returns one section with group: nil when there are no defined groups" do
      entity = create(:entity, customer: customer)
      entity.attribute_groups_json = []
      entity.property_schema_json  = [
        { "name" => "title", "name_slug" => "title" },
        { "name" => "body",  "name_slug" => "body"  }
      ]
      entity.save(validate: false)
      sections = described_class.new(Entity.find(entity.id)).grouped_organized_fields
      expect(sections.size).to eq(1)
      expect(sections[0][:group]).to be_nil
      expect(sections[0][:fields].map { |f| f["name"] }).to eq(["title", "body"])
    end
  end

  describe ".grouped" do
    let(:customer) { create(:customer) }

    it "delegates to grouped_organized_fields" do
      entity = create(:entity, customer: customer)
      expect(described_class.grouped(entity)).to eq(described_class.new(entity).grouped_organized_fields)
    end
  end

  it "leaves calculated and computed attributes out of own fields and grouped fields" do
    customer = create(:customer)
    entity = create(:entity, customer: customer)
    entity.property_schema_json = [
      { "name" => "Price", "name_slug" => "price", "type" => "Float" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "formula" => "price * 2" },
      { "name" => "Count", "name_slug" => "count", "type" => "Computed" }
    ]
    entity.save(validate: false)
    entity = Entity.find(entity.id)

    expect(described_class.call(entity)[:own_fields].map { |f| f["name_slug"] }).to eq(["price"])
    expect(described_class.grouped(entity).flat_map { |section| section[:fields] }.map { |f| f["name_slug"] }).to eq(["price"])
  end
end
