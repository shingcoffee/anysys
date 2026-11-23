# Flowchart Input/Output Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate that all flowchart inputs have corresponding outputs from reachable upstream elements, blocking activation of invalid flowcharts.

**Architecture:** Hybrid client/server validation. Server-side Ruby service is authoritative for activation blocking. Client-side JavaScript provides fast feedback via toolbar. Both read implicit keys from a shared YAML config file.

**Tech Stack:** Ruby/Rails, RSpec, JavaScript/Stimulus, existing IoExtractor and ElementReachability

---

## File Structure

| File | Responsibility |
|------|----------------|
| `config/flowchart_validation.yml` | Configurable list of implicit context keys |
| `app/services/flowchart_input_output_validator.rb` | Server-side validation service |
| `app/controllers/flowchart_validation_controller.rb` | Endpoint for implicit keys JSON |
| `app/javascript/flowchart/input_output_validation_service.js` | Client-side validation |
| `spec/services/flowchart_input_output_validator_spec.rb` | Server-side tests |
| `spec/controllers/flowchart_validation_controller_spec.rb` | Endpoint tests |

---

### Task 1: Create Configuration File

**Files:**
- Create: `config/flowchart_validation.yml`

- [ ] **Step 1: Create the YAML config file**

```yaml
# config/flowchart_validation.yml
# Context keys that are implicitly available without requiring an upstream output.
# These are typically provided by the runtime before flowchart execution begins.

implicit_context_keys:
  - bound_entity
  - customer_id
  - params
  - current_user
  - current_customer
```

- [ ] **Step 2: Verify the file loads correctly**

Run: `rails runner "puts YAML.load_file('config/flowchart_validation.yml').inspect"`

Expected: `{"implicit_context_keys"=>["bound_entity", "customer_id", "params", "current_user", "current_customer"]}`

- [ ] **Step 3: Commit**

```bash
git add config/flowchart_validation.yml
git commit -m "feat: add flowchart validation config with implicit context keys"
```

---

### Task 2: Create Server-Side Validator - Basic Structure

**Files:**
- Create: `app/services/flowchart_input_output_validator.rb`
- Create: `spec/services/flowchart_input_output_validator_spec.rb`

- [ ] **Step 1: Write failing test for basic interface**

```ruby
# spec/services/flowchart_input_output_validator_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FlowchartInputOutputValidator do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, :simple, customer: customer, entity: entity) }

  describe '.call' do
    it 'returns a result object' do
      result = described_class.call(flowchart)

      expect(result).to respond_to(:valid?)
      expect(result).to respond_to(:errors)
    end

    it 'returns valid? true for a simple flowchart with no inputs' do
      result = described_class.call(flowchart)

      expect(result.valid?).to be true
      expect(result.errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb -v`

Expected: FAIL with "uninitialized constant FlowchartInputOutputValidator"

- [ ] **Step 3: Write minimal implementation**

```ruby
# app/services/flowchart_input_output_validator.rb
# frozen_string_literal: true

class FlowchartInputOutputValidator
  Result = Struct.new(:valid?, :errors, keyword_init: true)

  def self.call(flowchart)
    new(flowchart).call
  end

  def initialize(flowchart)
    @flowchart = flowchart
    @errors = []
  end

  def call
    Result.new(valid?: @errors.empty?, errors: @errors)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_input_output_validator.rb spec/services/flowchart_input_output_validator_spec.rb
git commit -m "feat: add FlowchartInputOutputValidator basic structure"
```

---

### Task 3: Implement Implicit Keys Loading

**Files:**
- Modify: `app/services/flowchart_input_output_validator.rb`
- Modify: `spec/services/flowchart_input_output_validator_spec.rb`

- [ ] **Step 1: Write failing test for implicit keys loading**

Add to `spec/services/flowchart_input_output_validator_spec.rb`:

```ruby
  describe 'implicit keys' do
    it 'loads implicit keys from config file' do
      validator = described_class.new(flowchart)

      expect(validator.send(:implicit_keys)).to include('bound_entity', 'customer_id')
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb:25 -v`

Expected: FAIL with "undefined method `implicit_keys'"

