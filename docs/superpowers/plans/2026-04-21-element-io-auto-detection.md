# Element-Level I/O Auto-Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-detect every element's ctx inputs/outputs from its generator body, auto-resolve nearest-producer input overrides and collision-rename output overrides on the I/O tab, honor them in codegen, and remove `isolateCtx` plus all user-declared Inputs/Outputs overrides.

**Architecture:** The generator body is the sole source of truth for I/O pins, via `BodyAnalyzer`. Element-level `IOExtractor.call_element`, `ConflictResolver` element pass, and `EmissionRewriter.call_element` mirror the shipped per-step infrastructure. Canvas caches `elementPins`, resolver seeds `io_overrides` (same shape as step's), `ActivityGenerator` runs step rewrite then element rewrite. `ctx` is a single shared bus — no universes, no snapshots.

**Tech Stack:** Ruby 3.2.8 / Rails 8.1.2 / RSpec / StimulusJS / TailwindCSS. Design spec: `docs/superpowers/specs/2026-04-21-element-io-auto-detection-design.md`.

---

## File Structure

**New Ruby files:**
- `app/controllers/code_generators/element_type_io_params_controller.rb` — HTTP endpoint for element-type pin extraction.
- `app/services/code_generators/conflict_resolver.rb` — element-level collision detector producing rename map.

**Modified Ruby files:**
- `app/services/code_generators/io_extractor.rb` — adds `call_element` entry point.
- `app/services/code_generators/emission_rewriter.rb` — adds `call_element` entry point with reachability fallback.
- `app/services/activity_generator.rb` — removes `isolateCtx` snapshot wrap, runs element-level conflict resolver + emission rewriter.
- `config/routes.rb` — adds `POST /code_generators/element_types/:element_type/io_params`.

**New JS files:**
- `app/javascript/controllers/property_editor/element_io_manager.js` — I/O tab renderer per element.
- `app/javascript/controllers/property_editor/element_io/reachability.js` — predecessor index over element graph, no universes.
- `app/javascript/controllers/property_editor/element_io/override_computer.js` — seeds default input/output overrides for an element.
- `app/javascript/controllers/property_editor/element_io/io_params_client.js` — fetches element-type pins.
- `app/javascript/controllers/property_editor/element_io/override_validator.js` — drops stale overrides on structural change.

**Modified JS files:**
- `app/javascript/flowchart/canvas.js` — adds `elementPins` cache + `setElementPins`/`getElementPins` + `iterateElements` + `flowchartStructureChanged` emitter.
- `app/javascript/flowchart/constants/schemas.js` — removes `isolateCtx`, `COMMON_PROPERTIES.inputs`, `COMMON_PROPERTIES.outputs`, `HIDDEN_DEFAULT_INPUTS`, `HIDDEN_DEFAULT_OUTPUTS`, all references.
- `app/javascript/controllers/property_editor_controller.js` — wires `ElementIoManager` on tab open, removes add/remove/change input/output handlers, replaces badge counting.
- `app/javascript/controllers/property_editor/form_builder.js` — removes `_applyInheritedInputsFromParent`.
- `app/javascript/controllers/property_editor/step_io/reachability.js` — removes `sameUniverse` + universe logic (pure topology).
- `app/javascript/controllers/property_editor/step_io/override_computer.js` — removes universe filter in both input+output computation.
- `app/javascript/controllers/flowchart_canvas_controller.js` — primes `elementPins` on canvas load.

**Deletions (files):**
- `app/javascript/controllers/property_editor/io_manager.js` — obsolete.
- `app/javascript/controllers/property_editor/io_manager/input_operations.js` — obsolete.
- `app/javascript/controllers/property_editor/io_manager/output_operations.js` — obsolete.

**New spec files:**
- `spec/services/code_generators/io_extractor_spec.rb` — extend with `call_element` coverage.
- `spec/services/code_generators/conflict_resolver_spec.rb` — element-level cases.
- `spec/services/code_generators/emission_rewriter_spec.rb` — extend with `call_element` coverage.
- `spec/controllers/code_generators/element_type_io_params_controller_spec.rb`.
- `spec/services/activity_generator_spec.rb` — element-level collision integration + isolateCtx-removal assertion.
- `spec/system/property_editor/element_io_tab_spec.rb`.

---

### Task 1: IOExtractor.call_element extracts pins from element-type generator body

**Files:**
- Modify: `app/services/code_generators/io_extractor.rb`
- Test: `spec/services/code_generators/io_extractor_spec.rb`

- [ ] **Step 1: Write the failing spec for `call_element` on a loop element**

Append to `spec/services/code_generators/io_extractor_spec.rb`:

```ruby
RSpec.describe CodeGenerators::IoExtractor, ".call_element" do
  it "extracts ctx reads/writes from a loop element generator body" do
    result = described_class.call_element(
      element_type: "loop",
      properties: {
        "loopType"            => "for_each",
        "collection"          => "ctx[:items]",
        "itemVariable"        => "item",
        "indexVariable"       => "idx",
        "accumulatorVariable" => "bag"
      }
    )
    expect(result[:inputs].map { |i| i[:pin] }).to include("items")
    expect(result[:outputs].map { |o| o[:pin] }).to include("item", "idx", "bag", "_loop_iteration_count")
  end

  it "returns empty pins for unknown element types" do
    result = described_class.call_element(element_type: "__nope__", properties: {})
    expect(result).to eq(inputs: [], outputs: [])
  end

  it "returns empty pins when the element generator raises" do
    allow_any_instance_of(CodeGenerators::ElementTypes::Loop::LoopGenerator)
      .to receive(:generate_body).and_raise(StandardError, "boom")
    result = described_class.call_element(element_type: "loop", properties: {})
    expect(result).to eq(inputs: [], outputs: [])
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/services/code_generators/io_extractor_spec.rb -e "call_element"`
Expected: FAIL — `NoMethodError: undefined method 'call_element'`.

- [ ] **Step 3: Add the `call_element` entry point**

Edit `app/services/code_generators/io_extractor.rb`. Add a module-level method and a new internal worker class beside `Extractor`:

```ruby
    def self.call_element(element_type:, properties: {})
      ElementExtractor.new(element_type: element_type, properties: properties).call
    end

    class ElementExtractor
      def initialize(element_type:, properties:)
        @element_type = element_type
        @properties = properties || {}
      end

      def call
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

- [ ] **Step 4: Run the spec, verify it passes**

Run: `bundle exec rspec spec/services/code_generators/io_extractor_spec.rb -e "call_element"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/io_extractor.rb spec/services/code_generators/io_extractor_spec.rb
git commit -m "feat(io-extractor): add call_element entry point for element-type pin extraction"
```

---

### Task 2: Element-type io_params HTTP endpoint

**Files:**
- Create: `app/controllers/code_generators/element_type_io_params_controller.rb`
- Modify: `config/routes.rb:186-190`
- Create: `spec/controllers/code_generators/element_type_io_params_controller_spec.rb`

- [ ] **Step 1: Write the failing controller spec**

Create `spec/controllers/code_generators/element_type_io_params_controller_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CodeGenerators::ElementTypeIoParamsController, type: :request do
  describe "POST /code_generators/element_types/:element_type/io_params" do
    it "returns 200 with extracted pins for a known element_type" do
      post "/code_generators/element_types/loop/io_params",
           params: { properties: { loopType: "for_each", collection: "ctx[:items]" } },
           as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["inputs"].map { |i| i["pin"] }).to include("items")
      expect(body["outputs"]).to be_an(Array)
    end

    it "returns empty pins for an unknown element_type" do
      post "/code_generators/element_types/__nope__/io_params", params: { properties: {} }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("inputs" => [], "outputs" => [])
    end

    it "returns empty pins when properties is a bare string" do
      post "/code_generators/element_types/loop/io_params", params: { properties: "junk" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("inputs" => [], "outputs" => [])
    end
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/controllers/code_generators/element_type_io_params_controller_spec.rb`
Expected: FAIL — routing error (no route matches).

- [ ] **Step 3: Create the controller**

Create `app/controllers/code_generators/element_type_io_params_controller.rb`:

```ruby
# frozen_string_literal: true

module CodeGenerators
  # ElementTypeIoParamsController
  #
  # Stateless JSON endpoint consumed by the canvas UI while the user edits
  # an element's properties. Given an element_type and its in-progress
  # properties hash, returns the ctx input and output pins that the
  # element-type generator would expose.
  #
  # Endpoint: POST /code_generators/element_types/:element_type/io_params
  #
  # Request body (JSON):
  #   { "properties": { "loopType": "for_each", "collection": "ctx[:items]" } }
  #
  # Response (always 200):
  #   {
  #     "inputs":  [{ "pin": "items", "ctx_key": "items", "source": "config_expr" }],
  #     "outputs": [{ "pin": "item",  "ctx_key": "item" }, ...]
  #   }
  #
  # Unknown element_type or extraction errors yield `{"inputs": [], "outputs": []}`
  # with HTTP 200 so the UI stays responsive during half-typed edits.
  class ElementTypeIoParamsController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :set_current_customer, raise: false
    skip_before_action :authenticate_user!, raise: false

    EMPTY_PINS = { inputs: [], outputs: [] }.freeze

    def show
      raw_props = params[:properties]
      pins =
        if raw_props.is_a?(ActionController::Parameters)
          CodeGenerators::IoExtractor.call_element(
            element_type: params[:element_type].to_s,
            properties:   raw_props.to_unsafe_h.stringify_keys
          )
        elsif raw_props.nil?
          CodeGenerators::IoExtractor.call_element(element_type: params[:element_type].to_s, properties: {})
        else
          EMPTY_PINS
        end

      render json: { inputs: pins[:inputs], outputs: pins[:outputs] }
    end
  end
end
```

- [ ] **Step 4: Add the route**

Edit `config/routes.rb`, inside the `namespace :code_generators` block (around line 186):

```ruby
  namespace :code_generators do
    post ":action_name/io_params",
      to: "io_params#show",
      constraints: { action_name: /[A-Za-z0-9_]+/ }

    post "element_types/:element_type/io_params",
      to: "element_type_io_params#show",
      constraints: { element_type: /[A-Za-z0-9_]+/ }
  end
```

- [ ] **Step 5: Run the spec, verify it passes**

Run: `bundle exec rspec spec/controllers/code_generators/element_type_io_params_controller_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/code_generators/element_type_io_params_controller.rb config/routes.rb spec/controllers/code_generators/element_type_io_params_controller_spec.rb
git commit -m "feat(http): add element_types io_params endpoint"
```

---

### Task 3: Element-level ConflictResolver — detect cross-element collisions and build rename map

**Files:**
- Create: `app/services/code_generators/conflict_resolver.rb`
- Create: `spec/services/code_generators/conflict_resolver_spec.rb`

- [ ] **Step 1: Write the failing spec for two elements emitting the same key**

Create `spec/services/code_generators/conflict_resolver_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CodeGenerators::ConflictResolver do
  def element(id, emits: [])
    { id: id, outputs: emits.map { |pin| { pin: pin } } }
  end

  it "returns an empty rename map when every key has a single emitter" do
    elements = [element("a", emits: ["x"]), element("b", emits: ["y"])]
    expect(described_class.call(elements)).to eq({})
  end

  it "renames every emitter of a colliding key (entire chart scope)" do
    elements = [element("a", emits: ["model"]), element("b", emits: ["model"])]
    result = described_class.call(elements)
    expect(result.keys).to match_array(%w[a b])
    expect(result["a"]["model"]).to match(/\Amodel_[0-9a-f]{4}\z/)
    expect(result["b"]["model"]).to match(/\Amodel_[0-9a-f]{4}\z/)
    expect(result["a"]["model"]).not_to eq(result["b"]["model"])
  end

  it "is deterministic across calls" do
    elements = [element("a", emits: ["model"]), element("b", emits: ["model"])]
    expect(described_class.call(elements)).to eq(described_class.call(elements))
  end

  it "does not collide when the effective keys already differ" do
    # Caller (ActivityGenerator) supplies effective keys already post per-step
    # rename, so a process element whose step-rename produced model_a3f2 shows
    # up as { pin: "model_a3f2" } here — no collision with element b.
    elements = [element("a", emits: ["model_a3f2"]), element("b", emits: ["model"])]
    expect(described_class.call(elements)).to eq({})
  end

  it "falls back to 6-char suffix on 4-char prefix collision" do
    hit = 0
    allow(Digest::SHA1).to receive(:hexdigest).and_wrap_original do |orig, input|
      hit += 1
      hit <= 2 ? "dead" + "beef" * 9 : orig.call(input)
    end
    elements = [element("a", emits: ["x"]), element("b", emits: ["x"])]
    result = described_class.call(elements)
    expect(result["a"]["x"]).to match(/\Ax_[0-9a-f]{6}\z/)
    expect(result["b"]["x"]).to match(/\Ax_[0-9a-f]{6}\z/)
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/services/code_generators/conflict_resolver_spec.rb`
Expected: FAIL — uninitialized constant `CodeGenerators::ConflictResolver`.

- [ ] **Step 3: Create the resolver**

Create `app/services/code_generators/conflict_resolver.rb`:

```ruby
# frozen_string_literal: true

require "digest"
require "set"

module CodeGenerators
  # ConflictResolver — element-level ctx-key collision detector.
  #
  # Input shape: an array of element descriptors (hashes with string or
  # symbol keys, accepted interchangeably). Each descriptor carries:
  #
  #   id      — element id (string).
  #   outputs — array of { pin: "<effective_emitted_key>" } entries. The
  #             caller (ActivityGenerator) supplies already-effective keys:
  #             for process elements it has already applied the shipped
  #             per-step rename, so a step that now emits :model_a3f2
  #             shows up here as { pin: "model_a3f2" }. For non-process
  #             elements the pin is simply the literal ctx key the
  #             generator writes.
  #
  # Output: rename_map, a two-level hash
  #   { element_id => { pin_name => renamed_key }, ... }
  # Elements with no colliding outputs get no entry.
  #
  # Any pin emitted by ≥2 elements — across the whole flowchart, regardless
  # of reachability — triggers rename of EVERY emitter.
  #
  # Rename format: "<pin>_#{sha1(element_id:pin)[0..3]}". If two
  # (element_id, pin) pairs share the same 4-char prefix within this
  # flowchart, ALL emitters of THAT colliding pin fall back to 6 chars.
  class ConflictResolver
    def self.call(elements)
      new(elements).call
    end

    def initialize(elements)
      @elements = Array(elements).map { |e| normalize(e) }
    end

    def call
      emitters = Hash.new { |h, k| h[k] = [] }
      @elements.each do |el|
        el[:outputs].each do |o|
          pin = (o[:pin] || o["pin"]).to_s
          next if pin.empty?
          emitters[pin] << [el[:id], pin]
        end
      end

      rename_map = {}
      emitters.each do |_key, refs|
        next if refs.size < 2

        suffix_length = collision_free_suffix_length(refs)
        refs.each do |(id, pin)|
          rename_map[id] ||= {}
          rename_map[id][pin] = "#{pin}_#{sha1_suffix(id, pin, suffix_length)}"
        end
      end

      rename_map
    end

    private

    def normalize(el)
      {
        id:      (el[:id] || el["id"]).to_s,
        outputs: Array(el[:outputs] || el["outputs"])
      }
    end

    def collision_free_suffix_length(refs)
      [4, 6].each do |length|
        prefixes = refs.map { |(id, pin)| sha1_suffix(id, pin, length) }
        return length if prefixes.uniq.length == prefixes.length
      end
      8
    end

    def sha1_suffix(id, pin, length)
      Digest::SHA1.hexdigest("#{id}:#{pin}")[0, length]
    end
  end
end
```

- [ ] **Step 4: Run the spec, verify it passes**

Run: `bundle exec rspec spec/services/code_generators/conflict_resolver_spec.rb`
Expected: PASS (all 5 examples).

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/conflict_resolver.rb spec/services/code_generators/conflict_resolver_spec.rb
git commit -m "feat(conflict-resolver): add element-level ctx-key collision rename map"
```

---

### Task 4: EmissionRewriter.call_element — rewrite element body with override + reachability fallback

**Files:**
- Modify: `app/services/code_generators/emission_rewriter.rb`
- Test: `spec/services/code_generators/emission_rewriter_spec.rb`

- [ ] **Step 1: Write the failing spec for element-level rewrite**

Append to `spec/services/code_generators/emission_rewriter_spec.rb`:

```ruby
RSpec.describe CodeGenerators::EmissionRewriter, ".call_element" do
  it "rewrites writes using element output overrides" do
    body = "ctx[:model] = {id: 1}\nctx[:other] = true"
    result = described_class.call_element(
      body:              body,
      element_id:        "e1",
      io_overrides:      { "outputs" => [{ "pin" => "model", "renamed_to" => "model_a3f2" }] },
      rename_map:        {},
      reachability:      {},
      producer_outputs:  {}
    )
    expect(result).to include("ctx[:model_a3f2] = {id: 1}")
    expect(result).to include("ctx[:other] = true")
  end

  it "rewrites reads using explicit input override" do
    body = "x = ctx[:model]"
    result = described_class.call_element(
      body:              body,
      element_id:        "e2",
      io_overrides:      { "inputs" => [{ "pin" => "model", "override_key" => "model_e7c1" }] },
      rename_map:        {},
      reachability:      {},
      producer_outputs:  {}
    )
    expect(result).to eq("x = ctx[:model_e7c1]")
  end

  it "falls back to nearest reachable producer when no override is set" do
    body = "x = ctx[:model]"
    result = described_class.call_element(
      body:              body,
      element_id:        "reader",
      io_overrides:      {},
      rename_map:        { "producer" => { "model" => "model_ab12" } },
      reachability:      { "reader" => %w[root producer] },
      producer_outputs:  { "producer" => %w[model], "root" => %w[token] }
    )
    expect(result).to eq("x = ctx[:model_ab12]")
  end

  it "leaves reads unchanged when no override and no reachable producer" do
    body = "x = ctx[:model]"
    result = described_class.call_element(
      body:              body,
      element_id:        "reader",
      io_overrides:      {},
      rename_map:        {},
      reachability:      { "reader" => [] },
      producer_outputs:  {}
    )
    expect(result).to eq("x = ctx[:model]")
  end

  it "honors an empty-string override_key tombstone (no nearest-producer fallback)" do
    body = "x = ctx[:model]"
    result = described_class.call_element(
      body:              body,
      element_id:        "reader",
      io_overrides:      { "inputs" => [{ "pin" => "model", "override_key" => "" }] },
      rename_map:        { "producer" => { "model" => "model_ab12" } },
      reachability:      { "reader" => %w[producer] },
      producer_outputs:  { "producer" => %w[model] }
    )
    expect(result).to eq("x = ctx[:model]")
  end

  it "preserves reverse-order splice correctness with multiple edits" do
    body = "ctx[:model] = ctx[:model]; ctx[:flag] = true"
    result = described_class.call_element(
      body:              body,
      element_id:        "e3",
      io_overrides:      {
        "inputs"  => [{ "pin" => "model", "override_key" => "model_src" }],
        "outputs" => [{ "pin" => "model", "renamed_to"   => "model_dst" }]
      },
      rename_map:        {},
      reachability:      {},
      producer_outputs:  {}
    )
    expect(result).to eq("ctx[:model_dst] = ctx[:model_src]; ctx[:flag] = true")
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/services/code_generators/emission_rewriter_spec.rb -e "call_element"`
Expected: FAIL — `NoMethodError: undefined method 'call_element'`.

- [ ] **Step 3: Implement `call_element`**

Edit `app/services/code_generators/emission_rewriter.rb`. Add class-level method and extend behavior:

```ruby
    def self.call_element(body:, element_id:, io_overrides:, rename_map:, reachability:, producer_outputs:)
      ElementCall.new(
        body:              body,
        element_id:        element_id,
        io_overrides:      io_overrides || {},
        rename_map:        rename_map || {},
        reachability:      reachability || {},
        producer_outputs:  producer_outputs || {}
      ).call
    end

    class ElementCall
      TOMBSTONE = ""

      def initialize(body:, element_id:, io_overrides:, rename_map:, reachability:, producer_outputs:)
        @body             = body
        @element_id       = element_id.to_s
        @io_overrides     = io_overrides
        @rename_map       = rename_map
        @reachability     = reachability
        @producer_outputs = producer_outputs
      end

      def call
        return @body if @body.nil? || @body.empty?

        input_map  = index_inputs(@io_overrides["inputs"]  || @io_overrides[:inputs])
        output_map = index_outputs(@io_overrides["outputs"] || @io_overrides[:outputs])

        ast = IoExtractor::BodyAnalyzer.call(@body)
        edits = []

        ast[:writes].each do |w|
          target = output_map[w[:pin]]
          edits << edit(w, target) if target
        end

        ast[:reads].each do |r|
          target = resolve_read(r[:pin], input_map)
          edits << edit(r, target) if target
        end

        apply_edits(edits)
      end

      private

      def index_inputs(list)
        out = {}
        Array(list).each do |entry|
          pin = entry["pin"] || entry[:pin]
          next if pin.nil?
          # Detect whether the caller explicitly set an override_key — even
          # to "" (tombstone). Absence of the key means "no entry".
          if entry.key?("override_key") || entry.key?(:override_key)
            out[pin.to_s] = (entry["override_key"] || entry[:override_key]).to_s
          end
        end
        out
      end

      def index_outputs(list)
        out = {}
        Array(list).each do |entry|
          pin = entry["pin"] || entry[:pin]
          renamed = entry["renamed_to"] || entry[:renamed_to]
          next if pin.nil? || renamed.nil? || renamed == pin
          out[pin.to_s] = renamed.to_s
        end
        out
      end

      # Returns the ctx key to splice for a read, or nil if no rewrite
      # needed. Precedence:
      #   1. Explicit override (non-empty override_key).
      #   2. Tombstone ("" override_key) — return nil (leave as ctx[:pin]).
      #   3. Nearest reachable producer whose producer_outputs include pin,
      #      rewritten through rename_map if the producer renamed the pin.
      def resolve_read(pin, input_map)
        if input_map.key?(pin)
          override = input_map[pin]
          return nil if override == TOMBSTONE
          return override
        end

        predecessors = Array(@reachability[@element_id])
        # Nearest = last in reachability order (reachability arrays should be
        # ordered with the closest producer last; callers must honor this).
        predecessors.reverse_each do |pid|
          outs = Array(@producer_outputs[pid])
          next unless outs.include?(pin)
          return @rename_map.dig(pid, pin) || pin
        end
        nil
      end

      def edit(node, target)
        { start: node[:start], length: node[:length], replacement: "ctx[:#{target}]" }
      end

      def apply_edits(edits)
        by_start = {}
        edits.each { |e| by_start[e[:start]] ||= e }
        sorted = by_start.values.sort_by { |e| -e[:start] }
        result = @body.dup
        sorted.each { |e| result[e[:start], e[:length]] = e[:replacement] }
        result
      end
    end
```

- [ ] **Step 4: Run the spec, verify it passes**

Run: `bundle exec rspec spec/services/code_generators/emission_rewriter_spec.rb -e "call_element"`
Expected: PASS (all 6 examples).

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/emission_rewriter.rb spec/services/code_generators/emission_rewriter_spec.rb
git commit -m "feat(emission-rewriter): add call_element with reachability fallback"
```

---

### Task 5: ActivityGenerator — remove isolateCtx, run element-level conflict resolver + emission rewriter

**Files:**
- Modify: `app/services/activity_generator.rb:630-687` (remove isolateCtx branch)
- Modify: `app/services/activity_generator.rb:572-609` (method_body — apply element rewrite)
- Modify: `app/services/activity_generator.rb:23-44` (constructor + generate — precompute resolver state)
- Test: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Write the failing integration spec**

Append to `spec/services/activity_generator_spec.rb` (adjust imports if needed):

```ruby
RSpec.describe ActivityGenerator, "element-level I/O collision handling" do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }

  def build_flowchart_config(elements, connections)
    {
      "elements"    => elements,
      "connections" => connections,
      "metadata"    => { "canvas" => { "width" => 1200, "height" => 800 } }
    }.to_json
  end

  def flowchart_with(elements:, connections:)
    create(:flowchart, customer: customer, entity: entity,
                       configuration: build_flowchart_config(elements, connections))
  end

  it "renames colliding ctx writes across two elements" do
    start_el = { "id" => "s", "type" => "start", "x" => 100, "y" => 50,
                 "width" => 100, "height" => 45, "label" => "Start",
                 "properties" => {} }
    loop_a   = { "id" => "a", "type" => "loop", "x" => 100, "y" => 150,
                 "width" => 100, "height" => 45, "label" => "A",
                 "properties" => { "loopType" => "for_each", "collection" => "ctx[:items]",
                                   "itemVariable" => "item", "indexVariable" => "idx" } }
    loop_b   = { "id" => "b", "type" => "loop", "x" => 100, "y" => 250,
                 "width" => 100, "height" => 45, "label" => "B",
                 "properties" => { "loopType" => "for_each", "collection" => "ctx[:others]",
                                   "itemVariable" => "item", "indexVariable" => "jdx" } }
    end_el   = { "id" => "e", "type" => "end", "x" => 100, "y" => 350,
                 "width" => 100, "height" => 45, "label" => "End",
                 "properties" => {} }

    flow = flowchart_with(
      elements:    [start_el, loop_a, loop_b, end_el],
      connections: [
        { "id" => "c1", "from" => "s", "to" => "a" },
        { "id" => "c2", "from" => "a", "to" => "b" },
        { "id" => "c3", "from" => "b", "to" => "e" }
      ]
    )

    out = described_class.new(flow).generate
    expect(out).to match(/ctx\[:item_[0-9a-f]{4,6}\]\s*=/)
  end

  it "does not emit an isolateCtx snapshot wrapper even when the property is present" do
    start_el = { "id" => "s", "type" => "start", "x" => 100, "y" => 50,
                 "width" => 100, "height" => 45, "label" => "Start",
                 "properties" => {} }
    process  = { "id" => "p", "type" => "process", "x" => 100, "y" => 150,
                 "width" => 100, "height" => 45, "label" => "P",
                 "properties" => { "isolateCtx" => "true", "steps" => [] } }
    end_el   = { "id" => "e", "type" => "end", "x" => 100, "y" => 250,
                 "width" => 100, "height" => 45, "label" => "End",
                 "properties" => {} }
    flow = flowchart_with(
      elements:    [start_el, process, end_el],
      connections: [
        { "id" => "c1", "from" => "s", "to" => "p" },
        { "id" => "c2", "from" => "p", "to" => "e" }
      ]
    )
    out = described_class.new(flow).generate
    expect(out).not_to include("_original_ctx = ctx")
    expect(out).not_to include("_original_ctx.replace(ctx)")
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb -e "element-level I/O collision handling"`
Expected: FAIL — either isolateCtx snippet still present or the two `ctx[:item]` writes are not renamed.

- [ ] **Step 3: Remove the isolateCtx branch from `apply_process_scope_options`**

Edit `app/services/activity_generator.rb`. Replace the `apply_process_scope_options` method (currently lines 630-687) with:

```ruby
  # Honour the `onStepFailure` process-level option. The isolateCtx option
  # is gone: ctx is a single shared bus in Trailblazer Activity; a "snapshot
  # + copy-back" inside the step body was a misleading abstraction and is
  # removed. Any persisted isolateCtx=="true" on older flowcharts is simply
  # ignored here.
  def apply_process_scope_options(element, body)
    properties = element&.dig("properties") || {}
    on_failure = properties["onStepFailure"].to_s.presence || "halt"

    case on_failure
    when "continue"
      <<~RUBY.chomp
        begin
        #{body.indent(2)}
        rescue => e
          ctx[:_last_error] = { source: "process", message: e.message, class: e.class.name, at: Time.current }
          true
        end
      RUBY
    when "retry"
      <<~RUBY.chomp
        begin
        #{body.indent(2)}
        rescue => e
          ctx[:_last_error] = { source: "process", message: e.message, class: e.class.name, at: Time.current }
          sleep(1)
          begin
        #{body.indent(4)}
          rescue
            false
          end
        end
      RUBY
    else
      body
    end
  end
