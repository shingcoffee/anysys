# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageFieldPopulator do
  let_it_be(:customer) { create(:customer) }

  describe ".call" do
    it "returns empty array for nil entity" do
      expect(described_class.call(nil)).to eq([])
    end

    context "with entity having own fields" do
      let(:entity) do
        create(:entity, name: "User", customer: customer, property_schema: [
          { 'name' => 'Name', 'name_slug' => 'name', 'html_type' => 'text' },
          { 'name' => 'Age', 'name_slug' => 'age', 'html_type' => 'number' }
        ].to_json)
      end

      it "returns a single page tab" do
        result = described_class.call(entity)

        expect(result.length).to eq(1)
      end

      it "names the page tab after the entity" do
        result = described_class.call(entity)
        page = result.first

        expect(page["name"]).to eq("User")
        expect(page["id"]).to eq("page_1")
        expect(page["order"]).to eq(1)
      end

      it "includes entity fields in the page tab" do
        result = described_class.call(entity)
        fields = result.first["fields"]

        expect(fields.length).to eq(2)
      end

      it "creates fields with correct structure" do
        result = described_class.call(entity)
        field = result.first["fields"].first

        expect(field["id"]).to start_with("field_")
        expect(field["field_type"]).to eq("text")
        expect(field["property_slug"]).to eq("name")
        expect(field["property_type"]).to eq("string")
        expect(field["label"]).to eq("Name")
        expect(field["width"]).to eq("full")
        expect(field["required"]).to eq(false)
        expect(field["order"]).to eq(0)
      end

      it "sets correct property_type based on html_type" do
        result = described_class.call(entity)
        age_field = result.first["fields"].last

        expect(age_field["field_type"]).to eq("number")
        expect(age_field["property_type"]).to eq("integer")
      end

      it "generates unique IDs for each field" do
        result = described_class.call(entity)
        ids = result.first["fields"].map { |f| f["id"] }

        expect(ids.uniq.length).to eq(ids.length)
      end

      it "orders fields sequentially within the page" do
        result = described_class.call(entity)
        orders = result.first["fields"].map { |f| f["order"] }

        expect(orders).to eq([0, 1])
      end
    end

    context "with bridge entity associations" do
      let!(:entity) do
        create(:entity, name: "Student", customer: customer, property_schema: [
          { 'name' => 'Name', 'name_slug' => 'name', 'html_type' => 'text' }
        ].to_json)
      end

      let!(:target_entity) do
        create(:entity, name: "Course", customer: customer, property_schema: [
          { 'name' => 'Title', 'name_slug' => 'title', 'html_type' => 'text' }
        ].to_json)
      end

      let!(:bridge_entity) do
        create(:entity, name: "Enrollment", customer: customer, property_schema: [
          { 'name' => 'Student', 'name_slug' => 'student', 'type' => 'EntityReference', 'entity_id' => entity.id },
          { 'name' => 'Course', 'name_slug' => 'course', 'type' => 'EntityReference', 'entity_id' => target_entity.id },
          { 'name' => 'Grade', 'name_slug' => 'grade', 'html_type' => 'text' }
        ].to_json)
      end

      before do
        entity.associations_json = [{
          'target_entity_id' => target_entity.id,
          'target_entity_name' => target_entity.name,
          'bridge_entity_id' => bridge_entity.id,
          'bridge_entity_name' => bridge_entity.name,
          'association_type' => 'has_many',
          'display_field' => 'title',
          'display_field_label' => 'Title'
        }]
        entity.save!
      end

      it "leaves the associated entity out of the page" do
        result = described_class.call(entity)

        expect(result.length).to eq(1)
        expect(result.first["name"]).to eq("Student")
        expect(result.first["fields"].map { |f| f["property_slug"] }).to eq(["name"])
        expect(result.first["fields"].map { |f| f["source"] }.uniq).to eq(["entity"])
      end
    end

    context "source metadata" do
      let!(:entity) do
        create(:entity, name: "Student", customer: customer, property_schema: [
          { 'name' => 'Name', 'name_slug' => 'name', 'html_type' => 'text' }
        ].to_json)
      end

      let!(:course_entity) do
        create(:entity, name: "Course", customer: customer, property_schema: [
          { 'name' => 'Title', 'name_slug' => 'title', 'html_type' => 'text' }
        ].to_json)
      end

      let!(:bridge_entity) do
        create(:entity, name: "StudentCourse", customer: customer, property_schema: [
          { 'name' => 'Student', 'name_slug' => 'student', 'type' => 'EntityReference', 'entity_id' => entity.id },
          { 'name' => 'Course', 'name_slug' => 'course', 'type' => 'EntityReference', 'entity_id' => course_entity.id },
          { 'name' => 'Score', 'name_slug' => 'score', 'html_type' => 'number' }
        ].to_json)
      end

      before do
        entity.associations_json = [{
          'target_entity_id' => course_entity.id,
          'target_entity_name' => course_entity.name,
          'bridge_entity_id' => bridge_entity.id,
          'bridge_entity_name' => bridge_entity.name,
          'association_type' => 'has_many',
          'display_field' => 'title',
          'display_field_label' => 'Title'
        }]
        entity.save!
      end

      it "tags entity fields with source 'entity'" do
        result = described_class.call(entity)
        name_field = result.first["fields"].first

        expect(name_field["source"]).to eq("entity")
        expect(name_field["source_section"]).to eq("Student")
      end
    end

    context "with entity having no fields" do
      let(:entity) do
        create(:entity, name: "Empty", customer: customer, property_schema: [].to_json)
      end

      it "returns empty array" do
        expect(described_class.call(entity)).to eq([])
      end
    end

    context "with Calculated and Computed fields" do
      let(:entity) do
        e = create(:entity, name: "Invoice", customer: customer)
        e.property_schema_json = [
          { "name" => "Price", "name_slug" => "price", "html_type" => "number", "type" => "Float",
            "description" => "Unit price before tax" },
          { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
            "formula" => "price * 2" },
          { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed",
            "html_type" => "number" }
        ]
        e.save(validate: false)
        e
      end

      it "leaves derived fields out and copies the description into the help text" do
        fields = described_class.call(entity).first["fields"]

        expect(fields.map { |f| f["property_slug"] }).to eq(["price"])
        expect(fields.first["help_text"]).to eq("Unit price before tax")
        expect(fields.first).not_to have_key("readonly")
      end
    end

    context "with several associations" do
      it "builds one tab from the primary entity alone" do
        student = create(:entity, customer: customer, name: "Student",
                                  property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
        course = create(:entity, customer: customer, name: "Course",
                                 property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
        teacher = create(:entity, customer: customer, name: "Teacher",
                                  property_schema: [{ "name" => "Full Name", "name_slug" => "full_name", "html_type" => "text" }].to_json)
        bridges = [course, teacher].map do |target|
          create(:entity, customer: customer, name: "assoc_student_#{target.name.downcase}", category: :bridge, property_schema: [
            { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id },
            { "name" => target.name, "name_slug" => target.name.downcase, "type" => "EntityReference", "entity_id" => target.id },
            { "name" => "Note", "name_slug" => "note", "html_type" => "text" }
          ].to_json)
        end
        student.associations_json = [course, teacher].zip(bridges).map do |target, bridge|
          { "target_entity_id" => target.id, "target_entity_name" => target.name,
            "bridge_entity_id" => bridge.id, "bridge_entity_name" => bridge.name, "association_type" => "has_many" }
        end

        expect(EntityFieldOrganizer).not_to receive(:call)
        result = described_class.call(student)

        expect(result.map { |p| p.slice("id", "name", "order") }).to eq([{ "id" => "page_1", "name" => "Student", "order" => 1 }])
        expect(result.first["fields"].map { |f| f["property_slug"] }).to eq(["name"])
      end
    end
  end
end
