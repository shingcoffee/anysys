# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EntitySchemaValidation, type: :concern do
  let_it_be(:customer) { create(:customer) }
  let(:valid_attributes) do
    {
      icon: 'custom',
      color: '#6366f1',
      customer: customer,
      property_schema: [
        { 'name' => 'Name', 'name_slug' => 'name', 'html_type' => 'text' },
        { 'name' => 'Code', 'name_slug' => 'code', 'html_type' => 'text' }
      ].to_json
    }
  end

  # A well-formed attribute-group hash; pass overrides to vary a single field.
  def group(overrides = {})
    { "id" => "g_1", "name" => "A", "icon" => "folder", "color" => "slate" }.merge(overrides)
  end

  describe 'validate_unique_attribute_names' do
    it 'rejects duplicate attribute names' do
      schema = [
        { 'name' => 'title', 'name_slug' => 'title1', 'type' => 'String' },
        { 'name' => 'title', 'name_slug' => 'title2', 'type' => 'String' }
      ]
      entity = Entity.new(valid_attributes.merge(name: 'Test', property_schema: schema.to_json))

      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include('has duplicate attribute names: title')
    end

    it 'allows unique attribute names' do
      schema = [
        { 'name' => 'title', 'name_slug' => 'title', 'type' => 'String' },
        { 'name' => 'description', 'name_slug' => 'description', 'type' => 'String' }
      ]
      entity = Entity.new(valid_attributes.merge(name: 'Test', property_schema: schema.to_json))

      expect(entity).to be_valid
    end
  end

  describe 'validate_unique_attribute_slugs' do
    it 'rejects duplicate attribute slugs' do
      schema = [
        { 'name' => 'Title One', 'name_slug' => 'title', 'type' => 'String' },
        { 'name' => 'Title Two', 'name_slug' => 'title', 'type' => 'String' }
      ]
      entity = Entity.new(valid_attributes.merge(name: 'Test', property_schema: schema.to_json))

      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include('has duplicate attribute slugs: title')
    end
  end

  describe 'validate_no_bridge_entity_conflicts' do
    let!(:student) { Entity.create!(valid_attributes.merge(name: 'Student')) }
    let!(:course) { Entity.create!(valid_attributes.merge(name: 'Course')) }
    let!(:conflicting) { Entity.create!(valid_attributes.merge(name: 'assoc_student_course')) }

    it 'rejects when bridge name conflicts with existing entity' do
      student.associations_json = [{
        'target_entity_id' => course.id,
        'target_entity_name' => course.name,
        'additional_attributes' => []
      }]

      expect(student).not_to be_valid
      expect(student.errors[:associations]).to be_present
    end

    it 'skips validation for bridge entities' do
      bridge = Entity.new(
        valid_attributes.merge(
          name: 'assoc_test',
          category: :bridge,
          associations: [{ 'target_entity_id' => course.id }].to_json
        )
      )

      expect(bridge).to be_valid
    end

    it 'includes "(in trash)" in the error message when conflicting entity is inactive' do
      # conflicting is already named 'assoc_student_course' — same as bridge would be
      conflicting.update_columns(status: 'inactive')

      student.associations_json = [{
        'target_entity_id'    => course.id,
        'target_entity_name'  => course.name,
        'additional_attributes' => []
      }]

      expect(student).not_to be_valid
      expect(student.errors[:associations].join).to include("(in trash)")
    end
  end

  describe "attribute group validation" do
    let(:persisted_customer) { create(:customer) }
    let(:entity) { build(:entity, customer: persisted_customer) }

    it "is valid with no groups and no group_ids" do
      entity.attribute_groups = []
      entity.property_schema_json = [{ "name" => "a", "name_slug" => "a" }]
      expect(entity).to be_valid
    end

    it "is valid with a well-formed group + matching group_id" do
      entity.attribute_groups = [group("name" => "Contact", "icon" => "mail", "color" => "indigo")]
      entity.property_schema_json = [{ "name" => "email", "name_slug" => "email", "group_id" => "g_1" }]
      expect(entity).to be_valid
    end

    it "rejects duplicate group ids" do
      entity.attribute_groups = [group("name" => "A"), group("name" => "B")]
      expect(entity).not_to be_valid
      expect(entity.errors[:attribute_groups].join).to match(/duplicate/i)
    end

    it "rejects duplicate group names case-insensitively" do
      entity.attribute_groups = [group("name" => "Contact"), group("id" => "g_2", "name" => "contact")]
      expect(entity).not_to be_valid
      expect(entity.errors[:attribute_groups].join).to match(/duplicate/i)
    end

    it "rejects unknown icon" do
      entity.attribute_groups = [group("icon" => "rocket")]
      expect(entity).not_to be_valid
      expect(entity.errors[:attribute_groups].join).to match(/icon/i)
    end

    it "rejects unknown color" do
      entity.attribute_groups = [group("color" => "neon")]
      expect(entity).not_to be_valid
      expect(entity.errors[:attribute_groups].join).to match(/color/i)
    end

    it "rejects blank group name" do
      entity.attribute_groups = [group("name" => "  ")]
      expect(entity).not_to be_valid
      expect(entity.errors[:attribute_groups].join).to match(/name/i)
    end

    it "rejects dangling group_id on an attribute" do
      entity.attribute_groups = [group]
      entity.property_schema_json = [{ "name" => "x", "name_slug" => "x", "group_id" => "g_missing" }]
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema].join).to match(/group_id/i)
    end

    it "rejects ids with disallowed characters" do
      entity.attribute_groups = [group("id" => "g_<bad>")]
      expect(entity).not_to be_valid
      expect(entity.errors[:attribute_groups].join).to match(/id must be/i)
    end

    it "rejects ids longer than 50 chars" do
      entity.attribute_groups = [group("id" => "g_" + "x" * 60)]
      expect(entity).not_to be_valid
      expect(entity.errors[:attribute_groups].join).to match(/id must be/i)
    end
  end

  describe "parsed_attribute_groups — case branches" do
    let(:persisted_customer2) { create(:customer) }
    let(:entity2) { build(:entity, customer: persisted_customer2) }

    it "accepts Array directly without JSON parsing" do
      entity2.attribute_groups = [group("name" => "Direct")]
      entity2.property_schema_json = []
      expect(entity2).to be_valid
    end

    it "returns [] for nil (when nil branch)" do
      entity2.attribute_groups = nil
      entity2.property_schema_json = []
      expect(entity2).to be_valid
    end

    it "returns [] for blank String" do
      entity2.attribute_groups = ""
      entity2.property_schema_json = []
      expect(entity2).to be_valid
    end

    it "parses valid JSON String" do
      grp = [group("name" => "Parsed")]
      entity2.attribute_groups = grp.to_json
      entity2.property_schema_json = []
      expect(entity2).to be_valid
    end

    it "rejects unparseable JSON rather than treating it as an empty group list" do
      entity2.attribute_groups = "{bad json}"
      entity2.property_schema_json = []
      expect(entity2).not_to be_valid
      expect(entity2.errors.of_kind?(:attribute_groups, :invalid)).to be(true)
      expect(entity2.attribute_groups_json).to be_nil
      expect(entity2.attribute_groups).to eq("{bad json}")
    end

    it "reports a controlled validation error for a non-array group value" do
      entity2.attribute_groups = 42
      entity2.property_schema_json = []
      expect(entity2).not_to be_valid
      expect(entity2.errors.of_kind?(:attribute_groups, :invalid)).to be(true)
      expect(entity2.attribute_groups).to eq(42)
    end
  end

  describe "validate_attribute_groups_shape — edge cases" do
    let(:persisted_customer3) { create(:customer) }
    let(:entity3) { build(:entity, customer: persisted_customer3) }

    it "rejects group with valid id format but name too long (>60 chars)" do
      entity3.attribute_groups = [group("name" => "A" * 61)]
      expect(entity3).not_to be_valid
      expect(entity3.errors[:attribute_groups].join).to match(/name must be/i)
    end

    it "skips name/icon/color checks when id is blank (reports id error and moves to next)" do
      entity3.attribute_groups = [group("id" => "")]
      expect(entity3).not_to be_valid
      expect(entity3.errors[:attribute_groups].join).to match(/id is blank/i)
    end
  end

  describe "association validations" do
    let!(:source)  { Entity.create!(valid_attributes.merge(name: 'Source')) }
    let!(:target)  { Entity.create!(valid_attributes.merge(name: 'Target')) }

    let(:valid_assoc) do
      {
        'target_entity_id'    => target.id,
        'target_entity_name'  => target.name,
        'display_field'       => 'name',
        'display_field_label' => 'Name'
      }
    end

    describe "validate_no_duplicate_associations" do
      it "rejects two associations with same target+display_field" do
        source.associations_json = [valid_assoc, valid_assoc.dup]
        expect(source).not_to be_valid
        expect(source.errors[:associations].join).to match(/duplicate/i)
      end

      it "allows two associations with same target but different display_field" do
        source.associations_json = [
          valid_assoc,
          valid_assoc.merge('display_field' => 'code', 'display_field_label' => 'Code')
        ]
        expect(source).to be_valid
      end

      it "only reports each duplicate key once even when it appears 3+ times" do
        source.associations_json = [valid_assoc, valid_assoc.dup, valid_assoc.dup]
        source.valid?
        msg = source.errors[:associations].join
        # The error message should contain the key only once
        key = "#{target.id}|name"
        expect(msg.scan(key).length).to eq(1)
      end
    end

    describe "validate_no_self_referential_associations" do
      it "rejects an association pointing at the entity itself" do
        source.associations_json = [valid_assoc.merge('target_entity_id' => source.id, 'target_entity_name' => source.name)]
        expect(source).not_to be_valid
        expect(source.errors[:associations].join).to match(/own entity/i)
      end

      it "skips the check for unpersisted records" do
        unsaved = Entity.new(valid_attributes.merge(name: 'New'))
        unsaved.associations_json = [valid_assoc]
        expect(unsaved).to be_valid
      end
    end

    describe "validate_association_display_field_present" do
      it "rejects an association with blank display_field" do
        source.associations_json = [valid_assoc.merge('display_field' => '')]
        expect(source).not_to be_valid
        expect(source.errors[:associations].join).to match(/missing display field/i)
      end

      it "rejects an association with blank display_field_label" do
        source.associations_json = [valid_assoc.merge('display_field_label' => '   ')]
        expect(source).not_to be_valid
        expect(source.errors[:associations].join).to match(/missing display field/i)
      end

      it "rejects incomplete association entries without a target_entity_id" do
        source.associations_json = [{ 'display_field' => '', 'display_field_label' => '' }]
        expect(source).not_to be_valid
        expect(source.errors.of_kind?(:associations, :blank)).to be(true)
      end
    end

    describe "validate_association_target_exists" do
      it "rejects when target_entity_id does not exist in the customer" do
        source.associations_json = [valid_assoc.merge('target_entity_id' => 999_999)]
        expect(source).not_to be_valid
        expect(source.errors[:associations].join).to match(/not found in customer/i)
      end

      it "rejects when target_entity_id exists only in a different customer" do
        other_customer = create(:customer)
        cross_target = Entity.create!(valid_attributes.merge(customer: other_customer, name: 'CrossTarget'))
        source.associations_json = [valid_assoc.merge('target_entity_id' => cross_target.id)]
        expect(source).not_to be_valid
        expect(source.errors[:associations].join).to match(/not found in customer/i)
      end

      it "still accepts a soft-deleted target so the source can be edited to remove the reference" do
        target.update_columns(status: 'inactive')
        source.associations_json = [valid_assoc]
        expect(source).to be_valid
      end

      it "accepts a shared platform entity as an association target" do
        shared = create(:entity, :shared, name: "SharedTarget",
                        property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
        source.associations_json = [valid_assoc.merge("target_entity_id" => shared.id)]
        expect(source).to be_valid
      end
    end
  end

  describe "validate_owner_reference" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:name_schema) { [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json }
    let(:title_schema) { [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json }
    let!(:student) do
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      Entity.create!(valid_attributes.merge(name: "Student", extended_model: person_model, property_schema: name_schema))
    end
    let!(:teacher) do
      Entity.create!(valid_attributes.merge(name: "Teacher", extended_model: person_model, property_schema: name_schema))
    end
    let!(:course) { Entity.create!(valid_attributes.merge(name: "Course", property_schema: title_schema)) }

    def reference_select(slug, target, owner: nil, label_field: "name")
      attribute = {
        "name" => slug.capitalize,
        "name_slug" => slug,
        "html_type" => "select",
        "config" => {
          "options_source" => "entity_entries",
          "entity_id" => target.id.to_s,
          "label_field" => label_field
        }
      }
      attribute["owner"] = owner unless owner.nil?
      attribute
    end

    def owner_invalid_message(field)
      I18n.t("maint_core.errors.validations.entity_owner_reference_invalid", field: field)
    end

    def owner_multiple_message
      I18n.t("maint_core.errors.validations.entity_owner_reference_multiple")
    end

    it "accepts a single owner flag on a person reference and owner_reference resolves to it" do
      assignment = Entity.new(valid_attributes.merge(
        name: "Assignment",
        property_schema: [
          reference_select("student", student, owner: true),
          reference_select("teacher", teacher)
        ].to_json
      ))

      expect(assignment).to be_valid
      expect(People::Ownership.owner_reference(assignment))
        .to have_attributes(slug: "student", person_entity_id: student.id)
    end

    it "rejects an owner flag on a non-reference attribute" do
      entity = Entity.new(valid_attributes.merge(
        name: "Assignment",
        property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text", "owner" => true }].to_json
      ))

      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include(owner_invalid_message("Title"))
    end

    it "rejects an owner flag on a reference to a non-person entity" do
      entity = Entity.new(valid_attributes.merge(
        name: "Assignment",
        property_schema: [reference_select("course", course, owner: true, label_field: "title")].to_json
      ))

      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include(owner_invalid_message("Course"))
    end

    it "rejects an owner flag on any attribute of a person entity" do
      person = Entity.new(valid_attributes.merge(
        name: "Mentor",
        extended_model: person_model,
        property_schema: [reference_select("student", student, owner: true)].to_json
      ))

      expect(person).not_to be_valid
      expect(person.errors[:property_schema]).to include(owner_invalid_message("Student"))
    end

    it "rejects an owner flag on any attribute of a bridge entity" do
      bridge = Entity.new(valid_attributes.merge(
        name: "assoc_student_course_owner",
        category: :bridge,
        property_schema: [reference_select("student", student, owner: true)].to_json
      ))

      expect(bridge).not_to be_valid
      expect(bridge.errors[:property_schema]).to include(owner_invalid_message("Student"))
    end

    it "rejects two owner flags" do
      entity = Entity.new(valid_attributes.merge(
        name: "Assignment",
        property_schema: [
          reference_select("student", student, owner: true),
          reference_select("teacher", teacher, owner: true)
        ].to_json
      ))

      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include(owner_multiple_message)
    end

    it "treats owner false and a missing owner key as unflagged" do
      entity = Entity.new(valid_attributes.merge(
        name: "Review",
        property_schema: [
          reference_select("student", student, owner: false),
          reference_select("teacher", teacher)
        ].to_json
      ))

      expect(entity).to be_valid
      expect(People::Ownership.owner_reference(entity)).to be_nil
    end

    it "rejects an owner flag on association additional_attributes" do
      host = Entity.create!(valid_attributes.merge(name: "Host"))
      host.associations_json = [{
        "target_entity_id" => course.id,
        "target_entity_name" => course.name,
        "display_field" => "title",
        "display_field_label" => "Title",
        "additional_attributes" => [reference_select("student", student, owner: true)]
      }]

      expect(host).not_to be_valid
      expect(host.errors[:property_schema]).to include(owner_invalid_message("Student"))
    end
  end
end