- [ ] **Step 3: Implement implicit keys loading**

Update `app/services/flowchart_input_output_validator.rb`:

```ruby
# frozen_string_literal: true

class FlowchartInputOutputValidator
  Result = Struct.new(:valid?, :errors, keyword_init: true)
  CONFIG_PATH = Rails.root.join('config', 'flowchart_validation.yml').freeze

  def self.call(flowchart)
    new(flowchart).call
  end

  def initialize(flowchart)
    @flowchart = flowchart
    @errors = []
  end

  def call
    Result.new(valid?: @errors.empty?, errors: @errors)
  end

  private

  def implicit_keys
    @implicit_keys ||= begin
      config = YAML.load_file(CONFIG_PATH)
      Set.new(config['implicit_context_keys'] || [])
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_input_output_validator.rb spec/services/flowchart_input_output_validator_spec.rb
git commit -m "feat: add implicit keys loading from config"
```

---

### Task 4: Implement Reachability Graph

**Files:**
- Modify: `app/services/flowchart_input_output_validator.rb`
- Modify: `spec/services/flowchart_input_output_validator_spec.rb`

- [ ] **Step 1: Write failing test for reachability**

Add to `spec/services/flowchart_input_output_validator_spec.rb`:

```ruby
  describe 'reachability' do
    let(:config_with_chain) do
      {
        'elements' => [
          { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
          { 'id' => 'el_2', 'type' => 'process', 'label' => 'Process', 'properties' => { 'steps' => [] } },
          { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
        ],
        'connections' => [
          { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
          { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
        ],
        'metadata' => {}
      }.to_json
    end

    let(:flowchart_with_chain) { create(:flowchart, customer: customer, entity: entity, configuration: config_with_chain) }

    it 'computes predecessors for each element' do
      validator = described_class.new(flowchart_with_chain)
      predecessors = validator.send(:build_predecessors)

      expect(predecessors['el_1']).to eq([])
      expect(predecessors['el_2']).to contain_exactly('el_1')
      expect(predecessors['el_3']).to contain_exactly('el_1', 'el_2')
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb:35 -v`

Expected: FAIL with "undefined method `build_predecessors'"

- [ ] **Step 3: Implement reachability graph**

Add to `app/services/flowchart_input_output_validator.rb` private methods:

```ruby
  def elements
    @elements ||= @flowchart.configuration_json&.dig('elements') || []
  end

  def connections
    @connections ||= @flowchart.configuration_json&.dig('connections') || []
  end

  def build_predecessors
    reverse_graph = Hash.new { |h, k| h[k] = [] }
    elements.each { |el| reverse_graph[el['id']] }

    connections.each do |conn|
      reverse_graph[conn['to']] << conn['from'] if reverse_graph.key?(conn['to'])
    end

    predecessors = {}
    elements.each do |el|
      predecessors[el['id']] = compute_all_predecessors(el['id'], reverse_graph)
    end
    predecessors
  end

  def compute_all_predecessors(element_id, reverse_graph)
    visited = Set.new
    queue = reverse_graph[element_id].dup

    while queue.any?
      current = queue.shift
      next if visited.include?(current)

      visited << current
      queue.concat(reverse_graph[current])
    end

    visited.to_a
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_input_output_validator.rb spec/services/flowchart_input_output_validator_spec.rb
git commit -m "feat: implement reachability graph for predecessor computation"
```

---

### Task 5: Implement Output Collection

**Files:**
- Modify: `app/services/flowchart_input_output_validator.rb`
- Modify: `spec/services/flowchart_input_output_validator_spec.rb`

- [ ] **Step 1: Write failing test for output collection**

Add to `spec/services/flowchart_input_output_validator_spec.rb`:

