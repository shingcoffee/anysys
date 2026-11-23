# Process Element I/O Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate the property editor's I/O tab for process elements by extracting ctx reads/writes from every step's code generator (raw union, option A).

**Architecture:** Add a process-specific branch to `CodeGenerators::IoExtractor::ElementExtractor#call`. Instead of looking up a non-existent `process_generator.rb`, iterate over `properties["steps"]`, call `IoExtractor.call(action:, config:)` for each, and concatenate + dedupe the resulting pins. No frontend, routing, controller, or registry changes.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec.

**Spec:** `docs/superpowers/specs/2026-04-21-process-element-io-tab-design.md`

---

## File Structure

- **Modify:** `app/services/code_generators/io_extractor.rb` — extend `ElementExtractor#call` with process branch, add private `extract_process_io` method.
- **Modify:** `spec/services/code_generators/io_extractor_spec.rb` — add a new `RSpec.describe` block covering `call_element(element_type: "process", ...)` for all edge cases.
- **Modify:** `spec/controllers/code_generators/element_type_io_params_controller_spec.rb` — add one integration assertion hitting the process element path via HTTP.

No new files. No frontend changes. No controller changes.

---

## Task 1: Add failing process-branch tests to io_extractor_spec

**Files:**
- Modify: `spec/services/code_generators/io_extractor_spec.rb` (append new describe block at the end of the file)

- [ ] **Step 1: Write failing tests covering the process branch**

Append to `spec/services/code_generators/io_extractor_spec.rb`:

```ruby
RSpec.describe CodeGenerators::IoExtractor, ".call_element (process element)" do
  let(:api_call_config_get) do
    { "httpMethod"     => "GET",
      "url"            => '"https://example.com"',
      "resultVar"      => "resp",
      "responseFormat" => "json" }
  end

  let(:api_call_config_literal) do
    { "httpMethod"     => "GET",
      "resultVar"      => "resp2",
      "responseFormat" => "json" }
  end

  it "returns empty pins when properties has no steps key" do
    result = described_class.call_element(element_type: "process", properties: {})
    expect(result).to eq(inputs: [], outputs: [])
  end

  it "returns empty pins for an empty steps array" do
    result = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [] }
    )
    expect(result).to eq(inputs: [], outputs: [])
  end

  it "returns empty pins when steps is not an array" do
    result = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => "nonsense" }
    )
    expect(result).to eq(inputs: [], outputs: [])
  end

  it "unions outputs across multiple api_call steps" do
    result = described_class.call_element(
      element_type: "process",
      properties:   {
        "steps" => [
          { "action" => "api_call", "config" => api_call_config_get },
          { "action" => "api_call", "config" => api_call_config_literal }
        ]
      }
    )
    pins = result[:outputs].map { |o| o[:pin] }
    expect(pins).to include("resp", "resp2")
  end

  it "dedupes duplicate pins across steps preserving first-seen order" do
    result = described_class.call_element(
      element_type: "process",
      properties:   {
        "steps" => [
          { "action" => "api_call", "config" => api_call_config_get },
          { "action" => "api_call", "config" => api_call_config_get }
        ]
      }
    )
    pins = result[:outputs].map { |o| o[:pin] }
    expect(pins).to eq(pins.uniq)
    expect(pins).to include("resp")
  end

  it "reports a pin that is both read and written across steps in both inputs and outputs" do
    read_then_write = Class.new do
      def initialize(_element, _ctx); end
      def generate_body; "ctx[:foo] = ctx[:foo].to_i + 1"; end
    end
    registry = CodeGenerators::GeneratorRegistry.instance
    allow(registry).to receive(:find_step_action).with("rw_foo").and_return(read_then_write)
    allow(registry).to receive(:find_step_action).and_call_original

    result = described_class.call_element(
      element_type: "process",
      properties:   {
        "steps" => [{ "action" => "rw_foo", "config" => {} }]
      }
    )
    expect(result[:inputs].map { |i| i[:pin] }).to include("foo")
    expect(result[:outputs].map { |o| o[:pin] }).to include("foo")
  end

  it "skips steps with blank action" do
    result = described_class.call_element(
      element_type: "process",
      properties:   {
        "steps" => [
          { "action" => "",        "config" => {} },
          { "action" => nil,       "config" => {} },
          { "action" => "api_call", "config" => api_call_config_get }
        ]
      }
    )
    expect(result[:outputs].map { |o| o[:pin] }).to include("resp")
  end

  it "contributes nothing for a step whose action is unknown" do
    result = described_class.call_element(
      element_type: "process",
      properties:   {
        "steps" => [
          { "action" => "__not_a_real_action__", "config" => {} },
          { "action" => "api_call",              "config" => api_call_config_get }
        ]
      }
    )
    pins = result[:outputs].map { |o| o[:pin] }
    expect(pins).to include("resp")
    expect(pins).to all(be_a(String))
  end

  it "contributes nothing for a step whose generator raises" do
    exploding = Class.new do
      def initialize(_element, _ctx); end
      def generate_body; raise "boom"; end
    end
    registry = CodeGenerators::GeneratorRegistry.instance
    allow(registry).to receive(:find_step_action).with("exploding_step").and_return(exploding)
    allow(registry).to receive(:find_step_action).and_call_original

    result = described_class.call_element(
      element_type: "process",
      properties:   {
        "steps" => [
          { "action" => "exploding_step", "config" => {} },
          { "action" => "api_call",       "config" => api_call_config_get }
        ]
      }
    )
    expect(result[:outputs].map { |o| o[:pin] }).to include("resp")
  end

  it "accepts symbol keys for steps/action/config" do
    result = described_class.call_element(
      element_type: "process",
      properties:   {
        steps: [
          { action: "api_call", config: api_call_config_get }
        ]
      }
    )
    expect(result[:outputs].map { |o| o[:pin] }).to include("resp")
  end
end
```

