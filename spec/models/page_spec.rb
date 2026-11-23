require 'rails_helper'

RSpec.describe Page, type: :model do
  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }

  let(:valid_field) do
    {
      'id' => 'field_1',
      'property_slug' => 'email',
      'property_type' => 'string',
      'html_type' => 'text',
      'label' => 'Email Address',
      'placeholder' => 'Enter email',
      'required' => true,
      'width' => 'full',
      'order' => 0
    }
  end

  let(:valid_configuration) do
    {
      'pages' => [
        {
          'id' => 'page_1',
          'name' => 'Page 1',
          'fields' => [valid_field]
        }
      ],
      'metadata' => {
        'entity_id' => entity.id,
        'entity_name' => entity.name,
        'created_at' => Time.current.iso8601
      }
    }
  end

  # A valid page for the shared customer; pass a positional hash to override any
  # attribute (or clear one to nil) to exercise a specific validation.
  def build_page(overrides = {})
    described_class.new({ name: 'Test', configuration: valid_configuration.to_json, customer: customer }.merge(overrides))
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build_page(name: 'Test Page')).to be_valid
    end

    it 'requires a name' do
      page = build_page(name: nil)
      expect(page).not_to be_valid
      expect(page.errors[:name]).to include("can't be blank")
    end

    it 'requires name to be within length limits' do
      page = build_page(name: 'a' * 101)
      expect(page).not_to be_valid
      expect(page.errors[:name]).to include('is too long (maximum is 100 characters)')
    end

    it 'is a platform Shared Resource when customer_id is nil' do
      page = build_page(customer: nil)
      expect(page).to be_shared
    end

    it 'allows a shared page with null customer_id bound to a shared entity' do
      shared_entity = create(:entity, :shared)
      page = build_page(customer: nil, configuration: valid_configuration.merge(
                          "metadata" => {
                            "entity_id" => shared_entity.id,
                            "entity_name" => shared_entity.name
                          }
                        ).to_json)
      expect(page).to be_valid
      expect(page.customer_id).to be_nil
    end

    it 'rejects a shared page bound to a tenant entity' do
      page = build_page(customer: nil)
      expect(page).not_to be_valid
      expect(page.errors[:entity_id]).to be_present
    end

    it 'validates JSON format' do
      page = build_page(configuration: 'invalid json {')
      expect(page).not_to be_valid
      expect(page.errors[:configuration].first).to match(/must be valid JSON:/)
    end

    it 'validates required JSON structure' do
      page = build_page(configuration: { 'fields' => [] }.to_json) # Missing metadata
      expect(page).not_to be_valid
      expect(page.errors[:configuration]).to include('must include metadata')
    end

    it 'is valid with pages format (no top-level fields key)' do
      pages_config = {
        'pages' => [{ 'id' => 'page_1', 'name' => 'Page 1', 'fields' => [] }],
        'metadata' => { 'entity_id' => 1, 'entity_name' => 'Test' }
      }
      expect(build_page(name: 'Pages Format Test', configuration: pages_config.to_json)).to be_valid
    end

    it 'rejects configuration without pages' do
      page = build_page(configuration: { 'metadata' => {} }.to_json)
      expect(page).not_to be_valid
      expect(page.errors[:configuration]).to include('must include pages')
    end

    it 'validates page fields must be an array' do
      invalid_config = {
        'pages' => [{ 'id' => 'page_1', 'name' => 'Page 1', 'fields' => 'not an array' }],
        'metadata' => valid_configuration['metadata']
      }
      page = build_page(configuration: invalid_config.to_json)
      expect(page).not_to be_valid
      expect(page.errors[:configuration]).to include('Page 1 fields must be an array')
    end

    it 'validates metadata must be a hash' do
      invalid_config = valid_configuration.merge('metadata' => 'not a hash')
      page = build_page(configuration: invalid_config.to_json)
      expect(page).not_to be_valid
      expect(page.errors[:configuration]).to include('metadata must be an object')
    end

    it 'rejects configuration JSON that is not an object' do
      page = build_page(configuration: 'true')
      expect(page).not_to be_valid
      expect(page.errors[:configuration]).to include('must be a JSON object')
    end

    it 'allows duplicate page names for the same customer' do
      described_class.create!(name: 'Test', configuration: valid_configuration.to_json, customer: customer)
      page = build_page(name: 'Test')
      expect(page).to be_valid
      expect { page.save! }.not_to raise_error
    end
  end

  describe 'scopes' do
    let!(:old_page) { described_class.create!(name: 'Old', configuration: valid_configuration.to_json, customer: customer, created_at: 1.week.ago, updated_at: 1.week.ago) }
    let!(:new_page) { described_class.create!(name: 'New', configuration: valid_configuration.to_json, customer: customer, created_at: 1.day.ago, updated_at: 1.day.ago) }

    describe '.recent' do
      it 'orders pages by updated_at descending' do
        expect(described_class.recent.pluck(:name)).to eq(['New', 'Old'])
      end
    end

    describe '.by_name' do
      it 'orders pages by name ascending' do
        expect(described_class.by_name.pluck(:name)).to eq(['New', 'Old'])
      end
    end

    describe '.search_by_name' do
      it 'finds pages by name' do
        expect(described_class.search_by_name('Old').pluck(:name)).to eq(['Old'])
      end

      it 'returns all when query is blank' do
        expect(described_class.search_by_name('').count).to eq(2)
      end

      it 'is case insensitive' do
        expect(described_class.search_by_name('OLD').pluck(:name)).to eq(['Old'])
      end
    end
  end

  describe 'JSON serialization' do
    let(:page) { described_class.new(name: 'Test', configuration: valid_configuration.to_json, customer: customer) }

    describe '#configuration_json' do
      it 'parses JSON configuration' do
        # After migration, rules and calculations are added
        expected = valid_configuration.merge('rules' => [], 'calculations' => [])
        expect(page.configuration_json).to eq(expected)
      end

      it 'returns default value for invalid JSON' do
        page.configuration = 'invalid json'
        expect(page.configuration_json).to eq({ "pages" => [], "metadata" => {} })
      end

      it 'returns default value when JSON is a non-object' do
        page.configuration = 'true'
        expect(page.configuration_json).to eq({ "pages" => [], "metadata" => {} })
      end
    end

    describe '#configuration_json=' do
      it 'sets configuration as JSON string' do
        new_config = { 'test' => 'value' }
        page.configuration_json = new_config
        expect(page.configuration).to eq(new_config.to_json)
      end
    end
  end

  describe 'utility methods' do
    let(:page) { described_class.new(name: 'Test', configuration: valid_configuration.to_json, customer: customer) }

    describe '#fields' do
      it 'returns fields from all pages' do
        expect(page.fields).to eq([valid_field])
      end

      it "returns empty array when no pages" do
        config = valid_configuration.merge('pages' => nil)
        page.configuration_json = config
        expect(page.fields).to eq([])
      end

      it "skips null page slots instead of raising" do
        config = valid_configuration.merge(
          "pages" => [nil, { "id" => "page_1", "fields" => [{ "id" => "f1", "label" => "Field 1" }] }]
        )
        page.configuration_json = config
        expect(page.fields).to eq([{ "id" => "f1", "label" => "Field 1" }])
      end

      it 'returns fields from multiple pages' do
        pages_config = {
          'pages' => [
            { 'id' => 'page_1', 'fields' => [{ 'id' => 'f1', 'label' => 'Field 1' }] },
            { 'id' => 'page_2', 'fields' => [{ 'id' => 'f2', 'label' => 'Field 2' }] }
          ],
          'metadata' => { 'entity_id' => 1, 'entity_name' => 'Test' },
          'rules' => [],
          'calculations' => []
        }
        page.configuration_json = pages_config
        expect(page.fields.length).to eq(2)
        expect(page.fields.map { |f| f['id'] }).to eq(%w[f1 f2])
      end
    end

    describe '#metadata' do
      it 'returns metadata hash' do
        expect(page.metadata).to eq(valid_configuration['metadata'])
      end

      it 'returns empty hash when no metadata' do
        config = valid_configuration.merge('metadata' => nil)
        page.configuration_json = config
        expect(page.metadata).to eq({})
      end
    end
  end

  describe 'name_slug removal' do
    it 'does not respond to name_slug' do
      page = described_class.new(
        name: 'My Test Page',
        configuration: valid_configuration.to_json,
        customer: customer
      )
      expect(page).not_to respond_to(:name_slug)
    end
  end

  describe 'soft delete' do
    let!(:page) { described_class.create!(name: 'Test', configuration: valid_configuration.to_json, customer: customer) }

    it 'soft deletes the page' do
      page.soft_delete
      expect(page.reload.status).to eq('inactive')
    end

    it 'hides soft deleted pages from default scope' do
      page.soft_delete
      expect(described_class.exists?(page.id)).to be false
    end

    it 'can find soft deleted pages with only_deleted' do
      page.soft_delete
      expect(described_class.only_deleted.exists?(page.id)).to be true
    end

    it 'can restore soft deleted pages' do
      page.soft_delete
      page.restore
      expect(page.reload.status).to eq('active')
    end
  end

  describe '#configuration_json defaults' do
    context 'with existing rules' do
      let(:config_with_rules) do
        {
          'pages' => [{ 'id' => 'page_1', 'fields' => [{ 'id' => 'f1', 'property_type' => 'string' }] }],
          'metadata' => {},
          'rules' => [{
            'id' => 'rule_1',
            'enabled' => true,
            'conditions' => { 'logic' => 'all', 'groups' => [] },
            'actions' => [{ 'type' => 'show_field', 'target_id' => 'f1' }]
          }],
          'calculations' => []
        }
      end

      let(:page) { create(:page, configuration: config_with_rules.to_json) }

      it 'preserves existing rules' do
        config = page.configuration_json
        expect(config['rules'].length).to eq(1)
      end
    end

    context 'without rules or calculations keys' do
      let(:clean_config) do
        {
          'pages' => [{ 'id' => 'page_1', 'fields' => [{ 'id' => 'f1' }] }],
          'metadata' => {}
        }
      end

      let(:page) { create(:page, configuration: clean_config.to_json) }

      it 'initializes empty rules and calculations arrays' do
        config = page.configuration_json
        expect(config['rules']).to eq([])
        expect(config['calculations']).to eq([])
      end
    end
  end

  describe '.new_with_defaults' do
    it 'creates page with default configuration' do
      page = described_class.new_with_defaults(name: 'Test', customer: customer)

      expect(page.name).to eq('Test')
      expect(page.configuration).to be_present
      config = JSON.parse(page.configuration)
      expect(config['pages']).to be_an(Array)
      expect(config['pages'].first['fields']).to eq([])
      expect(config['metadata']).to be_a(Hash)
      expect(config['metadata']['created_at']).to be_present
    end

    it 'merges provided attributes with defaults' do
      page = described_class.new_with_defaults(name: 'Test', description: 'Test description', customer: customer)

      expect(page.name).to eq('Test')
      expect(page.description).to eq('Test description')
      expect(page.configuration).to be_present
    end
  end

  describe '#generate_content' do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [{ "name_slug" => "email", "type" => "String" }].to_json)
    end
    around { |example| Current.set(customer: customer, user: nil, shared_resources_mode: false) { example.run } }
    let(:page) { described_class.new(name: 'Test', configuration: valid_configuration.to_json, customer: customer) }

    it 'generates ERB template content' do
      content = page.generate_content
      expect(content).to include('FormFields::TextFieldComponent')
      expect(content).to include('field_name: "email"')
      expect(content).to include('label: "Email Address"')
    end
  end

  describe 'rules validation' do
    it 'validates rule has required id' do
      config = {
        'pages' => [], 'fields' => [], 'metadata' => {},
        'rules' => [{ 'enabled' => true, 'conditions' => {}, 'actions' => [] }]
      }
      page = build(:page, customer: customer, configuration: config.to_json)

      expect(page).not_to be_valid
      expect(page.errors[:configuration].join).to include('id')
    end

    it 'validates rule has conditions' do
      config = {
        'pages' => [], 'fields' => [], 'metadata' => {},
        'rules' => [{ 'id' => 'r1', 'enabled' => true, 'actions' => [] }]
      }
      page = build(:page, customer: customer, configuration: config.to_json)

      expect(page).not_to be_valid
      expect(page.errors[:configuration].join).to include('conditions')
    end

    it 'validates rule has actions' do
      config = {
        'pages' => [], 'fields' => [], 'metadata' => {},
        'rules' => [{ 'id' => 'r1', 'enabled' => true, 'conditions' => {} }]
      }
      page = build(:page, customer: customer, configuration: config.to_json)

      expect(page).not_to be_valid
      expect(page.errors[:configuration].join).to include('actions')
    end

    it 'accepts valid rule structure' do
      config = {
        'pages' => [{ 'id' => 'page_1', 'fields' => [{ 'id' => 'f1', 'property_type' => 'string' }] }],
        'fields' => [], 'metadata' => {},
        'rules' => [{
          'id' => 'r1',
          'enabled' => true,
          'conditions' => { 'logic' => 'all', 'groups' => [] },
          'actions' => [{ 'type' => 'show_field', 'target_id' => 'f1' }]
        }],
        'calculations' => []
      }
      page = build(:page, customer: customer, configuration: config.to_json)

      expect(page).to be_valid
    end
  end

  describe "audiences and action_key" do
    it "defaults to the admin audience only" do
      page = build(:page, customer: customer)
      expect(page.visible_audiences).to eq(%w[admin])
      expect(page.visible_to?(:admin)).to be(true)
      expect(page.visible_to?(:member)).to be(false)
      expect(page.visible_to?(:public)).to be(false)
    end

    it "requires at least one audience" do
      page = build_page(audience_admin: false, audience_member: false, audience_public: false)
      expect(page).not_to be_valid
      expect(page.errors[:base]).to include(I18n.t("maint_core.errors.validations.page_audiences_blank"))
    end

    it "rejects an invalid action key" do
      page = build_page(action_key: "Enroll")
      expect(page).not_to be_valid
      expect(page.errors[:action_key]).to include(I18n.t("maint_core.errors.validations.page_action_key_invalid"))
    end

    it "stores a blank action key as nil" do
      page = build_page(action_key: "  ")
      expect(page).to be_valid
      expect(page.action_key).to be_nil
    end

    it "accepts a valid action key" do
      expect(build_page(action_key: "enroll")).to be_valid
    end
  end

  describe 'calculations validation' do
    it 'validates calculation has target_field_id' do
      config = {
        'pages' => [], 'fields' => [], 'metadata' => {},
        'rules' => [],
        'calculations' => [{ 'id' => 'c1', 'formula' => 'a + b' }]
      }
      page = build(:page, customer: customer, configuration: config.to_json)

      expect(page).not_to be_valid
      expect(page.errors[:configuration].join).to include('target_field_id')
    end

    it 'validates calculation has formula' do
      config = {
        'pages' => [], 'fields' => [], 'metadata' => {},
        'rules' => [],
        'calculations' => [{ 'id' => 'c1', 'target_field_id' => 'total' }]
      }
      page = build(:page, customer: customer, configuration: config.to_json)

      expect(page).not_to be_valid
      expect(page.errors[:configuration].join).to include('formula')
    end

    it 'accepts valid calculation structure' do
      config = {
        'pages' => [{ 'id' => 'page_1', 'fields' => [
          { 'id' => 'total',    'property_type' => 'number' },
          { 'id' => 'price',    'property_type' => 'number' },
          { 'id' => 'quantity', 'property_type' => 'number' }
        ] }],
        'fields' => [], 'metadata' => {},
        'rules' => [],
        'calculations' => [{
          'id' => 'c1',
          'target_field_id' => 'total',
          'formula' => '{price} * {quantity}'
        }]
      }
      page = build(:page, customer: customer, configuration: config.to_json)

      expect(page).to be_valid
    end
  end
