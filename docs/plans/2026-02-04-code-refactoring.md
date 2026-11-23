# Code Refactoring Implementation Plan

> **For Copilot:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all CRITICAL, IMPORTANT, and MINOR issues identified in the code review to improve security, maintainability, and test coverage.

**Architecture:** Extract shared code into concerns, fix security vulnerabilities, add comprehensive test coverage, and ensure code follows project conventions.

**Tech Stack:** Ruby on Rails 8.1.2, RSpec, ViewComponent, TailwindCSS, StimulusJS, Trailblazer

---

## Task 1: Fix CSRF Protection Security Issue

**Files:**
- Modify: `app/controllers/flowcharts_controller.rb:2`

**Step 1: Remove CSRF skip**

Remove the line that skips CSRF verification since the JavaScript already sends CSRF tokens.

```ruby
# DELETE this line from flowcharts_controller.rb:2
skip_before_action :verify_authenticity_token, only: [:trace]
```

**Step 2: Verify trace endpoint still works**

Run: `bin/rails server` and test the trace endpoint via the UI.
Expected: Trace requests should work since JavaScript sends CSRF tokens.

**Step 3: Commit**

```bash
git add app/controllers/flowcharts_controller.rb
git commit -m "fix(security): remove CSRF protection bypass on trace endpoint"
```

---

## Task 2: Fix Bare Rescue in Controller

**Files:**
- Modify: `app/controllers/flowcharts_controller.rb:153-155`

**Step 1: Change bare rescue to specific exception**

```ruby
# Change from:
rescue
  ctx.to_s

# To:
rescue StandardError => e
  Rails.logger.warn("FlowchartsController#sanitize_context: #{e.class} - #{e.message}")
  ctx.to_s
```

**Step 2: Commit**

```bash
git add app/controllers/flowcharts_controller.rb
git commit -m "fix(security): replace bare rescue with StandardError in sanitize_context"
```

---

## Task 3: Extract Shared Activity Class Builder Concern

**Files:**
- Create: `app/services/concerns/activity_class_builder.rb`
- Modify: `app/services/activity_tracer.rb`
- Modify: `app/services/activity_diagram_generator.rb`

**Step 1: Create the shared concern**

```ruby
# frozen_string_literal: true

# ActivityClassBuilder
#
# Shared concern for building Trailblazer Activity classes from generated
# activity code strings. Used by both ActivityTracer and ActivityDiagramGenerator.
#
# @example
#   class MyService
#     include ActivityClassBuilder
#
#     def process
#       activity_class = build_activity_class(code_string)
#       # use activity_class
#     end
#   end
#
module ActivityClassBuilder
  extend ActiveSupport::Concern

  # Builds a Trailblazer::Activity::Railway subclass from activity code string.
  #
  # @param activity_code [String] Ruby code defining a Trailblazer Activity
  # @return [Class, nil] The Activity class or nil if building fails
  def build_activity_class(activity_code)
    return nil if activity_code.blank?

    namespace = Module.new
    namespace.module_eval(activity_code)
    namespace.constants
             .map { |c| namespace.const_get(c) }
             .find { |k| trailblazer_activity?(k) }
  rescue SyntaxError, StandardError => e
    Rails.logger.error("ActivityClassBuilder: Failed to build activity class - #{e.class}: #{e.message}")
    nil
  end

  # Derives a human-readable label from a Trailblazer node ID.
  #
  # @param node_id [Symbol, String] The node ID (e.g., :Start.default, :validate_input)
  # @return [String] Human-readable label
  def derive_node_label(node_id)
    case node_id.to_s
    when "Start.default" then "Start"
    when /^End\.(\w+)$/ then ::Regexp.last_match(1).capitalize
    else node_id.to_s.split("_").map(&:capitalize).join(" ")
    end
  end

  private

  def trailblazer_activity?(klass)
    klass < Trailblazer::Activity::Railway
  rescue TypeError
    false
  end
end
```

**Step 2: Update ActivityTracer to use the concern**

```ruby
# frozen_string_literal: true

require "trailblazer/developer"

# ActivityTracer
#
# Executes a generated Trailblazer Activity with tracing enabled using
# Trailblazer::Developer::Wtf. Captures the execution trace and provides
# structured results for visualization.
#
# @example
#   tracer = ActivityTracer.new(flowchart)
#   result = tracer.call(params: { name: "Test" })
#   result.success?      # => true/false
#   result.trace         # => formatted trace output
#   result.trace_nodes   # => structured trace data
#
class ActivityTracer
  include ActivityClassBuilder

  Result = Struct.new(:success?, :signal, :ctx, :trace, :trace_nodes, :error, keyword_init: true)

  attr_reader :flowchart

  def initialize(flowchart)
    @flowchart = flowchart
  end

  def call(input = {})
    return error_result("No activity code generated") if flowchart.activity.blank?

    activity_class = build_activity_class(flowchart.activity)
    return error_result("Failed to build activity class") unless activity_class

    execute_with_trace(activity_class, input)
  rescue StandardError => e
    error_result("Execution error: #{e.message}")
  end

  private

  def execute_with_trace(activity_class, input)
    # Execute with Trailblazer::Developer::Wtf for tracing
    signal, (ctx, flow_options) = Trailblazer::Developer::Wtf.invoke(
      activity_class,
      [input, {}]
    )

    # Get trace from flow_options
    stack = flow_options[:stack]
    trace_output = Trailblazer::Developer::Trace::Present.(stack)
    trace_nodes = build_trace_nodes(stack, activity_class)

    Result.new(
      success?: signal.to_h[:semantic] == :success,
      signal: signal,
      ctx: ctx,
      trace: trace_output,
      trace_nodes: trace_nodes,
      error: nil
    )
  end

  # Build structured trace data for UI visualization
  def build_trace_nodes(stack, activity_class)
    nodes_meta = activity_class.to_h[:nodes]

    stack.to_a.filter_map do |snapshot|
      next unless snapshot.is_a?(Trailblazer::Developer::Trace::Snapshot::After)

      task = snapshot.task
      next if task == activity_class # Skip the outer activity wrapper

      node_meta = nodes_meta[task]
      next unless node_meta

      signal = snapshot.data[:signal]

      {
        id: node_meta[:id].to_s,
        label: derive_node_label(node_meta[:id]),
        status: derive_status(signal),
        signal: signal.class.name.split("::").last
      }
    end
  end

  def derive_status(signal)
    # Signal can be a class (Right/Left) or an End instance
    signal_name = signal.is_a?(Class) ? signal.name : signal.class.name

    if signal_name.include?("Right")
      :success
    elsif signal_name.include?("Left")
      :failure
    elsif signal.respond_to?(:to_h)
      signal.to_h[:semantic] == :success ? :success : :failure
    else
      :unknown
    end
  end

  def error_result(message)
    Result.new(
      success?: false,
      signal: nil,
      ctx: {},
      trace: nil,
      trace_nodes: [],
      error: message
    )
  end
end
```