```ruby
  describe 'output collection' do
    let(:config_with_outputs) do
      {
        'elements' => [
          { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
          {
            'id' => 'el_2',
            'type' => 'process',
            'label' => 'Process',
            'properties' => {
              'steps' => [
                { 'action' => 'set_value', 'config' => { 'variableName' => 'user_name', 'value' => '"John"' } }
              ]
            }
          },
          { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
        ],
        'connections' => [
          { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
          { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
        ],
        'metadata' => {}
      }.to_json
    end

    let(:flowchart_with_outputs) { create(:flowchart, customer: customer, entity: entity, configuration: config_with_outputs) }

    it 'collects effective outputs per element' do
      validator = described_class.new(flowchart_with_outputs)
      outputs = validator.send(:collect_element_outputs)

      expect(outputs['el_2']).to include('user_name')
    end

    context 'with io_overrides renamed_to' do
      let(:config_with_rename) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'set_value', 'config' => { 'variableName' => 'result', 'value' => '42' } }
                ],
                'io_overrides' => {
                  'outputs' => [{ 'pin' => 'result', 'renamed_to' => 'result_abc123' }]
                }
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_with_rename) { create(:flowchart, customer: customer, entity: entity, configuration: config_with_rename) }

      it 'uses renamed_to as effective output key' do
        validator = described_class.new(flowchart_with_rename)
        outputs = validator.send(:collect_element_outputs)

        expect(outputs['el_2']).to include('result_abc123')
        expect(outputs['el_2']).not_to include('result')
      end
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb:60 -v`

Expected: FAIL with "undefined method `collect_element_outputs'"

- [ ] **Step 3: Implement output collection**

Add to `app/services/flowchart_input_output_validator.rb` private methods:

```ruby
  def collect_element_outputs
    outputs = {}

    elements.each do |element|
      element_id = element['id']
      element_type = element['type']
      properties = element['properties'] || {}

      pins = CodeGenerators::IoExtractor.call_element(
        element_type: element_type,
        properties: properties
      )

      output_overrides = properties.dig('io_overrides', 'outputs') || []
      override_map = output_overrides.each_with_object({}) do |o, h|
        h[o['pin']] = o['renamed_to']
      end

      effective_outputs = Set.new
      (pins[:outputs] || []).each do |pin|
        pin_name = pin[:pin]
        effective_key = override_map[pin_name] || pin_name
        effective_outputs << effective_key
      end

      outputs[element_id] = effective_outputs
    end

    outputs
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_input_output_validator.rb spec/services/flowchart_input_output_validator_spec.rb
git commit -m "feat: implement output collection with io_overrides support"
```

---

### Task 6: Implement Input Validation

**Files:**
- Modify: `app/services/flowchart_input_output_validator.rb`
- Modify: `spec/services/flowchart_input_output_validator_spec.rb`

- [ ] **Step 1: Write failing test for missing input detection**

Add to `spec/services/flowchart_input_output_validator_spec.rb`:

```ruby
  describe 'input validation' do
    context 'when input has no upstream output' do
      let(:config_with_missing_input) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:api_url]', 'method' => 'GET' } }
                ]
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_with_missing) { create(:flowchart, customer: customer, entity: entity, configuration: config_with_missing_input) }

      it 'returns invalid with error for missing input' do
        result = described_class.call(flowchart_with_missing)

        expect(result.valid?).to be false
        expect(result.errors.size).to eq(1)
        expect(result.errors.first[:missing_input]).to eq('api_url')
        expect(result.errors.first[:element_id]).to eq('el_2')
      end
    end

    context 'when input is satisfied by upstream output' do
      let(:config_with_satisfied_input) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Set URL',
              'properties' => {
                'steps' => [
                  { 'action' => 'set_value', 'config' => { 'variableName' => 'api_url', 'value' => '"https://api.example.com"' } }
                ]
              }
            },
            {
              'id' => 'el_3',
              'type' => 'process',
              'label' => 'Call API',
              'properties' => {
                'steps' => [
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:api_url]', 'method' => 'GET' } }
                ]
              }
            },
            { 'id' => 'el_4', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' },
            { 'id' => 'c3', 'from' => 'el_3', 'to' => 'el_4' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_satisfied) { create(:flowchart, customer: customer, entity: entity, configuration: config_with_satisfied_input) }

      it 'returns valid' do
        result = described_class.call(flowchart_satisfied)

        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end
    end

    context 'when input is an implicit key' do
      let(:config_with_implicit_input) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'set_value', 'config' => { 'variableName' => 'cid', 'value' => 'ctx[:customer_id]' } }
                ]
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_implicit) { create(:flowchart, customer: customer, entity: entity, configuration: config_with_implicit_input) }

      it 'returns valid because implicit keys are excluded' do
        result = described_class.call(flowchart_implicit)

        expect(result.valid?).to be true
      end
    end

    context 'when input has tombstone override' do
      let(:config_with_tombstone) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:api_url]', 'method' => 'GET' } }
                ],
                'io_overrides' => {
                  'inputs' => [{ 'pin' => 'api_url', 'override_key' => '' }]
                }
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_tombstone) { create(:flowchart, customer: customer, entity: entity, configuration: config_with_tombstone) }

      it 'returns valid because tombstone means user said no producer needed' do
        result = described_class.call(flowchart_tombstone)

        expect(result.valid?).to be true
      end
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb:120 -v`