end

RSpec.describe Page, "#hands_off?" do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "returns false when the bound flowchart has no module handoff step" do
    page = create(:page, customer: customer)
    expect(page.hands_off?).to be false
  end

  it "returns true when the bound flowchart has a hand_off_to_module step" do
    page = create(:page, customer: customer)
    bind_page_flowchart(page, steps: [{
      "action" => "hand_off_to_module",
      "config" => { "moduleKey" => "payment", "input" => [] }
    }])
    expect(page.reload.hands_off?).to be true
  end
end

RSpec.describe Page, "form_settings leftover after_submit" do
  let(:customer) { create(:customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "does not validate leftover after_submit or handoff keys" do
    page = build(:page, customer: customer,
                 configuration: {
                   pages: [{ id: "page_1", name: "Page 1", order: 1, fields: [] }],
                   metadata: {},
                   form_settings: { after_submit: "handoff", handoff: { module_key: "nonsense" } }
                 }.to_json)
    expect(page).to be_valid
  end
end

RSpec.describe Page, "searchable and sortable field keys" do
  describe "#searchable_field_keys" do
    it "defaults to name and description" do
      expect(described_class.new.searchable_field_keys).to eq(%w[name description])
    end
  end

  describe "#sortable_field_keys" do
    it "includes name, description, created_at, updated_at" do
      expect(described_class.new.sortable_field_keys).to eq(%w[name description created_at updated_at])
    end
  end
end

RSpec.describe Page, "#captcha_enabled?" do
  let(:page) { create(:page) }

  it "returns false when configuration_json has no captcha key" do
    expect(page.captcha_enabled?).to eq(false)
  end

  it "returns true when configuration_json[captcha][enabled] is true" do
    page.captcha_enabled = true
    page.save!(validate: false)
    expect(page.reload.captcha_enabled?).to eq(true)
  end

  it "returns false when explicitly disabled" do
    page.captcha_enabled = false
    page.save!(validate: false)
    expect(page.reload.captcha_enabled?).to eq(false)
  end
end

RSpec.describe Page, "configuration validation" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  def base_metadata
    { "entity_id" => entity.id, "entity_name" => entity.name }
  end

  it "is invalid when a calculation references an unknown field" do
    page = build(:page, customer: customer, entity: entity)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [{ "id" => "qty", "property_type" => "number" }] }],
      "metadata" => base_metadata,
      "calculations" => [{ "id" => "c1", "target_field_id" => "qty", "formula" => "{ghost} + 1" }]
    }
    expect(page).not_to be_valid
    expect(page.errors[:configuration].join).to match(/unknown field 'ghost'/i)
  end

  it "is invalid when a rule condition references an unknown field" do
    page = build(:page, customer: customer, entity: entity)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [{ "id" => "price", "property_type" => "number" }] }],
      "metadata" => base_metadata,
      "rules" => [{ "id" => "r1", "enabled" => true,
                    "conditions" => { "logic" => "all", "groups" => [
                      { "logic" => "all", "items" => [
                        { "field_id" => "ghost", "operator" => "equals", "value" => "x" }
                      ] }
                    ] },
                    "actions" => [{ "type" => "show_field", "target_id" => "price" }] }]
    }
    expect(page).not_to be_valid
    expect(page.errors[:configuration].join).to match(/unknown field 'ghost'/i)
  end

  it "is invalid when calculations form a circular dependency" do
    page = build(:page, customer: customer, entity: entity)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [
        { "id" => "price", "property_type" => "number" },
        { "id" => "qty",   "property_type" => "number" }
      ] }],
      "metadata" => base_metadata,
      "calculations" => [
        { "id" => "c1", "target_field_id" => "price", "formula" => "{qty} + 1" },
        { "id" => "c2", "target_field_id" => "qty",   "formula" => "{price} + 1" }
      ]
    }
    expect(page).not_to be_valid
    expect(page.errors[:configuration].join).to match(/circular/i)
  end

  it "is valid when all referenced fields exist" do
    page = build(:page, customer: customer, entity: entity)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [
        { "id" => "qty",   "property_type" => "number" },
        { "id" => "price", "property_type" => "number" }
      ] }],
      "metadata" => base_metadata,
      "calculations" => [{ "id" => "c1", "target_field_id" => "price", "formula" => "{qty} * 10" }]
    }
    expect(page).to be_valid
  end