**Step 3: Update ActivityDiagramGenerator to use the concern**

```ruby
# frozen_string_literal: true

require "trailblazer/developer"

# ActivityDiagramGenerator
#
# Generates a Mermaid flowchart diagram using Trailblazer's built-in
# introspection APIs:
#   - Trailblazer::Developer::Introspect::Graph for node iteration
#   - activity.to_h[:nodes] for node metadata (dsl_track, etc.)
#   - activity.to_h[:circuit] for connection mapping
#
# @example
#   ActivityDiagramGenerator.new(flowchart).generate
#   # => "flowchart TD\n  Start([Start])\n  ..."
#
class ActivityDiagramGenerator
  include ActivityClassBuilder

  # Mermaid node shapes mapped to Trailblazer task types
  SHAPES = {
    start:    ->(id, label) { "#{id}([#{label}])" },
    terminus: ->(id, label) { "#{id}([#{label}])" },
    step:     ->(id, label) { "#{id}[#{label}]" },
    pass:     ->(id, label) { "#{id}{#{label}}" }
  }.freeze

  # Mermaid styles mapped to Trailblazer semantics
  STYLES = {
    start:   "startNode",
    success: "successNode",
    failure: "failureNode",
    step:    "stepNode",
    pass:    "passNode"
  }.freeze

  STYLE_DEFS = <<~MERMAID.freeze
    classDef startNode fill:#22c55e,stroke:#16a34a,color:#fff
    classDef stepNode fill:#3b82f6,stroke:#2563eb,color:#fff
    classDef passNode fill:#f59e0b,stroke:#d97706,color:#fff
    classDef successNode fill:#22c55e,stroke:#16a34a,color:#fff
    classDef failureNode fill:#ef4444,stroke:#dc2626,color:#fff
  MERMAID

  attr_reader :flowchart

  def initialize(flowchart)
    @flowchart = flowchart
  end

  def generate
    return nil if flowchart.activity.blank?

    activity_class = build_activity_class(flowchart.activity)
    return nil unless activity_class

    build_mermaid(activity_class)
  rescue StandardError => e
    Rails.logger.error("ActivityDiagramGenerator: #{e.class} - #{e.message}")
    nil
  end

  private

  def build_mermaid(activity_class)
    # Use Trailblazer's built-in introspection
    graph = Trailblazer::Developer::Introspect::Graph.new(activity_class)
    activity_hash = activity_class.to_h
    nodes_meta = activity_hash[:nodes]
    circuit_map = activity_hash[:circuit].to_h[:map]

    nodes = collect_nodes(graph, nodes_meta)
    connections = collect_connections(circuit_map, nodes_meta)

    [
      "flowchart TD",
      nodes.map { |n| node_definition(n) },
      connections.map { |c| connection_definition(c) },
      style_assignments(nodes),
      "",
      STYLE_DEFS
    ].flatten.compact.join("\n")
  end

  # Use Trailblazer::Developer::Introspect::Graph to iterate nodes
  def collect_nodes(graph, nodes_meta)
    graph.collect do |node|
      task = node.task
      meta = nodes_meta[task] || {}
      dsl_track = meta.dig(:data, :dsl_track)

      {
        id: sanitize_id(node.id),
        label: derive_node_label(node.id),
        type: derive_type(task, dsl_track),
        style: derive_style(task, node.id, dsl_track)
      }
    end
  end

  # Use activity.to_h[:circuit] for connections
  def collect_connections(circuit_map, nodes_meta)
    circuit_map.flat_map do |from_task, outputs|
      from_id = sanitize_id(nodes_meta[from_task][:id])

      outputs.map do |signal, to_task|
        to_id = sanitize_id(nodes_meta[to_task][:id])
        # Trailblazer uses Right for success, Left for failure
        semantic = signal.to_s.include?("Right") ? :success : :failure

        { from: from_id, to: to_id, semantic: semantic }
      end
    end
  end

  def derive_type(task, dsl_track)
    case task
    when Trailblazer::Activity::Start then :start
    when Trailblazer::Activity::End   then :terminus
    else dsl_track == :pass ? :pass : :step
    end
  end

  def derive_style(task, node_id, dsl_track)
    case task
    when Trailblazer::Activity::Start then :start
    when Trailblazer::Activity::End
      node_id.to_s.include?("success") ? :success : :failure
    else
      dsl_track == :pass ? :pass : :step
    end
  end

  def node_definition(node)
    shape = SHAPES[node[:type]] || SHAPES[:step]
    "  #{shape.call(node[:id], escape_label(node[:label]))}"
  end

  def connection_definition(conn)
    case conn[:semantic]
    when :success then "  #{conn[:from]} -->|success| #{conn[:to]}"
    when :failure then "  #{conn[:from]} -.->|failure| #{conn[:to]}"
    else "  #{conn[:from]} --> #{conn[:to]}"
    end
  end

  def style_assignments(nodes)
    nodes.group_by { |n| n[:style] }.filter_map do |style, group|
      next unless STYLES[style]
      "  class #{group.map { |n| n[:id] }.join(',')} #{STYLES[style]}"
    end
  end

  def sanitize_id(id)
    id.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
  end

  def escape_label(label)
    label.to_s.gsub(/[\[\]{}()<>|"]/, "").strip
  end
end
```