Expected: FAIL (returns valid when should be invalid)

- [ ] **Step 3: Implement input validation in call method**

Update `app/services/flowchart_input_output_validator.rb`:

```ruby
# frozen_string_literal: true

class FlowchartInputOutputValidator
  Result = Struct.new(:valid?, :errors, keyword_init: true)
  CONFIG_PATH = Rails.root.join('config', 'flowchart_validation.yml').freeze

  def self.call(flowchart)
    new(flowchart).call
  end

  def initialize(flowchart)
    @flowchart = flowchart
    @errors = []
  end

  def call
    validate_inputs
    Result.new(valid?: @errors.empty?, errors: @errors)
  end

  private

  def validate_inputs
    predecessors = build_predecessors
    element_outputs = collect_element_outputs

    elements.each do |element|
      validate_element_inputs(element, predecessors, element_outputs)
    end
  end

  def validate_element_inputs(element, predecessors, element_outputs)
    element_id = element['id']
    element_type = element['type']
    properties = element['properties'] || {}

    pins = CodeGenerators::IoExtractor.call_element(
      element_type: element_type,
      properties: properties
    )

    input_overrides = properties.dig('io_overrides', 'inputs') || []
    override_map = input_overrides.each_with_object({}) do |o, h|
      h[o['pin']] = o['override_key']
    end

    upstream_ids = predecessors[element_id] || []
    available_outputs = upstream_ids.flat_map { |id| element_outputs[id]&.to_a || [] }.to_set

    (pins[:inputs] || []).each do |pin|
      pin_name = pin[:pin]
      effective_key = override_map.key?(pin_name) ? override_map[pin_name] : pin_name

      next if effective_key == ''
      next if implicit_keys.include?(effective_key)
      next if available_outputs.include?(effective_key)

      @errors << {
        element_id: element_id,
        element_label: element['label'] || element_id,
        missing_input: effective_key,
        message: "Input \"#{effective_key}\" has no upstream output"
      }
    end
  end

  def implicit_keys
    @implicit_keys ||= begin
      config = YAML.load_file(CONFIG_PATH)
      Set.new(config['implicit_context_keys'] || [])
    end
  end

  def elements
    @elements ||= @flowchart.configuration_json&.dig('elements') || []
  end

  def connections
    @connections ||= @flowchart.configuration_json&.dig('connections') || []
  end

  def build_predecessors
    reverse_graph = Hash.new { |h, k| h[k] = [] }
    elements.each { |el| reverse_graph[el['id']] }

    connections.each do |conn|
      reverse_graph[conn['to']] << conn['from'] if reverse_graph.key?(conn['to'])
    end

    predecessors = {}
    elements.each do |el|
      predecessors[el['id']] = compute_all_predecessors(el['id'], reverse_graph)
    end
    predecessors
  end

  def compute_all_predecessors(element_id, reverse_graph)
    visited = Set.new
    queue = reverse_graph[element_id].dup

    while queue.any?
      current = queue.shift
      next if visited.include?(current)

      visited << current
      queue.concat(reverse_graph[current])
    end

    visited.to_a
  end

  def collect_element_outputs
    outputs = {}

    elements.each do |element|
      element_id = element['id']
      element_type = element['type']
      properties = element['properties'] || {}

      pins = CodeGenerators::IoExtractor.call_element(
        element_type: element_type,
        properties: properties
      )

      output_overrides = properties.dig('io_overrides', 'outputs') || []
      override_map = output_overrides.each_with_object({}) do |o, h|
        h[o['pin']] = o['renamed_to']
      end

      effective_outputs = Set.new
      (pins[:outputs] || []).each do |pin|
        pin_name = pin[:pin]
        effective_key = override_map[pin_name] || pin_name
        effective_outputs << effective_key
      end

      outputs[element_id] = effective_outputs
    end

    outputs
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_input_output_validator.rb spec/services/flowchart_input_output_validator_spec.rb
git commit -m "feat: implement input validation against upstream outputs"
```