- [ ] **Step 2: Run the new describe block to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/io_extractor_spec.rb -e "process element"`

Expected: Multiple failures. The "returns empty pins when properties has no steps key" and similar "empty" cases may pass (current behavior already returns EMPTY for unknown element type "process"). The "unions outputs", "dedupes", "accepts symbol keys", "skips steps with blank action", "contributes nothing for unknown action", "contributes nothing for raising generator", and "reports a pin that is both read and written" cases MUST fail (they assert non-empty pins but current code returns EMPTY).

- [ ] **Step 3: Commit the failing tests**

```bash
git add spec/services/code_generators/io_extractor_spec.rb
git commit -m "test(io_extractor): add failing specs for process element I/O extraction"
```

---

## Task 2: Implement process branch in ElementExtractor

**Files:**
- Modify: `app/services/code_generators/io_extractor.rb` (around line 51, the `ElementExtractor#call` method, and add a private method)

- [ ] **Step 1: Update `ElementExtractor#call` to dispatch on element type**

Locate `ElementExtractor#call` in `app/services/code_generators/io_extractor.rb` (currently lines 51-65). Replace the method body so the whole class looks like:

```ruby
class ElementExtractor
  def initialize(element_type:, properties:)
    @element_type = element_type
    @properties = properties || {}
  end

  def call
    return extract_process_io if @element_type.to_s == "process"

    generator_class = CodeGenerators::GeneratorRegistry.instance.find_element_type(@element_type)
    return EMPTY unless generator_class

    body = build_body(generator_class)
    return EMPTY unless body

    ast = BodyAnalyzer.call(body)
    config_expr_pins = extract_config_expr_pins

    {
      inputs:  dedupe_preserving_order(ast[:reads]).map { |r| input_hash(r, config_expr_pins) },
      outputs: dedupe_preserving_order(ast[:writes]).map { |w| output_hash(w) }
    }
  end

  private

  def extract_process_io
    steps = @properties["steps"] || @properties[:steps]
    return EMPTY unless steps.is_a?(Array) && steps.any?

    inputs = []
    outputs = []

    steps.each do |step|
      next unless step.is_a?(Hash)

      action = step["action"] || step[:action]
      next if action.nil? || action.to_s.strip.empty?

      config = step["config"] || step[:config] || {}
      step_io = CodeGenerators::IoExtractor.call(action: action, config: config)

      inputs.concat(step_io[:inputs] || [])
      outputs.concat(step_io[:outputs] || [])
    end

    {
      inputs:  dedupe_hashes_by_pin(inputs),
      outputs: dedupe_hashes_by_pin(outputs)
    }
  end

  def dedupe_hashes_by_pin(entries)
    seen = Set.new
    entries.each_with_object([]) do |e, acc|
      pin = e[:pin]
      next if seen.include?(pin)

      seen << pin
      acc << e
    end
  end

  def build_body(generator_class)
    element = {
      "id"         => "__io_extract_elem_stub__",
      "label"      => "stub",
      "type"       => @element_type,
      "properties" => @properties,
      "config"     => @properties
    }
    generator_class.new(element, { config: @properties }).generate_body
  rescue StandardError
    nil
  end

  def extract_config_expr_pins
    pins = Set.new
    deep_each_string(@properties) do |value|
      value.scan(CTX_SYMBOL_IN_STRING) { |m| pins << m.first }
    end
    pins
  end

  def deep_each_string(obj, &block)
    case obj
    when String then yield(obj)
    when Hash   then obj.each_value { |v| deep_each_string(v, &block) }
    when Array  then obj.each       { |v| deep_each_string(v, &block) }
    end
  end

  def dedupe_preserving_order(entries)
    seen = Set.new
    entries.each_with_object([]) do |e, acc|
      next if seen.include?(e[:pin])

      seen << e[:pin]
      acc << e
    end
  end

  def input_hash(read, config_expr_pins)
    {
      pin:     read[:pin],
      ctx_key: read[:pin],
      source:  config_expr_pins.include?(read[:pin]) ? "config_expr" : "generator_literal"
    }
  end

  def output_hash(write)
    { pin: write[:pin], ctx_key: write[:pin] }
  end
end
```