**Step 4: Run tests to verify nothing broke**

Run: `bundle exec rspec`
Expected: All existing tests pass.

**Step 5: Commit**

```bash
git add app/services/concerns/activity_class_builder.rb app/services/activity_tracer.rb app/services/activity_diagram_generator.rb
git commit -m "refactor: extract shared ActivityClassBuilder concern from tracer and diagram generator"
```

---

## Task 4: Fix Soft Delete Test Expectation

**Files:**
- Modify: `spec/controllers/flowcharts_controller_spec.rb:227-244`

**Step 1: Update the destroy tests to verify soft delete behavior**

Replace the existing destroy tests with:

```ruby
describe 'DELETE #destroy' do
  it 'soft deletes the requested flowchart' do
    flowchart # Create the flowchart
    expect {
      delete :destroy, params: { id: flowchart.to_param }
    }.not_to change(Flowchart.with_deleted, :count)
  end

  it 'changes the flowchart status to deleted' do
    flowchart # Create the flowchart
    delete :destroy, params: { id: flowchart.to_param }
    expect(flowchart.reload.status).to eq('deleted')
  end

  it 'removes the flowchart from default scope' do
    flowchart # Create the flowchart
    delete :destroy, params: { id: flowchart.to_param }
    expect(Flowchart.exists?(flowchart.id)).to be false
  end

  it 'keeps the flowchart in only_deleted scope' do
    flowchart # Create the flowchart
    delete :destroy, params: { id: flowchart.to_param }
    expect(Flowchart.only_deleted.exists?(flowchart.id)).to be true
  end

  it 'redirects to the flowcharts list' do
    delete :destroy, params: { id: flowchart.to_param }
    expect(response).to redirect_to(flowcharts_url)
  end

  it 'sets a success notice' do
    delete :destroy, params: { id: flowchart.to_param }
    expect(flash[:notice]).to eq('Flowchart was successfully deleted.')
  end
end
```

**Step 2: Run the tests**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add spec/controllers/flowcharts_controller_spec.rb
git commit -m "fix(test): update destroy tests to verify soft delete behavior"
```

---

## Task 5: Remove Unused Method from Flowchart Model

**Files:**
- Modify: `app/models/flowchart.rb:192-198`

**Step 1: Remove the unused `default_end_properties` method**

Delete lines 192-198:

```ruby
# DELETE this method - it's never called
def default_end_properties
  {
    "inputs" => [],
    "outputs" => [{ "value" => "ctx" }],
    "description" => ""
  }