---

### Task 7: Create Implicit Keys Endpoint

**Files:**
- Create: `app/controllers/flowchart_validation_controller.rb`
- Create: `spec/controllers/flowchart_validation_controller_spec.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write failing test for endpoint**

```ruby
# spec/controllers/flowchart_validation_controller_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FlowchartValidationController, type: :controller do
  describe 'GET #implicit_keys' do
    it 'returns JSON with implicit keys' do
      get :implicit_keys, format: :json

      expect(response).to be_successful
      json = JSON.parse(response.body)
      expect(json['implicit_keys']).to be_an(Array)
      expect(json['implicit_keys']).to include('bound_entity', 'customer_id')
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/flowchart_validation_controller_spec.rb -v`

Expected: FAIL with "uninitialized constant FlowchartValidationController"

- [ ] **Step 3: Add route**

Add to `config/routes.rb` before the catch-all route (around line 196, after the code_generators namespace):

```ruby
  # Flowchart validation config endpoint
  get 'flowchart_validation/implicit_keys', to: 'flowchart_validation#implicit_keys'
```

- [ ] **Step 4: Create controller**

```ruby
# app/controllers/flowchart_validation_controller.rb
# frozen_string_literal: true

class FlowchartValidationController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :set_current_customer, raise: false
  skip_before_action :authenticate_user!, raise: false

  CONFIG_PATH = Rails.root.join('config', 'flowchart_validation.yml').freeze

  def implicit_keys
    config = YAML.load_file(CONFIG_PATH)
    render json: { implicit_keys: config['implicit_context_keys'] || [] }
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/flowchart_validation_controller_spec.rb -v`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/flowchart_validation_controller.rb spec/controllers/flowchart_validation_controller_spec.rb config/routes.rb
git commit -m "feat: add implicit keys endpoint for client-side validation"
```

---

### Task 8: Integrate Validation into Activate Action

**Files:**
- Modify: `app/controllers/flowcharts_controller.rb`
- Modify: `spec/controllers/flowcharts_controller_spec.rb`

- [ ] **Step 1: Write failing test for activation blocking**

Add to `spec/controllers/flowcharts_controller_spec.rb` inside `describe 'POST #activate'`:

```ruby
    context 'when flowchart has validation errors' do
      let(:config_with_missing_input) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'x' => 100, 'y' => 100, 'width' => 100, 'height' => 45, 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'x' => 100,
              'y' => 200,
              'width' => 100,
              'height' => 45,
              'properties' => {
                'steps' => [
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:missing_url]', 'method' => 'GET' } }
                ]
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'x' => 100, 'y' => 300, 'width' => 100, 'height' => 45, 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => { 'canvas' => { 'width' => 1200, 'height' => 800 } }
        }.to_json
      end

      let(:invalid_flowchart) { Flowchart.create!(valid_attributes.merge(status: :draft, configuration: config_with_missing_input)) }

      it 'does not activate the flowchart' do
        post :activate, params: { customer_id: customer.id, id: invalid_flowchart.to_param }
        invalid_flowchart.reload
        expect(invalid_flowchart.status).to eq('draft')
      end

      it 'redirects to edit page with show_validation param' do
        post :activate, params: { customer_id: customer.id, id: invalid_flowchart.to_param }
        expect(response).to redirect_to(edit_flowchart_path(customer.id, invalid_flowchart, show_validation: true))
      end

      it 'sets alert flash with error count' do
        post :activate, params: { customer_id: customer.id, id: invalid_flowchart.to_param }
        expect(flash[:alert]).to include('Cannot activate')
        expect(flash[:alert]).to include('missing upstream output')
      end

      it 'stores validation errors in flash' do
        post :activate, params: { customer_id: customer.id, id: invalid_flowchart.to_param }
        expect(flash[:validation_errors]).to be_present
        errors = JSON.parse(flash[:validation_errors])
        expect(errors.first['missing_input']).to eq('missing_url')
      end
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb:345 -v`