The only behavioral changes: (1) `call` now returns `extract_process_io` when element_type is "process"; (2) new private `extract_process_io` and `dedupe_hashes_by_pin` methods. All other private methods are unchanged.

- [ ] **Step 2: Run the process-branch specs to verify they pass**

Run: `bundle exec rspec spec/services/code_generators/io_extractor_spec.rb -e "process element"`

Expected: all examples pass (0 failures).

- [ ] **Step 3: Run the full io_extractor spec to verify no regressions**

Run: `bundle exec rspec spec/services/code_generators/io_extractor_spec.rb`

Expected: all examples pass (0 failures).

- [ ] **Step 4: Commit the implementation**

```bash
git add app/services/code_generators/io_extractor.rb
git commit -m "feat(io_extractor): extract process element I/O from step generators (raw union)"
```

---

## Task 3: Add HTTP integration test for process element_type route

**Files:**
- Modify: `spec/controllers/code_generators/element_type_io_params_controller_spec.rb`

- [ ] **Step 1: Add a request-level assertion for the process element_type**

Append a new `it` block inside the existing `describe "POST /code_generators/element_types/:element_type/io_params"`:

```ruby
it "returns 200 with unioned pins for a process element with steps" do
  post "/code_generators/element_types/process/io_params",
       params: {
         properties: {
           steps: [
             { action: "api_call",
               config: { httpMethod: "GET",
                         url:        '"https://example.com"',
                         resultVar:  "resp",
                         responseFormat: "json" } }
           ]
         }
       },
       as: :json
  expect(response).to have_http_status(:ok)
  body = JSON.parse(response.body)
  expect(body["outputs"].map { |o| o["pin"] }).to include("resp")
end

it "returns empty pins for a process element with no steps" do
  post "/code_generators/element_types/process/io_params",
       params: { properties: { steps: [] } },
       as: :json
  expect(response).to have_http_status(:ok)
  expect(JSON.parse(response.body)).to eq("inputs" => [], "outputs" => [])
end
```

- [ ] **Step 2: Run the request spec to verify it passes**

Run: `bundle exec rspec spec/controllers/code_generators/element_type_io_params_controller_spec.rb`

Expected: all examples pass (0 failures).

- [ ] **Step 3: Commit the integration test**

```bash
git add spec/controllers/code_generators/element_type_io_params_controller_spec.rb
git commit -m "test(element_type_io_params): cover process element HTTP path"
```

---

## Task 4: Manual verification in the browser

**Files:** none (verification only)

- [ ] **Step 1: Restart the Rails server if it is not already running**

Run: `ls tmp/pids/server.pid` — if present, the server is running and no action is needed. If missing, run `bundle exec rails server -b 0.0.0.0 -p 3000` in a background process.

- [ ] **Step 2: Precompile assets if recent asset changes are pending**

Not required for this change (no JS/CSS modifications), but safe to run: `rm -f public/assets/.manifest.json && RAILS_ENV=development bundle exec rails assets:precompile`

- [ ] **Step 3: Load the flowchart edit page and verify the I/O tab**

Open `/96546124/flowcharts/49/edit` in a browser. Click a process element. Select the **I/O** tab in the property editor.

Expected: the tab shows **Inputs** and **Outputs** sections populated with pins corresponding to the ctx reads/writes performed by the process's steps — not the "This element reads no ctx values" / "This element writes no ctx values" empty messages.

If the process has no steps, the empty-state messages should still appear.

- [ ] **Step 4: Check full spec suite for regressions**

Run: `bundle exec rspec spec/services/code_generators/ spec/controllers/code_generators/`

Expected: 0 failures across the full code-generators spec surface.

- [ ] **Step 5: Final commit (if any doc/plan touch-ups are needed)**

No code commit for this task. If any tweaks surfaced during manual verification, they belong to a new task; do not bundle them with verification.

---

## Verification Checklist

- [ ] `bundle exec rspec spec/services/code_generators/io_extractor_spec.rb` passes.
- [ ] `bundle exec rspec spec/controllers/code_generators/element_type_io_params_controller_spec.rb` passes.
- [ ] `bundle exec rspec spec/services/code_generators/ spec/controllers/code_generators/` passes (no regressions).
- [ ] Manual click-through on `/96546124/flowcharts/49/edit`: process element's I/O tab renders non-empty Inputs and Outputs when steps are present.
- [ ] Manual click-through: process element with no steps still renders the empty-state messages.