end
```

**Step 2: Run tests to verify nothing broke**

Run: `bundle exec rspec spec/models/flowchart_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add app/models/flowchart.rb
git commit -m "refactor: remove unused default_end_properties method"
```

---

## Task 6: Add Entity Model Spec

**Files:**
- Create: `spec/models/entity_spec.rb`

**Step 1: Create the entity spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entity, type: :model do
  let(:valid_attributes) do
    {
      name: 'Test Entity',
      element_type: 'custom',
      icon: 'custom',
      color: '#6366f1',
      description: 'A test entity',
      property_schema: [
        { 'name' => 'title', 'name_slug' => 'title', 'type' => 'Types::String' },
        { 'name' => 'count', 'name_slug' => 'count', 'type' => 'Types::Integer' }
      ].to_json,
      default_properties: { 'title' => 'Default' }.to_json
    }
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      entity = Entity.new(valid_attributes)
      expect(entity).to be_valid
    end

    it 'requires a name' do
      entity = Entity.new(valid_attributes.merge(name: ''))
      expect(entity).not_to be_valid
      expect(entity.errors[:name]).to include("can't be blank")
    end

    it 'requires a unique name' do
      Entity.create!(valid_attributes)
      duplicate = Entity.new(valid_attributes)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end

    it 'requires name to be at most 100 characters' do
      entity = Entity.new(valid_attributes.merge(name: 'a' * 101))
      expect(entity).not_to be_valid
      expect(entity.errors[:name]).to include('is too long (maximum is 100 characters)')
    end

    it 'requires element_type' do
      entity = Entity.new(valid_attributes.merge(element_type: ''))
      expect(entity).not_to be_valid
      expect(entity.errors[:element_type]).to include("can't be blank")
    end

    it 'validates unique attribute names in property_schema' do
      schema = [
        { 'name' => 'title', 'name_slug' => 'title1', 'type' => 'Types::String' },
        { 'name' => 'title', 'name_slug' => 'title2', 'type' => 'Types::String' }
      ]
      entity = Entity.new(valid_attributes.merge(property_schema: schema.to_json))
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include('has duplicate attribute names: title')
    end

    it 'validates unique attribute slugs in property_schema' do
      schema = [
        { 'name' => 'Title One', 'name_slug' => 'title', 'type' => 'Types::String' },
        { 'name' => 'Title Two', 'name_slug' => 'title', 'type' => 'Types::String' }
      ]
      entity = Entity.new(valid_attributes.merge(property_schema: schema.to_json))
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include('has duplicate attribute slugs: title')
    end
  end

  describe 'callbacks' do
    describe '#generate_name_slug' do
      it 'generates a slug from the name' do
        entity = Entity.create!(valid_attributes.merge(name: 'My Test Entity'))
        expect(entity.name_slug).to eq('my_test_entity')
      end

      it 'removes special characters from slug' do
        entity = Entity.create!(valid_attributes.merge(name: 'Test @#$% Entity!'))
        expect(entity.name_slug).to eq('test_entity')
      end

      it 'collapses multiple underscores' do
        entity = Entity.create!(valid_attributes.merge(name: 'Test   Multiple   Spaces'))
        expect(entity.name_slug).to eq('test_multiple_spaces')
      end
    end

    describe '#generate_model' do
      it 'generates model code on save' do
        entity = Entity.create!(valid_attributes)
        expect(entity.model).to be_present
        expect(entity.model).to include('class TestEntity')
      end
    end

    describe '#generate_contract' do
      it 'generates contract code on save' do
        entity = Entity.create!(valid_attributes)
        expect(entity.contract).to be_present
        expect(entity.contract).to include('Reform::Form')
      end
    end
  end

  describe 'scopes' do
    before do
      Entity.create!(valid_attributes.merge(name: 'Zebra Entity'))
      Entity.create!(valid_attributes.merge(name: 'Alpha Entity'))
    end

    describe '.by_name' do
      it 'orders entities alphabetically by name' do
        entities = Entity.by_name
        expect(entities.first.name).to eq('Alpha Entity')
        expect(entities.last.name).to eq('Zebra Entity')
      end
    end

    describe '.recent' do
      it 'orders entities by creation date descending' do
        entities = Entity.recent
        expect(entities.first.name).to eq('Alpha Entity')
      end
    end

    describe '.search_by_name' do
      it 'finds entities matching the query' do
        entities = Entity.search_by_name('alpha')
        expect(entities.count).to eq(1)
        expect(entities.first.name).to eq('Alpha Entity')
      end

      it 'returns all entities when query is blank' do
        entities = Entity.search_by_name('')
        expect(entities.count).to eq(2)
      end

      it 'is case insensitive' do
        entities = Entity.search_by_name('ZEBRA')
        expect(entities.count).to eq(1)
      end
    end
  end

  describe 'soft delete' do
    let(:entity) { Entity.create!(valid_attributes) }

    it 'can be soft deleted' do
      entity.soft_delete
      expect(entity.status).to eq('inactive')
    end

    it 'is not visible after soft delete' do
      entity.soft_delete
      expect(Entity.visible).not_to include(entity)
    end

    it 'can be restored' do
      entity.soft_delete
      entity.restore
      expect(entity.status).to eq('active')
      expect(Entity.visible).to include(entity)
    end
  end

  describe '#as_palette_item' do
    it 'returns a hash with palette item data' do
      entity = Entity.create!(valid_attributes)
      palette_item = entity.as_palette_item

      expect(palette_item[:id]).to eq(entity.id)
      expect(palette_item[:name]).to eq('Test Entity')
      expect(palette_item[:name_slug]).to eq('test_entity')
      expect(palette_item[:element_type]).to eq("custom_#{entity.id}")
      expect(palette_item[:icon]).to eq('custom')
      expect(palette_item[:color]).to eq('#6366f1')
      expect(palette_item[:property_schema]).to be_an(Array)
      expect(palette_item[:default_properties]).to be_a(Hash)
    end
  end

  describe 'JSON attributes' do
    it 'parses property_schema as JSON' do
      entity = Entity.create!(valid_attributes)
      expect(entity.property_schema_json).to be_an(Array)
      expect(entity.property_schema_json.first['name']).to eq('title')
    end

    it 'parses default_properties as JSON' do
      entity = Entity.create!(valid_attributes)
      expect(entity.default_properties_json).to be_a(Hash)
      expect(entity.default_properties_json['title']).to eq('Default')
    end
  end
end
```

**Step 2: Run the tests**

Run: `bundle exec rspec spec/models/entity_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add spec/models/entity_spec.rb
git commit -m "test: add comprehensive Entity model specs"
```

---

## Task 7: Add ActivityGenerator Service Spec

**Files:**
- Create: `spec/services/activity_generator_spec.rb`

**Step 1: Read the ActivityGenerator to understand its interface**

Read: `app/services/activity_generator.rb`

