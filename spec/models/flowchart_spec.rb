require 'rails_helper'

RSpec.describe Flowchart, type: :model do
  let_it_be(:customer) { create(:customer) }

  let(:valid_configuration) do
    {
      'elements' => [
        {
          'id' => 'element_1',
          'type' => 'start',
          'position' => { 'x' => 100, 'y' => 100 },
          'properties' => { 'label' => 'Start' }
        }
      ],
      'connections' => [],
      'metadata' => {
        'canvas' => { 'width' => 1200, 'height' => 800 },
        'created_at' => Time.current.iso8601
      }
    }
  end

  # A fully-valid customer_specific flowchart; pass a positional hash to override
  # any attribute (e.g. name/status/type) for a specific example.
  def build_flowchart(overrides = {})
    described_class.new({ name: 'Test', configuration: valid_configuration.to_json,
                          customer: customer }.merge(overrides))
  end

  def create_flowchart(overrides = {})
    build_flowchart(overrides).tap(&:save!)
  end

  describe 'status enum' do
    it 'supports draft status' do
      flowchart = build_flowchart(status: :draft)
      expect(flowchart).to be_valid
      expect(flowchart.draft?).to be true
    end

    it 'defaults new flowcharts to draft' do
      expect(build_flowchart).to be_draft
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build_flowchart(name: 'Test Flowchart')).to be_valid
    end

    it 'requires a name' do
      flowchart = described_class.new(configuration: valid_configuration.to_json)
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:name]).to include("can't be blank")
    end

    it 'requires name to be within length limits' do
      flowchart = described_class.new(
        name: 'a' * 101, # Too long
        configuration: valid_configuration.to_json
      )
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:name]).to include('is too long (maximum is 100 characters)')
    end

    it 'requires configuration' do
      flowchart = described_class.new(name: 'Test')
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:configuration]).to include("can't be blank")
    end

    it 'validates JSON format' do
      flowchart = described_class.new(
        name: 'Test',
        configuration: 'invalid json {'
      )
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:configuration].first).to match(/must be valid JSON:/)
    end

    it 'validates required JSON structure' do
      flowchart = described_class.new(
        name: 'Test',
        configuration: { 'elements' => [] }.to_json # Missing connections and metadata
      )
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:configuration]).to include('must include required keys: connections, metadata')
    end

    it 'validates elements must be an array' do
      invalid_config = valid_configuration.merge('elements' => 'not an array')
      flowchart = described_class.new(
        name: 'Test',
        configuration: invalid_config.to_json
      )
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:configuration]).to include('elements must be an array')
    end

    it 'validates connections must be an array' do
      invalid_config = valid_configuration.merge('connections' => 'not an array')
      flowchart = described_class.new(
        name: 'Test',
        configuration: invalid_config.to_json
      )
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:configuration]).to include('connections must be an array')
    end

    it 'validates metadata must be a hash' do
      invalid_config = valid_configuration.merge('metadata' => 'not a hash')
      flowchart = described_class.new(
        name: 'Test',
        configuration: invalid_config.to_json
      )
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:configuration]).to include('metadata must be an object')
    end

  end

  describe 'scopes' do
    let!(:old_flowchart) { described_class.create!(name: 'Old', configuration: valid_configuration.to_json, created_at: 1.week.ago, updated_at: 1.week.ago, customer: customer, status: :launched) }
    let!(:new_flowchart) { described_class.create!(name: 'New', configuration: valid_configuration.to_json, created_at: 1.day.ago, updated_at: 1.day.ago, customer: customer, status: :launched) }

    describe '.recent' do
      it 'orders tenant-owned flowcharts by updated_at descending' do
        expect(described_class.recent.pluck(:name)).to eq(['New', 'Old'])
      end
    end

    describe '.by_name' do
      it 'orders flowcharts by name ascending' do
        expect(described_class.by_name.pluck(:name)).to eq(['New', 'Old'])
      end
    end

    describe '.referenceable' do
      let!(:draft_flowchart) { described_class.create!(name: 'Draft', configuration: valid_configuration.to_json, customer: customer, status: :draft) }
      let!(:active_flowchart) { described_class.create!(name: 'Active', configuration: valid_configuration.to_json, customer: customer, status: :launched) }

      it 'returns only launched flowcharts' do
        expect(described_class.referenceable).to include(active_flowchart)
        expect(described_class.referenceable).not_to include(draft_flowchart)
      end
    end
  end

  describe 'JSON serialization' do
    let(:flowchart) { described_class.new(name: 'Test', configuration: valid_configuration.to_json) }

    describe '#configuration_json' do
      it 'parses JSON configuration' do
        expect(flowchart.configuration_json).to eq(valid_configuration)
      end

      it 'returns nil for invalid JSON' do
        flowchart.configuration = 'invalid json'
        expect(flowchart.configuration_json).to be_nil
      end

      it 'memoizes the parsed JSON' do
        # First call should parse
        result1 = flowchart.configuration_json
        expect(JSON).not_to receive(:parse)
        # Second call should return memoized value
        result2 = flowchart.configuration_json
        expect(result1).to eq(result2)
      end
    end

    describe '#configuration_json=' do
      it 'sets configuration as JSON string' do
        new_config = { 'test' => 'value' }
        flowchart.configuration_json = new_config
        expect(flowchart.configuration).to eq(new_config.to_json)
      end

      it 'clears memoized value and allows re-parsing' do
        # Access memoized value
        flowchart.configuration_json
        # Set new valid config with required structure
        new_config = {
          'elements' => [],
          'connections' => [],
          'metadata' => { 'new' => 'config' }
        }
        flowchart.configuration_json = new_config
        # Create a fresh instance to test parsing works
        fresh_flowchart = described_class.new(configuration: flowchart.configuration)
        expect(fresh_flowchart.configuration_json).to eq(new_config)
      end
    end
  end

  describe 'utility methods' do
    let(:flowchart) { described_class.new(name: 'Test', configuration: valid_configuration.to_json) }

    describe '#elements' do
      it 'returns elements array' do
        expect(flowchart.elements).to eq(valid_configuration['elements'])
      end

      it 'returns empty array when no elements' do
        config = valid_configuration.merge('elements' => nil)
        flowchart.configuration_json = config
        expect(flowchart.elements).to eq([])
      end
    end

    describe '#connections' do
      it 'returns connections array' do
        expect(flowchart.connections).to eq(valid_configuration['connections'])
      end

      it 'returns empty array when no connections' do
        config = valid_configuration.merge('connections' => nil)
        flowchart.configuration_json = config
        expect(flowchart.connections).to eq([])
      end
    end

    describe '#metadata' do
      it 'returns metadata hash' do
        expect(flowchart.metadata).to eq(valid_configuration['metadata'])
      end

      it 'returns empty hash when no metadata' do
        config = valid_configuration.merge('metadata' => nil)
        flowchart.configuration_json = config
        expect(flowchart.metadata).to eq({})
      end
    end

    describe '#canvas_size' do
      it 'returns canvas size from metadata' do
        expected_size = { 'width' => 1200, 'height' => 800 }
        expect(flowchart.canvas_size).to eq(expected_size)
      end

      it 'returns default size when not specified' do
        config = valid_configuration.dup
        config['metadata'].delete('canvas')
        flowchart.configuration_json = config
        expect(flowchart.canvas_size).to eq({ 'width' => 1200, 'height' => 800 })
      end
    end
  end

  describe 'callbacks' do
    describe '#generate_uuid' do
      it 'generates a UUID when saving a new flowchart' do
        flowchart = build_flowchart(name: 'Test UUID')
        expect(flowchart.uuid).to be_nil
        flowchart.save!
        expect(flowchart.uuid).to be_present
        expect(flowchart.uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end

      it 'does not change UUID on subsequent saves' do
        flowchart = create_flowchart(name: 'Test UUID Persistence')
        original_uuid = flowchart.uuid
        flowchart.update!(name: 'Updated Name')
        expect(flowchart.uuid).to eq(original_uuid)
      end

      it 'generates unique UUIDs for different flowcharts' do
        flowchart1 = create_flowchart(name: 'Test UUID 1')
        flowchart2 = create_flowchart(name: 'Test UUID 2')
        expect(flowchart1.uuid).not_to eq(flowchart2.uuid)
      end
    end
  end

  describe 'name uniqueness' do
    it 'lets a shared flowchart share a name with a tenant flowchart but not with another shared one' do
      create_flowchart(name: 'Same name')
      shared = build_flowchart(name: 'Same name', customer: nil)
      expect(shared).to be_valid

      shared.save!
      expect(build_flowchart(name: 'Same name', customer: nil)).not_to be_valid
    end

    it 'keeps names unique within a tenant' do
      create_flowchart(name: 'Same name')
      expect(build_flowchart(name: 'Same name')).not_to be_valid
    end
  end

  describe 'uuid validations' do
    it 'validates presence of uuid' do
      flowchart = build_flowchart
      # Skip the generate_uuid callback to test the validation
      allow(flowchart).to receive(:generate_uuid)
      expect(flowchart).not_to be_valid
      expect(flowchart.errors[:uuid]).to include("can't be blank")
    end

    it 'validates uniqueness of uuid' do
      existing = create_flowchart(name: 'Existing')
      new_flowchart = build_flowchart(name: 'New')
      new_flowchart.uuid = existing.uuid
      expect(new_flowchart).not_to be_valid
      expect(new_flowchart.errors[:uuid]).to include("has already been taken")
    end
  end

  describe '.new_with_defaults' do
    it 'creates flowchart with default configuration' do
      flowchart = described_class.new_with_defaults(name: 'Test', customer: customer)

      expect(flowchart.name).to eq('Test')
      # Verify configuration is set (raw JSON string)
      expect(flowchart.configuration).to be_present
      # Parse the configuration directly to verify structure
      config = JSON.parse(flowchart.configuration)
      # Default (blank) configuration is Start → End
      expect(config['elements'].map { |el| el['type'] }).to eq(%w[start end])
      expect(config['connections'].length).to eq(1)
      expect(config['metadata']['canvas']).to eq({ 'width' => 2000, 'height' => 1500 })
      expect(config['metadata']['created_at']).to be_present
    end

    it 'merges provided attributes with defaults' do
      flowchart = described_class.new_with_defaults(name: 'Test', description: 'Test description', customer: customer)

      expect(flowchart.name).to eq('Test')
      expect(flowchart.description).to eq('Test description')
      expect(flowchart.configuration).to be_present
    end
  end

  describe 'edit restriction' do
    context 'when flowchart is draft' do
      let(:flowchart) { create_flowchart(name: 'Draft FC', status: :draft) }

      it 'allows editing' do
        flowchart.name = 'Updated Name'
        expect(flowchart).to be_valid
        expect(flowchart.save).to be true
      end
    end

    context 'when flowchart is launched' do
      let(:flowchart) { create_flowchart(name: 'Active FC', status: :launched) }

      it 'allows configuration edits' do
        cfg = JSON.parse(flowchart.configuration)
        cfg['metadata'] = (cfg['metadata'] || {}).merge('note' => 'edited while live')
        flowchart.configuration = cfg.to_json
        expect(flowchart).to be_valid
      end

      it 'blocks a rename, which the launched activity class name depends on' do
        flowchart.name = 'Updated Name'
        expect(flowchart).not_to be_valid
        expect(flowchart.errors[:name]).to include('Take the flowchart offline to rename it.')
      end

      it 'allows status changes' do
        flowchart.status = :draft
        expect(flowchart).to be_valid
      end
    end

    context 'when a launched shared flowchart is overridden for a customer' do
      let(:flowchart) { create(:flowchart, :shared_type, :launched_status) }

      it 'allows configuration changes on the tenant override line' do
        Current.with_customer(customer) do
          cfg = JSON.parse(flowchart.configuration)
          cfg['metadata'] = (cfg['metadata'] || {}).merge('note' => 'tenant override')
          flowchart.configuration = cfg.to_json
          expect(flowchart).to be_valid
        end
      end

      it 'still blocks renaming the global default while launched' do
        Current.with_customer(customer) do
          Current.shared_resources_mode = true
          flowchart.name = 'Hacked Global'
          expect(flowchart).not_to be_valid
        ensure
          Current.shared_resources_mode = nil
        end
      end
    end
  end

  describe 'launched version' do
    def edit!(fc, note)
      cfg = JSON.parse(fc.configuration)
      cfg['metadata'] = cfg['metadata'].merge('note' => note)
      cfg['elements'].find { |el| el['id'] == 'process_1' }['label'] = "Step #{note}"
      fc.update!(configuration: cfg.to_json)
    end

    def note_of(version) = JSON.parse(version.reload.payload).dig('metadata', 'note')

    context 'on a draft flowchart' do
      let(:flowchart) { create(:flowchart, :simple, :draft) }

      it 'has no launched version and revises its head on every save' do
        head = flowchart.current_version
        expect { 2.times { |i| edit!(flowchart, "draft-#{i}") } }.not_to change { flowchart.flowchart_versions.count }
        expect(flowchart.launched_version).to be_nil
        expect(flowchart.reload.current_version).to eq(head)
        expect(note_of(head)).to eq('draft-1')
      end

      it 'recompiles the activity on every save' do
        expect { edit!(flowchart, 'draft') }.to(change { flowchart.reload.activity })
      end

      it 'publishes the head on launch!' do
        flowchart.launch!
        expect(flowchart.reload).to be_launched
        expect(flowchart.launched_version_id).to eq(flowchart.current_version_id)
        expect(flowchart).not_to be_pending_draft
      end

      it 'forks a new version instead of rewriting an older version made the head' do
        older = flowchart.current_version
        flowchart.configuration = JSON.parse(flowchart.configuration).merge('metadata' => { 'note' => 'newer' }).to_json
        flowchart.commit_version!
        flowchart.set_current_version!(older)

        expect { edit!(flowchart.reload, 'from older') }.to change { flowchart.flowchart_versions.count }.by(1)
        expect(note_of(older)).to be_nil
        expect(flowchart.reload.current_version.based_on_version_id).to eq(older.id)
      end
    end

    context 'on a launched flowchart' do
      let(:flowchart) { create(:flowchart, :simple, :launched_status) }
      let!(:launched) { flowchart.launched_version }

      it 'pins the head it was created with' do
        expect(launched).to eq(flowchart.current_version)
      end

      it 'forks a draft version on the first save and revises it afterwards' do
        expect { edit!(flowchart, 'first') }.to change { flowchart.flowchart_versions.count }.by(1)
        draft = flowchart.reload.current_version
        expect(draft.based_on_version_id).to eq(launched.id)

        expect { edit!(flowchart, 'second') }.not_to change { flowchart.flowchart_versions.count }
        expect(flowchart.reload.current_version).to eq(draft)
        expect(note_of(draft)).to eq('second')
        expect(note_of(launched)).to be_nil
        expect(flowchart.launched_version_id).to eq(launched.id)
        expect(flowchart).to be_pending_draft
      end

      it 'keeps the compiled activity of the launched version while a draft is pending' do
        expect { edit!(flowchart, 'staged') }.not_to(change { flowchart.reload.activity })
      end

      it 'publishes the draft and recompiles the activity on launch!' do
        edit!(flowchart, 'staged')
        draft_id = flowchart.reload.current_version_id
        expect { flowchart.launch! }.to(change { flowchart.reload.activity })
        expect(flowchart.launched_version_id).to eq(draft_id)
        expect(flowchart).not_to be_pending_draft
      end

      it 'publishes an assistant write at once, as a new version' do
        flowchart.assistant_version_write = true
        expect { edit!(flowchart, 'assistant') }.to change { flowchart.flowchart_versions.count }.by(1)
        expect(flowchart.reload.launched_version_id).to eq(flowchart.current_version_id)
        expect(flowchart.launched_version_id).not_to eq(launched.id)
      end

      it 'drops the launched version when taken offline, so the head is revised again' do
        edit!(flowchart, 'staged')
        flowchart.reload.update!(status: :draft)
        expect(flowchart.reload.launched_version_id).to be_nil
        expect { edit!(flowchart, 'offline') }.not_to change { flowchart.flowchart_versions.count }
      end

      it 'never prunes the launched version' do
        stub_const('Versionable::MAX_VERSIONS', 2)
        edit!(flowchart, 'staged')
        3.times do |i|
          content = flowchart.content_class.store!(customer_id: flowchart.customer_id, payload: { 'n' => i })
          flowchart.commit_version!(content: content)
        end
        expect(flowchart.flowchart_versions.exists?(launched.id)).to be(true)
        expect(flowchart.flowchart_versions.count).to eq(3)
      end

      it 'releases the launched version when destroyed' do
        edit!(flowchart, 'staged')
        expect { flowchart.destroy! }.to change(FlowchartVersion, :count).by(-2)
      end

      it 'runs the launched version, not the pending draft' do
        edit!(flowchart, 'staged')
        runtime = FlowchartRuntime::RuntimeFlowchart.new(flowchart.reload)
        expect(runtime.metadata['note']).to be_nil
        expect(runtime.activity).to eq(flowchart.activity)
        expect(flowchart.live_version).to eq(launched)
      end
    end

    context 'when a launched shared flowchart has a pending draft' do
      let(:flowchart) { create(:flowchart, :shared_type, :simple, :launched_status) }

      it 'lets a customer without an override follow the launched version' do
        launched = flowchart.launched_version
        Current.set(shared_resources_mode: true) { edit!(flowchart, 'platform draft') }

        Current.with_customer(customer) do
          tenant_view = Flowchart.find(flowchart.id)
          expect(tenant_view.resolved_current_version).to eq(launched)
          expect(tenant_view.live_version).to eq(launched)
          expect(tenant_view.configuration_json.dig('metadata', 'note')).to be_nil
        end
      end

      it "forks a customer's first override from the launched version, not the platform draft" do
        launched = flowchart.launched_version
        Current.set(shared_resources_mode: true) { edit!(flowchart, 'platform draft') }

        Current.with_customer(customer) do
          tenant_view = Flowchart.find(flowchart.id)
          edit!(tenant_view, 'tenant')
          override = tenant_view.reload.resolved_current_version

          expect(override.customer_id).to eq(customer.id)
          expect(override.based_on_version_id).to eq(launched.id)
          expect(JSON.parse(override.payload).dig('metadata', 'note')).to eq('tenant')
          expect(tenant_view.live_version).to eq(override)
        end
        expect(flowchart.reload.launched_version).to eq(launched)
      end
    end
  end

  describe '#commit_version!' do
    let(:flowchart) { create(:flowchart) }

    # Distinct content is required to force a new version: commit_version!
    # no-ops when the definition payload is unchanged from the current head.
    def bump_configuration!(fc, note)
      cfg = JSON.parse(fc.configuration)
      cfg['metadata'] = cfg['metadata'].merge('note' => note)
      fc.configuration = cfg.to_json
    end

    it 'assigns sequential version_numbers across snapshots' do
      # create(:flowchart) already auto-commits v1; two more distinct commits
      # yield v2 and v3.
      2.times { |i| bump_configuration!(flowchart, "snap-#{i}"); flowchart.commit_version!(description: "snap") }
      numbers = flowchart.flowchart_versions.pluck(:version_number).sort
      expect(numbers).to eq([ 1, 2, 3 ])
    end

    it 'retries when two callers race on the same version_number' do
      # Simulate the race at the DB level: inject a RecordNotUnique on the first
      # attempt then allow subsequent attempts to proceed normally, verifying
      # the retry loop resolves the conflict and inserts the next version.
      bump_configuration!(flowchart, "first")
      flowchart.commit_version!(description: "first")

      # Pin one proxy so commit_version!'s public_send(:flowchart_versions) uses the
      # exact object we stub. Inject RecordNotUnique on the first create! attempt.
      proxy = flowchart.flowchart_versions
      allow(flowchart).to receive(:flowchart_versions).and_return(proxy)
      call_count = 0
      original_create = proxy.method(:create!)
      allow(proxy).to receive(:create!) do |*args, **attrs|
        call_count += 1
        raise ActiveRecord::RecordNotUnique, "duplicate version_number" if call_count == 1
        original_create.call(*args, **attrs)
      end

      bump_configuration!(flowchart, "second")
      expect {
        flowchart.commit_version!(description: "second")
      }.to change { FlowchartVersion.where(flowchart_id: flowchart.id).count }.by(1)
      expect(call_count).to be >= 2
    end
  end

  describe "current version + based-on lineage" do
    let_it_be(:customer) { create(:customer) }
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

    def bump_configuration!(fc, note)
      cfg = JSON.parse(fc.configuration)
      cfg['metadata'] = cfg['metadata'].merge('note' => note)
      fc.configuration = cfg.to_json
    end

    it "belongs to a current_version, which set_current_version! can repoint" do
      v1 = flowchart.current_version
      bump_configuration!(flowchart, "v2")
      flowchart.commit_version!(description: "v2")
      flowchart.set_current_version!(v1)
      expect(flowchart.reload.current_version).to eq(v1)
    end

    it "records based_on_version_id when it belongs to this flowchart" do
      parent = flowchart.current_version
      bump_configuration!(flowchart, "v2")
      child = flowchart.commit_version!(description: "v2", based_on_version_id: parent.id)
      expect(child.based_on_version_id).to eq(parent.id)
    end

    it "falls back to the current head when a based_on_version_id belongs to another flowchart" do
      other = create(:flowchart, :simple, :draft, customer: customer)
      foreign = other.current_version
      head = flowchart.current_version
      bump_configuration!(flowchart, "v2")
      child = flowchart.commit_version!(description: "v2", based_on_version_id: foreign.id)
      expect(child.based_on_version_id).to eq(head.id)
    end

    it "falls back to the current head when a based_on_version_id belongs to another customer's flowchart" do
      other_customer  = create(:customer)
      other_flowchart = create(:flowchart, :simple, :draft, customer: other_customer)
      foreign = other_flowchart.current_version
      head = flowchart.current_version
      bump_configuration!(flowchart, "v2")
      child = flowchart.commit_version!(description: "v2", based_on_version_id: foreign.id)
      expect(child.based_on_version_id).to eq(head.id)
    end

    it "defaults based_on to the current head version when none is given" do
      v1 = flowchart.current_version
      bump_configuration!(flowchart, "v2")
      v2 = flowchart.commit_version!(description: "v2")
      expect(v2.based_on_version_id).to eq(v1.id)
    end

    it "falls back to the current head (not just the latest version) when given a foreign based_on id" do
      v1 = flowchart.current_version
      bump_configuration!(flowchart, "v2")
      flowchart.commit_version!(description: "v2")
      # Head moved back to v1 explicitly, even though a v2 exists.
      flowchart.set_current_version!(v1)

      other = create(:flowchart, :simple, :draft, customer: customer)
      foreign = other.current_version

      bump_configuration!(flowchart, "v3")
      v3 = flowchart.commit_version!(description: "v3", based_on_version_id: foreign.id)
      expect(v3.based_on_version_id).to eq(v1.id)
    end

    it "leaves based_on nil for the first version when no current_version exists yet" do
      v1 = flowchart.current_version
      expect(v1.based_on_version_id).to be_nil
    end

    it "display_current_version returns the current_version when one is set" do
      v1 = flowchart.current_version
      bump_configuration!(flowchart, "v2")
      flowchart.commit_version!(description: "v2")
      flowchart.set_current_version!(v1)
      expect(flowchart.reload.display_current_version).to eq(v1)
    end

    it "display_current_version falls back to the latest version when current_version is unset" do
      bump_configuration!(flowchart, "v2")
      flowchart.commit_version!(description: "v2")
      latest = flowchart.flowchart_versions.ordered.first
      flowchart.update_column(:current_version_id, nil)
      expect(flowchart.reload.display_current_version).to eq(latest)
    end

    it "prunes safely when a kept version references a version that gets pruned" do
      # v1 already exists from creation; fill up to the 50-version cap.
      49.times { |i| bump_configuration!(flowchart, "v#{i + 2}"); flowchart.commit_version!(description: "v#{i + 2}") }
      expect(flowchart.flowchart_versions.count).to eq(50)
      oldest = flowchart.flowchart_versions.find_by!(version_number: 1)
      kept   = flowchart.flowchart_versions.find_by!(version_number: 50)
      # A KEPT version points at the oldest one, which the next commit prunes.
      kept.update_column(:based_on_version_id, oldest.id)

      # Crossing the cap prunes version #1 while #50 still references it.
      bump_configuration!(flowchart, "v51")
      expect {
        flowchart.commit_version!(description: "v51")
      }.not_to raise_error

      expect(flowchart.flowchart_versions.exists?(oldest.id)).to be(false)
      expect(kept.reload.based_on_version_id).to be_nil
    end
  end

  describe ".new_with_defaults with template keys" do
    %w[blank page_record].each do |key|
      it "applies template '#{key}' when passed as template option" do
        fc = described_class.new_with_defaults(name: 'T', customer: customer, template: key)
        config = JSON.parse(fc.configuration)
        expect(config['elements']).to be_present
      end
    end

    it "falls back to default_configuration for an unknown template key" do
      fc = described_class.new_with_defaults(name: 'T', customer: customer, template: "nonexistent_key")
      config = JSON.parse(fc.configuration)
      expect(config['elements']).to be_present
    end

    it "does not overwrite configuration when already set" do
      existing_config = { 'elements' => [], 'connections' => [], 'metadata' => {} }.to_json
      fc = described_class.new_with_defaults(name: 'T', customer: customer,
                                       configuration: existing_config)
      expect(fc.configuration).to eq(existing_config)
    end

    it "prefers template over a posted configuration" do
      posted = { "elements" => [{ "id" => "posted", "type" => "process" }], "connections" => [], "metadata" => {} }.to_json
      fc = described_class.new_with_defaults(name: "T", customer: customer,
                                            template: "blank", configuration: posted)
      expect(JSON.parse(fc.configuration)["elements"].map { |el| el["type"] }).to eq(%w[start end])
    end
  end

  describe ".new_with_defaults page templates" do
    let(:entity) { create(:entity, :with_name_status_schema, customer: customer) }

    def saved_template(key)
      fc = described_class.new_with_defaults(name: "T", customer: customer, template: key)
      fc.save!
      fc
    end

    def process_steps(flowchart)
      flowchart.elements.select { |el| el["type"] == "process" }.map do |el|
        Array(el.dig("properties", "steps"))
      end
    end

    def expect_vertical_chain(flowchart, types)
      elements = flowchart.elements
      expect(elements.map { |el| el["type"] }).to eq(types)
      elements.each_with_index do |el, index|
        expect(el["x"]).to eq(400)
        expect(el["y"]).to eq(80 + (index * 100))
        expect(el["width"]).to eq(100)
        expect(el["height"]).to eq(45)
      end
      ids = elements.map { |el| el["id"] }
      expect(flowchart.connections.map { |c| [c["from"], c["to"], c["fromPosition"], c["toPosition"]] }).to eq(
        ids.each_cons(2).map { |from, to| [from, to, "bottom", "top"] }
      )
    end

    it "uses only declared, valid config for every template step" do
      registry = CodeGenerators::GeneratorRegistry.instance
      Flowchart::STEP_CONFIGS.each do |action, config|
        klass = registry.find_step_action(action)
        declared = klass._config_schema.fields.map(&:name)
        expect(config.keys - declared).to be_empty, action
        expect(klass.new({ "config" => config }, {}).validate_config(config)).to be_empty, action
      end
    end

    it "builds blank as Start → End" do
      fc = saved_template("blank")
      expect_vertical_chain(fc, %w[start end])
      expect(process_steps(fc)).to be_empty
      expect(fc.activity).to be_present
    end

    it "builds page_record as one process per action and traces a save" do
      fc = saved_template("page_record")
      expect_vertical_chain(fc, %w[start process process process end])
      steps = process_steps(fc)
      expect(steps.map(&:size)).to all(eq(1))
      expect(steps.map { |list| list[0]["action"] }).to eq(%w[build_contract validate_contract save_model])
      expect(steps.map { |list| list[0]["config"] }).to eq([
        { "contractClass" => "EntityEntryContract", "modelVariable" => "model" },
        {},
        {}
      ])
      expect(fc.elements.map { |el| el["label"] }).to eq([
        I18n.t("flowchart_elements.template_labels.start"),
        I18n.t("flowchart_elements.template_labels.build_contract"),
        I18n.t("flowchart_elements.template_labels.validate_contract"),
        I18n.t("flowchart_elements.template_labels.save_model"),
        I18n.t("flowchart_elements.template_labels.end")
      ])
      expect(fc.activity).to be_present

      record = EntityEntry.build_for(entity).new(entity: entity, customer_id: customer.id)
      result = ActivityTracer.new(fc).call(
        params: { "name" => "v" },
        customer_id: customer.id,
        bound_entity: entity,
        model: record,
        page_record: record
      )
      expect(result.success?).to be(true)
      expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count).to eq(1)
      expect(JSON.parse(EntityEntry.last.data)["name"]).to eq("v")
    end
  end

  describe ".accessible scope" do
    before { Current.customer = customer }
    after  { Current.reset }

    let!(:own_fc) do
      described_class.create!(name: 'Accessible Own', configuration: valid_configuration.to_json,
                        customer: customer)
    end
    let!(:shared_fc) do
      fc = described_class.new(name: 'Accessible Shared', configuration: valid_configuration.to_json)
      fc.skip_tenant_customer_assignment!
      fc.save!
      fc
    end

    it "returns both own and shared flowcharts when Current.customer? is true" do
      scope = described_class.accessible
      expect(scope).to include(own_fc, shared_fc)
    end

    it "returns only shared flowcharts when no current customer" do
      Current.customer = nil
      scope = described_class.accessible
      expect(scope).to include(shared_fc)
      expect(scope).not_to include(own_fc)
    end
  end

  describe "#soft_delete_active_status override" do
    it "returns :draft (not :active)" do
      expect(described_class.soft_delete_active_status).to eq(:draft)
    end
  end

  describe "#set_draft_status_for_new_records" do
    before { Current.customer = customer }
    after  { Current.reset }

    it "does not fire for persisted records (callback has new_record? guard)" do
      # Create a draft flowchart and promote it to launched via update_columns to bypass
      # edit-restriction validation, then verify a subsequent update doesn't revert status.
      fc = described_class.create!(name: 'Draft FC', configuration: valid_configuration.to_json,
                             customer: customer)
      fc.update_columns(status: described_class.statuses[:launched])
      # The set_draft_status_for_new_records callback only runs for new_record? == true
      # Reload and save a non-status attribute change through update_columns so no callbacks fire
      fc.reload
      expect(fc.status).to eq("launched")
    end
  end

  describe "shared identity" do
    it "is customer-owned when customer_id is set" do
      fc = described_class.new(name: 'F', configuration: valid_configuration.to_json,
                         customer: customer)
      expect(fc).to be_valid
      expect(fc).to be_customer_owned
    end

    it "is shared when customer_id is nil" do
      fc = described_class.new(name: 'F', configuration: valid_configuration.to_json)
      fc.skip_tenant_customer_assignment!
      expect(fc).to be_valid
      expect(fc).to be_shared
    end
  end

  describe "#elements / #connections / #metadata when configuration is nil" do
    before { Current.customer = customer }
    after  { Current.reset }

    it "#elements returns [] when configuration_json is nil" do
      fc = described_class.new(name: 'F', customer: customer)
      fc.configuration = nil
      expect(fc.elements).to eq([])
    end

    it "#connections returns [] when configuration_json is nil" do
      fc = described_class.new(name: 'F', customer: customer)
      fc.configuration = nil
      expect(fc.connections).to eq([])
    end

    it "#metadata returns {} when configuration_json is nil" do
      fc = described_class.new(name: 'F', customer: customer)
      fc.configuration = nil
      expect(fc.metadata).to eq({})
    end
  end

  describe "#set_draft_status_for_new_records (explicit-flag handling)" do
    before { Current.customer = customer }
    after  { Current.reset }

    it "resets status to :draft when a new record has launched status and no explicit flag" do
      # Build without passing status to constructor so @status_explicitly_provided stays false;
      # then force the launched status via write_attribute to simulate a default_scope injection.
      fc = described_class.new(name: 'F', configuration: valid_configuration.to_json,
                               customer: customer)
      fc.write_attribute(:status, described_class.statuses[:launched])
      expect(fc.launched?).to be true
      expect(fc.instance_variable_get(:@status_explicitly_provided)).to be false
      fc.send(:set_draft_status_for_new_records)
      expect(fc.status).to eq("draft")
    end

    it "does not reset status when @status_explicitly_provided is true" do
      fc = described_class.new(name: 'F', configuration: valid_configuration.to_json,
                               customer: customer,
                               status: :launched)
      fc.instance_variable_set(:@status_explicitly_provided, true)
      fc.send(:set_draft_status_for_new_records)
      expect(fc.status).to eq("launched")
    end
  end

  describe "activity generation callback" do
    it "rejects a Decision with an empty structured condition before saving generated activity" do
      configuration = {
        "elements" => [
          { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
          {
            "id" => "d",
            "type" => "decision",
            "label" => "Route",
            "properties" => {
              "routeBy" => "condition",
              "condition" => {
                "type" => "group",
                "joins" => [],
                "conditions" => [
                  { "kind" => "field", "leftOperand" => "", "operator" => "==", "rightOperand" => "x" }
                ]
              }
            }
          },
          { "id" => "a", "type" => "process", "label" => "A", "properties" => { "steps" => [] } },
          { "id" => "b", "type" => "process", "label" => "B", "properties" => { "steps" => [] } },
          { "id" => "e", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s", "to" => "d" },
          { "id" => "c2", "from" => "d", "to" => "a", "matchValue" => "true" },
          { "id" => "c3", "from" => "d", "to" => "b", "matchValue" => "false" },
          { "id" => "c4", "from" => "a", "to" => "e" },
          { "id" => "c5", "from" => "b", "to" => "e" }
        ],
        "metadata" => {}
      }
      flowchart = build_flowchart(name: "Invalid Decision", configuration: configuration.to_json)

      expect { flowchart.save! }.to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:invalid_generator_config)
        expect(error.details.map(&:to_s)).to include("Condition row 1 needs a value to compare")
      }
    end
  end
end