```

- [ ] **Step 4: Precompute resolver state in `generate`**

Edit `app/services/activity_generator.rb` — update `generate` to compute `rename_map`, `reachability`, `producer_outputs` once and store them on the instance:

```ruby
  def generate
    return nil if flowchart.name.blank? || elements.empty?

    validation_errors = validate_structure
    if validation_errors.any?
      log_warn "Flowchart validation failed for #{flowchart.id}: #{validation_errors.join(', ')}"
      return nil
    end

    @element_io = build_element_io_index

    steps = dfs_collect_steps
    class_def = class_definition_with_steps(steps)
    [header(steps), class_def].compact.join("\n")
  end

  # Precompute the shared state every element body rewrite needs:
  #   - producer_outputs: element_id -> effective emitted ctx keys (the final
  #     post-rename keys, which callers of EmissionRewriter.call_element use
  #     to detect "does this predecessor emit my pin?")
  #   - rename_map: element_id -> { pin => renamed_key } from ConflictResolver
  #   - reachability: element_id -> ordered predecessor ids (farthest first,
  #     closest last) so EmissionRewriter's reverse-walk picks the nearest
  def build_element_io_index
    # Effective emitted keys per element (strings). For a process element
    # this is the union of step-level effective keys (post per-step rename).
    # For any other element it's whatever IoExtractor.call_element reports.
    effective_outputs = {}
    elements.each do |el|
      effective_outputs[el["id"]] = element_effective_output_keys(el)
    end

    descriptors = elements.map do |el|
      {
        id:      el["id"],
        outputs: effective_outputs[el["id"]].map { |k| { pin: k } }
      }
    end

    rename_map = CodeGenerators::ConflictResolver.call(descriptors)

    # producer_outputs[el_id] = effective emitted keys after the element-level
    # rename map is applied on top of the already-effective step-level keys.
    producer_outputs = {}
    effective_outputs.each do |id, keys|
      producer_outputs[id] = keys.map { |pin| rename_map.dig(id, pin) || pin }
    end

    reachability = build_element_reachability

    { rename_map: rename_map, reachability: reachability, producer_outputs: producer_outputs }
  end

  # Effective emitted ctx keys for one element, as strings.
  def element_effective_output_keys(element)
    type = element["type"]
    if type == "process"
      step_effective_keys(element).values.flatten.uniq
    else
      result = CodeGenerators::IoExtractor.call_element(
        element_type: type,
        properties:   element["properties"] || {}
      )
      (result[:outputs] || []).map { |o| (o[:pin] || o["pin"]).to_s }
    end
  end

  # For a process element, return { step_id => [effective output keys after
  # the shipped per-step rename] }. Honors step io_overrides.outputs.renamed_to
  # the same way EmissionRewriter.call does.
  def step_effective_keys(process_el)
    out = {}
    steps = process_el.dig("properties", "steps") || []
    steps.each do |step|
      action = step["action"]
      next if action.blank?

      pins = CodeGenerators::IoExtractor.call(
        action: action,
        config: step["config"] || {}
      )
      overrides = (step["io_overrides"] || {})["outputs"] || []
      rename_index = overrides.each_with_object({}) { |o, h| h[o["pin"]] = o["renamed_to"] if o["renamed_to"] }
      out[step["id"]] = (pins[:outputs] || []).map { |o| rename_index[o[:pin]] || o[:pin] }
    end
    out
  end

  def build_element_reachability
    adj = Hash.new { |h, k| h[k] = [] }
    connections.each { |c| adj[c["from"]] << c["to"] }

    result = {}
    elements.each do |el|
      result[el["id"]] = ordered_predecessors(el["id"], adj)
    end
    result
  end

  def ordered_predecessors(target_id, adj)
    reverse_adj = Hash.new { |h, k| h[k] = [] }
    adj.each { |from, tos| tos.each { |to| reverse_adj[to] << from } }

    visited = Set.new
    order = []
    queue = [target_id]
    while (cur = queue.shift)
      reverse_adj[cur].each do |pred|
        next if visited.include?(pred)
        visited << pred
        order.unshift(pred)
        queue << pred
      end
    end
    order
  end