**Step 2: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityGenerator do
  let(:entity) { create(:entity) }

  let(:simple_flowchart) do
    create(:flowchart, :simple, entity: entity)
  end

  let(:complex_flowchart) do
    create(:flowchart, :complex, entity: entity)
  end

  describe '#generate' do
    context 'with a simple flowchart' do
      it 'generates valid Ruby code' do
        generator = described_class.new(simple_flowchart)
        code = generator.generate

        expect(code).to be_present
        expect { eval(code) }.not_to raise_error
      end

      it 'generates a Trailblazer::Activity::Railway class' do
        generator = described_class.new(simple_flowchart)
        code = generator.generate

        expect(code).to include('Trailblazer::Activity::Railway')
      end

      it 'includes the flowchart name in the class name' do
        simple_flowchart.update!(name: 'My Test Flow')
        generator = described_class.new(simple_flowchart)
        code = generator.generate

        expect(code).to include('class MyTestFlow')
      end
    end

    context 'with a complex flowchart' do
      it 'generates code with multiple steps' do
        generator = described_class.new(complex_flowchart)
        code = generator.generate

        expect(code).to include('step')
      end

      it 'generates methods for each process element' do
        generator = described_class.new(complex_flowchart)
        code = generator.generate

        expect(code).to include('def ')
      end
    end

    context 'with an empty flowchart' do
      let(:empty_flowchart) do
        create(:flowchart, :empty, entity: entity)
      end

      it 'generates minimal activity code' do
        generator = described_class.new(empty_flowchart)
        code = generator.generate

        expect(code).to be_present
        expect(code).to include('Trailblazer::Activity::Railway')
      end
    end

    context 'with decision elements' do
      let(:decision_flowchart) do
        create(:flowchart, entity: entity, configuration: decision_configuration.to_json)
      end

      let(:decision_configuration) do
        {
          'elements' => [
            { 'id' => 'start_1', 'type' => 'start', 'x' => 100, 'y' => 100, 'label' => 'Start', 'properties' => {} },
            { 'id' => 'decision_1', 'type' => 'decision', 'x' => 100, 'y' => 200, 'label' => 'Check', 'properties' => { 'branches' => [] } },
            { 'id' => 'end_1', 'type' => 'end', 'x' => 100, 'y' => 300, 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'decision_1' },
            { 'id' => 'conn_2', 'from' => 'decision_1', 'to' => 'end_1' }
          ],
          'metadata' => { 'canvas' => { 'width' => 1200, 'height' => 800 } }
        }
      end

      it 'generates pass macro for decision elements' do
        generator = described_class.new(decision_flowchart)
        code = generator.generate

        expect(code).to include('pass')
      end
    end
  end

  describe 'class name derivation' do
    it 'converts flowchart name to PascalCase' do
      simple_flowchart.update!(name: 'user_registration_flow')
      generator = described_class.new(simple_flowchart)
      code = generator.generate

      expect(code).to include('class UserRegistrationFlow')
    end

    it 'handles names with special characters' do
      simple_flowchart.update!(name: 'Test Flow #1')
      generator = described_class.new(simple_flowchart)
      code = generator.generate

      expect(code).to match(/class \w+/)
    end
  end
end
```

**Step 3: Run the tests**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add spec/services/activity_generator_spec.rb
git commit -m "test: add ActivityGenerator service specs"
```

---

## Task 8: Add ActivityClassBuilder Concern Spec

**Files:**
- Create: `spec/services/concerns/activity_class_builder_spec.rb`

**Step 1: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityClassBuilder do
  let(:test_class) do
    Class.new do
      include ActivityClassBuilder
    end
  end

  let(:instance) { test_class.new }

  describe '#build_activity_class' do
    context 'with valid activity code' do
      let(:valid_code) do
        <<~RUBY
          class TestActivity < Trailblazer::Activity::Railway
            step :validate

            def validate(ctx, **)
              true
            end
          end
        RUBY
      end

      it 'returns the Activity class' do
        result = instance.build_activity_class(valid_code)
        expect(result).to be_a(Class)
        expect(result < Trailblazer::Activity::Railway).to be true
      end
    end

    context 'with blank code' do
      it 'returns nil for nil' do
        expect(instance.build_activity_class(nil)).to be_nil
      end

      it 'returns nil for empty string' do
        expect(instance.build_activity_class('')).to be_nil
      end
    end

    context 'with invalid code' do
      it 'returns nil for syntax errors' do
        invalid_code = 'class Broken < def end'
        expect(instance.build_activity_class(invalid_code)).to be_nil
      end

      it 'returns nil for code without Activity class' do
        no_activity = 'class RegularClass; end'
        expect(instance.build_activity_class(no_activity)).to be_nil
      end
    end
  end

  describe '#derive_node_label' do
    it 'returns "Start" for Start.default' do
      expect(instance.derive_node_label('Start.default')).to eq('Start')
    end

    it 'capitalizes End semantic' do
      expect(instance.derive_node_label('End.success')).to eq('Success')
      expect(instance.derive_node_label('End.failure')).to eq('Failure')
    end

    it 'converts snake_case to Title Case' do
      expect(instance.derive_node_label('validate_input')).to eq('Validate Input')
      expect(instance.derive_node_label('save_to_database')).to eq('Save To Database')
    end

    it 'handles single words' do
      expect(instance.derive_node_label('process')).to eq('Process')
    end
  end