Expected: FAIL (flowchart gets activated despite validation errors)

- [ ] **Step 3: Modify activate action**

Update `app/controllers/flowcharts_controller.rb` `activate` method:

```ruby
  def activate
    if @flowchart.active?
      flash[:alert] = 'Flowchart is already active.'
      redirect_to flowchart_path(current_customer_id, @flowchart), status: :unprocessable_entity
      return
    end

    validation_result = FlowchartInputOutputValidator.call(@flowchart)

    if validation_result.errors.any?
      flash[:validation_errors] = validation_result.errors.to_json
      flash[:alert] = "Cannot activate: #{validation_result.errors.size} input(s) missing upstream outputs"
      redirect_to edit_flowchart_path(current_customer_id, @flowchart, show_validation: true)
      return
    end

    @flowchart.update!(status: :active)
    redirect_to flowchart_path(current_customer_id, @flowchart), notice: 'Flowchart activated successfully.'
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/flowcharts_controller.rb spec/controllers/flowcharts_controller_spec.rb
git commit -m "feat: block activation when input/output validation fails"
```

---

### Task 9: Create Client-Side Validation Service

**Files:**
- Create: `app/javascript/flowchart/input_output_validation_service.js`

- [ ] **Step 1: Create the JavaScript validation service**

```javascript
// app/javascript/flowchart/input_output_validation_service.js

import { ElementReachability } from "controllers/property_editor/element_io/reachability"

/**
 * Client-side input/output validation service.
 * Validates that all element inputs have corresponding outputs from reachable upstream elements.
 */
export class InputOutputValidationService {
  static _implicitKeysCache = null
  static _implicitKeysPromise = null

  constructor(canvas) {
    this.canvas = canvas
    this.implicitKeys = new Set()
  }

  /**
   * Load implicit keys from server. Caches result for subsequent calls.
   */
  async loadImplicitKeys() {
    if (InputOutputValidationService._implicitKeysCache) {
      this.implicitKeys = InputOutputValidationService._implicitKeysCache
      return
    }

    if (InputOutputValidationService._implicitKeysPromise) {
      await InputOutputValidationService._implicitKeysPromise
      this.implicitKeys = InputOutputValidationService._implicitKeysCache
      return
    }

    InputOutputValidationService._implicitKeysPromise = this._fetchImplicitKeys()
    await InputOutputValidationService._implicitKeysPromise
    this.implicitKeys = InputOutputValidationService._implicitKeysCache
  }

  async _fetchImplicitKeys() {
    try {
      const response = await fetch("/flowchart_validation/implicit_keys.json")
      if (response.ok) {
        const data = await response.json()
        InputOutputValidationService._implicitKeysCache = new Set(data.implicit_keys || [])
      } else {
        InputOutputValidationService._implicitKeysCache = new Set()
      }
    } catch (e) {
      console.warn("[InputOutputValidationService] Failed to load implicit keys:", e)
      InputOutputValidationService._implicitKeysCache = new Set()
    }
  }

  /**
   * Validate all elements and return errors.
   * @returns {Array<{elementId: string, type: string, message: string}>}
   */
  validate() {
    const errors = []
    const reachability = new ElementReachability(this.canvas)
    const elementOutputs = this._collectElementOutputs()

    this.canvas.iterateElements((element) => {
      const elementErrors = this._validateElementInputs(element, reachability, elementOutputs)
      errors.push(...elementErrors)
    })

    return errors
  }

  _collectElementOutputs() {
    const outputs = new Map()

    this.canvas.iterateElements((element) => {
      const pins = this.canvas.getElementPins(element.id)
      const outputPins = pins?.outputs || []
      const overrideList = element.properties?.io_overrides?.outputs || []

      const overrideMap = new Map()
      for (const o of overrideList) {
        overrideMap.set(o.pin, o.renamed_to)
      }

      const effectiveOutputs = new Set()
      for (const pin of outputPins) {
        const pinName = pin.pin
        const effectiveKey = overrideMap.get(pinName) || pinName
        effectiveOutputs.add(effectiveKey)
      }

      outputs.set(element.id, effectiveOutputs)
    })

    return outputs
  }

  _validateElementInputs(element, reachability, elementOutputs) {
    const errors = []
    const pins = this.canvas.getElementPins(element.id)
    const inputPins = pins?.inputs || []

    const overrideList = element.properties?.io_overrides?.inputs || []
    const overrideMap = new Map()
    for (const o of overrideList) {
      overrideMap.set(o.pin, o.override_key)
    }

    const predecessorIds = reachability.predecessors(element.id)
    const availableOutputs = new Set()
    for (const predId of predecessorIds) {
      const predOutputs = elementOutputs.get(predId)
      if (predOutputs) {
        for (const key of predOutputs) {
          availableOutputs.add(key)
        }
      }
    }

    for (const pin of inputPins) {
      const pinName = pin.pin
      const effectiveKey = overrideMap.has(pinName) ? overrideMap.get(pinName) : pinName

      // Skip tombstone (empty string means user said no producer needed)
      if (effectiveKey === "") continue

      // Skip implicit keys
      if (this.implicitKeys.has(effectiveKey)) continue

      // Check if available in upstream outputs
      if (availableOutputs.has(effectiveKey)) continue

      errors.push({
        elementId: element.id,
        type: "missing_input",
        message: `Input "${this._safe(effectiveKey)}" has no upstream output`
      })
    }

    return errors
  }

  _safe(text) {
    if (!text) return ""
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
```

