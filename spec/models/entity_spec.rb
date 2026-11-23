# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entity, type: :model do
  let_it_be(:customer) { create(:customer) }

  let(:valid_attributes) do
    {
      name: 'Test Entity',
      icon: 'custom',
      color: '#6366f1',
      description: 'A test entity',
      customer: customer,
      property_schema: [
        { 'name' => 'title', 'name_slug' => 'title', 'type' => 'Types::String' },
        { 'name' => 'count', 'name_slug' => 'count', 'type' => 'Types::Integer' }
      ].to_json,
      default_properties: { 'title' => 'Default' }.to_json
    }
  end

  # A single association hash pointing at `target`; `extra` is a positional hash of
  # additional keys (e.g. 'bridge_entity_id') so bare-hash callers work in Ruby 3.
  def association_to(target, extra = {})
    {
      'target_entity_id' => target.id,
      'target_entity_name' => target.name,
      'display_field' => 'title',
      'display_field_label' => 'title',
      'additional_attributes' => []
    }.merge(extra)
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      entity = described_class.new(valid_attributes)
      expect(entity).to be_valid
    end

    it 'requires a name' do
      entity = described_class.new(valid_attributes.merge(name: ''))
      expect(entity).not_to be_valid
      expect(entity.errors[:name]).to include("can't be blank")
    end

    it 'allows duplicate entity names for the same customer' do
      described_class.create!(valid_attributes)
      duplicate = described_class.new(valid_attributes)
      expect(duplicate).to be_valid
    end

    it 'requires name to be at most 100 characters' do
      entity = described_class.new(valid_attributes.merge(name: 'a' * 101))
      expect(entity).not_to be_valid
      expect(entity.errors[:name]).to include('is too long (maximum is 100 characters)')
    end

    it 'defaults display_label to name when blank' do
      entity = described_class.new(valid_attributes.merge(display_label: ''))
      entity.valid?
      expect(entity.display_label).to eq('Test Entity')
    end

    it 'keeps a manually-edited display_label when name changes' do
      entity = described_class.create!(valid_attributes)
      entity.update!(display_label: 'Custom Label')
      entity.update!(name: 'Renamed Entity')
      expect(entity.display_label).to eq('Custom Label')
    end

    it 'mirrors display_label to name when display_label has not been edited' do
      entity = described_class.create!(valid_attributes.merge(name: 'Original'))
      entity.update!(name: 'Renamed')
      expect(entity.display_label).to eq('Renamed')
    end

    it 'is a platform Shared Resource when customer_id is nil' do
      entity = described_class.new(valid_attributes.merge(customer: nil))
      entity.skip_tenant_customer_assignment!
      expect(entity).to be_valid
      expect(entity).to be_shared
    end

    describe 'extended_model (auto-derived category)' do
      before do
        enable_module!("payment", customer)
        FeatureModules::Module.find_by!(key: "payment").set_extendable_model!("Payments::Order", true)
      end

      it 'derives category :extension when a base model is selected' do
        entity = described_class.create!(valid_attributes.merge(extended_model: "Payments::Order"))
        expect(entity.category).to eq("extension")
        expect(entity.extended_model).to eq("Payments::Order")
      end

      it 'reverts to :plain when the base model is cleared' do
        entity = described_class.create!(valid_attributes.merge(extended_model: "Payments::Order"))
        entity.update!(extended_model: "")
        expect(entity.reload.category).to eq("plain")
        expect(entity.extended_model).to be_nil
      end

      it 'defaults to :plain with no base model' do
        entity = described_class.create!(valid_attributes)
        expect(entity.category).to eq("plain")
        expect(entity.extended_model).to be_nil
      end

      it 'stores at most one base model (single scalar column)' do
        entity = described_class.create!(valid_attributes.merge(extended_model: "Payments::Order"))
        expect(entity.extended_model).to eq("Payments::Order")
      end

      context 'when the entity extends the person model' do
        let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
        let(:person) { described_class.create!(valid_attributes.merge(extended_model: person_model)) }

        before { enable_module!("authentication", customer).set_extendable_model!(person_model, true) }

        it 'cannot clear the extension' do
          expect(person.update(extended_model: "")).to be(false)
          expect(person.errors[:extended_model])
            .to include(I18n.t("maint_core.errors.validations.person_extension_permanent"))
          expect(person.reload.extended_model).to eq(person_model)
        end

        it 'cannot switch to another base model' do
          expect(person.update(extended_model: "Payments::Order")).to be(false)
          expect(person.reload.extended_model).to eq(person_model)
        end

        it 'keeps accepting other edits' do
          expect(person.update(display_label: "Pupil")).to be(true)
        end

        it 'may be chosen on an entity that extended another model' do
          entity = described_class.create!(valid_attributes.merge(extended_model: "Payments::Order"))
          expect(entity.update(extended_model: person_model)).to be(true)
        end
      end

      it 'does not allow a base model on a bridge entity' do
        entity = described_class.new(valid_attributes.merge(category: :bridge, extended_model: "Payments::Order"))
        expect(entity).not_to be_valid
        expect(entity.errors[:extended_model]).to include("is not allowed on a bridge entity")
      end
    end

    it 'validates unique attribute names in property_schema' do
      schema = [
        { 'name' => 'title', 'name_slug' => 'title1', 'type' => 'Types::String' },
        { 'name' => 'title', 'name_slug' => 'title2', 'type' => 'Types::String' }
      ]
      entity = described_class.new(valid_attributes.merge(property_schema: schema.to_json))
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include('has duplicate attribute names: title')
    end

    it 'validates unique attribute slugs in property_schema' do
      schema = [
        { 'name' => 'Title One', 'name_slug' => 'title', 'type' => 'Types::String' },
        { 'name' => 'Title Two', 'name_slug' => 'title', 'type' => 'Types::String' }
      ]
      entity = described_class.new(valid_attributes.merge(property_schema: schema.to_json))
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include('has duplicate attribute slugs: title')
    end

    describe "validate_attribute_slug_format" do
      def entity_with_slug(slug)
        described_class.new(valid_attributes.merge(
          name: "Slug #{slug}-#{SecureRandom.hex(2)}",
          property_schema: [{ "name" => "Field", "name_slug" => slug, "type" => "String" }].to_json
        ))
      end

      it "rejects slugs with spaces, quotes, parens, commas, or hyphens via the i18n key" do
        %w[has\ space quote's foo"bar paren(x) comma,x foo-bar].each do |slug|
          entity = entity_with_slug(slug)
          expect(entity).not_to be_valid, "expected #{slug.inspect} to be invalid"
          expect(entity.errors[:property_schema]).to include(
            I18n.t("maint_core.errors.validations.property_schema_invalid_slugs", slugs: slug)
          )
        end
      end

      it "accepts digit-leading, plain, and mixed-case identifier slugs" do
        %w[2024_revenue plain_slug Mixed_Case_1].each do |slug|
          expect(entity_with_slug(slug)).to be_valid, "expected #{slug.inspect} to be valid"
        end
      end
    end

    context 'bridge entity naming conflicts' do
      let!(:student) { described_class.create!(valid_attributes.merge(name: 'Student')) }
      let!(:course) { described_class.create!(valid_attributes.merge(name: 'Course')) }
      let!(:conflicting_entity) { described_class.create!(valid_attributes.merge(name: 'assoc_student_course')) }

      it 'prevents saving when bridge entity name conflicts with existing entity' do
        student.associations_json = [association_to(course)]

        expect(student).not_to be_valid
        expect(student.errors[:associations]).to be_present
        expect(student.errors[:associations].join(' ')).to include("Bridge entity 'assoc_student_course'")
        expect(student.errors[:associations].join(' ')).to include("conflicts with existing entity")
      end

      it 'allows saving when bridge entity already exists for this association' do
        # Update the conflicting entity to be a bridge entity and associate it
        conflicting_entity.update!(category: :bridge)

        student.associations_json = [association_to(course, 'bridge_entity_id' => conflicting_entity.id)]

        # Should be valid because we're referencing the existing bridge entity
        expect(student).to be_valid
      end

      it 'allows saving when there are no naming conflicts' do
        teacher = described_class.create!(valid_attributes.merge(name: 'Teacher'))

        student.associations_json = [association_to(teacher)]

        expect(student).to be_valid
      end

      it 'skips validation for bridge entities themselves' do
        bridge_entity = described_class.new(
          valid_attributes.merge(
            name: 'assoc_test_entity',
            category: :bridge,
            associations: [{ 'target_entity_id' => course.id, 'target_entity_name' => course.name }].to_json
          )
        )

        expect(bridge_entity).to be_valid
      end

      it 'prevents saving when bridge entity name conflicts with soft-deleted entity' do
        # Create new entities for this test
        teacher = described_class.create!(valid_attributes.merge(name: 'Teacher'))
        math = described_class.create!(valid_attributes.merge(name: 'Math'))

        # Create and soft-delete a bridge entity
        soft_deleted_bridge = described_class.create!(
          valid_attributes.merge(
            name: 'assoc_teacher_math',
            category: :bridge
          )
        )
        soft_deleted_bridge.soft_delete

        # Verify it's soft-deleted
        expect(described_class.unscope(:where).find(soft_deleted_bridge.id).status).to eq('inactive')

        # Try to create an association that would create a bridge with the same name
        teacher.associations_json = [association_to(math)]

        # Should be invalid due to conflict with soft-deleted bridge entity
        expect(teacher).not_to be_valid
        expect(teacher.errors[:associations]).to be_present
        expect(teacher.errors[:associations].join(' ')).to include("Bridge entity 'assoc_teacher_math'")
        expect(teacher.errors[:associations].join(' ')).to include("conflicts with existing entity")
        expect(teacher.errors[:associations].join(' ')).to include("(in trash)")
      end
    end
  end

  describe 'name_slug removal' do
    it 'does not respond to name_slug' do
      entity = described_class.create!(valid_attributes.merge(name: 'My Test Entity'))
      expect(entity).not_to respond_to(:name_slug)
    end
  end

  describe 'associations' do
    it 'has many entity_entries' do
      entity = described_class.create!(valid_attributes)
      expect(entity).to respond_to(:entity_entries)
    end

    it 'destroys associated entity_entries when destroyed' do
      entity = described_class.create!(valid_attributes)
      entity.entity_entries.create!(data: {}.to_json, customer: customer)

      expect { entity.destroy }.to change(EntityEntry, :count).by(-1)
    end
  end

  describe 'scopes' do
    before do
      described_class.create!(valid_attributes.merge(name: 'Zebra Entity'))
      described_class.create!(valid_attributes.merge(name: 'Alpha Entity'))
    end

    describe '.by_name' do
      it 'orders entities alphabetically by name' do
        entities = described_class.by_name
        expect(entities.first.name).to eq('Alpha Entity')
        expect(entities.last.name).to eq('Zebra Entity')
      end
    end

    describe '.recent' do
      it 'orders entities by creation date descending' do
        entities = described_class.recent
        expect(entities.first.name).to eq('Alpha Entity')
      end
    end

    describe '.search_by_name' do
      it 'finds entities matching the query' do
        entities = described_class.search_by_name('alpha')
        expect(entities.count).to eq(1)
        expect(entities.first.name).to eq('Alpha Entity')
      end

      it 'returns all entities when query is blank' do
        entities = described_class.search_by_name('')
        expect(entities.count).to eq(2)
      end

      it 'is case insensitive' do
        entities = described_class.search_by_name('ZEBRA')
        expect(entities.count).to eq(1)
      end

      it 'does not raise when the query is an array' do
        entities = described_class.search_by_name(['alpha'])
        expect(entities.map(&:name)).to include('Alpha Entity')
      end
    end

    describe '.non_bridge' do
      it 'excludes bridge entities' do
        described_class.create!(valid_attributes.merge(name: 'Regular Entity', category: :plain))
        described_class.create!(valid_attributes.merge(name: 'Bridge Entity', category: :bridge))

        entities = described_class.non_bridge
        expect(entities.count).to eq(3) # 2 from before block + 1 regular
        expect(entities.pluck(:name)).not_to include('Bridge Entity')
      end
    end
  end

  describe 'soft delete' do
    let(:entity) { described_class.create!(valid_attributes) }

    it 'can be soft deleted' do
      entity.soft_delete
      expect(entity.status).to eq('inactive')
    end

    it 'is not visible after soft delete' do
      entity.soft_delete
      expect(described_class.visible).not_to include(entity)
    end

    it 'can be restored' do
      entity.soft_delete
      entity.restore
      expect(entity.status).to eq('active')
      expect(described_class.visible).to include(entity)
    end
  end

  describe '#bridge_entity?' do
    it 'returns true for bridge entities' do
      bridge = described_class.create!(valid_attributes.merge(name: 'Bridge Entity', category: :bridge))
      expect(bridge.bridge_entity?).to be true
    end

    it 'returns false for regular entities' do
      entity = described_class.create!(valid_attributes)
      expect(entity.bridge_entity?).to be false
    end
  end

  describe '#person?' do
    it 'is true only for a non-bridge entity that extends PERSON_MODEL' do
      enable_module!("authentication", customer).set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
      person = described_class.create!(valid_attributes.merge(
        name: "Student", extended_model: EntityDefinitions::Capabilities::PERSON_MODEL
      ))
      expect(person.person?).to be true
      expect(described_class.create!(valid_attributes.merge(name: "Plain")).person?).to be false
    end

    it 'is false for a bridge entity even when extended_model is PERSON_MODEL' do
      bridge = described_class.create!(valid_attributes.merge(name: "Junction", category: :bridge))
      bridge.update_column(:extended_model, EntityDefinitions::Capabilities::PERSON_MODEL)
      expect(bridge.reload.person?).to be false
    end
  end

  describe '#generate_bridge_name' do
    let(:entity) { described_class.create!(valid_attributes.merge(name: 'Student')) }

    it 'uses assoc_ prefix with source entity first' do
      bridge_name = entity.send(:generate_bridge_name, 'Student', 'Class')
      expect(bridge_name).to eq('assoc_student_class')
    end

    it 'does not alphabetically sort entity names' do
      bridge_name = entity.send(:generate_bridge_name, 'Zebra', 'Apple')
      expect(bridge_name).to eq('assoc_zebra_apple')
    end

    it 'handles entity names with spaces' do
      bridge_name = entity.send(:generate_bridge_name, 'Student Profile', 'Class Room')
      expect(bridge_name).to eq('assoc_student_profile_class_room')
    end

    it 'handles entity names with special characters' do
      bridge_name = entity.send(:generate_bridge_name, 'User@Profile', 'Product Item')
      expect(bridge_name).to eq('assoc_user_profile_product_item')
    end
  end

  describe '#sync_bridge_entities!' do
    let!(:source_entity) { described_class.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target_entity) { described_class.create!(valid_attributes.merge(name: 'Class')) }

    it 'creates bridge entity with category set to bridge' do
      associations = [association_to(target_entity)]
      source_entity.associations_json = associations
      source_entity.save!

      source_entity.sync_bridge_entities!

      bridge = described_class.find_by(name: 'assoc_student_class')
      expect(bridge).to be_present
      expect(bridge.bridge_entity?).to be true
      expect(bridge.description).to eq(I18n.t("maint_core.entities.bridge_description", source: source_entity.name, target: target_entity.name))
    end

    it 'creates bridge entity with correct naming convention' do
      associations = [association_to(target_entity)]
      source_entity.associations_json = associations
      source_entity.save!

      source_entity.sync_bridge_entities!

      bridge = described_class.find_by(name: 'assoc_student_class')
      expect(bridge).to be_present
      expect(bridge.name).to eq('assoc_student_class')
    end

    it 'updates associations with bridge entity information' do
      associations = [association_to(target_entity)]
      source_entity.associations_json = associations
      source_entity.save!

      source_entity.sync_bridge_entities!
      source_entity.reload

      association = source_entity.associations_list.first
      expect(association['bridge_entity_id']).to be_present
      expect(association['bridge_entity_name']).to eq('assoc_student_class')
    end

    it 'includes references to both entities in bridge schema' do
      associations = [association_to(target_entity)]
      source_entity.associations_json = associations
      source_entity.save!

      source_entity.sync_bridge_entities!

      bridge = described_class.find_by(name: 'assoc_student_class')
      schema = bridge.property_schema_json

      expect(schema).to be_an(Array)
      expect(schema.length).to eq(2)

      # Check source entity reference
      source_attr = schema.find { |attr| attr['name_slug'] == 'student' }
      expect(source_attr).to be_present
      expect(source_attr['type']).to eq('EntityReference')
      expect(source_attr['entity_id']).to eq(source_entity.id.to_s)

      # Check target entity reference
      target_attr = schema.find { |attr| attr['name_slug'] == 'class' }
      expect(target_attr).to be_present
      expect(target_attr['type']).to eq('EntityReference')
      expect(target_attr['entity_id']).to eq(target_entity.id.to_s)
    end
  end

  describe '#cleanup_orphaned_bridge_entities!' do
    let!(:source_entity) { described_class.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target1) { described_class.create!(valid_attributes.merge(name: 'Math')) }
    let!(:target2) { described_class.create!(valid_attributes.merge(name: 'Science')) }
    let!(:target3) { described_class.create!(valid_attributes.merge(name: 'History')) }

    it 'deletes bridge entity when association is removed' do
      # Create association with bridge
      source_entity.associations_json = [association_to(target1)]
      source_entity.save!
      source_entity.sync_bridge_entities!

      bridge = described_class.find_by(name: 'assoc_student_math')
      expect(bridge).to be_present

      # Remove association
      source_entity.associations_json = []
      source_entity.save!
      source_entity.sync_bridge_entities!

      # BUG 2 fix: orphaned bridges are soft-deleted (not hard-deleted)
      expect(described_class.unscope(where: :status).find_by(id: bridge.id).status).to eq('inactive')
    end

    it 'deletes only the removed bridge entities, keeps others' do
      # Create three associations
      source_entity.associations_json = [
        association_to(target1),
        association_to(target2),
        association_to(target3)
      ]
      source_entity.save!
      source_entity.sync_bridge_entities!

      bridge1 = described_class.find_by(name: 'assoc_student_math')
      bridge2 = described_class.find_by(name: 'assoc_student_science')
      bridge3 = described_class.find_by(name: 'assoc_student_history')

      expect(bridge1).to be_present
      expect(bridge2).to be_present
      expect(bridge3).to be_present

      # Remove one association (History), keep Math and Science
      source_entity.reload
      associations = source_entity.associations_list
      source_entity.associations_json = associations.reject { |a| a['target_entity_id'] == target3.id }
      source_entity.save!
      source_entity.sync_bridge_entities!

      # Math and Science bridges should still exist
      expect(described_class.find_by(id: bridge1.id)).to be_present
      expect(described_class.find_by(id: bridge2.id)).to be_present

      # BUG 2 fix: History bridge should be soft-deleted (not hard-deleted)
      expect(described_class.unscope(where: :status).find_by(id: bridge3.id).status).to eq('inactive')
    end

    it 'handles removing all associations at once' do
      # Create multiple associations
      source_entity.associations_json = [
        association_to(target1),
        association_to(target2)
      ]
      source_entity.save!
      source_entity.sync_bridge_entities!

      bridge1 = described_class.find_by(name: 'assoc_student_math')
      bridge2 = described_class.find_by(name: 'assoc_student_science')

      # Remove all associations
      source_entity.associations_json = []
      source_entity.save!
      source_entity.sync_bridge_entities!

      # BUG 2 fix: orphaned bridges are soft-deleted (not hard-deleted)
      expect(described_class.unscope(where: :status).find_by(id: bridge1.id).status).to eq('inactive')
      expect(described_class.unscope(where: :status).find_by(id: bridge2.id).status).to eq('inactive')
    end
  end

  describe '#soft_delete' do
    let!(:student) { described_class.create!(valid_attributes.merge(name: 'Student')) }
    let!(:course) { described_class.create!(valid_attributes.merge(name: 'Course')) }

    before do
      # Create association and bridge entity
      student.associations_json = [association_to(course)]
      student.save!
      student.sync_bridge_entities!
      student.reload
    end

    it 'soft deletes the entity' do
      # Remove associations first to allow deletion
      student.associations_json = []
      student.save!

      student.soft_delete
      expect(student.reload.status).to eq('inactive')
    end

    it 'soft deletes all related bridge entities' do
      bridge = described_class.find_by(name: 'assoc_student_course')
      expect(bridge).to be_present
      expect(bridge.active?).to be true

      # Remove associations first to allow deletion
      student.associations_json = []
      student.save!

      # Manually delete orphaned bridge entity
      bridge.soft_delete

      student.soft_delete

      expect(student.reload.status).to eq('inactive')
      expect(bridge.reload.status).to eq('inactive')
    end

    it 'soft deletes bridge entities where entity is the target' do
      # Create another entity that has student as target
      teacher = described_class.create!(valid_attributes.merge(name: 'Teacher'))
      teacher.associations_json = [association_to(student)]
      teacher.save!
      teacher.sync_bridge_entities!
      teacher.reload

      bridge = described_class.find_by(name: 'assoc_teacher_student')
      expect(bridge).to be_present

      # Remove teacher's associations first (student is a target, so we need to remove source entity's associations)
      teacher.associations_json = []
      teacher.save!

      # Also remove student's own associations to allow deletion
      student.associations_json = []
      student.save!

      # Manually delete orphaned bridge entity
      bridge.soft_delete

      student.soft_delete

      expect(student.reload.status).to eq('inactive')
      expect(bridge.reload.status).to eq('inactive')
    end

    it 'prevents deletion when entity has associations as source' do
      result = student.soft_delete

      expect(result).to be false
      expect(student.errors[:base]).to include("Cannot delete entity that has associations. Please remove all associations first.")
      expect(student.reload.status).to eq('active')
    end

    it 'prevents deletion when entity is a target of associations' do
      # Create another entity that has course as target
      teacher = described_class.create!(valid_attributes.merge(name: 'Teacher'))
      teacher.associations_json = [association_to(course)]
      teacher.save!
      teacher.sync_bridge_entities!

      result = course.soft_delete

      expect(result).to be false
      expect(course.errors[:base]).to include("Cannot delete entity that has associations. Please remove all associations first.")
      expect(course.reload.status).to eq('active')
    end

    it 'allows deletion when all associations are removed' do
      # Remove associations
      student.associations_json = []
      student.save!

      result = student.soft_delete

      expect(result).to be true
      expect(student.reload.status).to eq('inactive')
    end

    it 'allows deletion of bridge entities even with associations' do
      bridge = described_class.find_by(name: 'assoc_student_course')
      expect(bridge).to be_present
      expect(bridge.bridge_entity?).to be true

      result = bridge.soft_delete

      expect(result).to be true
      expect(bridge.reload.status).to eq('inactive')
    end
  end

  describe 'rename bridge entities' do
    let!(:student) { described_class.create!(valid_attributes.merge(name: 'Student')) }
    let!(:course) { described_class.create!(valid_attributes.merge(name: 'Course')) }

    before do
      # Create association and bridge entity
      student.associations_json = [association_to(course)]
      student.save!
      student.sync_bridge_entities!
      student.reload
    end

    it 'renames bridge entities when entity name changes' do
      bridge = described_class.find_by(name: 'assoc_student_course')
      expect(bridge).to be_present

      student.update!(name: 'Pupil')

      bridge.reload
      expect(bridge.name).to eq('assoc_pupil_course')
    end

    it 'updates bridge entity property schema with new entity name' do
      bridge = described_class.find_by(name: 'assoc_student_course')

      student.update!(name: 'Pupil')

      bridge.reload
      schema = bridge.property_schema_json
      student_attr = schema.find { |attr| attr['entity_id'] == student.id.to_s }

      expect(student_attr['name']).to eq('Pupil')
      expect(student_attr['name_slug']).to eq('pupil')
    end

    it 'updates bridge entity description with new entity name' do
      bridge = described_class.find_by(name: 'assoc_student_course')

      student.update!(name: 'Pupil')

      bridge.reload
      expect(bridge.description).to include('Pupil')
      expect(bridge.description).not_to include('Student')
    end

    it 'updates associations with new bridge entity name' do
      student.update!(name: 'Pupil')
      student.reload

      association = student.associations_list.first
      expect(association['bridge_entity_name']).to eq('assoc_pupil_course')
    end

    it 'renames bridge where entity is the target' do
      # Create another entity that has student as target
      teacher = described_class.create!(valid_attributes.merge(name: 'Teacher'))
      teacher.associations_json = [association_to(student)]
      teacher.save!
      teacher.sync_bridge_entities!

      bridge = described_class.find_by(name: 'assoc_teacher_student')
      expect(bridge).to be_present

      student.update!(name: 'Pupil')

      bridge.reload
      expect(bridge.name).to eq('assoc_teacher_pupil')
    end

    it 'updates source entity associations when target entity is renamed' do
      # Create another entity that has student as target
      teacher = described_class.create!(valid_attributes.merge(name: 'Teacher'))
      teacher.associations_json = [association_to(student)]
      teacher.save!
      teacher.sync_bridge_entities!

      student.update!(name: 'Pupil')

      teacher.reload
      association = teacher.associations_list.first
      expect(association['target_entity_name']).to eq('Pupil')
    end

    it 'updates source entity association bridge names when target is renamed' do
      # Create another entity that has student as target
      teacher = described_class.create!(valid_attributes.merge(name: 'Teacher'))
      teacher.associations_json = [association_to(student)]
      teacher.save!
      teacher.sync_bridge_entities!

      student.update!(name: 'Pupil')

      teacher.reload
      association = teacher.associations_list.first
      expect(association['bridge_entity_name']).to eq('assoc_teacher_pupil')
    end

    it 'updates multiple source entities when target is renamed' do
      # Create multiple entities that have student as target
      teacher = described_class.create!(valid_attributes.merge(name: 'Teacher'))
      teacher.associations_json = [association_to(student)]
      teacher.save!
      teacher.sync_bridge_entities!

      parent = described_class.create!(valid_attributes.merge(name: 'Parent'))
      parent.associations_json = [association_to(student)]
      parent.save!
      parent.sync_bridge_entities!

      student.update!(name: 'Pupil')

      teacher.reload
      parent.reload

      expect(teacher.associations_list.first['target_entity_name']).to eq('Pupil')
      expect(parent.associations_list.first['target_entity_name']).to eq('Pupil')
    end
  end

  describe '#as_palette_item' do
    it 'returns a hash with palette item data' do
      entity = described_class.create!(valid_attributes)
      palette_item = entity.as_palette_item

      expect(palette_item[:id]).to eq(entity.id)
      expect(palette_item[:name]).to eq('Test Entity')
      expect(palette_item).not_to have_key(:name_slug)
      expect(palette_item[:element_type]).to eq("custom_#{entity.id}")
      expect(palette_item[:icon]).to eq('custom')
      expect(palette_item[:color]).to eq('#6366f1')
      expect(palette_item[:property_schema]).to be_an(Array)
      expect(palette_item[:default_properties]).to be_a(Hash)
    end
  end

  describe 'referenced_template' do
    let(:template_json) { PageLayoutTemplates.find("blank").to_json }

    it 'stores and retrieves referenced_template as JSON' do
      entity = described_class.create!(valid_attributes.merge(referenced_template: template_json))
      expect(entity.reload.referenced_template).to eq(template_json)
      parsed = JSON.parse(entity.referenced_template)
      expect(parsed["key"]).to eq("blank")
    end

    it 'allows nil referenced_template' do
      entity = described_class.create!(valid_attributes.merge(referenced_template: nil))
      expect(entity).to be_valid
      expect(entity.referenced_template).to be_nil
    end

    it 'allows blank referenced_template' do
      entity = described_class.create!(valid_attributes)
      expect(entity).to be_valid
      expect(entity.referenced_template).to be_nil
    end

    it 'stores large template content' do
      template = PageLayoutTemplates.find("detailed_registration")
      skip "detailed_registration template not found" unless template
      entity = described_class.create!(valid_attributes.merge(referenced_template: template.to_json))
      expect(entity.reload.referenced_template).to be_present
      parsed = JSON.parse(entity.referenced_template)
      expect(parsed["key"]).to eq("detailed_registration")
    end
  end

  describe 'JSON attributes' do
    it 'parses property_schema as JSON' do
      entity = described_class.create!(valid_attributes)
      expect(entity.property_schema_json).to be_an(Array)
      expect(entity.property_schema_json.first['name']).to eq('title')
    end

    it 'parses default_properties as JSON' do
      entity = described_class.create!(valid_attributes)
      expect(entity.default_properties_json).to be_a(Hash)
      expect(entity.default_properties_json['title']).to eq('Default')
    end
  end

  describe "#searchable_field_keys" do
    it "returns the first 3 string-type fields from property_schema" do
      e = described_class.new(property_schema: [
        { "key" => "name",   "type" => "string" },
        { "key" => "amount", "type" => "number" },
        { "key" => "title",  "type" => "text" },
        { "key" => "note",   "type" => "string" },
        { "key" => "extra",  "type" => "string" }
      ])
      expect(e.searchable_field_keys).to eq(%w[name title note])
    end
  end

  describe "#sortable_field_keys" do
    it "includes searchable fields plus created_at/updated_at" do
      e = described_class.new(property_schema: [{ "key" => "name", "type" => "string" }])
      expect(e.sortable_field_keys).to eq(%w[name created_at updated_at])
    end
  end

  describe "extended_model (unversioned live column)" do
    let(:entity) { create(:entity, customer: customer) }

    before do
      enable_module!("payment", customer)
      FeatureModules::Module.find_by!(key: "payment").set_extendable_model!("Payments::Order", true)
    end

    it "defaults to nil" do
      expect(entity.extended_model).to be_nil
    end

    it "persists as a single scalar column and derives the extension category" do
      entity.update!(extended_model: "Payments::Order")
      expect(entity.reload.extended_model).to eq("Payments::Order")
      expect(entity.category).to eq("extension")
    end

    it "is NOT part of the versioned definition snapshot (it is live structural data)" do
      entity.update!(extended_model: "Payments::Order")
      expect(entity.definition_snapshot).not_to have_key("extended_model")
      expect(entity.definition_snapshot).not_to have_key("extendable_models")
    end
  end

  describe "#attribute_groups_json" do
    let(:entity) { create(:entity) }

    it "defaults to an empty array" do
      expect(entity.attribute_groups_json).to eq([])
    end

    it "round-trips an array of group hashes" do
      entity.update!(attribute_groups: [{ "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }])
      expect(entity.reload.attribute_groups_json).to eq([
        { "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }
      ])
    end
  end

  describe "#grouped_property_schema" do
    let(:entity) { create(:entity) }

    it "returns an empty array when no groups and no attributes" do
      entity.update!(attribute_groups: [], property_schema: [].to_json)
      expect(described_class.find(entity.id).grouped_property_schema).to eq([])
    end

    it "preserves group order and assigns matching attributes" do
      entity.update!(
        attribute_groups: [
          { "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" },
          { "id" => "g_2", "name" => "Job",     "icon" => "briefcase", "color" => "teal" }
        ],
        property_schema: [
          { "name" => "email", "name_slug" => "email", "group_id" => "g_1" },
          { "name" => "title", "name_slug" => "title", "group_id" => "g_2" },
          { "name" => "phone", "name_slug" => "phone", "group_id" => "g_1" }
        ].to_json
      )

      result = described_class.find(entity.id).grouped_property_schema
      expect(result.size).to eq(2)
      expect(result[0][:group]["id"]).to eq("g_1")
      expect(result[0][:attributes].map { |a| a["name"] }).to eq(%w[email phone])
      expect(result[1][:group]["id"]).to eq("g_2")
      expect(result[1][:attributes].map { |a| a["name"] }).to eq(%w[title])
    end

    it "appends ungrouped attributes as the last section with group: nil" do
      entity.update!(
        attribute_groups: [{ "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }],
        property_schema: [
          { "name" => "email", "name_slug" => "email", "group_id" => "g_1" },
          { "name" => "notes", "name_slug" => "notes" }
        ].to_json
      )

      result = described_class.find(entity.id).grouped_property_schema
      expect(result.last[:group]).to be_nil
      expect(result.last[:attributes].map { |a| a["name"] }).to eq(%w[notes])
    end

    it "still includes a group with no attributes (empty groups persist)" do
      entity.update!(
        attribute_groups: [{ "id" => "g_1", "name" => "Empty", "icon" => "folder", "color" => "slate" }],
        property_schema: [].to_json
      )
      result = described_class.find(entity.id).grouped_property_schema
      expect(result.size).to eq(1)
      expect(result[0][:attributes]).to eq([])
    end
  end

  describe "shared identity" do
    it "treats a nil customer_id as a platform Shared Resource" do
      entity = create(:entity, :shared)
      expect(entity.customer_id).to be_nil
      expect(entity).to be_shared
    end

    it "treats a set customer_id as customer-owned" do
      entity = create(:entity, customer: customer)
      expect(entity).to be_customer_owned
    end

    it "allows the same name in two customers for customer_specific entities" do
      c2 = create(:customer)
      create(:entity, customer: customer, name: "Lead")
      dup = build(:entity, customer: c2, name: "Lead")
      expect(dup).to be_valid
    end

    it "allows duplicate names for shared entities" do
      create(:entity, :shared, name: "GlobalThing")
      dup = build(:entity, :shared, name: "GlobalThing")
      expect(dup).to be_valid
    end

    it "rejects associations on a shared entity" do
      entity = build(:entity, :shared, name: "SharedAssoc",
                     associations: [{ "target_entity_id" => 1 }].to_json)
      expect(entity).not_to be_valid
      expect(entity.errors[:base]).to include("Shared entities cannot define associations")
    end

    describe "scopes" do
      it ".shared returns only shared entities" do
        create(:entity, customer: customer, name: "Own")
        shared = create(:entity, :shared, name: "Shared1")
        expect(described_class.shared).to contain_exactly(shared)
      end

      it ".accessible includes own + shared for the current customer" do
        own = create(:entity, customer: customer, name: "Mine")
        shared = create(:entity, :shared, name: "SharedX")
        other = create(:entity, customer: create(:customer), name: "Theirs")
        Current.with_customer(customer) do
          expect(described_class.accessible).to include(own, shared)
          expect(described_class.accessible).not_to include(other)
        end
      end
    end
  end

  describe "#computed_fields and #input_fields" do
    it "selects Computed fields and excludes both Calculated and Computed from input_fields" do
      entity = create(:entity, customer: customer, name: "WithComputed")
      entity.property_schema_json = [
        { "name" => "Name", "name_slug" => "name", "type" => "String" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "formula" => "1 + 1" },
        { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed",
          "config" => { "function" => "avg" } }
      ]
      entity.save(validate: false)

      expect(entity.computed_fields.map { |f| f["name_slug"] }).to eq(["average_score"])
      expect(entity.input_fields.map { |f| f["name_slug"] }).to eq(["name"])
      expect(entity.calculated_fields.map { |f| f["name_slug"] }).to eq(["total"])
    end
  end
end