end
```

**Step 2: Run the tests**

Run: `bundle exec rspec spec/services/concerns/activity_class_builder_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add spec/services/concerns/activity_class_builder_spec.rb
git commit -m "test: add ActivityClassBuilder concern specs"
```

---

## Task 9: Add Entities Controller Spec

**Files:**
- Create: `spec/controllers/entities_controller_spec.rb`

**Step 1: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EntitiesController, type: :controller do
  let(:valid_attributes) do
    {
      name: 'Test Entity',
      element_type: 'custom',
      icon: 'custom',
      color: '#6366f1',
      description: 'A test entity',
      property_schema: [].to_json,
      default_properties: {}.to_json
    }
  end

  let(:invalid_attributes) do
    {
      name: '',
      element_type: ''
    }
  end

  let(:entity) { Entity.create!(valid_attributes) }

  describe 'GET #index' do
    it 'returns a success response' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns entities by name' do
      entity1 = Entity.create!(valid_attributes.merge(name: 'Zebra'))
      entity2 = Entity.create!(valid_attributes.merge(name: 'Alpha'))

      get :index
      expect(assigns(:entities).first).to eq(entity2)
    end

    context 'with search query' do
      it 'filters entities by name' do
        Entity.create!(valid_attributes.merge(name: 'User Entity'))
        Entity.create!(valid_attributes.merge(name: 'Product Entity'))

        get :index, params: { q: 'user' }
        expect(assigns(:entities).count).to eq(1)
        expect(assigns(:entities).first.name).to eq('User Entity')
      end
    end
  end

  describe 'GET #show' do
    it 'returns a success response' do
      get :show, params: { id: entity.to_param }
      expect(response).to be_successful
    end

    it 'assigns the requested entity' do
      get :show, params: { id: entity.to_param }
      expect(assigns(:entity)).to eq(entity)
    end
  end

  describe 'GET #new' do
    it 'returns a success response' do
      get :new
      expect(response).to be_successful
    end

    it 'assigns a new entity' do
      get :new
      expect(assigns(:entity)).to be_a_new(Entity)
    end
  end

  describe 'GET #edit' do
    it 'returns a success response' do
      get :edit, params: { id: entity.to_param }
      expect(response).to be_successful
    end
  end

  describe 'POST #create' do
    context 'with valid params' do
      it 'creates a new Entity' do
        expect {
          post :create, params: { entity: valid_attributes }
        }.to change(Entity, :count).by(1)
      end

      it 'redirects to the entities list' do
        post :create, params: { entity: valid_attributes }
        expect(response).to redirect_to(entities_url)
      end
    end

    context 'with invalid params' do
      it 'does not create an entity' do
        expect {
          post :create, params: { entity: invalid_attributes }
        }.not_to change(Entity, :count)
      end

      it 'renders the new template' do
        post :create, params: { entity: invalid_attributes }
        expect(response).to render_template(:new)
      end
    end
  end

  describe 'PATCH #update' do
    context 'with valid params' do
      it 'updates the entity' do
        patch :update, params: { id: entity.to_param, entity: { name: 'Updated Name' } }
        entity.reload
        expect(entity.name).to eq('Updated Name')
      end

      it 'redirects to the entities list' do
        patch :update, params: { id: entity.to_param, entity: valid_attributes }
        expect(response).to redirect_to(entities_url)
      end
    end

    context 'with invalid params' do
      it 'renders the edit template' do
        patch :update, params: { id: entity.to_param, entity: invalid_attributes }
        expect(response).to render_template(:edit)
      end
    end
  end

  describe 'DELETE #destroy' do
    it 'soft deletes the entity' do
      entity # Create entity
      delete :destroy, params: { id: entity.to_param }
      expect(entity.reload.status).to eq('inactive')
    end

    it 'redirects to the entities list' do
      delete :destroy, params: { id: entity.to_param }
      expect(response).to redirect_to(entities_url)
    end
  end

  describe 'PATCH #restore' do
    it 'restores a deleted entity' do
      entity.soft_delete
      patch :restore, params: { id: entity.to_param }
      expect(entity.reload.status).to eq('active')
    end
  end

  describe 'GET #trash' do
    it 'shows deleted entities' do
      entity.soft_delete
      get :trash
      expect(assigns(:entities)).to include(entity)
    end
  end
end
```

**Step 2: Run the tests**

Run: `bundle exec rspec spec/controllers/entities_controller_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add spec/controllers/entities_controller_spec.rb
git commit -m "test: add EntitiesController specs"
```

---

## Task 10: Add ActivityTracer Service Spec

**Files:**
- Create: `spec/services/activity_tracer_spec.rb`

**Step 1: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityTracer do
  let(:entity) { create(:entity) }
  let(:flowchart) { create(:flowchart, :simple, entity: entity) }

  describe '#call' do
    context 'with a valid flowchart' do
      it 'returns a Result struct' do
        tracer = described_class.new(flowchart)
        result = tracer.call({})

        expect(result).to be_a(ActivityTracer::Result)
      end

      it 'executes the activity successfully' do
        tracer = described_class.new(flowchart)
        result = tracer.call({})

        expect(result.error).to be_nil
      end

      it 'includes trace output' do
        tracer = described_class.new(flowchart)
        result = tracer.call({})

        expect(result.trace).to be_present
      end

      it 'includes trace nodes for visualization' do
        tracer = described_class.new(flowchart)
        result = tracer.call({})

        expect(result.trace_nodes).to be_an(Array)
      end
    end

    context 'with no activity code' do
      let(:flowchart_without_activity) do
        f = create(:flowchart, :empty, entity: entity)
        f.update_column(:activity, nil)
        f
      end

      it 'returns an error result' do
        tracer = described_class.new(flowchart_without_activity)
        result = tracer.call({})

        expect(result.success?).to be false
        expect(result.error).to eq('No activity code generated')
      end
    end

    context 'with invalid activity code' do
      let(:flowchart_with_bad_code) do
        f = create(:flowchart, :simple, entity: entity)
        f.update_column(:activity, 'invalid ruby code def end')
        f
      end

      it 'returns an error result' do
        tracer = described_class.new(flowchart_with_bad_code)
        result = tracer.call({})

        expect(result.success?).to be false
        expect(result.error).to include('Failed to build activity class')
      end
    end

    context 'with input parameters' do
      it 'passes input to the activity' do
        tracer = described_class.new(flowchart)
        result = tracer.call(name: 'Test', value: 42)

        expect(result.ctx).to include(:name, :value)
      end
    end
  end