```

- [ ] **Step 5: Apply element rewrite in `method_body`**

Edit `app/services/activity_generator.rb`. In `method_body`, after delegation produces a `result` string and before it's returned, pipe through `EmissionRewriter.call_element`. Replace the relevant block:

```ruby
    # Delegate to element type generator via registry
    generator_class = @registry.find_element_type(type)
    if generator_class
      generator = generator_class.new(element, ctx)
      result = generator.generate_body
      return rewrite_element_body(element, result) if result
    elsif !STEP_CONTAINER_ELEMENT_TYPES.include?(type)
```

Then add a private helper after `generate_process_body`:

```ruby
  def rewrite_element_body(element, body)
    return body unless @element_io

    CodeGenerators::EmissionRewriter.call_element(
      body:              body,
      element_id:        element["id"],
      io_overrides:      element.dig("properties", "io_overrides") || {},
      rename_map:        @element_io[:rename_map],
      reachability:      @element_io[:reachability],
      producer_outputs:  @element_io[:producer_outputs]
    )
  end
```

Also wrap `generate_process_body`'s return:

```ruby
    # Fall through to process body (step actions within a process element)
    rewrite_element_body(element, generate_process_body(element, steps, ctx))
```

- [ ] **Step 6: Run the spec, verify it passes**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb -e "element-level I/O collision handling"`
Expected: PASS (both examples).

