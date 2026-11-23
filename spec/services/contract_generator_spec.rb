# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContractGenerator do
  let(:entity) do
    create(:entity,
      name: 'User Registration',
      property_schema: schema.to_json
    )
  end

  let(:schema) do
    [
      {
        'name' => 'email',
        'name_slug' => 'email',
        'type' => 'Types::String',
        'validators' => ['presence', 'format_email']
      },
      {
        'name' => 'age',
        'name_slug' => 'age',
        'type' => 'Types::Integer',
        'validators' => ['numericality', 'greater_than']
      }
    ]
  end

  # Generated source for the shared `entity`/`schema` above. Lazy, so contexts
  # that override `schema`/`entity` regenerate against their own definition.
  let(:code) { described_class.new(entity).generate }

  # Builds a single-attribute entity around `validators` and returns its
  # generated source — the property is always named :f.
  def generate_for(validators)
    schema = [{ "name" => "f", "name_slug" => "f", "type" => "Types::String", "validators" => validators }]
    entity = create(:entity, name: "Gen#{SecureRandom.hex(4)}", property_schema: schema.to_json)
    described_class.new(entity).generate
  end

  describe '#generate' do
    it 'generates Ruby code' do
      expect(code).to be_present
    end

    it 'uses EntityEntryContract.class_eval instead of defining a new class' do
      expect(code).to include('EntityEntryContract.class_eval do')
      expect(code).not_to match(/class \w+Contract < Reform::Form/)
    end

    it 'uses property_accessor DSL' do
      expect(code).to include('property_accessor :email')
      expect(code).to include('property_accessor :age')
    end

    it 'includes validates hash for attributes with validators' do
      expect(code).to include('property_accessor :email, validates: {')
      expect(code).to include('presence: true')
      expect(code).to include('EMAIL_REGEXP')
    end

    it 'includes numericality validations' do
      expect(code).to include('numericality:')
      expect(code).to include('greater_than')
    end

    context 'with empty schema' do
      let(:schema) { [] }

      it 'returns nil' do
        expect(code).to be_nil
      end
    end

    context 'with blank name' do
      let(:entity) do
        build(:entity, name: '', property_schema: schema.to_json)
      end

      it 'returns nil' do
        expect(code).to be_nil
      end
    end
  end

  describe 'header generation' do
    it 'includes frozen_string_literal pragma' do
      expect(code).to include('# frozen_string_literal: true')
    end

    it 'includes EntityEntryContract reference' do
      expect(code).to include('EntityEntryContract configuration for:')
      expect(code).to include('Dynamically extends EntityEntryContract')
    end

    it 'does not include require statements' do
      expect(code).not_to include('require "reform"')
      expect(code).not_to include('require "reform/form/dry"')
    end
  end

  describe 'validation merging' do
    context 'with multiple numericality validators' do
      let(:schema) do
        [
          {
            'name' => 'quantity',
            'name_slug' => 'quantity',
            'type' => 'Types::Integer',
            'validators' => ['numericality', 'greater_than', 'less_than']
          }
        ]
      end

      it 'merges numericality options into a single validation' do
        expect(code).to include('numericality:')
        expect(code).to include('greater_than')
        expect(code).to include('less_than')
      end
    end
  end

  describe 'blank optional values' do
    let(:schema) do
      [
        { 'name' => 'Grade', 'name_slug' => 'grade', 'validators' => [{ 'type' => 'presence' }, { 'type' => 'numericality' }] },
        { 'name' => 'Result', 'name_slug' => 'result',
          'validators' => [{ 'type' => 'inclusion', 'config' => { 'values' => %w[pass fail] } }, { 'type' => 'acceptance' }] }
      ]
    end

    it 'adds allow_blank to every check except presence and acceptance, like the runtime contract' do
      expect(code).to include('validates: { presence: true, numericality: { allow_blank: true } }')
      expect(code).to include('validates: { inclusion: { in: ["pass", "fail"], allow_blank: true }, acceptance: true }')
    end
  end

  describe 'all validator types' do
    context 'with length validators' do
      let(:schema) do
        [
          {
            'name' => 'username',
            'name_slug' => 'username',
            'type' => 'Types::String',
            'validators' => ['length_minimum', 'length_maximum']
          }
        ]
      end

      it 'includes length validations' do
        expect(code).to include('length:')
        expect(code).to include('minimum')
        expect(code).to include('maximum')
      end
    end

    context 'with inclusion validator' do
      let(:schema) do
        [
          {
            'name' => 'status',
            'name_slug' => 'status',
            'type' => 'Types::String',
            'validators' => ['inclusion']
          }
        ]
      end

      it 'includes inclusion validation' do
        expect(code).to include('inclusion:')
      end
    end

    context 'with format validators' do
      let(:schema) do
        [
          {
            'name' => 'website',
            'name_slug' => 'website',
            'type' => 'Types::String',
            'validators' => ['format_url']
          },
          {
            'name' => 'phone',
            'name_slug' => 'phone',
            'type' => 'Types::String',
            'validators' => ['format_phone']
          }
        ]
      end

      it 'includes URL format validation' do
        expect(code).to include('format:')
        expect(code).to include('http')
      end

      it 'includes phone format validation' do
        expect(code).to include('property_accessor :phone')
      end
    end
  end

  describe 'attributes without validators' do
    let(:schema) do
      [
        {
          'name' => 'notes',
          'name_slug' => 'notes',
          'type' => 'Types::String',
          'validators' => []
        },
        {
          'name' => 'email',
          'name_slug' => 'email',
          'type' => 'Types::String',
          'validators' => ['presence']
        }
      ]
    end

    it 'includes property_accessor for all attributes' do
      expect(code).to include('property_accessor :notes')
      expect(code).to include('property_accessor :email')
    end

    it 'only adds validates hash for attributes with validators' do
      # notes has no validators -- plain property_accessor without validates:
      expect(code).to match(/property_accessor :notes\n/)
      # email has validators
      expect(code).to include('property_accessor :email, validates:')
    end
  end

  # -----------------------------------------------------------------------
  # New-format (Hash) validator dispatch — covers the uncovered branches
  # in build_validator_option when validator.is_a?(Hash)
  # -----------------------------------------------------------------------
  describe "new-format (Hash) validator dispatch" do
    context "length_in_range with config (lines 98-100)" do
      it "uses range config when min and max are present" do
        code = generate_for([{ "type" => "length_in_range", "config" => { "min" => 2, "max" => 50 } }])
        expect(code).to include("length: { in: 2..50, allow_blank: true }")
      end

      it "uses default range when config is absent (line 102)" do
        code = generate_for([{ "type" => "length_in_range" }])
        expect(code).to include("length:")
      end
    end

    context "comparison validators with config (lines 104-109)" do
      %w[greater_than_or_equal_to less_than_or_equal_to equal_to not_equal_to greater_than less_than].each do |type|
        it "#{type} with config value" do
          code = generate_for([{ "type" => type, "config" => { "value" => 5 } }])
          expect(code).to include("numericality:")
        end

        it "#{type} without config falls back to default (line 108)" do
          code = generate_for([{ "type" => type }])
          expect(code).to include("numericality:")
        end
      end
    end

    context "length_minimum/length_maximum with config (lines 110-115)" do
      it "length_minimum with config value" do
        code = generate_for([{ "type" => "length_minimum", "config" => { "value" => 3 } }])
        expect(code).to include("length: { minimum: 3, allow_blank: true }")
      end

      it "length_maximum with config value" do
        code = generate_for([{ "type" => "length_maximum", "config" => { "value" => 20 } }])
        expect(code).to include("length: { maximum: 20, allow_blank: true }")
      end

      it "length_minimum without config falls back to default (line 114)" do
        code = generate_for([{ "type" => "length_minimum" }])
        expect(code).to include("length:")
      end
    end

    context "format_custom without config falls back to default (line 125)" do
      it "returns default empty-regex code when no pattern supplied" do
        code = generate_for([{ "type" => "format_custom" }])
        expect(code).to include("format:")
      end
    end

    context "inclusion / exclusion with newline-delimited string values (lines 127-133)" do
      it "splits string values on newlines for inclusion" do
        code = generate_for([{ "type" => "inclusion", "config" => { "values" => "a\nb\nc" } }])
        expect(code).to include('inclusion: { in: ["a", "b", "c"], allow_blank: true }')
      end

      it "splits string values on newlines for exclusion" do
        code = generate_for([{ "type" => "exclusion", "config" => { "values" => "x\ny" } }])
        expect(code).to include('exclusion: { in: ["x", "y"], allow_blank: true }')
      end

      it "falls back to default inclusion when no values config (line 132)" do
        code = generate_for([{ "type" => "inclusion" }])
        expect(code).to include("inclusion:")
      end
    end

    context "unknown / nil validator type (lines 93, 137-139)" do
      it "returns nil for a non-Hash, non-String validator (line 138)" do
        schema = [{ "name" => "f", "name_slug" => "f", "type" => "Types::String", "validators" => [42] }]
        entity = create(:entity, name: "IntValidator", property_schema: schema.to_json)
        # 42 is neither a String nor a Hash — build_validator_option returns nil, no crash
        expect { described_class.new(entity).generate }.not_to raise_error
      end

      it "returns nil when Hash type key is missing from VALIDATORS_CODE (line 93)" do
        code = generate_for([{ "type" => "nonexistent_validator" }])
        expect(code).to be_present  # generates without crashing
      end
    end

    context "else branch for registered but uncategorised validator types (line 135)" do
      it "dispatches acceptance validator via the else branch" do
        code = generate_for([{ "type" => "acceptance" }])
        expect(code).to include("acceptance:")
      end

      it "dispatches numericality_integer validator via the else branch" do
        code = generate_for([{ "type" => "numericality_integer" }])
        expect(code).to include("numericality:")
      end
    end
  end

  describe "format_custom regex pattern safety" do
    let(:malicious_schema) do
      [
        {
          "name" => "code",
          "name_slug" => "code",
          "type" => "Types::String",
          "validators" => [
            { "type" => "format_custom", "config" => { "pattern" => '/.+#{system("id")}.+/' } }
          ]
        }
      ]
    end

    let(:malicious_entity) do
      create(:entity, name: "Regex Inject", property_schema: malicious_schema.to_json)
    end

    it "embeds the pattern as a String literal (compiled via Regexp.new) so user input cannot inject Ruby" do
      code = described_class.new(malicious_entity).generate
      # Before the fix this would produce `format: { with: /...#{system("id")}.../ }`
      # — a Ruby regex literal that evaluates the interpolation at load
      # time. The generator now emits `Regexp.new(...)` over an inspected
      # string literal.
      expect(code).to include("Regexp.new")
      expect(code).not_to match(%r{format:\s*\{\s*with:\s*/.*\#\{system})
    end

    it "produces source that is parseable Ruby" do
      code = described_class.new(malicious_entity).generate
      expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
    end
  end

  # -----------------------------------------------------------------------
  # Branch-coverage additions — covers the remaining :else/:then arms not
  # reached by the scenarios above.
  # -----------------------------------------------------------------------

  describe "build_validator_option — remaining branch coverage" do
    it "VALIDATORS_CODE[key].call returns nil for unknown old-format string key (safe-nav else, line 87)" do
      # Old-format string that is NOT in VALIDATORS_CODE — safe-nav &.call returns nil,
      # build_validator_option returns nil, and the attribute is emitted without validates:.
      code = generate_for(["nonexistent_old_key"])
      # The field is still emitted, just without a validates: block
      expect(code).to include("property_accessor :f\n")
    end

    it "Hash validator with nil type key returns nil (line 90, &. nil branch)" do
      # validator["type"] is nil — validator_type is nil — the `return nil unless …` guard fires
      code = generate_for([{ "config" => {} }])
      expect(code).to include("property_accessor :f\n")
    end

    it "length_in_range with partial config (min present, max absent) falls back to no-arg call (line 102)" do
      code = generate_for([{ "type" => "length_in_range", "config" => { "min" => 2 } }])
      expect(code).to include("length:")
    end

    it "comparison validator with config but no 'value' key falls back to no-arg call (line 108)" do
      code = generate_for([{ "type" => "greater_than", "config" => { "other_key" => 5 } }])
      expect(code).to include("numericality:")
    end

    it "length_minimum with config but no 'value' key falls back to no-arg call (line 114)" do
      code = generate_for([{ "type" => "length_minimum", "config" => { "other_key" => 3 } }])
      expect(code).to include("length:")
    end

    it "inclusion with config but no 'values' key falls back to default inclusion code (line 132)" do
      code = generate_for([{ "type" => "inclusion", "config" => { "other_key" => "x" } }])
      expect(code).to include("inclusion:")
    end
  end

  describe "merge_hash_validator — merge_options :else / :then branches" do
    # Tests the merge logic when multiple numericality constraints are combined.

    it "emits a single bare numericality check when all merged opts are bare 'numericality: true' (line 164 then-branch)" do
      # Two bare numericality validators with no sub-options → merge_hash_validator
      # iterates both opts; both are 'numericality: true' so the merged hash stays empty
      # → returns ["numericality: true"], which then gains allow_blank
      schema = [
        { "name" => "n", "name_slug" => "n", "type" => "Types::Integer",
          "validators" => ["numericality", "numericality"] }
      ]
      entity = create(:entity, name: "MergeBare#{SecureRandom.hex(4)}", property_schema: schema.to_json)
      code   = described_class.new(entity).generate
      expect(code).to include("validates: { numericality: { allow_blank: true } }")
    end
  end

  describe "runtime write-boundary parity" do
    let(:schema) do
      [
        { "name" => "Title", "name_slug" => "title" },
        { "name" => "Hidden", "name_slug" => "hidden", "visibility" => { "admin" => false } },
        { "name" => "Derived", "name_slug" => "derived", "type" => "Calculated",
          "validators" => [{ "type" => "presence" }], "validator_apply" => { "public" => false } },
        { "name" => "Storage", "name_slug" => "storage", "storage" => "computed" }
      ]
    end

    it "emits read-only options while preserving audience validators" do
      expect(code).to include('property_accessor :derived, validates: { presence: true, if: -> { validators_apply_to_audience?(["admin", "member"]) } }, writeable: false, parse: false')
      expect(code).to include('property_accessor :storage, writeable: false, parse: false')
      expect(code).to include("property_accessor :hidden\n")
    end

    it "evaluates generated source with the same read, validation, sync and save behavior as the factory" do
      generated_class = Class.new(EntityEntryContract)
      namespace = Module.new
      namespace.const_set(:EntityEntryContract, generated_class)
      namespace.module_eval(described_class.new(entity, writable_slugs: [:title]).generate)
      generated_class.default_validation_audience = "public"
      runtime_class = EntityEntryContract.build_for(entity, audience: "public", writable_slugs: [:title])
      [generated_class, runtime_class].each do |klass|
        model = EntityEntry.build_for(entity).new(customer: entity.customer)
        contract = klass.new(model)
        expect(contract).to respond_to(:hidden, :derived, :storage)
        expect(contract.validate("title" => "Course", "hidden" => "forged", "derived" => "forged", "storage" => 10)).to be(true)
        expect(contract.derived).to be_nil
        contract.sync
        expect(contract.save).to be(true)
        expect(model.reload.data_json).to eq("title" => "Course")
      end
      generated_class.default_validation_audience = "admin"
      expect(generated_class.new(EntityEntry.build_for(entity).new(customer: entity.customer)).validate("derived" => "forged")).to be(false)
    end
  end

  describe "reserved-property parity" do
    let(:reserved) { EntityEntry.column_names + %w[entity customer] }
    let(:schema) do
      [{ "name" => "Title", "name_slug" => "title" }] +
        reserved.map { |slug| { "name" => slug, "name_slug" => slug } }
    end

    it "emits unconditional read-only flags for all reserved properties" do
      [nil, reserved + ["title"]].each do |write_set|
        source = described_class.new(entity, writable_slugs: write_set).generate
        reserved.each do |slug|
          expect(source).to include("property_accessor :#{slug}, writeable: false, parse: false")
        end
      end
    end

    it "protects real runtime records with evaluated generated and default factory contracts" do
      generated_class = Class.new(EntityEntryContract)
      namespace = Module.new
      namespace.const_set(:EntityEntryContract, generated_class)
      namespace.module_eval(code)
      [generated_class, EntityEntryContract.build_for(entity)].each do |klass|
        model = EntityEntry.build_for(entity).create!(customer: entity.customer, data: { "title" => "Original" }.to_json)
        original = model.attributes.slice(*reserved)
        contract = klass.new(model)
        expect(contract.validate(reserved.index_with { "forged" }.merge("title" => "Allowed", "data" => "[]"))).to be(true)
        contract.sync
        expect(model.attributes.slice(*(reserved - ["data"]))).to eq(original.except("data"))
        expect(model.entity).to eq(entity)
        expect(model.customer).to eq(entity.customer)
        expect(contract.save).to be(true)
        expect(model.reload.data_json).to eq("title" => "Allowed")
        expect(model).to have_attributes(id: original["id"], entity_id: entity.id, customer_id: entity.customer_id)
      end
    end
  end

  describe "audience-scoped validator_apply" do
    let(:schema) do
      [
        {
          "name" => "age",
          "name_slug" => "age",
          "type" => "Types::Integer",
          "validators" => [{ "type" => "presence" }],
          "visibility" => { "admin" => true, "member" => true, "public" => true },
          "validator_apply" => { "admin" => false, "member" => false, "public" => true }
        },
        {
          "name" => "notes",
          "name_slug" => "notes",
          "type" => "Types::String",
          "validators" => [{ "type" => "presence" }],
          "visibility" => { "admin" => true, "member" => true, "public" => true },
          "validator_apply" => { "admin" => true, "member" => true, "public" => true }
        }
      ]
    end

    it "emits an if: guard for validators that apply to a subset of audiences" do
      expect(code).to include('property_accessor :age, validates: {')
      expect(code).to include('if: -> { validators_apply_to_audience?(["public"]) }')
    end

    it "omits if: when validators apply to every audience" do
      expect(code).to include("property_accessor :notes, validates: { presence: true }")
      expect(code).not_to match(/property_accessor :notes, validates: \{[^}]*if:/)
    end

    it "intersects visibility with validator_apply" do
      schema.first["visibility"] = { "admin" => true, "member" => true, "public" => false }
      schema.first["validator_apply"] = { "admin" => true, "member" => true, "public" => true }

      expect(code).to include('if: -> { validators_apply_to_audience?(["admin", "member"]) }')
    end

    it "omits validates entirely when no audience applies the validators" do
      schema.first["validator_apply"] = { "admin" => false, "member" => false, "public" => false }

      expect(code).to include("property_accessor :age\n")
      expect(code).not_to match(/property_accessor :age, validates:/)
    end
  end
end