end
```

**Step 2: Run the tests**

Run: `bundle exec rspec spec/services/activity_tracer_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add spec/services/activity_tracer_spec.rb
git commit -m "test: add ActivityTracer service specs"
```

---

## Task 11: Add ActivityDiagramGenerator Service Spec

**Files:**
- Create: `spec/services/activity_diagram_generator_spec.rb`

**Step 1: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityDiagramGenerator do
  let(:entity) { create(:entity) }
  let(:flowchart) { create(:flowchart, :simple, entity: entity) }

  describe '#generate' do
    context 'with a valid flowchart' do
      it 'generates Mermaid diagram code' do
        generator = described_class.new(flowchart)
        diagram = generator.generate

        expect(diagram).to be_present
        expect(diagram).to include('flowchart TD')
      end

      it 'includes node definitions' do
        generator = described_class.new(flowchart)
        diagram = generator.generate

        expect(diagram).to include('Start')
      end

      it 'includes style definitions' do
        generator = described_class.new(flowchart)
        diagram = generator.generate

        expect(diagram).to include('classDef')
        expect(diagram).to include('startNode')
        expect(diagram).to include('stepNode')
      end

      it 'includes connections between nodes' do
        generator = described_class.new(flowchart)
        diagram = generator.generate

        expect(diagram).to match(/-->/)
      end
    end

    context 'with no activity code' do
      let(:flowchart_without_activity) do
        f = create(:flowchart, :empty, entity: entity)
        f.update_column(:activity, nil)
        f
      end

      it 'returns nil' do
        generator = described_class.new(flowchart_without_activity)
        expect(generator.generate).to be_nil
      end
    end

    context 'with invalid activity code' do
      let(:flowchart_with_bad_code) do
        f = create(:flowchart, :simple, entity: entity)
        f.update_column(:activity, 'invalid ruby code')
        f
      end

      it 'returns nil and logs error' do
        generator = described_class.new(flowchart_with_bad_code)
        expect(Rails.logger).to receive(:error).with(/ActivityDiagramGenerator/)
        expect(generator.generate).to be_nil
      end
    end

    context 'with complex flowchart' do
      let(:complex_flowchart) { create(:flowchart, :complex, entity: entity) }

      it 'generates diagram with multiple steps' do
        generator = described_class.new(complex_flowchart)
        diagram = generator.generate

        expect(diagram).to be_present
        expect(diagram.scan('-->').count).to be > 1
      end
    end
  end
end
```

**Step 2: Run the tests**

Run: `bundle exec rspec spec/services/activity_diagram_generator_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add spec/services/activity_diagram_generator_spec.rb
git commit -m "test: add ActivityDiagramGenerator service specs"
```

---

## Task 12: Add ModelGenerator Service Spec

**Files:**
- Create: `spec/services/model_generator_spec.rb`

**Step 1: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ModelGenerator do
  let(:entity) do
    create(:entity,
      name: 'User Profile',
      property_schema: schema.to_json
    )
  end

  let(:schema) do
    [
      { 'name' => 'name', 'name_slug' => 'name', 'type' => 'Types::String' },
      { 'name' => 'age', 'name_slug' => 'age', 'type' => 'Types::Integer' },
      { 'name' => 'email', 'name_slug' => 'email', 'type' => 'Types::String' }
    ]
  end

  describe '#generate' do
    it 'generates valid Ruby code' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to be_present
      expect { eval(code) }.not_to raise_error
    end

    it 'generates a class inheriting from ApplicationRecord' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to include('class UserProfile < ApplicationRecord')
    end

    it 'includes attribute declarations' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to include('attribute :name')
      expect(code).to include('attribute :age')
      expect(code).to include('attribute :email')
    end

    it 'maps dry-types to Rails types' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to include(':string')
      expect(code).to include(':integer')
    end

    context 'with empty schema' do
      let(:schema) { [] }

      it 'generates a minimal model' do
        generator = described_class.new(entity)
        code = generator.generate

        expect(code).to include('class UserProfile')
        expect(code).not_to include('attribute :')
      end
    end

    context 'with various types' do
      let(:schema) do
        [
          { 'name' => 'active', 'name_slug' => 'active', 'type' => 'Types::Bool' },
          { 'name' => 'price', 'name_slug' => 'price', 'type' => 'Types::Decimal' },
          { 'name' => 'created', 'name_slug' => 'created', 'type' => 'Types::DateTime' }
        ]
      end

      it 'maps boolean type correctly' do
        generator = described_class.new(entity)
        code = generator.generate

        expect(code).to include(':boolean')
      end

      it 'maps decimal type correctly' do
        generator = described_class.new(entity)
        code = generator.generate

        expect(code).to include(':decimal')
      end

      it 'maps datetime type correctly' do
        generator = described_class.new(entity)
        code = generator.generate

        expect(code).to include(':datetime')
      end
    end
  end
end
```

**Step 2: Run the tests**

Run: `bundle exec rspec spec/services/model_generator_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add spec/services/model_generator_spec.rb
git commit -m "test: add ModelGenerator service specs"
```

---

## Task 13: Add ContractGenerator Service Spec

**Files:**
- Create: `spec/services/contract_generator_spec.rb`

**Step 1: Create the spec file**

```ruby
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
        'validations' => [
          { 'type' => 'presence', 'value' => true },
          { 'type' => 'format', 'value' => '/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i' }
        ]
      },
      {
        'name' => 'age',
        'name_slug' => 'age',
        'type' => 'Types::Integer',
        'validations' => [
          { 'type' => 'numericality', 'value' => { 'greater_than' => 0, 'less_than' => 150 } }
        ]
      }
    ]
  end

  describe '#generate' do
    it 'generates valid Ruby code' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to be_present
      expect { eval(code) }.not_to raise_error
    end

    it 'generates a Reform::Form class' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to include('Reform::Form')
    end

    it 'includes property declarations' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to include('property :email')
      expect(code).to include('property :age')
    end

    it 'includes presence validations' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to include('validates :email')
      expect(code).to include('presence: true')
    end

    it 'includes format validations' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to include('format:')
    end

    it 'includes numericality validations' do
      generator = described_class.new(entity)
      code = generator.generate

      expect(code).to include('numericality:')
      expect(code).to include('greater_than')
    end

    context 'with empty schema' do
      let(:schema) { [] }

      it 'generates a minimal contract' do
        generator = described_class.new(entity)
        code = generator.generate

        expect(code).to include('class UserRegistrationContract')
        expect(code).not_to include('property :')
      end
    end

    context 'with length validations' do
      let(:schema) do
        [
          {
            'name' => 'username',
            'name_slug' => 'username',
            'type' => 'Types::String',
            'validations' => [
              { 'type' => 'length', 'value' => { 'minimum' => 3, 'maximum' => 20 } }
            ]
          }
        ]
      end

      it 'includes length validations' do
        generator = described_class.new(entity)
        code = generator.generate

        expect(code).to include('length:')
        expect(code).to include('minimum')
        expect(code).to include('maximum')
      end
    end

    context 'with inclusion validations' do
      let(:schema) do
        [
          {
            'name' => 'status',
            'name_slug' => 'status',
            'type' => 'Types::String',
            'validations' => [
              { 'type' => 'inclusion', 'value' => ['active', 'pending', 'inactive'] }
            ]
          }
        ]
      end

      it 'includes inclusion validations' do
        generator = described_class.new(entity)
        code = generator.generate

        expect(code).to include('inclusion:')
        expect(code).to include('in:')
      end
    end
  end