end

RSpec.describe Page, "#entity_id= branches" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "clears entity_id and entity_name when value is nil" do
    page = build(:page, customer: customer, entity: entity)
    page.entity_id = nil
    config = page.configuration_json
    expect(config.dig("metadata", "entity_id")).to be_nil
    expect(config.dig("metadata", "entity_name")).to be_nil
  end

  it "clears entity_id and entity_name when value is empty string" do
    page = build(:page, customer: customer, entity: entity)
    page.entity_id = ""
    config = page.configuration_json
    expect(config.dig("metadata", "entity_id")).to be_nil
  end

  it "sets entity_id when a valid integer string is given" do
    page = build(:page, customer: customer)
    page.entity_id = entity.id.to_s
    expect(page.entity_id).to eq(entity.id)
    expect(page.configuration_json.dig("metadata", "entity_name")).to eq(entity.name)
  end

  it "sets entity_id when entity not found (nil entity, still stores the id)" do
    page = build(:page, customer: customer)
    page.entity_id = 99999999
    expect(page.entity_id).to eq(99999999)
    # entity not found → entity_name nil
    expect(page.configuration_json.dig("metadata", "entity_name")).to be_nil
  end
end

RSpec.describe Page, "#launch! and #launchable?" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  def launchable_page
    page = create(:page, customer: customer, entity: entity)
    config = page.configuration_json
    config["pages"] = [{ "id" => "p1", "name" => "Page 1", "order" => 1, "fields" => [
      { "id" => "f1", "label" => "Name", "property_type" => "string" }
    ] }]
    config["metadata"] = { "entity_id" => entity.id, "entity_name" => entity.name }
    page.configuration_json = config
    page.save!(validate: false)
    page
  end

  it "launchable? returns true when no launch errors" do
    page = launchable_page
    expect(page.launchable?).to be true
  end

  it "launch! sets launched = true" do
    page = launchable_page
    page.launch!
    expect(page.reload.launched).to be true
  end

  it "launch! raises when entity is missing" do
    page = create(:page, customer: customer)
    page.instance_variable_set(:@entity, nil)
    allow(page).to receive(:entity).and_return(nil)
    expect { page.launch! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "lists entity_missing when the bound entity has been soft-deleted" do
    page = launchable_page
    entity.soft_delete
    expect(page.launch_errors).to include(I18n.t("maint_core.errors.page_launch.entity_missing"))
    expect(page.launchable?).to be false
  end

  it "lists I18n launch errors for a missing entity and empty fields" do
    page = create(:page, customer: customer)
    allow(page).to receive(:entity).and_return(nil)
    expect(page.launch_errors).to include(
      I18n.t("maint_core.errors.page_launch.entity_missing"),
      I18n.t("maint_core.errors.page_launch.no_fields")
    )
  end

  it "take_offline! sets launched = false" do
    page = launchable_page
    page.update_column(:launched, true)
    page.take_offline!
    expect(page.reload.launched).to be false
  end

  it "refuses to launch a public form bound to an owned entity" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    learner = create(:entity, customer: customer, name: "Learner", extended_model: person_model,
                     property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    owned = create(:entity, customer: customer, name: "Homework", display_label: "Homework",
                   property_schema: [
                     { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
                     { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
                       "config" => { "options_source" => "entity_entries", "entity_id" => learner.id.to_s,
                                     "label_field" => "name" } }
                   ].to_json)
    page = create(:page, :for_member, :for_public, customer: customer, entity: owned)
    config = page.configuration_json
    config["pages"] = [{ "id" => "p1", "name" => "Page 1", "order" => 1, "fields" => [
      { "id" => "f1", "label" => "Title", "property_slug" => "title", "property_type" => "string", "source" => "entity" }
    ] }]
    config["metadata"] = { "entity_id" => owned.id, "entity_name" => owned.name }
    page.configuration_json = config
    page.save!(validate: false)

    expect(page.launch_errors).to include(
      I18n.t("maint_core.errors.page_launch.owned_entity_public_audience", entity: "Homework")
    )
    expect { page.launch! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(page.reload.launched).to be(false)
  end

  it "launches a member form bound to an owned entity when other checks pass" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    learner = create(:entity, customer: customer, name: "Learner", extended_model: person_model,
                     property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    owned = create(:entity, customer: customer, name: "Homework", display_label: "Homework",
                   property_schema: [
                     { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
                     { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
                       "config" => { "options_source" => "entity_entries", "entity_id" => learner.id.to_s,
                                     "label_field" => "name" } }
                   ].to_json)
    page = create(:page, :for_member, customer: customer, entity: owned)
    config = page.configuration_json
    config["pages"] = [{ "id" => "p1", "name" => "Page 1", "order" => 1, "fields" => [
      { "id" => "f1", "label" => "Title", "property_slug" => "title", "property_type" => "string", "source" => "entity" }
    ] }]
    config["metadata"] = { "entity_id" => owned.id, "entity_name" => owned.name }
    page.configuration_json = config
    page.save!(validate: false)

    expect(page.launch_errors).to eq([])
    page.launch!
    expect(page.reload.launched).to be(true)
  end
end

RSpec.describe Page, "configuration_must_be_valid_json non-String branch" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  it "adds a 'must be a JSON string' error when configuration is a Hash object" do
    page = build(:page, customer: customer, entity: entity)
    # AR text columns always return a String, so the non-String guard is a
    # defensive branch. Stub the reader to return a Hash to exercise it.
    allow(page).to receive(:configuration).and_return({ "pages" => [], "metadata" => {} })
    page.valid?
    expect(page.errors[:configuration]).to include("must be a JSON string")
  end
end

RSpec.describe Page, "#reload clears configuration memo" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  it "re-parses configuration after reload" do
    Current.customer = customer
    page = create(:page, customer: customer, entity: entity)
    # Access config to populate the memo
    original = page.configuration_json
    expect(original).to be_a(Hash)

    # configuration is a virtual attribute backed by the head version's
    # content, not a DB column, so `update_column(:configuration, ...)` is no
    # longer valid. Commit a new head version through a second in-memory copy
    # of the same row, without touching the first page's in-memory state.
    new_config = original.merge("pages" => [{ "id" => "p99", "name" => "Reloaded", "order" => 1, "fields" => [] }])
    twin = described_class.find(page.id)
    twin.configuration = new_config.to_json
    twin.save!

    # After reload the memo should be cleared and re-parsed from the new head content
    page.reload
    expect(page.configuration_json["pages"].first["id"]).to eq("p99")
  ensure
    Current.customer = nil
  end
end

RSpec.describe Page, "orphan_rule_errors rule name vs id fallback" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "uses rule['name'] when present in the error message" do
    page = build(:page, customer: customer, entity: entity)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [{ "id" => "price", "property_type" => "number" }] }],
      "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name },
      "rules" => [{
        "id" => "r1", "name" => "My Rule", "enabled" => true,
        "conditions" => { "logic" => "all", "groups" => [] },
        "actions" => [{ "type" => "show_field", "target_id" => "ghost_field" }]
      }]
    }
    errors = page.launch_errors
    expect(errors.join).to include("My Rule").and include("ghost_field")
  end

  it "falls back to rule['id'] when name is absent" do
    page = build(:page, customer: customer, entity: entity)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [{ "id" => "price", "property_type" => "number" }] }],
      "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name },
      "rules" => [{
        "id" => "r99", "enabled" => true,
        "conditions" => { "logic" => "all", "groups" => [] },
        "actions" => [{ "type" => "show_field", "target_id" => "ghost_field" }]
      }]
    }
    errors = page.launch_errors
    expect(errors.join).to include("r99").and include("ghost_field")
  end