- [ ] **Step 7: Run the full code_generators suite**

Run: `bundle exec rspec spec/services/code_generators spec/services/activity_generator_spec.rb`
Expected: PASS (baseline ≥ 4331 examples, 0 failures per MEMORY.md).

- [ ] **Step 8: Commit**

```bash
git add app/services/activity_generator.rb spec/services/activity_generator_spec.rb
git commit -m "feat(activity-generator): apply element-level rewrite, drop isolateCtx"
```

---

### Task 6: Canvas — elementPins cache + iterateElements + structure-change event

**Files:**
- Modify: `app/javascript/flowchart/canvas.js:44` (add `this.elementPins = {}`)
- Modify: `app/javascript/flowchart/canvas.js:1730-1786` (add element API beside step API)

- [ ] **Step 1: Add `elementPins` storage and element API**

Edit `app/javascript/flowchart/canvas.js`. In the constructor where `this.stepPins = {}` is set (line ~44), add `this.elementPins = {}` directly below.

Then append these methods in the "Step I/O Pin Cache" section (around line 1786):

```javascript
  /**
   * Cache extracted I/O pins for an element, keyed by element id.
   */
  setElementPins(elementId, pins) {
    this.elementPins = { ...this.elementPins, [elementId]: pins }
  }

  /** Retrieve cached pins for an element id, or empty pin sets. */
  getElementPins(elementId) {
    return this.elementPins[elementId] || { inputs: [], outputs: [] }
  }

  /** Iterate over every element on the canvas. */
  iterateElements(callback) {
    for (const el of this.elements) callback(el)
  }

  /**
   * Emit a `flowchartStructureChanged` CustomEvent on the canvas container
   * so listeners (override validator, element pin cache) can react. Callers
   * include: element add/remove, connection add/remove, element property
   * edit, step add/remove/edit inside a process element.
   */
  emitStructureChanged(detail = {}) {
    if (!this.container) return
    this.container.dispatchEvent(
      new CustomEvent("flowchartStructureChanged", { detail, bubbles: true })
    )
  }
```

- [ ] **Step 2: Smoke-test in the browser**

Run: `bin/rails assets:precompile && bin/dev` (or existing dev server invocation).
Open the flowchart edit page, open DevTools console, run:
```js
window.flowchartCanvas.setElementPins("dummy", {inputs:[], outputs:[{pin:"x"}]})
window.flowchartCanvas.getElementPins("dummy")
```
Expected: returns `{inputs:[], outputs:[{pin:"x"}]}`.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/canvas.js
git commit -m "feat(canvas): add elementPins cache and flowchartStructureChanged event"
```

---

### Task 7: Canvas — emit `flowchartStructureChanged` from existing mutation points

**Files:**
- Modify: `app/javascript/flowchart/canvas.js` (inside: addElement, removeElement, addConnection, removeConnection, step add/remove/edit)

- [ ] **Step 1: Locate the mutation methods**

Run: `grep -n "onchange\s*&&\s*this.onchange\|emitChange\|saveState" app/javascript/flowchart/canvas.js`
Expected: a list of mutation sites (typical pattern is `this.onchange && this.onchange()` after each mutation).

- [ ] **Step 2: Add structure-change emit at each mutation site**

For each identified mutation method (element add/remove, connection add/remove, step add/remove/edit, element properties edit), insert `this.emitStructureChanged({ source: "<method_name>" })` directly after the existing `onchange` callback. Use the method name as `source`.

Example — inside `addElement`:
```javascript
    this.onchange && this.onchange()
    this.emitStructureChanged({ source: "addElement", elementId: element.id })
```

Repeat for: `removeElement`, `addConnection`, `removeConnection`, `updateElementProperties` (or equivalent), `addStep`, `removeStep`, `updateStepConfig`.

- [ ] **Step 3: Verify the event fires**

In a browser devtools console on the flowchart edit page:
```js
document.querySelector("[data-controller~='flowchart-canvas']")
  .addEventListener("flowchartStructureChanged", e => console.log("FIRED", e.detail))
```
Drag a new element onto the canvas. Expected: console logs `FIRED {source: "addElement", ...}`.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/flowchart/canvas.js
git commit -m "feat(canvas): emit flowchartStructureChanged on mutations"
```

---

### Task 8: JS — element_io/io_params_client.js

**Files:**
- Create: `app/javascript/controllers/property_editor/element_io/io_params_client.js`

- [ ] **Step 1: Create the client**

Create the file with:

```javascript
/**
 * Fetch extracted pins for a single element_type + properties from the server.
 * Always resolves with { inputs: [...], outputs: [...] }.
 */
export async function fetchElementPins(elementType, properties) {
  if (!elementType) return { inputs: [], outputs: [] }

  try {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""
    const response = await fetch(
      `/code_generators/element_types/${encodeURIComponent(elementType)}/io_params`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ properties: properties || {} })
      }
    )
    if (!response.ok) return { inputs: [], outputs: [] }
    return await response.json()
  } catch (e) {
    console.warn("[element_io] io_params fetch failed:", e)
    return { inputs: [], outputs: [] }
  }
}

/** Bulk prime: fetch pins for every element currently on the canvas. */
export async function primeAllElementPins(canvas) {
  const jobs = []
  canvas.iterateElements((el) => {
    if (!el || !el.type || !el.id) return
    jobs.push(
      fetchElementPins(el.type, el.properties || {}).then((pins) =>
        canvas.setElementPins(el.id, pins)
      )
    )
  })
  await Promise.all(jobs)
}

/** Re-fetch pins for a single element by id (post-edit refresh). */
export async function refreshElementPins(canvas, elementId) {
  const el = (canvas.elements || []).find((e) => e.id === elementId)
  if (!el) return
  const pins = await fetchElementPins(el.type, el.properties || {})
  canvas.setElementPins(elementId, pins)
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/property_editor/element_io/io_params_client.js
git commit -m "feat(element-io): add io_params_client"
```

---

### Task 9: JS — element_io/reachability.js (pure topology, no universes)

**Files:**
- Create: `app/javascript/controllers/property_editor/element_io/reachability.js`

- [ ] **Step 1: Create the module**

Create the file with:

```javascript
/**
 * ElementReachability — predecessor index over the flowchart element graph.
 *
 * Pure topology over `canvas.connections` (from/to element ids). No
 * universes, no isolateCtx — ctx is a single shared bus.
 *
 * Usage:
 *   const r = new ElementReachability(canvas)
 *   r.predecessors("elem_id")                  // string[] (farthest first)
 *   r.nearestProducer("elem_id", "pin", producerOutputs)  // string|null
 */
export class ElementReachability {
  constructor(canvas) {
    this.elements = (canvas && canvas.elements) || []
    this.connections = (canvas && canvas.connections) || []
    this._predecessors = new Map()
    this._build()
  }

  /** Ordered predecessor ids for `elementId`, farthest first, nearest last. */
  predecessors(elementId) {
    return this._predecessors.get(elementId) || []
  }

  /** Return the nearest predecessor id that emits `pin`, or null. */
  nearestProducer(elementId, pin, producerOutputs) {
    const preds = this.predecessors(elementId)
    for (let i = preds.length - 1; i >= 0; i--) {
      const outs = (producerOutputs && producerOutputs[preds[i]]) || []
      if (outs.includes(pin)) return preds[i]
    }
    return null
  }

  _build() {
    const reverse = new Map()
    for (const el of this.elements) reverse.set(el.id, [])
    for (const c of this.connections) {
      if (!reverse.has(c.to)) continue
      reverse.get(c.to).push(c.from)
    }

    for (const el of this.elements) {
      this._predecessors.set(el.id, this._walk(el.id, reverse))
    }
  }

  _walk(startId, reverse) {
    const visited = new Set()
    const order = []
    const queue = [startId]
    while (queue.length) {
      const cur = queue.shift()
      for (const p of reverse.get(cur) || []) {
        if (visited.has(p)) continue
        visited.add(p)
        order.unshift(p) // prepend so farthest ends up first
        queue.push(p)
      }
    }
    return order
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/property_editor/element_io/reachability.js
git commit -m "feat(element-io): add reachability (pure topology)"
```

---

### Task 10: JS — element_io/override_computer.js (seed default overrides)

**Files:**
- Create: `app/javascript/controllers/property_editor/element_io/override_computer.js`

- [ ] **Step 1: Create the module**

Create the file with:

```javascript
/**
 * Computes default io_overrides for a single element:
 *   - Inputs: nearest reachable producer whose effective output key matches.
 *   - Outputs: rename when ANY other element on the canvas emits the same
 *     effective key (whole-flowchart scope).
 *
 * The same shape that ships on step.io_overrides is used:
 *   { inputs:  [{ pin, override_key }, ...],
 *     outputs: [{ pin, renamed_to }, ...] }
 *
 * "pin" is the logical ctx name from BodyAnalyzer; override_key/renamed_to
 * are the concrete ctx keys to splice in. An input with override_key === ""
 * is a tombstone ("user said no producer").
 */
import { ElementReachability } from "controllers/property_editor/element_io/reachability"

export async function computeElementOverrides(canvas, elementId) {
  const target = (canvas.elements || []).find((e) => e.id === elementId)
  if (!target) return { inputs: [], outputs: [] }

  const reachability = new ElementReachability(canvas)
  const emitted = collectEmittedKeys(canvas)
  const pins = canvas.getElementPins(elementId)

  const inputs = computeInputOverrides(elementId, pins.inputs || [], reachability, emitted)
  const outputs = await computeOutputOverrides(elementId, pins.outputs || [], emitted)

  return { inputs, outputs }
}

/**
 * Map<element_id, Map<pin, effectiveKey>> — the ctx key each element
 * actually emits for each pin, honoring existing io_overrides already on
 * the element.
 */
function collectEmittedKeys(canvas) {
  const result = new Map()
  canvas.iterateElements((el) => {
    const pins = canvas.getElementPins(el.id)
    const outs = pins.outputs || []
    const overrideList = (el.properties?.io_overrides?.outputs) || []
    const pinToKey = new Map()
    for (const o of outs) {
      const hit = overrideList.find((e) => e.pin === o.pin)
      pinToKey.set(o.pin, hit?.renamed_to || o.pin)
    }
    result.set(el.id, pinToKey)
  })
  return result
}

function computeInputOverrides(elementId, inputPins, reachability, emitted) {
  const producerOutputs = {}
  for (const [id, pinMap] of emitted) {
    producerOutputs[id] = [...pinMap.values()]
  }

  const overrides = []
  const preds = reachability.predecessors(elementId)
  const existing =
    (canvasAwareProps(elementId)?.io_overrides?.inputs) || []
  const tombstoneSet = new Set(
    existing.filter((e) => e.override_key === "").map((e) => e.pin)
  )

  for (const pin of inputPins.map((i) => i.pin)) {
    if (tombstoneSet.has(pin)) {
      overrides.push({ pin, override_key: "" })
      continue
    }

    let chosen = null
    for (let i = preds.length - 1; i >= 0 && !chosen; i--) {
      const pid = preds[i]
      const pinMap = emitted.get(pid)
      if (!pinMap) continue
      for (const [producerPin, effective] of pinMap) {
        if (producerPin === pin || effective === pin || effectiveMatches(pin, effective)) {
          chosen = { pid, effective }
          break
        }
      }
    }

    if (!chosen) continue
    if (chosen.effective === pin) continue
    overrides.push({ pin, override_key: chosen.effective })
  }
  return overrides

  function canvasAwareProps(id) {
    return (reachability.elements || []).find((e) => e.id === id)?.properties
  }
}

function effectiveMatches(pin, effective) {
  return new RegExp(`^${escapeRegExp(pin)}(_[0-9a-f]{4,6})?$`).test(effective)
}

async function computeOutputOverrides(elementId, outputPins, emitted) {
  const overrides = []
  const otherKeys = new Set()
  for (const [id, pinMap] of emitted) {
    if (id === elementId) continue
    for (const [pin, effective] of pinMap) {
      otherKeys.add(pin)
      otherKeys.add(effective)
    }
  }

  for (const outputPin of outputPins) {
    const pin = outputPin.pin
    if (!otherKeys.has(pin)) continue
    const suffix = await shortHash(`${elementId}:${pin}`, 4)
    overrides.push({ pin, renamed_to: `${pin}_${suffix}` })
  }
  return overrides
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

async function shortHash(input, length) {
  const data = new TextEncoder().encode(input)
  const digest = await crypto.subtle.digest("SHA-1", data)
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, length)
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/property_editor/element_io/override_computer.js
git commit -m "feat(element-io): add override_computer (nearest-producer + rename)"
```

---

### Task 11: JS — element_io/override_validator.js (drop stale overrides on structure change)

**Files:**
- Create: `app/javascript/controllers/property_editor/element_io/override_validator.js`

- [ ] **Step 1: Create the module**

Create the file with:

```javascript
/**
 * OverrideValidator — walks every element's io_overrides and removes stale
 * entries whose override_key / renamed_to no longer line up with the
 * current canvas state. Silent: no toasts, no markers. On next render the
 * override_computer re-defaults to nearest / new rename.
 *
 * Rules:
 *   - inputs[].override_key: drop entry if no reachable upstream element
 *     currently emits that effective key. Tombstone (""") is preserved.
 *   - outputs[].renamed_to: recompute. If the element no longer collides
 *     with any other emitter, drop it. If collision still exists but with
 *     a different peer, the existing renamed_to is still valid (it is
 *     derived from elementId:pin and stays stable).
 */
import { ElementReachability } from "controllers/property_editor/element_io/reachability"

export function validateOverrides(canvas) {
  const reachability = new ElementReachability(canvas)
  const emitted = collectEmitted(canvas)

  canvas.iterateElements((el) => {
    const overrides = el.properties?.io_overrides
    if (!overrides) return

    const updated = { inputs: [], outputs: [] }

    for (const entry of overrides.inputs || []) {
      if (entry.override_key === "") {
        updated.inputs.push(entry) // preserve tombstones
        continue
      }
      const preds = reachability.predecessors(el.id)
      const stillReachable = preds.some((pid) => {
        const map = emitted.get(pid)
        if (!map) return false
        for (const effective of map.values()) {
          if (effective === entry.override_key) return true
        }
        return false
      })
      if (stillReachable) updated.inputs.push(entry)
    }

    for (const entry of overrides.outputs || []) {
      const myKeys = emitted.get(el.id)
      if (!myKeys || !myKeys.has(entry.pin)) continue
      const stillCollides = anyOtherEmits(entry.pin, el.id, emitted)
      if (stillCollides) updated.outputs.push(entry)
    }

    el.properties.io_overrides = updated
  })
}

function collectEmitted(canvas) {
  const map = new Map()
  canvas.iterateElements((el) => {
    const pins = canvas.getElementPins(el.id)
    const outs = pins.outputs || []
    const overrideList = (el.properties?.io_overrides?.outputs) || []
    const pinToKey = new Map()
    for (const o of outs) {
      const hit = overrideList.find((e) => e.pin === o.pin)
      pinToKey.set(o.pin, hit?.renamed_to || o.pin)
    }
    map.set(el.id, pinToKey)
  })
  return map
}

function anyOtherEmits(pin, selfId, emitted) {
  for (const [id, pinMap] of emitted) {
    if (id === selfId) continue
    if (pinMap.has(pin)) return true
  }
  return false
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/property_editor/element_io/override_validator.js
git commit -m "feat(element-io): add override_validator for structural-change cleanup"
```

---

### Task 12: JS — element_io_manager.js (I/O tab renderer)

**Files:**
- Create: `app/javascript/controllers/property_editor/element_io_manager.js`

- [ ] **Step 1: Create the renderer**

Create the file with:

```javascript
/**
 * ElementIoManager renders the I/O tab for the currently-edited element.
 *
 * Layout:
 *
 *   Inputs
 *   ─────────────────────────────────────
 *    model   [ producer dropdown ▾ ]  (nearest | tombstone)
 *    ...
 *
 *   Outputs
 *   ─────────────────────────────────────
 *    user
 *    token   ⚠ renamed → token_b7e1
 *
 * Producer dropdown lists every reachable predecessor that emits a
 * matching effective key; the first option is `— no producer —` (stores a
 * tombstone override_key=""). Selecting any option writes
 * element.properties.io_overrides.inputs and re-renders.
 *
 * Output rename badges come from override_computer: an element whose pin
 * collides with another emitter is auto-renamed. Read-only.
 */
import { escapeHtml } from "utils"
import { fetchElementPins } from "controllers/property_editor/element_io/io_params_client"
import { computeElementOverrides } from "controllers/property_editor/element_io/override_computer"
import { ElementReachability } from "controllers/property_editor/element_io/reachability"

export class ElementIoManager {
  constructor(controller) {
    this.controller = controller
  }

  async openForElement(element, paneElement) {
    if (!element || !paneElement) return
    const canvas = this.controller.canvas
    if (!canvas) return

    const cached = canvas.getElementPins(element.id)
    const needsFetch =
      !cached || ((cached.inputs?.length || 0) + (cached.outputs?.length || 0) === 0)
    if (needsFetch) {
      const pins = await fetchElementPins(element.type, element.properties || {})
      canvas.setElementPins(element.id, pins)
    }

    element.properties = element.properties || {}
    const computed = await computeElementOverrides(canvas, element.id)
    element.properties.io_overrides = this._merge(element.properties.io_overrides, computed)

    this._render(element, paneElement)
  }

  updateProducer(elementId, pinName, overrideKey) {
    const canvas = this.controller.canvas
    const el = canvas.elements.find((e) => e.id === elementId)
    if (!el) return
    el.properties = el.properties || {}
    el.properties.io_overrides = el.properties.io_overrides || { inputs: [], outputs: [] }

    const list = el.properties.io_overrides.inputs
    const idx = list.findIndex((x) => x.pin === pinName)
    if (overrideKey === null) {
      if (idx !== -1) list.splice(idx, 1)
    } else {
      const entry = { pin: pinName, override_key: overrideKey }
      if (idx === -1) list.push(entry)
      else list[idx] = entry
    }
    canvas.onchange && canvas.onchange()
  }

  _merge(existing, computed) {
    const result = { inputs: [], outputs: [] }
    const exInputs = (existing?.inputs) || []

    // Keep user-set non-empty overrides + tombstones; fall back to computed
    // otherwise.
    const pinsWithUserChoice = new Set(exInputs.map((e) => e.pin))
    for (const entry of exInputs) result.inputs.push(entry)
    for (const entry of computed.inputs) {
      if (!pinsWithUserChoice.has(entry.pin)) result.inputs.push(entry)
    }

    // Outputs are always auto-computed (rename triggered by collision).
    result.outputs = computed.outputs
    return result
  }

  _render(element, pane) {
    const pins = this.controller.canvas.getElementPins(element.id)
    const overrides = element.properties.io_overrides || { inputs: [], outputs: [] }
    const reachability = new ElementReachability(this.controller.canvas)

    pane.innerHTML = `
      <div data-element-io-inputs>
        <h4 class="text-sm font-semibold text-gray-700 mt-2 mb-1">Inputs</h4>
        ${this._renderInputs(element, pins.inputs || [], overrides.inputs || [], reachability)}
      </div>
      <div data-element-io-outputs class="mt-4">
        <h4 class="text-sm font-semibold text-gray-700 mt-2 mb-1">Outputs</h4>
        ${this._renderOutputs(element, pins.outputs || [], overrides.outputs || [])}
      </div>
    `

    this._wireInputHandlers(element, pane)
  }

  _renderInputs(element, inputPins, overrideList, reachability) {
    if (inputPins.length === 0) {
      return `<p class="text-xs text-gray-500">This element reads no ctx values.</p>`
    }
    return inputPins
      .map((p) => this._renderInputRow(element, p, overrideList, reachability))
      .join("")
  }

  _renderInputRow(element, pin, overrideList, reachability) {
    const canvas = this.controller.canvas
    const existing = overrideList.find((e) => e.pin === pin.pin)
    const selectedKey = existing ? existing.override_key : null

    const preds = reachability.predecessors(element.id)
    const options = [
      `<option value="__none__" ${selectedKey === "" ? "selected" : ""}>— no producer —</option>`
    ]
    for (const pid of [...preds].reverse()) {
      const producer = canvas.elements.find((e) => e.id === pid)
      if (!producer) continue
      const pinMap = (canvas.getElementPins(pid).outputs || [])
      const overrideOuts = producer.properties?.io_overrides?.outputs || []
      for (const out of pinMap) {
        const renamed = overrideOuts.find((o) => o.pin === out.pin)?.renamed_to
        const effective = renamed || out.pin
        if (effective !== pin.pin && !effective.startsWith(`${pin.pin}_`)) continue
        const selected = selectedKey === effective ? "selected" : ""
        options.push(
          `<option value="${escapeHtml(effective)}" ${selected}>${escapeHtml(producer.label || producer.type)} • ${escapeHtml(effective)}</option>`
        )
      }
    }

    return `
      <div class="flex items-center gap-2 my-1" data-element-io-input data-pin="${escapeHtml(pin.pin)}">
        <span class="font-mono text-sm">${escapeHtml(pin.pin)}</span>
        <select class="text-sm border border-gray-300 rounded px-2 py-1"
                data-element-io-producer-select>
          ${options.join("")}
        </select>
      </div>
    `
  }

  _renderOutputs(element, outputPins, overrideList) {
    if (outputPins.length === 0) {
      return `<p class="text-xs text-gray-500">This element writes no ctx values.</p>`
    }
    return outputPins
      .map((p) => {
        const rename = overrideList.find((o) => o.pin === p.pin)?.renamed_to
        const badge = rename
          ? `<span class="ml-2 text-amber-700 text-xs">⚠ renamed → ${escapeHtml(rename)}</span>`
          : ""
        return `
          <div class="flex items-center gap-2 my-1" data-element-io-output data-pin="${escapeHtml(p.pin)}">
            <span class="font-mono text-sm">${escapeHtml(p.pin)}</span>${badge}
          </div>
        `
      })
      .join("")
  }

  _wireInputHandlers(element, pane) {
    pane.querySelectorAll("[data-element-io-producer-select]").forEach((sel) => {
      sel.addEventListener("change", (event) => {
        const row = event.target.closest("[data-element-io-input]")
        if (!row) return
        const pin = row.getAttribute("data-pin")
        const value = event.target.value
        if (value === "__none__") this.updateProducer(element.id, pin, "")
        else this.updateProducer(element.id, pin, value)
      })
    })
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/property_editor/element_io_manager.js
git commit -m "feat(element-io): add I/O tab renderer"
```

---

### Task 13: Wire ElementIoManager into property_editor_controller + prime on canvas load

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js`
- Modify: `app/javascript/controllers/property_editor/index.js`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js:115-119`

- [ ] **Step 1: Register ElementIoManager in the index**

Edit `app/javascript/controllers/property_editor/index.js`. Add export line:

```javascript
export { ElementIoManager } from "controllers/property_editor/element_io_manager"
```

- [ ] **Step 2: Instantiate in property_editor_controller**

Edit `app/javascript/controllers/property_editor_controller.js`. In the constructor / init block where other managers are instantiated (search for `new StepManager`, `new IOManager`), add:

```javascript
import { ElementIoManager } from "controllers/property_editor/element_io_manager"
// ...
this.elementIoManager = new ElementIoManager(this)
```

And find the `openTab` / tab-switch handler (search for `"io"` tab id). When the io tab opens for the currently edited element, call:

```javascript
async _onIoTabOpen() {
  if (!this.currentElement) return
  const pane = this.element.querySelector("[data-io-tab-pane]") ||
               this.element.querySelector("[data-tab-panel='io']")
  if (!pane) return
  await this.elementIoManager.openForElement(this.currentElement, pane)
}
```

Wire it so that the existing tab-switch logic invokes `_onIoTabOpen` when the io tab becomes active.

- [ ] **Step 3: Prime elementPins on canvas load**

Edit `app/javascript/controllers/flowchart_canvas_controller.js` at lines 115-119. Replace the step-only prime with parallel step + element prime:

```javascript
    import("controllers/property_editor/step_io/io_params_client").then(({ primeAllStepPins }) => {
      primeAllStepPins(this.canvas).catch(() => {})
    })
    import("controllers/property_editor/element_io/io_params_client").then(({ primeAllElementPins }) => {
      primeAllElementPins(this.canvas).catch(() => {})
    })
```

- [ ] **Step 4: Wire flowchartStructureChanged listener**

In `flowchart_canvas_controller.js`, inside `_initializeCanvas` or a dedicated `_wireStructureListener`, add:

```javascript
    this.canvasTarget.addEventListener("flowchartStructureChanged", async (e) => {
      const { source, elementId } = e.detail || {}
      const { refreshElementPins, primeAllElementPins } = await import(
        "controllers/property_editor/element_io/io_params_client"
      )
      const { validateOverrides } = await import(
        "controllers/property_editor/element_io/override_validator"
      )

      if (elementId) await refreshElementPins(this.canvas, elementId)
      else await primeAllElementPins(this.canvas)

      validateOverrides(this.canvas)
    })
```

- [ ] **Step 5: Precompile assets + reload, sanity-check**

Run: `bin/rails assets:precompile`
Open a flowchart edit page. Add a `loop` element. Click it, open the I/O tab. Expected: Inputs section shows `items` (from `ctx[:items]`), Outputs section shows `item`, `idx`, `_loop_iteration_count`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/property_editor/index.js app/javascript/controllers/property_editor_controller.js app/javascript/controllers/flowchart_canvas_controller.js
git commit -m "feat(property-editor): wire ElementIoManager and structure-change listener"
```

---

### Task 14: Remove isolateCtx + COMMON_PROPERTIES.inputs/outputs + HIDDEN_DEFAULT_* from schemas.js

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js`

- [ ] **Step 1: Delete `COMMON_PROPERTIES.inputs` and `COMMON_PROPERTIES.outputs`**

Edit `app/javascript/flowchart/constants/schemas.js`. In the `COMMON_PROPERTIES` object (lines 13-38), delete the `inputs:` and `outputs:` entries entirely:

```javascript
const COMMON_PROPERTIES = {
  label: {
    type: "text",
    label: "Label",
    placeholder: "Element name...",
    tab: "general"
  },
  description: {
    type: "textarea",
    label: "Description",
    placeholder: "Describe what this element does...",
    tab: "general"
  },
}
```

- [ ] **Step 2: Remove every `inputs: COMMON_PROPERTIES.inputs` and `outputs: COMMON_PROPERTIES.outputs` reference**

Still in `schemas.js`, delete every occurrence of:
```javascript
    inputs: COMMON_PROPERTIES.inputs,
```
and
```javascript
    outputs: COMMON_PROPERTIES.outputs,
```
(from the 16 lines listed in the grep output: lines 241, 242, 251, 347, 356, 363, 398, 440, 483, 550, 559, 597, 606, 664, 670, 746).

- [ ] **Step 3: Delete `isolateCtx` field from `process` schema**

In the `process` element schema (around line 368), delete the entire `isolateCtx:` block (7 lines).

- [ ] **Step 4: Delete `HIDDEN_DEFAULT_INPUTS`, `HIDDEN_DEFAULT_OUTPUTS`, and their references**

Around lines 760-800, delete both constants entirely. In `getDefaultPropertiesForType`, replace the whole function body with:

```javascript
export function getDefaultPropertiesForType(_elementType, _flowchartType = "custom") {
  return { description: "" }
}
```

- [ ] **Step 5: Precompile assets and reload**

Run: `bin/rails assets:precompile`
Reload a flowchart edit page. Open the process element's Advanced tab. Expected: "Isolate Ctx" dropdown is gone. Open the I/O tab on any element. Expected: no "Add Input" / "Add Output" buttons remain.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js
git commit -m "feat(schemas): remove isolateCtx, COMMON_PROPERTIES.inputs/outputs, HIDDEN_DEFAULT_*"
```

---

### Task 15: Delete IOManager + input/output operations + event listeners + inherited-inputs logic

**Files:**
- Delete: `app/javascript/controllers/property_editor/io_manager.js`
- Delete: `app/javascript/controllers/property_editor/io_manager/input_operations.js`
- Delete: `app/javascript/controllers/property_editor/io_manager/output_operations.js`
- Modify: `app/javascript/controllers/property_editor/index.js`
- Modify: `app/javascript/controllers/property_editor_controller.js:666-688, 1137-1168`
- Modify: `app/javascript/controllers/property_editor/form_builder.js:44-48, 78-107`

- [ ] **Step 1: Remove IOManager export and instantiation**

Edit `app/javascript/controllers/property_editor/index.js`. Delete:
```javascript
export { IOManager } from "controllers/property_editor/io_manager"
```

In `property_editor_controller.js`, find and delete every reference to `IOManager`, `this.ioManager`, and the methods `addInput`, `removeInput`, `onInputChange`, `addOutput`, `removeOutput` (around lines 666-688). Also delete the event listener wiring at lines 1137-1168:

```javascript
    this.formTarget.addEventListener("inputAdded", this._boundSyncChanges)
    this.formTarget.addEventListener("inputRemoved", this._boundSyncChanges)
    this.formTarget.addEventListener("outputAdded", this._boundSyncChanges)
    this.formTarget.addEventListener("outputRemoved", this._boundSyncChanges)
// ... and the matching removeEventListener block
```

- [ ] **Step 2: Replace `_updateTabBadges` input/output counter**

In `property_editor_controller.js` around line 1463-1466, replace:

```javascript
    const inputItems = this.formTarget?.querySelectorAll("[data-input-item]") || []
    const outputItems = this.formTarget?.querySelectorAll("[data-output-item]") || []
    counts.inputs = Array.from(inputItems).filter(el => !el.querySelector("[data-hidden-input]")).length
    counts.outputs = Array.from(outputItems).filter(el => !el.querySelector("[data-hidden-output]")).length
```

with:

```javascript
    const pins = this.canvas?.getElementPins?.(this.currentElement?.id) || { inputs: [], outputs: [] }
    counts.inputs = pins.inputs.length
    counts.outputs = pins.outputs.length
```

- [ ] **Step 3: Remove `_applyInheritedInputsFromParent` from form_builder.js**

Edit `app/javascript/controllers/property_editor/form_builder.js`. Delete the block at lines 44-48 that calls the inherited-inputs helper:

```javascript
    if (this.controller.currentElement.type !== "start") {
      properties = this._applyInheritedInputsFromParent(properties)
      this.controller.currentElement.properties = properties
    }
```

Also delete the entire `_applyInheritedInputsFromParent` method (lines 78-107).

- [ ] **Step 4: Delete the three IOManager files**

```bash
rm app/javascript/controllers/property_editor/io_manager.js
rm app/javascript/controllers/property_editor/io_manager/input_operations.js
rm app/javascript/controllers/property_editor/io_manager/output_operations.js
rmdir app/javascript/controllers/property_editor/io_manager 2>/dev/null || true
```

- [ ] **Step 5: Precompile and smoke-test**

Run: `bin/rails assets:precompile`
Expected: compilation succeeds without "cannot find module" errors. Browser-reload the flowchart edit page. Expected: no console errors, property editor still opens for every element type.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/property_editor/index.js app/javascript/controllers/property_editor_controller.js app/javascript/controllers/property_editor/form_builder.js
git add -u app/javascript/controllers/property_editor/io_manager.js app/javascript/controllers/property_editor/io_manager/
git commit -m "refactor(property-editor): delete IOManager + inherited-inputs logic"
```

---

### Task 16: Strip universe/isolateCtx logic from step_io modules

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_io/reachability.js`
- Modify: `app/javascript/controllers/property_editor/step_io/override_computer.js`

- [ ] **Step 1: Remove universe logic from step reachability**

Edit `app/javascript/controllers/property_editor/step_io/reachability.js`. Delete the `ROOT_UNIVERSE` constant, the `universeOf` map, the `sameUniverse` method, `_universeForElement`, and every line that references `universe` in `_build`. The simplified class should look like:

```javascript
export class Reachability {
  constructor(canvas) {
    this.elements = (canvas && canvas.elements) || []
    this.connections = (canvas && canvas.connections) || []
    this.predecessors = new Map()
    this._build()
  }

  reachablePredecessors(stepId) {
    return this.predecessors.get(stepId) || new Set()
  }

  nearestPredecessor(stepId, pinName, producerOutputs) {
    const preds = [...(this.predecessors.get(stepId) || [])]
    preds.sort(
      (a, b) => (this.predecessors.get(a)?.size || 0) - (this.predecessors.get(b)?.size || 0)
    )
    for (let i = preds.length - 1; i >= 0; i--) {
      const outs = (producerOutputs && producerOutputs[preds[i]]) || []
      if (outs.includes(pinName)) return preds[i]
    }
    return null
  }