end
```

**Step 2: Run the tests**

Run: `bundle exec rspec spec/services/contract_generator_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add spec/services/contract_generator_spec.rb
git commit -m "test: add ContractGenerator service specs"
```

---

## Task 14: Add DryTypesExtractor Service Spec

**Files:**
- Create: `spec/services/dry_types_extractor_spec.rb`

**Step 1: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DryTypesExtractor do
  describe '.all_types' do
    it 'returns an array of type definitions' do
      types = described_class.all_types
      expect(types).to be_an(Array)
      expect(types).not_to be_empty
    end

    it 'includes common types' do
      types = described_class.all_types.map { |t| t[:name] }
      expect(types).to include('Types::String')
      expect(types).to include('Types::Integer')
      expect(types).to include('Types::Bool')
    end
  end

  describe '.types_for_select' do
    it 'returns types formatted for select options' do
      options = described_class.types_for_select
      expect(options).to be_an(Array)
      expect(options.first).to be_an(Array)
      expect(options.first.length).to eq(2)
    end

    it 'includes label and value pairs' do
      options = described_class.types_for_select
      labels = options.map(&:first)
      values = options.map(&:last)

      expect(labels).to include('String')
      expect(values).to include('Types::String')
    end
  end

  describe '.grouped_types_for_select' do
    it 'returns types grouped by category' do
      grouped = described_class.grouped_types_for_select
      expect(grouped).to be_a(Hash)
    end

    it 'includes category keys' do
      grouped = described_class.grouped_types_for_select
      expect(grouped.keys).to include('Nominal')
    end
  end

  describe '.form_input_for' do
    it 'returns text input for string types' do
      expect(described_class.form_input_for('Types::String')).to eq(:text)
    end

    it 'returns number input for integer types' do
      expect(described_class.form_input_for('Types::Integer')).to eq(:number)
    end

    it 'returns checkbox for boolean types' do
      expect(described_class.form_input_for('Types::Bool')).to eq(:checkbox)
    end

    it 'returns date input for date types' do
      expect(described_class.form_input_for('Types::Date')).to eq(:date)
    end

    it 'returns datetime input for datetime types' do
      expect(described_class.form_input_for('Types::DateTime')).to eq(:datetime)
    end

    it 'returns text as default for unknown types' do
      expect(described_class.form_input_for('Types::Unknown')).to eq(:text)
    end
  end
end
```

**Step 2: Run the tests**

Run: `bundle exec rspec spec/services/dry_types_extractor_spec.rb`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add spec/services/dry_types_extractor_spec.rb
git commit -m "test: add DryTypesExtractor service specs"
```

---

## Task 15: Fix Create Redirect in FlowchartsController Spec

**Files:**
- Modify: `spec/controllers/flowcharts_controller_spec.rb:115-117`

**Step 1: Update the redirect test**

The controller redirects to `edit_flowchart_path`, not `show`. Update the test:

```ruby
# Change from:
it 'redirects to the created flowchart' do
  post :create, params: { flowchart: valid_attributes }
  expect(response).to redirect_to(Flowchart.last)
end

# To:
it 'redirects to the edit page of the created flowchart' do
  post :create, params: { flowchart: valid_attributes }
  expect(response).to redirect_to(edit_flowchart_path(Flowchart.last))
end
```

**Step 2: Update the new template test**

The new template test expects name to be 'New Flowchart' but controller passes empty string:

```ruby
# Change from:
expect(flowchart.name).to eq('New Flowchart')

# To:
expect(flowchart.name).to eq('')
```

**Step 3: Run the tests**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add spec/controllers/flowcharts_controller_spec.rb
git commit -m "fix(test): correct redirect and default name expectations in controller spec"
```

---

## Task 16: Run Full Test Suite

**Step 1: Run all tests**

Run: `bundle exec rspec`
Expected: All tests pass.

**Step 2: Commit if any fixes needed**

---

## Task 17: Final Commit and Summary

**Step 1: Create summary commit if needed**

```bash
git status
```

If there are any unstaged changes, commit them.

**Step 2: Tag the refactoring milestone**

```bash
git tag -a v1.1.0-refactored -m "Code refactoring: security fixes, shared concerns, comprehensive tests"
```

---

## Summary

This plan addresses:

| Category | Issues Fixed |
|----------|-------------|
| CRITICAL | 3 (CSRF, bare rescue, code duplication with shared concern) |
| IMPORTANT | 8 (test fixes, new specs for Entity, services) |
| MINOR | 1 (unused method removal) |

**Total new test files:** 8
**Total modified files:** 5
**Estimated commits:** 15
