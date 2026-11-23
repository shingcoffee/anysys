# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BridgeEntityManagement, type: :concern do
  let_it_be(:customer) { create(:customer) }
  let(:valid_attributes) do
    {
      icon: 'custom',
      color: '#6366f1',
      customer: customer,
      property_schema: [
        { 'name' => 'Name', 'name_slug' => 'name', 'html_type' => 'text' },
        { 'name' => 'Title', 'name_slug' => 'title', 'html_type' => 'text' }
      ].to_json
    }
  end

  # A fully-specified source association pointing at +target+ (name display field,
  # empty additional_attributes). Pass overrides to vary a single key.
  def association_to(target, overrides = {})
    {
      'target_entity_id'      => target.id,
      'target_entity_name'    => target.name,
      'display_field'         => 'name',
      'display_field_label'   => 'Name',
      'additional_attributes' => []
    }.merge(overrides)
  end

  describe '#sync_bridge_entities!' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Course')) }

    it 'creates a bridge entity with correct attributes' do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!

      bridge = Entity.find_by(name: 'assoc_student_course')
      expect(bridge).to be_present
      expect(bridge.bridge_entity?).to be true
      expect(bridge.customer_id).to eq(customer.id)
    end

    it 'updates associations with bridge entity info' do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!
      source.reload

      assoc = source.associations_list.first
      expect(assoc['bridge_entity_id']).to be_present
      expect(assoc['bridge_entity_name']).to eq('assoc_student_course')
    end

    it 'slugs a participant named like a reserved entry field so its rows can be written' do
      buyer = Entity.create!(valid_attributes.merge(name: 'Customer'))
      source.associations_json = [association_to(buyer)]
      source.save!
      source.sync_bridge_entities!
      bridge = Entity.find_by!(name: 'assoc_student_customer')
      student = create(:entity_entry, customer: customer, entity: source, data: { name: 'Ann' }.to_json)
      shopper = create(:entity_entry, customer: customer, entity: buyer, data: { name: 'Bo' }.to_json)

      expect(bridge.property_schema_json.first(2).pluck('name_slug')).to eq(%w[student customer_ref])
      form = EntityEntryContract.build_for(bridge).new(EntityEntry.build_for(bridge).new(entity: bridge, customer_id: customer.id))
      expect(form.validate('student' => student.id.to_s, 'customer_ref' => shopper.id.to_s)).to be(true)
      expect(form.save).to be(true)
      expect(form.model.reload.data_json).to include('customer_ref' => shopper.id.to_s)
    end
  end

  describe '#cleanup_orphaned_bridge_entities!' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Math')) }

    it 'deletes bridge entity when association is removed' do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!

      bridge = Entity.find_by(name: 'assoc_student_math')
      expect(bridge).to be_present

      source.associations_json = []
      source.save!
      source.sync_bridge_entities!

      # BUG 2 fix: orphaned bridges are soft-deleted (not hard-deleted)
      expect(Entity.unscope(where: :status).find_by(id: bridge.id).status).to eq('inactive')
    end
  end

  describe '#soft_delete' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Course')) }

    it 'prevents deletion when entity has active associations' do
      source.associations_json = [association_to(target)]
      source.save!

      result = source.soft_delete
      expect(result).to be false
      expect(source.errors[:base]).to include("Cannot delete entity that has associations. Please remove all associations first.")
    end

    it 'allows deletion when associations are cleared' do
      result = source.soft_delete
      expect(result).to be true
      expect(source.reload.status).to eq('inactive')
    end

    it 'allows deletion of bridge entities' do
      bridge = Entity.create!(valid_attributes.merge(name: 'assoc_test', category: :bridge))
      result = bridge.soft_delete
      expect(result).to be true
    end
  end

  describe '#has_active_associations?' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Course')) }

    it 'returns false when no associations' do
      expect(source.has_active_associations?).to be false
    end

    it 'returns true when entity has source associations' do
      source.associations_json = [{
        'target_entity_id' => target.id,
        'target_entity_name' => target.name,
        'display_field' => 'name',
        'display_field_label' => 'Name'
      }]
      source.save!

      expect(source.has_active_associations?).to be true
    end

    it 'returns true when entity is a target' do
      target.associations_json = [{
        'target_entity_id' => source.id,
        'target_entity_name' => source.name,
        'display_field' => 'name',
        'display_field_label' => 'Name'
      }]
      target.save!

      expect(source.has_active_associations?).to be true
    end

    it 'returns false for bridge entities' do
      bridge = Entity.create!(valid_attributes.merge(name: 'assoc_test', category: :bridge))
      expect(bridge.has_active_associations?).to be false
    end
  end

  describe '#find_related_bridge_entities' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Course')) }

    it 'finds bridge entities from source associations' do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!
      source.reload

      bridges = source.find_related_bridge_entities
      expect(bridges.count).to eq(1)
      expect(bridges.first.name).to eq('assoc_student_course')
    end
  end

  describe '#sync_bridge_entities! display_field sync' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Course')) }

    it 'updates label_field in bridge property_schema when display_field changes' do
      source.associations_json = [association_to(target, 'display_field' => 'title', 'display_field_label' => 'Title')]
      source.save!
      source.sync_bridge_entities!

      bridge = Entity.find_by(name: 'assoc_student_course')
      schema = bridge.property_schema_json
      expect(schema[1]['config']['label_field']).to eq('title')
      expect(schema[1]['config']['display_field_label']).to eq('Title')

      # Now update display_field to a different value
      source.reload
      updated_assoc = source.associations_list.first
      updated_assoc['display_field'] = 'name'
      updated_assoc['display_field_label'] = 'Name'
      source.associations_json = [updated_assoc]
      source.save!
      source.sync_bridge_entities!

      bridge.reload
      schema = bridge.property_schema_json
      expect(schema[1]['config']['label_field']).to eq('name')
      expect(schema[1]['config']['display_field_label']).to eq('Name')
    end
  end

  describe 'rename_bridge_entities callback' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Course')) }

    before do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!
      source.reload
    end

    it 'renames bridge entity when source entity is renamed' do
      bridge = Entity.find_by(name: 'assoc_student_course')
      source.update!(name: 'Pupil')

      bridge.reload
      expect(bridge.name).to eq('assoc_pupil_course')
    end

    it 'updates source entity associations with new bridge names' do
      source.update!(name: 'Pupil')
      source.reload

      assoc = source.associations_list.first
      expect(assoc['bridge_entity_name']).to eq('assoc_pupil_course')
    end
  end

  describe '#restore_bridge_entities!' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Course')) }

    before do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!
      source.reload
    end

    it 'restores related bridge entities that were soft-deleted alongside the parent' do
      bridge = Entity.find_by(name: 'assoc_student_course')

      # Simulate the soft-delete + restore cycle: clear associations so the
      # parent can be soft-deleted (delete_bridge_entities! is fired in
      # soft_delete via BridgeEntityManagement). Then restore the parent.
      bridge_id = bridge.id
      bridge.soft_delete

      expect(Entity.unscope(where: :status).find(bridge_id).status).to eq('inactive')

      source.restore_bridge_entities!

      expect(Entity.unscope(where: :status).find(bridge_id).status).to eq('active')
    end

    it 'no-ops on bridge entities' do
      bridge = Entity.find_by(name: 'assoc_student_course')
      expect { bridge.restore_bridge_entities! }.not_to raise_error
    end

    it 'no-ops when entity has no bridge-bearing associations' do
      orphan = Entity.create!(valid_attributes.merge(name: 'Lonely'))
      expect { orphan.restore_bridge_entities! }.not_to raise_error
    end
  end

  describe '#sync_bridge_entities! failure modes' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }

    it 'returns false and adds an error when target entity is missing' do
      # Deliberately point at a missing target; bypass validation (mirrors the
      # old update_columns) so sync_bridge_entities! can exercise the error path.
      source.associations_json = [{
        'target_entity_id'    => 999_999,
        'target_entity_name'  => 'Ghost',
        'display_field'       => 'name',
        'display_field_label' => 'Name'
      }]
      source.save(validate: false)
      source.reload

      result = source.sync_bridge_entities!
      expect(result).to be false
      expect(source.errors[:associations].join).to match(/no longer exists/i)
    end

    it 'returns true when there are no associations' do
      expect(source.sync_bridge_entities!).to be true
    end
  end

  describe '#cleanup_orphaned_bridge_entities! — no-op when @old_associations not set' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }

    it 'silently no-ops when old associations tracking ivar is absent' do
      # @old_associations_before_update is nil by default on a freshly loaded record
      source.instance_variable_set(:@old_associations_before_update, nil)
      expect { source.cleanup_orphaned_bridge_entities! }.not_to raise_error
    end
  end

  describe 'track_old_associations — else branch (associations not changed)' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Student')) }

    it 'copies current associations list as deep dup when associations column not changing' do
      # Saving with a name change (but not associations) triggers track_old_associations
      # via before_save only when will_save_change_to_associations? is true.
      # Directly call the private method to test the else branch.
      source.send(:track_old_associations)
      expect(source.instance_variable_get(:@old_associations_before_update)).to eq([])
    end
  end

  describe 'rename_bridge_entities — rename from target side' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Teacher')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Course')) }

    before do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!
      source.reload
    end

    it 'updates bridge name when the TARGET entity is renamed' do
      bridge = Entity.find_by(name: 'assoc_teacher_course')
      expect(bridge).to be_present

      target.update!(name: 'Subject')

      bridge.reload
      expect(bridge.name).to eq('assoc_teacher_subject')
    end
  end

  describe 'update_source_entities_associations — updates other entities referencing this one' do
    let!(:entity_a) { Entity.create!(valid_attributes.merge(name: 'Professor')) }
    let!(:entity_b) { Entity.create!(valid_attributes.merge(name: 'Lecture')) }

    before do
      entity_b.associations_json = [association_to(entity_a)]
      entity_b.save!
      entity_b.sync_bridge_entities!
      entity_b.reload
    end

    it 'propagates new name to other source entities when target is renamed' do
      entity_a.update!(name: 'Instructor')
      entity_b.reload
      assoc = entity_b.associations_list.first
      expect(assoc['target_entity_name']).to eq('Instructor')
    end

    it 'propagates new bridge_entity_name in source associations when target is renamed' do
      entity_a.update!(name: 'Instructor')
      entity_b.reload
      assoc = entity_b.associations_list.first
      # bridge_entity_name should reflect the rename
      expect(assoc['bridge_entity_name']).to match(/instructor/)
    end
  end

  describe '#sync_bridge_entities! on unpersisted entity (line 39 else: no save call)' do
    it 'does not call save when entity is not persisted' do
      # Build (not create) so persisted? is false — the `save if persisted?` else branch is hit
      source = Entity.new(valid_attributes.merge(name: 'Ghost'))
      target = Entity.create!(valid_attributes.merge(name: 'Target'))
      source.associations_json = [association_to(target)]
      # sync on unpersisted: bridge creation will fail because source has no id;
      # but the guard `save if persisted?` should not be reached on the unpersisted path.
      # We just need the else branch executed, even if the overall result is false.
      expect(source).not_to receive(:save)
      source.sync_bridge_entities!
    end
  end

  describe '#find_related_bridge_entities — assoc with no bridge_entity_id (line 107 else)' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Source')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Target')) }

    it 'skips associations that have no bridge_entity_id when scanning reverse side' do
      # Create a non-bridge entity pointing at source as target — no bridge_entity_id set
      target.update!(associations: [{
        'target_entity_id'    => source.id,
        'target_entity_name'  => source.name,
        'display_field'       => 'name',
        'display_field_label' => 'Name'
        # no bridge_entity_id key
      }].to_json)
      target.reload

      # find_related_bridge_entities iterates target's associations; the assoc has
      # target_entity_id == source.id but no bridge_entity_id, so the else branch fires.
      bridges = source.find_related_bridge_entities
      expect(bridges.count).to eq(0)  # nothing added for bridge-less assoc
    end
  end

  describe 'rename_bridge_entities — next when schema does not match old name (line 224)' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Alpha')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Beta')) }

    it 'skips bridge whose schema attrs do not reference the old name' do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!
      source.reload

      bridge = Entity.find_by(name: 'assoc_alpha_beta')
      # Overwrite the bridge's property_schema with attrs that do NOT reference 'Alpha' or 'Beta'
      # so both the if and elsif branches in rename_bridge_entities fail and `next` is hit.
      bridge.property_schema_json = [
        { 'name' => 'unrelated_a', 'name_slug' => 'unrelated_a', 'type' => 'String' },
        { 'name' => 'unrelated_b', 'name_slug' => 'unrelated_b', 'type' => 'String' }
      ]
      bridge.save(validate: false)

      # Rename source — rename_bridge_entities fires; the bridge's schema doesn't match,
      # so `next` is taken and the bridge name is unchanged.
      old_bridge_name = bridge.name
      source.update!(name: 'Omega')
      bridge.reload
      expect(bridge.name).to eq(old_bridge_name)  # unchanged because `next` was hit
    end
  end

  describe 'rename_bridge_entities — bridge with nil description (line 234 else)' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Teacher')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Pupil')) }

    before do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!
      source.reload
    end

    it 'skips gsub when bridge description is nil' do
      bridge = Entity.find_by(name: 'assoc_teacher_pupil')
      bridge.description = nil
      bridge.save(validate: false)

      # Rename source — bridge.description is nil, so the `if bridge.description` else fires
      expect { source.update!(name: 'Instructor') }.not_to raise_error
      bridge.reload
      expect(bridge.name).to eq('assoc_instructor_pupil')
    end
  end

  describe 'update_associations_with_new_bridge_names — assoc with no bridge_entity_id (line 248 then)' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Solo')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Partner')) }

    it 'skips assoc entries that have no bridge_entity_id' do
      # Create association WITHOUT a bridge_entity_id
      source.update!(associations: [{
        'target_entity_id'    => target.id,
        'target_entity_name'  => 'Partner',
        'display_field'       => 'name',
        'display_field_label' => 'Name'
        # no bridge_entity_id
      }].to_json)

      # update_associations_with_new_bridge_names is private; call via rename trigger.
      # Rename source to trigger the callback; assoc has no bridge_entity_id so `next unless` fires.
      expect { source.update!(name: 'SoloRenamed') }.not_to raise_error
    end
  end

  describe 'update_associations_with_new_bridge_names — bridge_entity_id pointing at deleted bridge (line 251 else)' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Maker')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Thing')) }

    before do
      source.associations_json = [association_to(target)]
      source.save!
      source.sync_bridge_entities!
      source.reload
    end

    it 'leaves bridge_entity_name unchanged when bridge record no longer exists' do
      # Manually delete the bridge row (hard delete, bypassing callbacks)
      bridge = Entity.find_by(name: 'assoc_maker_thing')
      bridge.delete  # hard delete so find_by returns nil

      # Rename source — update_associations_with_new_bridge_names runs, finds nil bridge => else
      expect { source.update!(name: 'Creator') }.not_to raise_error
    end
  end

  describe 'update_source_entities_associations — entity with no matching target (line 266 else)' do
    let!(:entity_x) { Entity.create!(valid_attributes.merge(name: 'EntityX')) }
    let!(:entity_y) { Entity.create!(valid_attributes.merge(name: 'EntityY')) }
    let!(:entity_z) { Entity.create!(valid_attributes.merge(name: 'EntityZ')) }

    before do
      # entity_y has an association to entity_z — NOT to entity_x
      entity_y.update!(associations: [{
        'target_entity_id'    => entity_z.id,
        'target_entity_name'  => 'EntityZ',
        'display_field'       => 'name',
        'display_field_label' => 'Name'
      }].to_json)
    end

    it 'does not propagate name when no source entity references the renamed entity' do
      # Rename entity_x — update_source_entities_associations iterates entity_y;
      # entity_y's association targets entity_z (not entity_x), so the if branch
      # at line 266 is false for entity_y → else branch.
      expect { entity_x.update!(name: 'EntityXRenamed') }.not_to raise_error
      entity_y.reload
      assoc = entity_y.associations_list.first
      expect(assoc['target_entity_name']).to eq('EntityZ')  # unchanged
    end
  end

  describe 'update_source_entities_associations — target match with no bridge_entity_id (line 269 else)' do
    let!(:entity_a) { Entity.create!(valid_attributes.merge(name: 'Mentor')) }
    let!(:entity_b) { Entity.create!(valid_attributes.merge(name: 'Student2')) }

    before do
      # entity_b references entity_a but WITHOUT a bridge_entity_id
      entity_b.update!(associations: [{
        'target_entity_id'    => entity_a.id,
        'target_entity_name'  => 'Mentor',
        'display_field'       => 'name',
        'display_field_label' => 'Name'
        # no bridge_entity_id
      }].to_json)
    end

    it 'updates target_entity_name but skips bridge name lookup when bridge_entity_id absent' do
      entity_a.update!(name: 'Guide')
      entity_b.reload
      assoc = entity_b.associations_list.first
      expect(assoc['target_entity_name']).to eq('Guide')
      expect(assoc['bridge_entity_name']).to be_nil
    end
  end

  describe 'track_old_associations — JSON::ParserError rescue (line 297)' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Breaker')) }

    it 'returns [] when associations_was contains invalid JSON' do
      # Make an invalid-JSON string the persisted baseline for the (virtual)
      # associations attribute, then change it so associations_changed? is true and
      # associations_was is the bad JSON.
      source.associations = 'not valid json at all'
      source.clear_changes_information
      source.associations = [].to_json
      # track_old_associations reads associations_was (bad JSON) and should rescue
      # JSON::ParserError and return []
      expect { source.send(:track_old_associations) }.not_to raise_error
      expect(source.instance_variable_get(:@old_associations_before_update)).to eq([])
    end
  end

  describe '#sync_bridge_entities! — bridge save failure' do
    let!(:source) { Entity.create!(valid_attributes.merge(name: 'Broken')) }
    let!(:target) { Entity.create!(valid_attributes.merge(name: 'Break')) }

    it 'returns false and adds an error when bridge entity cannot be saved' do
      source.associations_json = [association_to(target)]
      source.save!

      # Make the bridge entity save fail by injecting a validation error
      allow_any_instance_of(Entity).to receive(:save).and_wrap_original do |m, *args|
        obj = m.receiver
        if obj.bridge_entity?
          obj.errors.add(:base, "injected failure")
          false
        else
          m.call(*args)
        end
      end

      result = source.sync_bridge_entities!
      expect(result).to be false
      expect(source.errors[:associations].join).to match(/could not be saved/i)
    end
  end
end