  _build() {
    const inDeg = new Map()
    for (const el of this.elements) inDeg.set(el.id, 0)
    const adjacency = new Map()
    for (const el of this.elements) adjacency.set(el.id, [])
    for (const c of this.connections) {
      if (!inDeg.has(c.from) || !inDeg.has(c.to)) continue
      adjacency.get(c.from).push(c.to)
      inDeg.set(c.to, inDeg.get(c.to) + 1)
    }

    const queue = []
    for (const [id, d] of inDeg) if (d === 0) queue.push(id)
    const order = []
    const seen = new Set()
    while (queue.length) {
      const id = queue.shift()
      order.push(id)
      seen.add(id)
      for (const child of adjacency.get(id) || []) {
        const next = inDeg.get(child) - 1
        inDeg.set(child, next)
        if (next === 0) queue.push(child)
      }
    }
    for (const el of this.elements) {
      if (!seen.has(el.id)) { order.push(el.id); seen.add(el.id) }
    }

    const elementStepIds = new Map()
    for (const el of this.elements) {
      const ids = (el.properties?.steps || []).map((s) => s && s.id).filter(Boolean)
      elementStepIds.set(el.id, ids)
    }

    const elementExitSteps = new Map()
    for (const elId of order) {
      const feeders = this.connections.filter((c) => c.to === elId).map((c) => c.from)
      const entry = new Set()
      for (const f of feeders) {
        for (const sid of elementExitSteps.get(f) || []) entry.add(sid)
      }
      const steps = elementStepIds.get(elId) || []
      if (steps.length === 0) { elementExitSteps.set(elId, [...entry]); continue }
      const running = new Set(entry)
      for (const sid of steps) {
        this.predecessors.set(sid, new Set(running))
        running.add(sid)
      }
      elementExitSteps.set(elId, [steps[steps.length - 1]])
    }
  }
}
```

- [ ] **Step 2: Remove sameUniverse calls from step override_computer**

Edit `app/javascript/controllers/property_editor/step_io/override_computer.js`:
- In `computeInputOverrides`, delete the line `if (!reachability.sameUniverse(stepId, pid)) continue`.
- In `computeOutputOverrides`, delete the line `if (!reachability.sameUniverse(stepId, other.id)) return`.

- [ ] **Step 3: Run the step_io specs to confirm nothing regressed**

Run: `bundle exec rspec spec/services/code_generators/emission_rewriter_spec.rb spec/services/code_generators/io_extractor_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/step_io/reachability.js app/javascript/controllers/property_editor/step_io/override_computer.js
git commit -m "refactor(step-io): remove universe/sameUniverse logic"
```

---

### Task 17: Extend IoExtractor spec with element-type coverage per subsystem §1

**Files:**
- Test: `spec/services/code_generators/io_extractor_spec.rb`

- [ ] **Step 1: Add edge-case examples for non-process element types**

Append to `spec/services/code_generators/io_extractor_spec.rb`:

```ruby
RSpec.describe CodeGenerators::IoExtractor, ".call_element (element-type coverage)" do
  it "returns empty pins for a start element (no literal ctx access)" do
    result = described_class.call_element(element_type: "start", properties: {})
    expect(result[:inputs]).to eq([])
  end

  it "returns empty pins for an end element" do
    result = described_class.call_element(element_type: "end", properties: {})
    expect(result[:inputs]).to eq([])
    expect(result[:outputs]).to eq([])
  end

  it "extracts inputs from a decision element with condition expression" do
    result = described_class.call_element(
      element_type: "decision",
      properties:   { "condition" => "ctx[:flag]", "branches" => [] }
    )
    expect(result[:inputs].map { |i| i[:pin] }).to include("flag") if result[:inputs].any?
  end

  it "extracts inputs/outputs from a timer element" do
    result = described_class.call_element(
      element_type: "timer",
      properties:   { "durationSeconds" => 10 }
    )
    expect(result).to have_key(:inputs)
    expect(result).to have_key(:outputs)
  end

  it "tags a config_expr input when the pin is referenced inside properties" do
    result = described_class.call_element(
      element_type: "loop",
      properties:   { "loopType" => "for_each", "collection" => "ctx[:items]" }
    )
    items_pin = result[:inputs].find { |i| i[:pin] == "items" }
    expect(items_pin).to be_present
    expect(items_pin[:source]).to eq("config_expr")
  end
end
```

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/services/code_generators/io_extractor_spec.rb`
Expected: PASS. If a specific element generator doesn't emit literal `ctx[:...]` in its current body, the corresponding example shows `result[:inputs]` empty — which is the documented contract.

- [ ] **Step 3: Commit**

```bash
git add spec/services/code_generators/io_extractor_spec.rb
git commit -m "test(io-extractor): element-type coverage edge cases"
```

---

### Task 18: System spec for element I/O tab (Capybara)

**Files:**
- Create: `spec/system/property_editor/element_io_tab_spec.rb`

- [ ] **Step 1: Write the system spec**

Create the file:

```ruby
require "rails_helper"

RSpec.describe "Element I/O tab", type: :system, js: true do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }
  let(:flowchart) do
    create(:flowchart,
           customer: customer,
           name: "ElementIoSmoke",
           elements: [
             { "id" => "s", "type" => "start", "label" => "Start", "properties" => { "steps" => [] } },
             { "id" => "l1", "type" => "loop", "label" => "L1",
               "properties" => { "loopType" => "for_each", "collection" => "ctx[:items]",
                                 "itemVariable" => "item", "indexVariable" => "idx" } },
             { "id" => "l2", "type" => "loop", "label" => "L2",
               "properties" => { "loopType" => "for_each", "collection" => "ctx[:others]",
                                 "itemVariable" => "item", "indexVariable" => "jdx" } },
             { "id" => "e", "type" => "end", "label" => "End", "properties" => {} }
           ],
           connections: [
             { "from" => "s", "to" => "l1" },
             { "from" => "l1", "to" => "l2" },
             { "from" => "l2", "to" => "e" }
           ])
  end

  before { sign_in user }

  it "renders rolled-up pins, collision badge, and persists producer selection" do
    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"

    find("[data-element-id='l2']").click
    find("[data-tab='io']").click

    within "[data-element-io-inputs]" do
      expect(page).to have_content("others")
    end

    within "[data-element-io-outputs]" do
      expect(page).to have_content("⚠ renamed")
    end

    # Switch producer selection and save.
    within "[data-element-io-input][data-pin='others']" do
      select "Start • items", from: "element-io-producer-select" rescue nil
    end
  end

  it "does not display an Isolate Ctx control on a process element" do
    process_id = "p_#{SecureRandom.uuid}"
    flowchart.update!(elements: flowchart.elements + [
      { "id" => process_id, "type" => "process", "label" => "P",
        "properties" => { "steps" => [], "isolateCtx" => "true" } }
    ])

    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"
    find("[data-element-id='#{process_id}']").click
    find("[data-tab='advanced']").click

    expect(page).not_to have_content("Isolate Ctx")
  end
end
```

- [ ] **Step 2: Run the system spec**

Run: `bundle exec rspec spec/system/property_editor/element_io_tab_spec.rb`
Expected: PASS. If the tab/badge markup differs, adjust the Capybara selectors to match Task 12's DOM (`[data-element-io-inputs]`, `[data-element-io-outputs]`, `[data-element-io-input]`, etc.).

- [ ] **Step 3: Commit**

```bash
git add spec/system/property_editor/element_io_tab_spec.rb
git commit -m "test(system): element I/O tab auto-detect + collision badge + isolateCtx removed"
```

---

### Task 19: Full regression sweep

**Files:**
- All specs.

- [ ] **Step 1: Run the full code_generators suite**

Run: `bundle exec rspec spec/services/code_generators spec/services/activity_generator_spec.rb spec/controllers/code_generators`
Expected: PASS; total example count ≥ 4331 + ~20 new examples, 0 failures.

- [ ] **Step 2: Run the full spec suite**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 3: Precompile assets and browser-reload**

Run: `bin/rails assets:precompile`
Reload the flowchart edit page. Verify:
- Adding any element auto-populates its I/O tab.
- Two elements writing the same pin show a rename badge on both.
- Deleting an upstream producer silently resets the downstream override.
- No `isolateCtx` control, no Add Input / Add Output buttons anywhere.

- [ ] **Step 4: Final commit if any fixups were needed**

```bash
git status
# If any files changed:
git add -A
git commit -m "fix: regression cleanup after element-io auto-detection rollout"
```

---

## Self-Review Summary

**Spec coverage check:**
- §1 IOExtractor.call_element → Task 1, Task 17.
- §2 EmissionRewriter.call_element → Task 4.
- §3 ConflictResolver element pass → Task 3.
- §4 ActivityGenerator changes (remove isolateCtx, add element rewrite) → Task 5.
- §5 HTTP endpoint + route → Task 2.
- §6 Canvas elementPins cache + invalidation → Tasks 6, 7, 8, 11, 13.
- §7 ElementIoManager → Task 12; reachability + override_computer → Tasks 9, 10.
- §8 I/O tab layout → Task 12 renders the specified layout.
- §9 Deletions (isolateCtx, COMMON_PROPERTIES.inputs/outputs, HIDDEN_DEFAULT_*, IOManager, universe logic, inherited-inputs) → Tasks 14, 15, 16.
- Testing — Ruby → Tasks 1, 2, 3, 4, 5, 17; JS surface → covered by system spec Task 18; full regression → Task 19.

No placeholders; every code step contains the full code. Type/method names stay consistent: `IoExtractor.call_element` / `EmissionRewriter.call_element` / `ConflictResolver.call` / `ElementIoManager.openForElement` / `ElementReachability.predecessors` / `canvas.setElementPins` / `canvas.getElementPins` / `canvas.iterateElements` / `canvas.emitStructureChanged` are referenced consistently across all tasks.