- [ ] **Step 2: Verify file exists and has no syntax errors**

Run: `node --check app/javascript/flowchart/input_output_validation_service.js`

Expected: No output (no syntax errors)

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/input_output_validation_service.js
git commit -m "feat: add client-side input/output validation service"
```

---

### Task 10: Integrate Client-Side Validation into Canvas Controller

**Files:**
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js`

- [ ] **Step 1: Add import at top of file**

Add after the existing imports (around line 9):

```javascript
import { InputOutputValidationService } from "flowchart/input_output_validation_service"
```

- [ ] **Step 2: Add autoValidate value**

Add to `static values` object:

```javascript
  static values = {
    id: Number,
    customerId: Number,
    configuration: String,
    entityAttributes: Array,
    flowchartType: String,
    readOnly: { type: Boolean, default: false },
    autoValidate: { type: Boolean, default: false }
  }
```

- [ ] **Step 3: Modify validate method to be async and include I/O validation**

Replace the existing `validate()` method:

```javascript
  async validate() {
    // Existing structural validation
    const structuralValidator = new ValidationService(this.canvas.elements, this.canvas.connections)
    const { errors: structuralErrors, warnings } = structuralValidator.validate()

    // New input/output validation
    const ioValidator = new InputOutputValidationService(this.canvas)
    await ioValidator.loadImplicitKeys()
    const ioErrors = ioValidator.validate()

    // Merge results
    const allErrors = [...structuralErrors, ...ioErrors]
    this._showValidationResults(allErrors, warnings)

    return allErrors.length === 0
  }
```

- [ ] **Step 4: Add auto-validation trigger in _onCanvasReady**

Add at the end of `_onCanvasReady()` method (before the closing brace):

```javascript
    // Auto-validate if redirected from failed activation
    if (this.autoValidateValue) {
      requestAnimationFrame(() => this.validate())
    }
```

- [ ] **Step 5: Verify the file has no syntax errors**

Run: `node --check app/javascript/controllers/flowchart_canvas_controller.js`

