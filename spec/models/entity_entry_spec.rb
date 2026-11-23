# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EntityEntry, type: :model do
  let_it_be(:customer) { create(:customer) }

  let(:entity) do
    create(:entity,
      name: 'Test Entity',
      customer: customer,
      property_schema: [
        { 'name' => 'title', 'name_slug' => 'title', 'type' => 'Types::String' },
        { 'name' => 'count', 'name_slug' => 'count', 'type' => 'Types::Integer' }
      ].to_json
    )
  end

  # Build/create an entry bound to `entity` + `customer`; override `entity:`/`data:` as needed.
  def new_entry(**overrides)
    described_class.new(entity: entity, customer: customer, **overrides)
  end

  def create_entry(**overrides)
    described_class.create!(entity: entity, customer: customer, **overrides)
  end

  describe 'schema' do
    it 'has the expected columns' do
      columns = described_class.column_names
      expect(columns).to match_array(%w[id entity_id customer_id data entity_version_number user_id created_at updated_at])
    end
  end

  describe 'associations' do
    it 'belongs to an entity' do
      expect(new_entry.entity).to eq(entity)
    end

    it 'belongs to an optional user' do
      user = create(:user, customer: customer)
      entry = create_entry(user: user)
      expect(entry.user).to eq(user)
      expect(new_entry.user).to be_nil
    end
  end

  describe '#linked?' do
    it 'is true only when user_id is present' do
      expect(new_entry.linked?).to be(false)
      expect(new_entry.tap { |row| row.user_id = create(:user, customer: customer).id }.linked?).to be(true)
    end
  end

  describe "person-link uniqueness" do
    it "rejects a second entry of the same entity linked to the same user at the database" do
      user = create(:user, customer: customer)
      create_entry(user: user)

      expect {
        described_class.create!(entity: entity, customer: customer, user: user)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same user on two different entities and many unlinked rows on one entity" do
      user = create(:user, customer: customer)
      other = create(:entity, customer: customer, name: "OtherPerson")

      expect {
        create_entry(user: user)
        described_class.create!(entity: other, customer: customer, user: user)
        create_entry
        create_entry
      }.not_to raise_error
    end
  end

  describe 'validations' do
    it 'is valid with valid data keys' do
      entry = new_entry(data: { 'title' => 'Hello', 'count' => '5' }.to_json)
      expect(entry).to be_valid
    end

    it 'is valid with partial data' do
      entry = new_entry(data: { 'title' => 'Hello' }.to_json)
      expect(entry).to be_valid
    end

    it 'is valid with empty data' do
      entry = new_entry(data: {}.to_json)
      expect(entry).to be_valid
    end

    it 'is invalid with keys not in property_schema' do
      entry = new_entry(data: { 'unknown_field' => 'value' }.to_json)
      expect(entry).not_to be_valid
      expect(entry.errors[:data]).to include('contains invalid keys: unknown_field')
    end

    it 'allows reserved identity keys on an unlinked person entry' do
      enable_module!("authentication", customer).set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
      person = create(:entity, customer: customer, name: "Student",
                       extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)
      entry = described_class.new(
        entity: person,
        customer: customer,
        data: { "first_name" => "Ada", "last_name" => "Lovelace", "email" => "ada@example.com" }.to_json
      )
      expect(entry).to be_valid
    end

    it 'rejects reserved identity keys on a non-person entry' do
      entry = new_entry(data: { "first_name" => "Ada" }.to_json)
      expect(entry).not_to be_valid
      expect(entry.errors[:data]).to include("contains invalid keys: first_name")
    end

    it 'requires an entity' do
      entry = new_entry(entity: nil)
      expect(entry).not_to be_valid
    end
  end

  describe 'entity version stamp (provenance)' do
    it 'stamps the entity head version_number on create' do
      expect(entity.current_version.version_number).to eq(1)

      entry = create_entry(data: { 'title' => 'A' }.to_json)
      expect(entry.entity_version_number).to eq(1)
    end

    it 'freezes the stamp against later entity edits (new versions)' do
      entry = create_entry(data: { 'title' => 'A' }.to_json)
      original = entry.entity_version_number

      # Author a new entity version by editing the definition.
      entity.property_schema = [
        { 'name' => 'title', 'name_slug' => 'title', 'type' => 'Types::String' }
      ].to_json
      entity.save!
      expect(entity.reload.current_version.version_number).to be > original

      expect(entry.reload.entity_version_number).to eq(original)
    end

    it 'is NULL when the entity has no current version' do
      entity.update_column(:current_version_id, nil)
      entity.association(:current_version).reset

      entry = create_entry(data: {}.to_json)
      expect(entry.entity_version_number).to be_nil
    end

    it 'is authoritative — overwrites a client-supplied value to prevent forging' do
      # Simulates a crafted submission reaching the real column via #[]= (super).
      entry = create_entry(data: {}.to_json, entity_version_number: 999)
      expect(entry.entity_version_number).to eq(entity.current_version.version_number)
    end

    it 'stamps entries created through the build_for runtime path' do
      Current.customer = customer
      model_class = described_class.build_for(entity)
      entry = model_class.new
      entry.title = 'Runtime'
      entry.save!

      expect(entry.entity_version_number).to eq(entity.current_version.version_number)
    ensure
      Current.reset
    end
  end

  describe '.attribute_slug_for' do
    it 'reserves every column and association and slugs those names clear of them' do
      expect(described_class.reserved_attribute_slugs).to include('customer', 'customer_id', 'entity', 'user', 'data', 'id')
      expect(described_class.attribute_slug_for('Customer')).to eq('customer_ref')
      expect(described_class.attribute_slug_for('User')).to eq('user_ref')
      expect(described_class.attribute_slug_for('Unit price')).to eq('unit_price')
    end
  end

  describe 'JSON data access' do
    it 'parses data as JSON' do
      entry = create_entry(data: { 'title' => 'Test' }.to_json)
      expect(entry.data_json).to be_a(Hash)
      expect(entry.data_json['title']).to eq('Test')
    end

    it 'defaults to empty hash when data is blank' do
      expect(new_entry.data_json).to eq({})
    end
  end

  describe 'hash-like access ([] / []=)' do
    it 'reads attribute values via []' do
      entry = new_entry(data: { 'title' => 'Hello' }.to_json)
      expect(entry[:title]).to eq('Hello')
    end

    it 'writes attribute values via []=' do
      entry = new_entry
      entry[:title] = 'World'
      expect(entry[:title]).to eq('World')
    end

    it 'merges new keys into existing data' do
      entry = new_entry(data: { 'title' => 'A' }.to_json)
      entry[:count] = 42
      expect(entry[:title]).to eq('A')
      expect(entry[:count]).to eq(42)
    end
  end

  describe 'dynamic attribute dispatch (method_missing)' do
    it 'reads valid schema attributes as methods' do
      entry = new_entry(data: { 'title' => 'Dynamic' }.to_json)
      expect(entry.title).to eq('Dynamic')
    end

    it 'writes valid schema attributes as methods' do
      entry = new_entry
      entry.title = 'Assigned'
      expect(entry.title).to eq('Assigned')
    end

    it 'raises NoMethodError for unknown attributes' do
      entry = new_entry
      expect { entry.nonexistent_field }.to raise_error(NoMethodError)
    end

    it 'responds to valid schema attributes' do
      entry = new_entry
      expect(entry).to respond_to(:title)
      expect(entry).to respond_to(:title=)
      expect(entry).to respond_to(:count)
      expect(entry).not_to respond_to(:nonexistent_field)
    end

    it 'supports chained writes' do
      entry = new_entry
      entry.title = 'First'
      entry.count = 10
      expect(entry.data_json).to eq({ 'title' => 'First', 'count' => 10 })
    end
  end

  describe '.attribute_accessor via class_eval' do
    before do
      # Dynamically extend EntityEntry, mirroring ModelGenerator output
      EntityEntry.class_eval do
        attribute_accessor :title, :string
        attribute_accessor :count, :integer
      end
    end

    it 'defines getter methods on EntityEntry' do
      entry = new_entry(data: { 'title' => 'DSL Test' }.to_json)
      expect(entry.title).to eq('DSL Test')
    end

    it 'defines setter methods on EntityEntry' do
      entry = new_entry
      entry.title = 'Set via DSL'
      expect(entry.title).to eq('Set via DSL')
    end
  end

  describe 'persistence' do
    it 'round-trips variable-length data through save/reload' do
      entry = create_entry(data: { 'title' => 'Saved', 'count' => 99 }.to_json)
      reloaded = described_class.find(entry.id)

      expect(reloaded[:title]).to eq('Saved')
      expect(reloaded[:count]).to eq(99)
    end

    it 'persists data set via dynamic methods' do
      entry = new_entry
      entry.title = 'Dynamic Save'
      entry.count = 7
      entry.save!

      reloaded = described_class.find(entry.id)
      expect(reloaded.title).to eq('Dynamic Save')
      expect(reloaded.count).to eq(7)
    end
  end

  describe '.build_for' do
    # Set Current.customer so auto-assignment works for build_for instances
    before { Current.customer = customer }
    after { Current.reset }

    it 'returns self when entity is nil' do
      expect(described_class.build_for(nil)).to eq(described_class)
    end

    it 'returns a subclass of EntityEntry' do
      model_class = described_class.build_for(entity)

      expect(model_class).to be < described_class
      expect(model_class.superclass).to eq(described_class)
    end

    it 'stores bound_entity as class attribute' do
      model_class = described_class.build_for(entity)

      expect(model_class.bound_entity).to eq(entity)
    end

    it 'retains the Rails model name for translated errors on anonymous runtime classes' do
      model_class = described_class.build_for(entity)
      entry = model_class.new(customer: customer)
      entry.errors.add(:title, :invalid)

      expect(model_class.model_name).to eq(described_class.model_name)
      expect(entry.errors.messages[:title]).to eq([I18n.t('errors.messages.invalid')])
      expect { ActiveRecord::RecordInvalid.new(entry) }.not_to raise_error
    end

    it 'keeps real columns and tenant associations authoritative when schema slugs collide' do
      entity.property_schema_json += %w[id data customer_id entity_id entity_version_number user_id entity customer].map do |slug|
        { 'name' => slug, 'name_slug' => slug }
      end
      entry = described_class.build_for(entity).new(customer: customer, entity: entity)

      expect(entry.customer_id).to eq(customer.id)
      expect(entry.entity_id).to eq(entity.id)
      expect(entry.data_json).to eq({})
      expect(entry.save).to be(true)
      expect(entry.reload.data_json).to eq({})
    end

    it 'uses EntityEntry table_name' do
      model_class = described_class.build_for(entity)

      expect(model_class.table_name).to eq(described_class.table_name)
    end

    it 'defines attribute accessors from property_schema' do
      model_class = described_class.build_for(entity)
      entry = model_class.new

      entry.title = 'Build For Test'
      entry.count = 42

      expect(entry.title).to eq('Build For Test')
      expect(entry.count).to eq(42)
    end

    it 'automatically sets entity association on new instances' do
      model_class = described_class.build_for(entity)
      entry = model_class.new

      expect(entry.entity).to eq(entity)
    end

    it 'persists data correctly' do
      model_class = described_class.build_for(entity)
      entry = model_class.new
      entry.title = 'Persisted'
      entry.count = 100
      entry.save!

      reloaded = described_class.find(entry.id)
      expect(reloaded.title).to eq('Persisted')
      expect(reloaded.count).to eq(100)
      expect(reloaded.entity).to eq(entity)
    end

    context 'integration with Trailblazer Activity pattern' do
      it 'works with build_for -> new -> save flow' do
        # Simulate Trailblazer Activity usage
        model_class = described_class.build_for(entity)
        entry = model_class.new
        entry.title = 'Activity Test'
        entry.count = 5

        expect(entry).to be_valid
        expect { entry.save! }.not_to raise_error
        expect(entry).to be_persisted
      end
    end

    context 'entity with Calculated fields' do
      let(:entity_with_calc) do
        create(:entity,
          name: 'Calc Entity',
          customer: customer,
          property_schema: [
            { 'name' => 'value', 'name_slug' => 'value', 'type' => 'Types::Integer' },
            { 'name' => 'computed', 'name_slug' => 'computed', 'type' => 'Calculated' }
          ].to_json
        )
      end

      it 'does not define a setter for Calculated attributes' do
        model_class = described_class.build_for(entity_with_calc)
        entry = model_class.new
        expect(entry).to respond_to(:value)
        expect(entry).to respond_to(:value=)
        expect(entry).to respond_to(:computed)
        expect(entry).not_to respond_to(:computed=)
      end
    end
  end

  describe 'hash-like access — has_attribute? branch' do
    it '[] delegates to ActiveRecord super when column exists on the model' do
      entry = new_entry
      # `id` is a real AR column, so has_attribute?(:id) => true
      expect(entry[:id]).to be_nil  # nil before save, but reads via super
    end

    it '[]= delegates to ActiveRecord super when column exists' do
      entry = new_entry
      entry[:customer_id] = customer.id
      expect(entry.customer_id).to eq(customer.id)
    end
  end

  describe 'method_missing — setter with invalid attribute returns super (NoMethodError)' do
    it 'raises NoMethodError for an unknown setter' do
      entry = new_entry
      expect { entry.nonexistent_field = "value" }.to raise_error(NoMethodError)
    end
  end

  describe 'valid_attribute_slugs caches entity schema rejecting Calculated' do
    let(:entity_with_calc) do
      create(:entity,
        name: 'Calc2',
        customer: customer,
        property_schema: [
          { 'name' => 'score', 'name_slug' => 'score', 'type' => 'Types::Integer' },
          { 'name' => 'derived', 'name_slug' => 'derived', 'type' => 'Calculated' }
        ].to_json
      )
    end

    it 'excludes Calculated fields from valid_attribute_slugs' do
      entry = new_entry(entity: entity_with_calc)
      expect(entry).to respond_to(:score)
      expect(entry).not_to respond_to(:derived)
    end
  end

  describe 'build_for with nil entity returns class itself' do
    it 'returns EntityEntry class when entity is nil' do
      result = described_class.build_for(nil)
      expect(result).to eq(described_class)
    end
  end

  describe 'build_for with schema attrs missing name_slug (next unless slug)' do
    before { Current.customer = customer }
    after  { Current.reset }

    it 'skips attribute definitions for schema entries without a name_slug' do
      entity_no_slug = create(:entity, customer: customer, name: 'NoSlug',
        property_schema: [
          { 'name' => 'valid_one', 'name_slug' => 'valid_one', 'type' => 'Types::String' }
        ].to_json
      )
      entity_no_slug.property_schema_json = [
        { 'name' => 'valid_one', 'name_slug' => 'valid_one', 'type' => 'Types::String' },
        { 'name' => 'missing_slug', 'type' => 'Types::String' }
      ]
      expect(entity_no_slug).not_to be_valid
      model_class = described_class.build_for(entity_no_slug)
      entry = model_class.new
      # valid_one should be defined; missing_slug has no slug so it is skipped
      expect(entry).to respond_to(:valid_one)
      expect(entry).not_to respond_to(:missing_slug)
    end
  end

  describe 'merge_data before data_json has been called (ivar not defined)' do
    it 'works correctly when @data_json ivar is not yet cached' do
      entry = new_entry
      # Ensure no cached ivar
      expect(entry.instance_variable_defined?(:@data_json)).to be false
      # Calling []= triggers merge_data without the ivar being defined first
      entry[:title] = 'direct'
      expect(entry[:title]).to eq('direct')
    end
  end

  describe 'valid_attribute_slugs when entity is nil' do
    it 'returns empty array when entry has no entity (entity&.property_schema_json safe-nav)' do
      entry = described_class.new(customer: customer)
      entry.entity = nil
      # Call valid_attribute_slugs directly via the private path — entity is nil so
      # entity&.property_schema_json returns nil, defaulting to []
      slugs = entry.send(:valid_attribute_slugs)
      expect(slugs).to eq([])
    end
  end

  describe "Computed attributes" do
    let(:computed_entity) do
      e = create(:entity, name: "Computed Host", customer: customer)
      e.property_schema_json = [
        { "name" => "Name", "name_slug" => "name", "type" => "String" },
        { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed",
          "html_type" => "number", "readonly" => true, "storage" => "computed",
          "config" => { "function" => "avg", "bridge_role" => "source", "source_slug" => "score" } }
      ]
      e.save(validate: false)
      e
    end

    it "rejects a forged average_score key in submitted data" do
      entry = described_class.new(
        entity: computed_entity,
        customer: customer,
        data: { "name" => "John", "average_score" => "99" }.to_json
      )
      expect(entry).not_to be_valid
      expect(entry.errors[:data].join).to include("average_score")
    end

    it "does not generate a writer for a Computed slug via build_for" do
      Current.customer = customer
      model_class = described_class.build_for(computed_entity)
      entry = model_class.new
      expect(entry).to respond_to(:name)
      expect(entry).to respond_to(:name=)
      expect(entry).to respond_to(:average_score)
      expect(entry).not_to respond_to(:average_score=)
    ensure
      Current.reset
    end

    it "reads a Computed slug's derived value through its build_for reader" do
      model_class = described_class.build_for(computed_entity)
      entry = model_class.new(customer: customer, data: { "name" => "John" }.to_json)
      entry.prime_derived_values!("average_score" => 87.5)
      expect(entry.average_score).to eq(87.5)
      expect(entry.name).to eq("John")
    end

    it "returns {} from #derived_values when the entity has no computed fields" do
      entry = create_entry(data: { "title" => "A" }.to_json)
      expect(entry.derived_values).to eq({})
    end

    context "with a live bridge aggregate" do
      let!(:klass) { create(:entity, name: "Class", customer: customer) }
      let!(:bridge) do
        create(:entity, name: "assoc_computed_host_class", customer: customer, category: :bridge,
          property_schema: [
            { "name" => "Host", "name_slug" => "computed_host", "type" => "EntityReference", "entity_id" => computed_entity.id.to_s },
            { "name" => "Class", "name_slug" => "class", "type" => "EntityReference", "entity_id" => klass.id.to_s },
            { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" }
          ].to_json)
      end
      let!(:john) { create(:entity_entry, entity: computed_entity, customer: customer, data: { "name" => "John" }.to_json) }
      let!(:math) { create(:entity_entry, entity: klass, customer: customer, data: {}.to_json) }

      before do
        computed_entity.property_schema_json = [
          { "name" => "Name", "name_slug" => "name", "type" => "String" },
          { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed",
            "html_type" => "number", "readonly" => true, "storage" => "computed",
            "config" => {
              "bridge_entity_id" => bridge.id,
              "bridge_role" => "source",
              "source_slug" => "score",
              "function" => "avg",
              "precision" => 2
            } }
        ]
        computed_entity.save(validate: false)
        computed_entity.reload
        create(:entity_entry, entity: bridge, customer: customer,
          data: { "computed_host" => john.id.to_s, "class" => math.id.to_s, "score" => "90" }.to_json)
        create(:entity_entry, entity: bridge, customer: customer,
          data: { "computed_host" => john.id.to_s, "class" => math.id.to_s, "score" => "85" }.to_json)
        john.reload
      end

      it "returns the resolved hash from #derived_values and memoizes it" do
        expect(john.derived_values).to eq("average_score" => 87.5)

        queries = []
        subscriber = lambda do |*, payload|
          sql = payload[:sql].to_s
          next if sql.match?(/\A(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
          queries << sql
        end
        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          expect(john.derived_values).to eq("average_score" => 87.5)
        end
        expect(queries).to eq([])
      end

      it "uses primed values without issuing another query" do
        Entities::DerivedValues.prime!([john], customer_id: customer.id)
        expect(john.derived_values).to eq("average_score" => 87.5)
      end

      def score!(host, score)
        create(:entity_entry, entity: bridge, customer: customer,
                              data: { "computed_host" => host.id.to_s, "class" => math.id.to_s, "score" => score }.to_json)
      end

      it "has nothing to derive before a new record is saved, and derives once it is" do
        jane = described_class.build_for(computed_entity).new(entity: computed_entity, customer: customer, data: { "name" => "Jane" }.to_json)
        expect(jane.derived_values).to eq({})

        jane.save!
        score!(jane, "70")
        expect(jane.derived_values).to eq("average_score" => 70.0)
      end

      it "derives again once the record is saved or reloaded" do
        expect(john.derived_values).to eq("average_score" => 87.5)

        score!(john, "75")
        john.save!
        expect(john.derived_values).to eq("average_score" => 83.33)

        score!(john, "0")
        expect(john.reload.derived_values).to eq("average_score" => 62.5)
      end
    end
  end
end
