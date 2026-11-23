# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EntityEntryContract do
  it 'inherits from Reform::Form' do
    expect(described_class.superclass).to eq(Reform::Form)
  end

  describe '.build_for' do
    let(:entity) do
      create(:entity,
        name: 'User Profile',
        property_schema: schema.to_json
      )
    end

    let(:schema) do
      [
        { 'name' => 'email', 'name_slug' => 'email', 'validators' => [{ 'type' => 'presence' }, { 'type' => 'format_email' }] },
        { 'name' => 'age', 'name_slug' => 'age', 'validators' => [{ 'type' => 'numericality' }, { 'type' => 'greater_than' }] },
        { 'name' => 'notes', 'name_slug' => 'notes', 'validators' => [] }
      ]
    end

    let(:model) { Struct.new(:email, :age, :notes, keyword_init: true) }
    let(:contract_class) { described_class.build_for(entity) }

    it 'returns self when entity is nil' do
      expect(described_class.build_for(nil)).to eq(described_class)
    end

    it 'returns self when entity has empty schema' do
      empty_entity = create(:entity, name: 'Empty', property_schema: '[]')
      expect(described_class.build_for(empty_entity)).to eq(described_class)
    end

    it 'returns a subclass of EntityEntryContract' do
      expect(contract_class).to be < described_class
      expect(contract_class.superclass).to eq(described_class)
    end

    it 'defines properties from entity schema' do
      contract = contract_class.new(model.new(email: 'test@example.com', age: 25, notes: 'hello'))

      expect(contract.email).to eq('test@example.com')
      expect(contract.age).to eq(25)
      expect(contract.notes).to eq('hello')
    end

    it 'applies presence validation' do
      contract = contract_class.new(model.new(email: nil, age: 25, notes: nil))

      expect(contract.validate({})).to be false
      expect(contract.errors[:email]).to include("can't be blank")
    end

    it 'applies format validation' do
      contract = contract_class.new(model.new(email: 'invalid', age: 25, notes: nil))

      expect(contract.validate({})).to be false
      expect(contract.errors[:email]).to be_present
    end

    it 'applies numericality validation' do
      contract = contract_class.new(model.new(email: 'test@example.com', age: 'not a number', notes: nil))

      expect(contract.validate({})).to be false
      expect(contract.errors[:age]).to be_present
    end

    it 'passes validation with valid data' do
      contract = contract_class.new(model.new(email: 'test@example.com', age: 25, notes: 'hello'))

      expect(contract.validate({})).to be true
    end

    it 'syncs params to model on validate' do
      instance = model.new(email: nil, age: nil, notes: nil)
      contract = contract_class.new(instance)

      contract.validate('email' => 'new@example.com', 'age' => 30, 'notes' => 'updated')

      expect(contract.email).to eq('new@example.com')
      expect(contract.age).to eq(30)
      expect(contract.notes).to eq('updated')
    end

    context 'integration with Trailblazer Activity pattern' do
      it 'works with build_contract -> validate -> sync flow' do
        # Simulate Trailblazer Activity steps
        ctx = { entity: entity, params: { 'email' => 'user@example.com', 'age' => 21, 'notes' => 'test' } }

        # Step 1: Build model
        ctx[:model] = model.new(email: nil, age: nil, notes: nil)

        # Step 2: Build contract
        contract_class = described_class.build_for(ctx[:entity])
        ctx[:contract] = contract_class.new(ctx[:model])

        # Step 3: Validate
        result = ctx[:contract].validate(ctx[:params])

        expect(result).to be true
        expect(ctx[:contract].email).to eq('user@example.com')
        expect(ctx[:contract].age).to eq(21)
        expect(ctx[:contract].notes).to eq('test')
      end
    end
  end

  # Use a subclass per context to avoid leaking property_accessor definitions
  # across tests (class_eval on the base class would be permanent).

  describe '.property_accessor' do
    let(:contract_class) do
      Class.new(described_class) do
        property_accessor :name
        property_accessor :email, validates: { presence: true }
      end
    end

    let(:model) { Struct.new(:name, :email, keyword_init: true) }

    it 'registers Reform properties' do
      instance = contract_class.new(model.new(name: 'Alice', email: 'alice@example.com'))

      expect(instance.name).to eq('Alice')
      expect(instance.email).to eq('alice@example.com')
    end

    it 'applies validations when provided' do
      instance = contract_class.new(model.new(name: 'Alice', email: nil))

      expect(instance.validate({})).to be false
      expect(instance.errors[:email]).to be_present
    end

    it 'passes validation when constraints are satisfied' do
      instance = contract_class.new(model.new(name: nil, email: 'test@example.com'))

      expect(instance.validate({})).to be true
    end

    it 'allows property without validations' do
      instance = contract_class.new(model.new(name: nil, email: 'a@b.com'))

      expect(instance.validate({})).to be true
      expect(instance.name).to be_nil
    end
  end

  describe '#validate' do
    let(:contract_class) do
      Class.new(described_class) do
        property_accessor :title
        property_accessor :count
      end
    end

    it 'syncs params to the model' do
      model = Struct.new(:title, :count, keyword_init: true).new(title: nil, count: nil)
      instance = contract_class.new(model)

      instance.validate('title' => 'Hello', 'count' => 5)

      expect(instance.title).to eq('Hello')
      expect(instance.count).to eq(5)
    end
  end

  describe 'dynamic configuration via class_eval' do
    it 'supports variable-length attributes from entity schema' do
      klass = Class.new(described_class)
      klass.class_eval do
        property_accessor :name
        property_accessor :email, validates: { presence: true }
        property_accessor :age
      end

      model = Struct.new(:name, :email, :age, keyword_init: true)
                   .new(name: 'Test', email: 'a@b.com', age: 25)
      contract = klass.new(model)

      expect(contract.validate({})).to be true
      expect(contract.name).to eq('Test')
      expect(contract.email).to eq('a@b.com')
      expect(contract.age).to eq(25)
    end
  end

  # These examples exercise the uncovered branches inside build_validation_options
  # and invoke_validator_proc via the build_for factory method.
  describe '.build_for with advanced validator configs' do
    let(:model_struct) { Struct.new(:score, :tag, :category, :amount, :pattern_field, keyword_init: true) }

    def build_entity(schema)
      create(:entity, property_schema: schema.to_json)
    end

    def build_contract(schema)
      described_class.build_for(build_entity(schema))
    end

    it 'builds a contract for length_maximum with a string config value and rejects a 51-character value' do
      klass = described_class.build_for(build_entity([
        { 'name' => 'Notes', 'name_slug' => 'notes',
          'validators' => [{ 'type' => 'length_maximum', 'config' => { 'value' => '50' } }] }
      ]))
      notes_model = Struct.new(:notes, keyword_init: true)

      expect(klass.new(notes_model.new(notes: 'x' * 51)).validate({})).to be false
      expect(klass.new(notes_model.new(notes: 'x' * 50)).validate({})).to be true
    end

    it 'lets an optional field stay blank while still checking a submitted value' do
      klass = build_contract([
        { 'name' => 'Score', 'name_slug' => 'score',
          'validators' => [{ 'type' => 'numericality' }, { 'type' => 'less_than_or_equal_to', 'config' => { 'value' => 100 } }] },
        { 'name' => 'Category', 'name_slug' => 'category',
          'validators' => [{ 'type' => 'inclusion', 'config' => { 'values' => %w[a b] } }] },
        { 'name' => 'Pattern', 'name_slug' => 'pattern_field', 'validators' => [{ 'type' => 'format_email' }] }
      ])

      [nil, ''].each do |blank|
        expect(klass.new(model_struct.new(score: blank, category: blank, pattern_field: blank)).validate({})).to be true
      end

      invalid = klass.new(model_struct.new(score: '101', category: 'z', pattern_field: 'nope'))
      expect(invalid.validate({})).to be false
      expect(invalid.errors.attribute_names).to contain_exactly(:score, :category, :pattern_field)
    end

    it 'still requires a value when the field has a presence validator' do
      klass = build_contract([
        { 'name' => 'Score', 'name_slug' => 'score', 'validators' => [{ 'type' => 'presence' }, { 'type' => 'numericality' }] }
      ])

      contract = klass.new(model_struct.new(score: ''))
      expect(contract.validate({})).to be false
      expect(contract.errors.details[:score]).to eq([{ error: :blank }])
    end

    it 'applies length_in_range validator with min/max config' do
      klass = build_contract([
        { 'name' => 'Tag', 'name_slug' => 'tag',
          'validators' => [{ 'type' => 'length_in_range', 'config' => { 'min' => '2', 'max' => '10' } }] }
      ])
      instance = klass.new(model_struct.new(tag: 'x'))
      expect(instance.validate({})).to be false
      expect(instance.errors[:tag]).to be_present

      instance2 = klass.new(model_struct.new(tag: 'hello'))
      expect(instance2.validate({})).to be true
    end

    it 'applies greater_than_or_equal_to validator with value config' do
      klass = build_contract([
        { 'name' => 'Score', 'name_slug' => 'score',
          'validators' => [{ 'type' => 'greater_than_or_equal_to', 'config' => { 'value' => '5' } }] }
      ])
      instance = klass.new(model_struct.new(score: 3))
      expect(instance.validate({})).to be false

      instance2 = klass.new(model_struct.new(score: 10))
      expect(instance2.validate({})).to be true
    end

    it 'applies less_than_or_equal_to validator with value config' do
      # length_minimum/length_maximum with float config is a known production bug
      # (Rails length validators reject non-integer values). Use a numericality
      # validator instead to cover the same invoke_validator_proc code arm.
      klass = build_contract([
        { 'name' => 'Score', 'name_slug' => 'score',
          'validators' => [{ 'type' => 'less_than_or_equal_to', 'config' => { 'value' => '100' } }] }
      ])
      instance = klass.new(model_struct.new(score: 200))
      expect(instance.validate({})).to be false

      instance2 = klass.new(model_struct.new(score: 50))
      expect(instance2.validate({})).to be true
    end

    it 'applies format_custom validator with pattern config' do
      klass = build_contract([
        { 'name' => 'Pattern field', 'name_slug' => 'pattern_field',
          'validators' => [{ 'type' => 'format_custom', 'config' => { 'pattern' => '\A[A-Z]+\z' } }] }
      ])
      instance = klass.new(model_struct.new(pattern_field: 'lowercase'))
      expect(instance.validate({})).to be false

      instance2 = klass.new(model_struct.new(pattern_field: 'UPPER'))
      expect(instance2.validate({})).to be true
    end

    it 'applies inclusion validator with array values config' do
      klass = build_contract([
        { 'name' => 'Category', 'name_slug' => 'category',
          'validators' => [{ 'type' => 'inclusion', 'config' => { 'values' => %w[foo bar] } }] }
      ])
      instance = klass.new(model_struct.new(category: 'baz'))
      expect(instance.validate({})).to be false

      instance2 = klass.new(model_struct.new(category: 'foo'))
      expect(instance2.validate({})).to be true
    end

    it 'applies inclusion validator with newline-separated string values' do
      klass = build_contract([
        { 'name' => 'Category', 'name_slug' => 'category',
          'validators' => [{ 'type' => 'inclusion', 'config' => { 'values' => "foo\nbar\n" } }] }
      ])
      instance = klass.new(model_struct.new(category: 'baz'))
      expect(instance.validate({})).to be false

      instance2 = klass.new(model_struct.new(category: 'foo'))
      expect(instance2.validate({})).to be true
    end

    it 'applies exclusion validator with array values config' do
      klass = build_contract([
        { 'name' => 'Category', 'name_slug' => 'category',
          'validators' => [{ 'type' => 'exclusion', 'config' => { 'values' => %w[banned] } }] }
      ])
      instance = klass.new(model_struct.new(category: 'banned'))
      expect(instance.validate({})).to be false

      instance2 = klass.new(model_struct.new(category: 'ok'))
      expect(instance2.validate({})).to be true
    end

    it 'deep-merges multiple numericality constraints onto the same field' do
      # Two validators that both produce { numericality: { ... } } — they must be merged
      klass = build_contract([
        { 'name' => 'Amount', 'name_slug' => 'amount',
          'validators' => [
            { 'type' => 'greater_than_or_equal_to', 'config' => { 'value' => '0' } },
            { 'type' => 'less_than_or_equal_to',    'config' => { 'value' => '100' } }
          ] }
      ])

      instance = klass.new(model_struct.new(amount: -1))
      expect(instance.validate({})).to be false

      instance2 = klass.new(model_struct.new(amount: 200))
      expect(instance2.validate({})).to be false

      instance3 = klass.new(model_struct.new(amount: 50))
      expect(instance3.validate({})).to be true
    end

    it 'skips validators with a non-Hash entry (normalize_validator returns nil)' do
      # Should not raise — non-Hash entries are skipped gracefully
      expect {
        build_contract([
          { 'name' => 'Score', 'name_slug' => 'score',
            'validators' => ["presence", { 'type' => 'presence' }] }
        ])
      }.not_to raise_error
    end

    it 'skips validator entries that have a nil type (safe-navigation returns nil)' do
      # normalize_validator returns [nil, config]; validator_proc lookup for nil key returns nil; skipped
      klass = build_contract([
        { 'name' => 'Score', 'name_slug' => 'score',
          'validators' => [{ 'config' => {} }] }  # no "type" key
      ])
      instance = klass.new(model_struct.new(score: 'anything'))
      expect(instance.validate({})).to be true
    end

    it 'skips validator entries with unknown type (no proc in VALIDATORS)' do
      klass = build_contract([
        { 'name' => 'Score', 'name_slug' => 'score',
          'validators' => [{ 'type' => 'completely_unknown_validator' }] }
      ])
      instance = klass.new(model_struct.new(score: 'anything'))
      # No validation applied for unknown type — should pass
      expect(instance.validate({})).to be true
    end

    it 'skips schema entries without a name_slug and returns a subclass without those properties' do
      # Exercise the factory's defensive reader with an in-memory legacy
      # definition, without persisting a schema that the model now rejects.
      entity = build_entity([{ 'name' => 'Valid', 'name_slug' => 'score', 'validators' => [] }])
      entity.property_schema_json = [{ 'name' => 'No Slug', 'validators' => [] }]
      expect(entity).not_to be_valid

      klass = described_class.build_for(entity)
      expect(klass).to be < described_class
      expect(klass.new(model_struct.new)).not_to respond_to(:score)
    end

    it 'falls through to proc.call when a validator has a config but its key is not in the special cases' do
      # :numericality has a config here but its key is not listed in the invoke_validator_proc
      # case statement, so it hits the else branch and calls proc.call without args.
      klass = build_contract([
        { 'name' => 'Score', 'name_slug' => 'score',
          'validators' => [{ 'type' => 'numericality', 'config' => { 'irrelevant' => true } }] }
      ])
      instance = klass.new(model_struct.new(score: 'not_a_number'))
      expect(instance.validate({})).to be false
    end
  end

  describe '.build_for with attribute-level validator_apply' do
    let(:model_struct) { Struct.new(:nickname, keyword_init: true) }

    def entity_with(validators:, validator_apply: nil)
      attr = { 'name' => 'Nickname', 'name_slug' => 'nickname', 'validators' => validators }
      attr['validator_apply'] = validator_apply if validator_apply
      instance_double(Entity, property_schema_json: [attr])
    end

    it 'applies all validators when audience is omitted (backward compatible)' do
      klass = described_class.build_for(entity_with(
        validators: [{ 'type' => 'presence' }],
        validator_apply: { 'admin' => true, 'member' => false, 'public' => false }
      ))
      expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be false
    end

    it 'skips all validators when validator_apply is false for the audience' do
      klass = described_class.build_for(
        entity_with(
          validators: [{ 'type' => 'presence' }, { 'type' => 'format_email' }],
          validator_apply: { 'admin' => true, 'member' => false, 'public' => true }
        ),
        audience: :member
      )
      expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be true
    end

    it 'applies all validators when validator_apply is true for the audience' do
      klass = described_class.build_for(
        entity_with(
          validators: [{ 'type' => 'presence' }],
          validator_apply: { 'admin' => false, 'member' => true, 'public' => false }
        ),
        audience: :member
      )
      expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be false
    end

    it 'treats missing validator_apply as applying to every audience' do
      klass = described_class.build_for(
        entity_with(validators: [{ 'type' => 'presence' }]),
        audience: :public
      )
      expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be false
    end

    def entity_with_visibility(validators:, visibility: nil, validator_apply: nil)
      attr = { 'name' => 'Nickname', 'name_slug' => 'nickname', 'validators' => validators }
      attr['visibility'] = visibility if visibility
      attr['validator_apply'] = validator_apply if validator_apply
      instance_double(Entity, property_schema_json: [attr])
    end

    it 'skips validators when visibility is false for the audience even if validator_apply is true' do
      klass = described_class.build_for(
        entity_with_visibility(
          validators: [{ 'type' => 'presence' }],
          visibility: { 'admin' => true, 'member' => true, 'public' => false },
          validator_apply: { 'admin' => true, 'member' => true, 'public' => true }
        ),
        audience: :public
      )
      expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be true
    end

    it 'skips validators when visibility is false and validator_apply is missing' do
      klass = described_class.build_for(
        entity_with_visibility(
          validators: [{ 'type' => 'presence' }],
          visibility: { 'admin' => true, 'member' => true, 'public' => false }
        ),
        audience: :public
      )
      expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be true
    end

    it 'still applies validators when visible and validator_apply is missing' do
      klass = described_class.build_for(
        entity_with_visibility(
          validators: [{ 'type' => 'presence' }],
          visibility: { 'admin' => true, 'member' => true, 'public' => true }
        ),
        audience: :public
      )
      expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be false
    end

    it 'exposes the built audience on the contract class' do
      entity = entity_with(validators: [{ 'type' => 'presence' }])

      expect(described_class.build_for(entity, audience: :member).validation_audience).to eq('member')
      expect(described_class.build_for(entity).validation_audience).to be_nil
    end

    it 'never declares validators that apply to no audience at all' do
      klass = described_class.build_for(entity_with(
        validators: [{ 'type' => 'presence' }],
        validator_apply: { 'admin' => false, 'member' => false, 'public' => false }
      ))

      # No audience at all is the "apply everything" case, so staying valid here
      # proves the validator was never declared rather than merely guarded out.
      expect(klass.validation_audience).to be_nil
      expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be true
    end

    it 'does not leak the build_for audience into a sibling contract class' do
      entity = entity_with(
        validators: [{ 'type' => 'presence' }],
        validator_apply: { 'admin' => false, 'member' => false, 'public' => true }
      )
      described_class.build_for(entity, audience: :admin)
      unscoped = described_class.build_for(entity)

      expect(unscoped.new(model_struct.new(nickname: nil)).validate({})).to be false
    end
  end

  describe '.build_for write boundaries with real runtime entries' do
    let(:customer) { create(:customer) }
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { 'name' => 'Title', 'name_slug' => 'title' },
        { 'name' => 'Hidden', 'name_slug' => 'hidden', 'visibility' => { 'admin' => false } },
        { 'name' => 'Calculated', 'name_slug' => 'calculated', 'type' => 'Calculated' },
        { 'name' => 'Storage', 'name_slug' => 'storage', 'storage' => 'computed' }
      ].to_json)
    end

    it 'ignores derived deserialization and never invokes setters during sync or save' do
      # Computed accessors use the same runtime factory; no bridge lookup is
      # needed to verify the contract's write/read boundary on an unsaved entry.
      entity.property_schema_json += [{ 'name' => 'Computed', 'name_slug' => 'computed', 'type' => 'Computed' }]
      model = EntityEntry.build_for(entity).new(customer: customer)
      contract = described_class.build_for(entity, audience: 'admin').new(model)
      expect(model).not_to respond_to(:calculated=)
      expect(model).not_to respond_to(:computed=)
      expect(model).not_to receive(:storage=)
      expect(contract.validate('title' => 'Course', 'calculated' => 99, 'computed' => 99, 'storage' => 99)).to be(true)
      expect(contract.calculated).to be_nil
      expect(contract.computed).to be_nil
      expect(contract.storage).to be_nil
      expect { contract.sync }.not_to raise_error
      expect(contract.save).to be(true)
      expect(model.reload.data_json).to eq('title' => 'Course', 'hidden' => nil)
    end

    it 'keeps excluded readers and existing values while limiting both deserialization and syncing' do
      model = EntityEntry.build_for(entity).new(customer: customer, data: { 'hidden' => 'kept' }.to_json)
      contract = described_class.build_for(entity, audience: 'admin', writable_slugs: [:title]).new(model)
      expect(model).not_to receive(:hidden=)
      expect(contract.validate('title' => 'Course', 'hidden' => 'forged')).to be(true)
      expect(contract.hidden).to eq('kept')
      contract.sync
      expect(contract.save).to be(true)
      expect(model.reload.data_json).to eq('title' => 'Course', 'hidden' => 'kept')
    end

    it 'never creates hidden nil keys in a new entry when its write set omits them' do
      model = EntityEntry.build_for(entity).new(customer: customer)
      contract = described_class.build_for(entity, audience: 'admin', writable_slugs: ['title']).new(model)
      expect(contract.validate('title' => 'Course')).to be(true)
      expect(contract.save).to be(true)
      expect(model.reload.data_json).to eq('title' => 'Course')
    end

    it 'retains derived readers and audience-scoped validators instead of accepting forged values' do
      entity.property_schema_json = [{ 'name' => 'Calculated', 'name_slug' => 'calculated', 'type' => 'Calculated',
                                      'validators' => [{ 'type' => 'presence' }], 'validator_apply' => { 'public' => false } }]
      model = EntityEntry.build_for(entity).new(customer: customer)
      admin = described_class.build_for(entity, audience: 'admin', writable_slugs: []).new(model)
      expect(admin).to respond_to(:calculated)
      expect(admin.validate('calculated' => 'forged')).to be(false)
      expect(admin.calculated).to be_nil
      expect(admin.errors[:calculated]).to be_present
      public_contract = described_class.build_for(entity, audience: 'public').new(model)
      expect(public_contract.validate({})).to be(true)
    end

    it 'leaves ordinary properties writable when the optional write set is nil' do
      model = EntityEntry.build_for(entity).new(customer: customer)
      contract = described_class.build_for(entity, audience: 'admin').new(model)
      expect(contract.validate('title' => 'Course', 'hidden' => 'ordinary input')).to be(true)
      expect(contract.save).to be(true)
      expect(model.reload.data_json['hidden']).to eq('ordinary input')
    end
  end

  describe '.build_for reserved properties' do
    let(:customer) { create(:customer) }
    let(:reserved) { EntityEntry.reserved_attribute_slugs.to_a }
    let(:entity) do
      create(:entity, customer: customer, property_schema: (
        [{ 'name' => 'Title', 'name_slug' => 'title' },
         { 'name' => 'Secret', 'name_slug' => 'admin_secret', 'visibility' => { 'public' => false } }] +
        reserved.map { |slug| { 'name' => slug, 'name_slug' => slug } }
      ).to_json)
    end

    it 'protects every real column and association in default contracts even with an explicit allowlist' do
      foreign_customer = create(:customer)
      foreign_entity = create(:entity, customer: foreign_customer)
      [nil, reserved + ['title']].each do |write_set|
        model = EntityEntry.build_for(entity).create!(customer: customer, data: { 'admin_secret' => 'kept' }.to_json)
        original = model.attributes.slice(*reserved)
        contract = described_class.build_for(entity, audience: 'public', writable_slugs: write_set).new(model)
        params = reserved.index_with { 'forged' }.merge(
          'title' => 'Allowed', 'id' => 999_999, 'entity_id' => foreign_entity.id, 'customer_id' => foreign_customer.id,
          'data' => { 'admin_secret' => 'anonymous overwrite' }.to_json,
          'entity' => foreign_entity, 'customer' => foreign_customer
        )

        expect(contract.validate(params)).to be(true)
        reserved.each { |slug| expect(contract.public_send(slug)).to eq(model.public_send(slug)) }
        %w[id entity_id customer_id entity customer].each { |slug| expect(model).not_to receive("#{slug}=") }
        contract.sync
        expect(model.attributes.slice(*(reserved - ['data']))).to eq(original.except('data'))
        expect(contract.save).to be(true)
        expect(model.reload).to have_attributes(customer_id: customer.id, entity_id: entity.id, id: original['id'])
        expect(model.data_json).to eq('title' => 'Allowed', 'admin_secret' => 'kept')
      end
    end

    it 'retains model JSON shape and schema-key validation instead of accepting forged repairs' do
      entity.property_schema_json = [{ 'name' => 'Data', 'name_slug' => 'data' }]
      ['[]', 'not JSON', '{"unknown":"value"}'].each do |invalid_json|
        model = EntityEntry.build_for(entity).new(customer: customer, data: invalid_json)
        contract = described_class.build_for(entity).new(model)
        expect(contract.validate('data' => '{}')).to be(true)
        expect(contract.data).to eq(invalid_json)
        expect(contract.save).to be(false)
        expect(model).to be_new_record
        expect(model.errors[:data]).to be_present
      end
    end
  end

  describe '.build_for audience tamper-resistance' do
    let(:model_struct) { Struct.new(:audience, :validation_audience, :email, keyword_init: true) }

    # An entity is free to slug an attribute `audience` or `validation_audience`.
    # The audience lives on the contract CLASS, so neither a property accessor
    # nor a submitted param can shadow it and downgrade validation.
    let(:klass) do
      schema = [
        { 'name' => 'Audience', 'name_slug' => 'audience' },
        { 'name' => 'Validation audience', 'name_slug' => 'validation_audience' },
        {
          'name' => 'Email', 'name_slug' => 'email',
          'validators' => [{ 'type' => 'presence' }],
          'validator_apply' => { 'admin' => true, 'member' => true, 'public' => false }
        }
      ]
      described_class.build_for(instance_double(Entity, property_schema_json: schema), audience: :admin)
    end

    let(:model) { model_struct.new(audience: nil, validation_audience: nil, email: nil) }

    it 'keeps the server-assigned audience when params carry a colliding slug' do
      contract = klass.new(model)

      expect(contract.validate('audience' => 'public', 'validation_audience' => 'public', 'email' => nil)).to be false
      expect(klass.validation_audience).to eq('admin')
    end

    it 'still round-trips the colliding property values through the twin' do
      contract = klass.new(model)
      contract.validate('audience' => 'public', 'validation_audience' => 'public', 'email' => 'a@b.com')
      contract.sync

      expect(model.audience).to eq('public')
      expect(model.validation_audience).to eq('public')
      expect(klass.validation_audience).to eq('admin')
    end
  end

  describe "entity_entries references" do
    let(:customer) { create(:customer) }
    let(:course) do
      create(:entity, customer: customer, name: "Course",
                      property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    end
    let(:application) do
      create(:entity, customer: customer, name: "Application", property_schema: [
        { "name" => "Course", "name_slug" => "course", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" } },
        { "name" => "Note", "name_slug" => "note", "html_type" => "text" }
      ].to_json)
    end
    let(:biology) { create(:entity_entry, customer: customer, entity: course, data: { title: "Biology" }.to_json) }
    let(:missing) { I18n.t("common.errors.dynamic.association_target_missing", field: "Course") }

    def contract_for(entry, writable_slugs: nil)
      described_class.build_for(application, audience: EntityAttributeAudience::ADMIN, writable_slugs: writable_slugs).new(entry)
    end

    def new_entry = EntityEntry.build_for(application).new(entity: application, customer_id: customer.id)

    it "accepts the id of a record of the target entity in the same customer" do
      expect(contract_for(new_entry).validate("course" => biology.id.to_s)).to be(true)
    end

    it "accepts a blank reference" do
      expect(contract_for(new_entry).validate("course" => "")).to be(true)
    end

    it "rejects a foreign tenant's record, another entity's record and a non-id on :base" do
      foreign = create(:entity_entry, customer: create(:customer), entity: course, data: { title: "X" }.to_json)
      other_entity_entry = create(:entity_entry, customer: customer, entity: application, data: {}.to_json)

      [foreign.id.to_s, other_entity_entry.id.to_s, "abc", "999999"].each do |value|
        contract = contract_for(new_entry)
        expect(contract.validate("course" => value)).to be(false)
        expect(contract.errors[:base]).to include(missing)
      end
    end

    it "checks every value of a multi-valued reference" do
      contract = contract_for(new_entry)

      expect(contract.validate("course" => [biology.id.to_s, "999999"])).to be(false)
      expect(contract.errors[:base]).to include(missing)
    end

    it "skips a reference the caller may not write" do
      expect(contract_for(new_entry, writable_slugs: %w[note]).validate("note" => "hi")).to be(true)
    end

    it "never checks a reference slugged after the record's own tenant association" do
      application.update!(property_schema: [
        { "name" => "Customer", "name_slug" => "customer", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" } }
      ].to_json)

      expect(contract_for(new_entry).validate("customer" => biology.id.to_s)).to be(true)
    end

    it "keeps an unchanged reference on a persisted entry even after its target is deleted" do
      entry = create(:entity_entry, customer: customer, entity: application, data: { course: biology.id.to_s }.to_json)
      biology.destroy!

      contract = contract_for(EntityEntry.build_for(application).find(entry.id))
      expect(contract.validate("course" => entry.data_json["course"], "note" => "edited")).to be(true)
    end
  end
end