Expected: No output (no syntax errors)

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/flowchart_canvas_controller.js
git commit -m "feat: integrate I/O validation into canvas controller"
```

---

### Task 11: Add Auto-Validate Data Attribute to Editor View

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb`

- [ ] **Step 1: Add auto-validate data attribute**

Find the opening div with `data-controller="flowchart-canvas"` (around line 3-10) and add the auto-validate attribute:

Change from:

```erb
     data-flowchart-canvas-read-only-value="<%= @flowchart.active? %>">
```

To:

```erb
     data-flowchart-canvas-read-only-value="<%= @flowchart.active? %>"
     data-flowchart-canvas-auto-validate-value="<%= params[:show_validation] == 'true' %>">
```

- [ ] **Step 2: Verify the change renders correctly**

Run: `rails runner "puts ActionController::Base.helpers.sanitize('<%= params[:show_validation] %>').inspect"`

Expected: Should not error

- [ ] **Step 3: Commit**

```bash
git add app/views/flowcharts/_editor.html.erb
git commit -m "feat: add auto-validate trigger when redirected from failed activation"
```

---

### Task 12: Add Factory Trait for Invalid Flowchart

**Files:**
- Modify: `spec/factories/flowcharts.rb`

- [ ] **Step 1: Add trait for flowchart with missing input**

Add to `spec/factories/flowcharts.rb` before the closing `end`:

```ruby
    trait :with_missing_input do
      configuration do
        {
          'elements' => [
            {
              'id' => 'start_1',
              'type' => 'start',
              'x' => 150,
              'y' => 100,
              'width' => 100,
              'height' => 45,
              'label' => 'Start',
              'properties' => {}
            },
            {
              'id' => 'process_1',
              'type' => 'process',
              'x' => 150,
              'y' => 200,
              'width' => 100,
              'height' => 45,
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:missing_api_url]', 'method' => 'GET' } }
                ]
              }
            },
            {
              'id' => 'end_1',
              'type' => 'end',
              'x' => 150,
              'y' => 300,
              'width' => 100,
              'height' => 45,
              'label' => 'End',
              'properties' => {}
            }
          ],
          'connections' => [
            { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'process_1' },
            { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'end_1' }
          ],
          'metadata' => {
            'canvas' => { 'width' => 1200, 'height' => 800 },
            'created_at' => Time.current.iso8601
          }
        }.to_json
      end
    end
```

- [ ] **Step 2: Verify factory works**

Run: `rails runner "FactoryBot.build(:flowchart, :with_missing_input).valid?"`

Expected: `true` (factory creates valid flowchart record, but it has missing inputs for our validation)

- [ ] **Step 3: Commit**

```bash
git add spec/factories/flowcharts.rb
git commit -m "test: add factory trait for flowchart with missing input"
```

---

### Task 13: Run Full Test Suite

**Files:** None (verification only)

- [ ] **Step 1: Run service validator specs**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb -v`

Expected: All tests pass

- [ ] **Step 2: Run controller specs**

Run: `bundle exec rspec spec/controllers/flowcharts_controller_spec.rb -v`

Expected: All tests pass

- [ ] **Step 3: Run validation controller specs**

Run: `bundle exec rspec spec/controllers/flowchart_validation_controller_spec.rb -v`

Expected: All tests pass

- [ ] **Step 4: Run full spec suite to check for regressions**

Run: `bundle exec rspec --format progress`

Expected: All tests pass

- [ ] **Step 5: Final commit with all changes**

```bash
git status
git log --oneline -10
```

Expected: Clean working tree, all commits present

---

## Summary

This plan implements flowchart input/output validation in 13 tasks:

1. **Task 1:** Config file for implicit keys
2. **Tasks 2-6:** Server-side validator with TDD (basic structure, implicit keys, reachability, outputs, inputs)
3. **Task 7:** Implicit keys endpoint
4. **Task 8:** Activation blocking integration
5. **Tasks 9-10:** Client-side validation service and canvas integration
6. **Task 11:** Auto-validate on redirect
7. **Task 12:** Test factory trait
8. **Task 13:** Full test verification