end

RSpec.describe Page, "orphan_calculation_errors name vs id fallback" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  it "uses calc['name'] when present in the error message" do
    page = build(:page, customer: customer, entity: entity)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [{ "id" => "price", "property_type" => "number" }] }],
      "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name },
      "calculations" => [{
        "id" => "c1", "name" => "My Calc", "target_field_id" => "ghost_target", "formula" => "{price} * 2"
      }]
    }
    errors = page.launch_errors
    expect(errors.join).to include("My Calc")
  end

  it "uses calc['id'] when name is absent" do
    page = build(:page, customer: customer, entity: entity)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [{ "id" => "price", "property_type" => "number" }] }],
      "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name },
      "calculations" => [{
        "id" => "c99", "target_field_id" => "ghost_target", "formula" => "{price} * 2"
      }]
    }
    errors = page.launch_errors
    expect(errors.join).to include("c99")
  end
end

RSpec.describe Page, "#visible_audiences with no audience selected" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  it "returns an empty array when every audience boolean is off" do
    page = build(:page, customer: customer, entity: entity)
    page.visible_audiences = []
    expect(page.visible_audiences).to eq([])
  end
end

RSpec.describe Page, "#launch_errors" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  def page_with(rules: [])
    page = create(:page, customer: customer, entity: entity)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [
        { "id" => "qty",   "property_type" => "number" },
        { "id" => "price", "property_type" => "number" }
      ] }],
      "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name },
      "rules" => rules
    }
    page
  end

  # Regression: orphan_rule_errors used to assume conditions was an array of
  # groups (Array(hash) explodes a hash into key/value pairs → TypeError) and
  # actions used "target_field_id" instead of the engine's "target_id".
  it "accepts the canonical rule shape (grouped conditions hash, action target_id)" do
    page = page_with(rules: [{
      "id" => "r1", "name" => "canonical", "enabled" => true,
      "conditions" => { "logic" => "all", "groups" => [
        { "logic" => "all", "items" => [
          { "field_id" => "qty", "operator" => "equals", "value" => 1 }
        ] }
      ] },
      "actions" => [{ "type" => "set_value", "target_id" => "price", "value" => "10" }]
    }])
    expect(page.launch_errors).to be_empty
  end

  it "reports a rule whose condition references a deleted field" do
    page = page_with(rules: [{
      "id" => "r1", "name" => "stale condition", "enabled" => true,
      "conditions" => { "logic" => "all", "groups" => [
        { "logic" => "all", "items" => [
          { "field_id" => "ghost", "operator" => "equals", "value" => 1 }
        ] }
      ] },
      "actions" => []
    }])
    expect(page.launch_errors.join).to include("stale condition")
      .and include("ghost")
  end

  it "reports a rule whose action targets a deleted field" do
    page = page_with(rules: [{
      "id" => "r1", "name" => "stale action", "enabled" => true,
      "conditions" => { "logic" => "all", "groups" => [] },
      "actions" => [{ "type" => "set_value", "target_id" => "ghost", "value" => "x" }]
    }])
    expect(page.launch_errors.join).to include("stale action")
      .and include("ghost")
  end
end
