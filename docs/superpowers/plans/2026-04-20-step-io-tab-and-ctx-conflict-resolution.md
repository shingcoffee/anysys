# Step I/O Tab & Ctx Conflict Resolution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate the property editor's I/O tab for step actions (inputs/outputs extracted from generator bodies) and resolve runtime `ctx[:x]` collisions by automatically renaming colliding output keys and binding readers to producers structurally.

**Architecture:** Three new server services — `IoExtractor`, `ConflictResolver`, `EmissionRewriter` — sharing a Ripper-based `BodyAnalyzer`. One new JSON endpoint, one new JS manager in the step modal with a client-side port of the resolver. New `io_bindings` field on each step; rename keys are SHA1(`step_id:pin`)[0..3] suffixed.

**Tech Stack:** Ruby 3.2 / Rails 8.1 (Ripper stdlib for AST), Trailblazer Activity (unchanged ctx bus), StimulusJS, TailwindCSS, RSpec, Capybara.

**Spec:** [2026-04-20-step-io-tab-and-ctx-conflict-resolution-design.md](../specs/2026-04-20-step-io-tab-and-ctx-conflict-resolution-design.md)

---

## File Structure

### New files

- `app/services/code_generators/io_extractor.rb` — public service: generator + config → pins list.
- `app/services/code_generators/io_extractor/body_analyzer.rb` — Ripper walker returning `{reads, writes}` with source positions.
- `app/services/code_generators/conflict_resolver.rb` — whole-flowchart pass → rename map.
- `app/services/code_generators/emission_rewriter.rb` — per-body splice.
- `app/services/code_generators/reachability_index.rb` — predecessor index from flowchart connections, isolateCtx-aware.
- `app/controllers/code_generators/io_params_controller.rb` — JSON endpoint.
- `app/javascript/controllers/property_editor/step_io_manager.js` — orchestrates step modal I/O tab.
- `app/javascript/controllers/property_editor/step_io/body_analyzer.js` — JS port (regex-based, see Task 11).
- `app/javascript/controllers/property_editor/step_io/reachability.js` — JS predecessor walker.
- `app/javascript/controllers/property_editor/step_io/conflict_detector.js` — JS port of resolver.
- `app/javascript/controllers/property_editor/step_io/io_params_client.js` — fetch wrapper for the endpoint.
- `spec/services/code_generators/io_extractor_spec.rb`
- `spec/services/code_generators/io_extractor/body_analyzer_spec.rb`
- `spec/services/code_generators/conflict_resolver_spec.rb`
- `spec/services/code_generators/emission_rewriter_spec.rb`
- `spec/services/code_generators/reachability_index_spec.rb`
- `spec/controllers/code_generators/io_params_controller_spec.rb`
- `spec/system/property_editor/step_io_tab_spec.rb`
- `spec/fixtures/flowcharts/conflict_scenarios/*.json` — shared fixtures for Ruby + JS contract tests.

### Modified files

- `config/routes.rb` — add the io_params POST route.
- `app/services/activity_generator.rb:689-710` — splice `EmissionRewriter` into `generate_step_code`; build rename map + reachability once.
- `app/services/activity_generator.rb:32-44` — extend `generate` to compute resolver inputs before DFS.
- `app/javascript/controllers/property_editor_controller.js` — instantiate `StepIoManager`; wire into step modal open/close.
- `app/javascript/controllers/property_editor/step_manager.js` — hook into step modal open + field-change events so I/O tab refreshes.
- `app/javascript/flowchart/canvas.js` — add `stepPins` cache and bookkeeping API.
- `app/javascript/controllers/flowchart_canvas_controller.js` — on canvas ready, bulk-prime `stepPins` for all existing steps.
- `spec/services/activity_generator_spec.rb` — integration case for conflict rename + binding resolution.
- `config/initializers/inflections.rb` (only if missing `IO` acronym — check first).

---

## Task 1: BodyAnalyzer — Ripper walker, reads and writes with positions

**Files:**
- Create: `app/services/code_generators/io_extractor/body_analyzer.rb`
- Test: `spec/services/code_generators/io_extractor/body_analyzer_spec.rb`

**Design contract:**

```ruby
CodeGenerators::IoExtractor::BodyAnalyzer.call(ruby_source_string)
# => {
#   reads:  [{ pin: "x", start: 10, length: 7 }, ...],   # 'ctx[:x]' positions
#   writes: [{ pin: "y", start: 40, length: 7 }, ...]    # LHS of ctx[:y] = ...
# }
```

A ctx occurrence that is the LHS of `=` / `op_assign` becomes both a write and (for op_assigns) a read. `start` is a 0-based byte offset into `ruby_source_string`; `length` covers the full `ctx[:sym]` token span.

- [ ] **Step 1: Write the first failing spec**

`spec/services/code_generators/io_extractor/body_analyzer_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::IoExtractor::BodyAnalyzer do
  describe ".call" do
    it "returns empty arrays for empty source" do
      expect(described_class.call("")).to eq(reads: [], writes: [])
    end

    it "detects a single ctx read" do
      src = "x = ctx[:user]"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(["user"])
      expect(result[:writes]).to be_empty
      read = result[:reads].first
      expect(src.byteslice(read[:start], read[:length])).to eq("ctx[:user]")
    end

    it "detects a single ctx write" do
      src = "ctx[:model] = User.new"
      result = described_class.call(src)
      expect(result[:writes].map { |w| w[:pin] }).to eq(["model"])
      expect(result[:reads]).to be_empty
      w = result[:writes].first
      expect(src.byteslice(w[:start], w[:length])).to eq("ctx[:model]")
    end

    it "treats op-assign (||=) as both read and write" do
      src = "ctx[:count] ||= 0"
      result = described_class.call(src)
      expect(result[:writes].map { |w| w[:pin] }).to eq(["count"])
      expect(result[:reads].map { |r| r[:pin] }).to eq(["count"])
    end

    it "dedupes repeated reads but preserves first-seen order" do
      src = "a = ctx[:x]\nb = ctx[:y]\nc = ctx[:x]"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }.uniq).to eq(["x", "y"])
      expect(result[:reads].size).to eq(3)  # positions kept for rewriter
    end

    it "skips dynamic access ctx[some_var]" do
      src = "ctx[some_var] = 1\nctx[config['k'].to_sym]"
      result = described_class.call(src)
      expect(result[:reads]).to be_empty
      expect(result[:writes]).to be_empty
    end

    it "detects only the outermost symbol in chained access ctx[:x][:y]" do
      src = "a = ctx[:x][:y]"
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(["x"])
    end

    it "detects ctx[:x] inside string interpolation" do
      src = 'puts "value: #{ctx[:greeting]}"'
      result = described_class.call(src)
      expect(result[:reads].map { |r| r[:pin] }).to eq(["greeting"])
    end

    it "ignores ctx[:x] inside comments" do
      src = "# ctx[:ignored]\nctx[:real] = 1"
      result = described_class.call(src)
      expect(result[:reads]).to be_empty
      expect(result[:writes].map { |w| w[:pin] }).to eq(["real"])
    end

    it "returns empty arrays when source is unparseable" do
      result = described_class.call("def broken")
      expect(result).to eq(reads: [], writes: [])
    end
  end
end
```

- [ ] **Step 2: Run spec, confirm failure**

```
bundle exec rspec spec/services/code_generators/io_extractor/body_analyzer_spec.rb
```
Expected: NameError / uninitialized constant `CodeGenerators::IoExtractor::BodyAnalyzer`.

- [ ] **Step 3: Implement BodyAnalyzer**

`app/services/code_generators/io_extractor/body_analyzer.rb`:

```ruby
# frozen_string_literal: true

require "ripper"

module CodeGenerators
  class IoExtractor
    # BodyAnalyzer
    #
    # Parses a Ruby source string with Ripper and collects every literal
    # `ctx[:symbol]` occurrence, classifying each as a read or a write
    # (LHS of `=` or op-assign).
    #
    # Only literal symbol references (`ctx[:foo]`) are detected. Dynamic
    # access (`ctx[var]`, `ctx[expr]`) is intentionally skipped; see the
    # I/O tab design doc for rationale.
    class BodyAnalyzer
      EMPTY = { reads: [], writes: [] }.freeze

      def self.call(source)
        return EMPTY if source.nil? || source.empty?

        new(source).analyze
      end

      def initialize(source)
        @source = source
        @reads = []
        @writes = []
      end

      def analyze
        sexp = Ripper.sexp(@source)
        return EMPTY unless sexp

        walk(sexp, write_lhs: false)
        { reads: @reads, writes: @writes }
      rescue StandardError
        EMPTY
      end

      private

      # Recursive descent over Ripper sexps. Nodes we care about:
      #
      #   assign        [:assign, TARGET, VALUE]          # TARGET is a write
      #   opassign      [:opassign, TARGET, op, VALUE]    # TARGET is both read and write
      #   aref          [:aref, [:var_ref,[:@ident,"ctx"]], [:args_add_block, [[:symbol_literal,...]], false]]
      #     -> a read when not in write position.
      #   aref_field    like aref, but appears as LHS of assign/opassign.
      def walk(node, write_lhs:)
        return unless node.is_a?(Array)

        kind = node.first

        case kind
        when :assign
          _, target, value = node
          record_ctx_occurrence(target, write: true)
          walk(value, write_lhs: false)
        when :opassign
          _, target, _op, value = node
          record_ctx_occurrence(target, write: true)
          record_ctx_occurrence(target, write: false)
          walk(value, write_lhs: false)
        when :aref, :aref_field
          if ctx_symbol_aref?(node)
            record_ctx_occurrence(node, write: write_lhs)
            # Don't recurse into its indices — nested `[:y]` indexing past
            # an outer `ctx[:x]` is not a separate pin.
            return
          end
          node[1..].each { |child| walk(child, write_lhs: false) }
        else
          node[1..].each { |child| walk(child, write_lhs: false) } if node.size > 1
        end
      end

      # Recognizes `ctx[:sym]` nodes in both :aref and :aref_field forms.
      def ctx_symbol_aref?(node)
        _, receiver, args = node
        return false unless receiver.is_a?(Array)
        return false unless receiver[0] == :var_ref || receiver[0] == :var_field
        ident = receiver[1]
        return false unless ident.is_a?(Array) && ident[0] == :@ident && ident[1] == "ctx"
        extract_literal_symbol(args) != nil
      end

      # Given the args-part of ctx[...], return the literal symbol name string,
      # or nil if not a literal symbol.
      def extract_literal_symbol(args)
        return nil unless args.is_a?(Array)
        # Ripper produces [:args_add_block, [ARG], false]
        arg_list = if args[0] == :args_add_block
                     args[1]
                   else
                     args
                   end
        return nil unless arg_list.is_a?(Array) && arg_list.size == 1
        sym_node = arg_list.first
        return nil unless sym_node.is_a?(Array) && sym_node[0] == :symbol_literal
        inner = sym_node[1]
        return nil unless inner.is_a?(Array) && inner[0] == :symbol
        ident = inner[1]
        return nil unless ident.is_a?(Array) && (ident[0] == :@ident || ident[0] == :@const || ident[0] == :@kw)
        ident[1]
      end

      # Record the ctx occurrence in @reads or @writes with its source position.
      def record_ctx_occurrence(aref_node, write:)
        _, receiver, args = aref_node
        pin = extract_literal_symbol(args)
        return unless pin
        pos = locate_span(aref_node)
        return unless pos
        entry = { pin: pin, start: pos[:start], length: pos[:length] }
        (write ? @writes : @reads) << entry
      end

      # Ripper doesn't include byte offsets in sexp nodes, so we locate
      # each `ctx[:sym]` span by scanning the source. Since pin names
      # resolve uniquely per position (every literal `ctx[:sym]` in the
      # source corresponds to one node), we scan in order and consume
      # each match once.
      def locate_span(aref_node)
        pin = extract_literal_symbol(aref_node[2])
        return nil unless pin

        @scan_offsets ||= Hash.new(0)
        pattern = "ctx[:#{pin}]"
        start = @source.index(pattern, @scan_offsets[pin])
        return nil unless start

        @scan_offsets[pin] = start + pattern.length
        { start: start, length: pattern.length }
      end
    end
  end
end
```

- [ ] **Step 4: Run spec, confirm pass**

```
bundle exec rspec spec/services/code_generators/io_extractor/body_analyzer_spec.rb
```
Expected: all examples pass.

- [ ] **Step 5: Commit**

```
git add app/services/code_generators/io_extractor/body_analyzer.rb \
        spec/services/code_generators/io_extractor/body_analyzer_spec.rb
git commit -m "feat(codegen): add BodyAnalyzer for ctx read/write extraction"
```

---

## Task 2: IoExtractor — run generator, classify pins, return structured result

**Files:**
- Create: `app/services/code_generators/io_extractor.rb`
- Test: `spec/services/code_generators/io_extractor_spec.rb`

**Design contract:**

```ruby
CodeGenerators::IoExtractor.call(action: "api_call", config: {...})
# => {
#   inputs:  [{ pin: "api_url", ctx_key: "api_url", source: "config_expr" }],
#   outputs: [{ pin: "api_response", ctx_key: "api_response" }]
# }
```

- [ ] **Step 1: Write failing specs**

`spec/services/code_generators/io_extractor_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::IoExtractor do
  describe ".call" do
    it "returns empty pins for unknown action" do
      result = described_class.call(action: "definitely_not_a_real_action", config: {})
      expect(result).to eq(inputs: [], outputs: [])
    end

    it "extracts outputs from api_call generator" do
      result = described_class.call(
        action: "api_call",
        config: { "httpMethod" => "GET", "url" => '"https://example.com"', "resultVar" => "resp", "responseFormat" => "json" }
      )
      expect(result[:outputs].map { |o| o[:pin] }).to include("resp")
    end

    it "tags ctx reads that originate from a config expression as source: config_expr" do
      result = described_class.call(
        action: "api_call",
        config: { "httpMethod" => "GET", "url" => "ctx[:target_url]", "resultVar" => "resp", "responseFormat" => "json" }
      )
      expect(result[:inputs]).to include(hash_including(pin: "target_url", source: "config_expr"))
    end

    it "tags literal reads from generator body as source: generator_literal" do
      # api_call's build_url_resolution falls back to ctx[:api_url] when url is blank
      result = described_class.call(
        action: "api_call",
        config: { "httpMethod" => "GET", "resultVar" => "resp", "responseFormat" => "json" }
      )
      expect(result[:inputs]).to include(hash_including(pin: "api_url", source: "generator_literal"))
    end

    it "dedupes pins" do
      result = described_class.call(
        action: "api_call",
        config: { "httpMethod" => "GET", "url" => '"https://example.com"', "resultVar" => "resp", "responseFormat" => "json" }
      )
      expect(result[:outputs].map { |o| o[:pin] }.uniq).to eq(result[:outputs].map { |o| o[:pin] })
    end

    it "returns empty pins when generator raises during body generation" do
      stub_gen = Class.new do
        def initialize(_element, _ctx); end
        def generate_body; raise "boom"; end
      end
      registry = CodeGenerators::GeneratorRegistry.instance
      allow(registry).to receive(:find_step_action).with("exploding_action").and_return(stub_gen)

      result = described_class.call(action: "exploding_action", config: {})
      expect(result).to eq(inputs: [], outputs: [])
    end

    it "populates ctx_key equal to pin in v1" do
      result = described_class.call(
        action: "api_call",
        config: { "httpMethod" => "GET", "url" => '"https://example.com"', "resultVar" => "resp", "responseFormat" => "json" }
      )
      result[:outputs].each { |o| expect(o[:ctx_key]).to eq(o[:pin]) }
      result[:inputs].each { |i| expect(i[:ctx_key]).to eq(i[:pin]) }
    end
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/services/code_generators/io_extractor_spec.rb
```

- [ ] **Step 3: Implement IoExtractor**

`app/services/code_generators/io_extractor.rb`:

```ruby
# frozen_string_literal: true

require_relative "io_extractor/body_analyzer"

module CodeGenerators
  class IoExtractor
    EMPTY = { inputs: [], outputs: [] }.freeze
    CTX_SYMBOL_IN_STRING = /ctx\[:([a-zA-Z_][a-zA-Z0-9_]*)\]/.freeze

    def self.call(action:, config: {})
      new(action: action, config: config).call
    end

    def initialize(action:, config:)
      @action = action
      @config = config || {}
    end

    def call
      generator_class = CodeGenerators::GeneratorRegistry.instance.find_step_action(@action)
      return EMPTY unless generator_class

      body = build_body(generator_class)
      return EMPTY unless body

      ast = BodyAnalyzer.call(body)
      config_expr_pins = extract_config_expr_pins

      {
        inputs: dedupe_preserving_order(ast[:reads]).map { |r| input_hash(r, config_expr_pins) },
        outputs: dedupe_preserving_order(ast[:writes]).map { |w| output_hash(w) }
      }
    end

    private

    def build_body(generator_class)
      element = { "id" => "__extract_stub__", "label" => "stub", "action" => @action, "properties" => @config, "config" => @config }
      generator = generator_class.new(element, { config: @config })
      generator.generate_body
    rescue StandardError
      nil
    end

    def extract_config_expr_pins
      set = Set.new
      @config.each_value do |value|
        next unless value.is_a?(String)
        value.scan(CTX_SYMBOL_IN_STRING) { |m| set << m.first }
      end
      set
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
      { pin: read[:pin], ctx_key: read[:pin],
        source: config_expr_pins.include?(read[:pin]) ? "config_expr" : "generator_literal" }
    end

    def output_hash(write)
      { pin: write[:pin], ctx_key: write[:pin] }
    end
  end
end
```

- [ ] **Step 4: Run spec, confirm pass**

```
bundle exec rspec spec/services/code_generators/io_extractor_spec.rb
```

- [ ] **Step 5: Commit**

```
git add app/services/code_generators/io_extractor.rb \
        spec/services/code_generators/io_extractor_spec.rb
git commit -m "feat(codegen): add IoExtractor service"
```

---

## Task 3: ReachabilityIndex — predecessor graph with isolateCtx boundaries

**Files:**
- Create: `app/services/code_generators/reachability_index.rb`
- Test: `spec/services/code_generators/reachability_index_spec.rb`

**Design contract:**

```ruby
idx = CodeGenerators::ReachabilityIndex.build(flowchart)
idx.reachable_predecessors(step_id)  # Set<String> of every step id upstream on any path
idx.nearest_predecessor(step_id, producing: pin_name, producer_outputs: {...})  # String | nil
idx.same_universe?(step_a_id, step_b_id)  # true unless an isolateCtx boundary separates them
```

A "step id" here is the id field on a step inside a `process.steps[]` array OR the element id for element-level steps that are themselves steps (none in v1 scope). The index treats each step-action as a node; element-level edges (connections between process/decision/etc.) are traversed but processes are expanded into their contained steps in order.

- [ ] **Step 1: Write failing specs**

```ruby
# spec/services/code_generators/reachability_index_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ReachabilityIndex do
  def flowchart_double(elements:, connections:)
    instance_double("Flowchart", elements: elements, connections: connections)
  end

  def step(id, action: "noop")
    { "id" => id, "action" => action, "config" => {} }
  end

  def process_element(id, steps:, properties: {})
    { "id" => id, "type" => "process", "properties" => properties.merge("steps" => steps) }
  end

  describe ".build + predecessors" do
    it "returns empty set for step with no predecessors" do
      fc = flowchart_double(
        elements: [
          { "id" => "start1", "type" => "start" },
          process_element("p1", steps: [step("s1")])
        ],
        connections: [{ "from" => "start1", "to" => "p1" }]
      )
      idx = described_class.build(fc)
      expect(idx.reachable_predecessors("s1")).to eq(Set.new)
    end

    it "reports sequential predecessors within a process" do
      fc = flowchart_double(
        elements: [
          { "id" => "start1", "type" => "start" },
          process_element("p1", steps: [step("s1"), step("s2"), step("s3")])
        ],
        connections: [{ "from" => "start1", "to" => "p1" }]
      )
      idx = described_class.build(fc)
      expect(idx.reachable_predecessors("s3")).to eq(Set.new(%w[s1 s2]))
      expect(idx.reachable_predecessors("s2")).to eq(Set.new(%w[s1]))
    end

    it "treats both branches of a decision as reachable to a reader past the merge" do
      fc = flowchart_double(
        elements: [
          { "id" => "start1", "type" => "start" },
          process_element("p_if",   steps: [step("a1")]),
          process_element("p_else", steps: [step("a2")]),
          { "id" => "d1", "type" => "decision" },
          process_element("p_after", steps: [step("a3")])
        ],
        connections: [
          { "from" => "start1", "to" => "d1" },
          { "from" => "d1", "to" => "p_if" },
          { "from" => "d1", "to" => "p_else" },
          { "from" => "p_if",   "to" => "p_after" },
          { "from" => "p_else", "to" => "p_after" }
        ]
      )
      idx = described_class.build(fc)
      expect(idx.reachable_predecessors("a3")).to include("a1", "a2")
    end

    it "does not cross isolateCtx boundaries" do
      fc = flowchart_double(
        elements: [
          { "id" => "start1", "type" => "start" },
          process_element("p_outside", steps: [step("out1")]),
          process_element("p_iso", steps: [step("in1")], properties: { "isolateCtx" => "true" })
        ],
        connections: [
          { "from" => "start1", "to" => "p_outside" },
          { "from" => "p_outside", "to" => "p_iso" }
        ]
      )
      idx = described_class.build(fc)
      expect(idx.reachable_predecessors("in1")).not_to include("out1")
      expect(idx.same_universe?("out1", "in1")).to be false
    end

    it "same_universe? true for steps in the same non-isolated scope" do
      fc = flowchart_double(
        elements: [
          { "id" => "start1", "type" => "start" },
          process_element("p", steps: [step("a"), step("b")])
        ],
        connections: [{ "from" => "start1", "to" => "p" }]
      )
      idx = described_class.build(fc)
      expect(idx.same_universe?("a", "b")).to be true
    end
  end

  describe "#nearest_predecessor" do
    it "returns the most recent producer on the path" do
      fc = flowchart_double(
        elements: [
          { "id" => "start1", "type" => "start" },
          process_element("p", steps: [step("a"), step("b"), step("c")])
        ],
        connections: [{ "from" => "start1", "to" => "p" }]
      )
      idx = described_class.build(fc)
      producer_outputs = { "a" => ["model"], "b" => ["model"], "c" => [] }
      expect(idx.nearest_predecessor("c", producing: "model", producer_outputs: producer_outputs)).to eq("b")
    end

    it "returns nil if no predecessor produces the pin" do
      fc = flowchart_double(
        elements: [
          { "id" => "start1", "type" => "start" },
          process_element("p", steps: [step("a"), step("b")])
        ],
        connections: [{ "from" => "start1", "to" => "p" }]
      )
      idx = described_class.build(fc)
      producer_outputs = { "a" => [], "b" => [] }
      expect(idx.nearest_predecessor("b", producing: "model", producer_outputs: producer_outputs)).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/services/code_generators/reachability_index_spec.rb
```

- [ ] **Step 3: Implement ReachabilityIndex**

```ruby
# app/services/code_generators/reachability_index.rb
# frozen_string_literal: true

module CodeGenerators
  # ReachabilityIndex
  #
  # Computes per-step predecessor sets over a flowchart tree, respecting
  # isolateCtx process boundaries (a separate reachability universe).
  # Steps inside different process elements are linked by the connection
  # graph on elements; steps inside one process are linearly ordered.
  class ReachabilityIndex
    def self.build(flowchart)
      new(flowchart).tap(&:build!)
    end

    attr_reader :predecessors, :universe_of

    def initialize(flowchart)
      @elements = flowchart.elements || []
      @connections = flowchart.connections || []
      @predecessors = Hash.new { |h, k| h[k] = Set.new }
      @universe_of = {}  # step_id -> universe_id (parent process id or :root)
    end

    def build!
      assign_universes
      compute_predecessors
      self
    end

    def reachable_predecessors(step_id)
      @predecessors[step_id]
    end

    def same_universe?(a, b)
      @universe_of[a] && @universe_of[a] == @universe_of[b]
    end

    def nearest_predecessor(step_id, producing:, producer_outputs:)
      order = topological_order[step_id] || []
      order.reverse_each do |candidate|
        next unless producer_outputs[candidate]&.include?(producing)
        return candidate
      end
      nil
    end

    private

    # Map each step id to the "universe" it belongs to: the nearest enclosing
    # isolateCtx-true process, or :root if none.
    def assign_universes
      @elements.each do |el|
        steps = Array(el.dig("properties", "steps"))
        universe = universe_for_element(el)
        steps.each { |s| @universe_of[s["id"]] = universe }
      end
    end

    def universe_for_element(el)
      return :root unless el["type"] == "process"
      el.dig("properties", "isolateCtx").to_s == "true" ? el["id"] : :root
    end

    def compute_predecessors
      element_steps = Hash.new { |h, k| h[k] = [] }
      @elements.each do |el|
        steps = Array(el.dig("properties", "steps"))
        element_steps[el["id"]] = steps.map { |s| s["id"] }
      end

      # Within each element, each step inherits the predecessors of the step before,
      # plus that prior step itself. Between elements, inherit from the last steps of
      # every element that has a connection ending at this element.
      element_last_steps = {}
      # Topological walk over elements using connections; since element topology
      # can include cycles (loop elements), we use an iterative worklist that
      # re-processes until fixed point. For a typical DAG the cost is linear.
      order = element_topo_order
      order.each do |el_id|
        entry_predecessors = element_entry_predecessors(el_id, element_last_steps)
        steps = element_steps[el_id]
        running = entry_predecessors.dup
        steps.each do |sid|
          # Only inherit predecessors that share the same universe.
          @predecessors[sid] = running.select { |p| @universe_of[p] == @universe_of[sid] }.to_set
          running << sid
        end
        element_last_steps[el_id] = steps.empty? ? entry_predecessors.to_a : [steps.last]
      end
    end

    def element_topo_order
      in_degree = Hash.new(0)
      @elements.each { |el| in_degree[el["id"]] = 0 }
      @connections.each { |c| in_degree[c["to"]] += 1 if in_degree.key?(c["to"]) }

      queue = in_degree.select { |_, v| v.zero? }.keys
      order = []
      while (id = queue.shift)
        order << id
        @connections.each do |c|
          next unless c["from"] == id && in_degree.key?(c["to"])
          in_degree[c["to"]] -= 1
          queue << c["to"] if in_degree[c["to"]].zero?
        end
      end

      # Append any unordered ids (cycles) so we never drop elements.
      unordered = @elements.map { |el| el["id"] } - order
      order + unordered
    end

    def element_entry_predecessors(el_id, element_last_steps)
      feeders = @connections.select { |c| c["to"] == el_id }.map { |c| c["from"] }
      feeders.flat_map { |f| element_last_steps[f] || [] }.to_set
    end

    def topological_order
      @topological_order ||= begin
        map = {}
        @predecessors.each do |step_id, preds|
          # Represent predecessors in deterministic order: their own predecessor-set size.
          map[step_id] = preds.to_a.sort_by { |p| @predecessors[p].size }
        end
        map
      end
    end
  end
end
```

- [ ] **Step 4: Run, confirm pass**

```
bundle exec rspec spec/services/code_generators/reachability_index_spec.rb
```

- [ ] **Step 5: Commit**

```
git add app/services/code_generators/reachability_index.rb \
        spec/services/code_generators/reachability_index_spec.rb
git commit -m "feat(codegen): add ReachabilityIndex for step predecessors + isolateCtx scoping"
```

---

## Task 4: ConflictResolver — rename map from multi-producer pins

**Files:**
- Create: `app/services/code_generators/conflict_resolver.rb`
- Test: `spec/services/code_generators/conflict_resolver_spec.rb`

**Design contract:**

```ruby
result = CodeGenerators::ConflictResolver.call(flowchart)
result.rename_map        # { step_id => { pin => "pin_xxxx" } }
result.producer_outputs  # { step_id => ["pin", ...] }  (reused downstream)
result.reachability      # ReachabilityIndex
```

Rename policy: if ≥2 producers of the same pin are both reachable to ANY single reader, ALL producers of that pin get renamed. Suffix `_` + first 4 hex chars of `SHA1("#{step_id}:#{pin}")`; fall back to 6 chars on collision.

- [ ] **Step 1: Write failing specs**

```ruby
# spec/services/code_generators/conflict_resolver_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ConflictResolver do
  def fc(elements:, connections:)
    instance_double("Flowchart", elements: elements, connections: connections)
  end

  def step(id, action:, config: {})
    { "id" => id, "action" => action, "config" => config, "io_bindings" => [] }
  end

  def process_element(id, steps:, properties: {})
    { "id" => id, "type" => "process", "properties" => properties.merge("steps" => steps) }
  end

  # A trivial stub generator so tests don't depend on real generator internals.
  before do
    stub_registry = CodeGenerators::GeneratorRegistry.instance

    writer_a = Class.new do
      def initialize(_e, _c); end
      def generate_body; "ctx[:model] = 1"; end
    end
    writer_b = Class.new do
      def initialize(_e, _c); end
      def generate_body; "ctx[:model] = 2"; end
    end
    reader_c = Class.new do
      def initialize(_e, _c); end
      def generate_body; "x = ctx[:model]"; end
    end
    unique_writer = Class.new do
      def initialize(_e, _c); end
      def generate_body; "ctx[:only] = 1"; end
    end

    allow(stub_registry).to receive(:find_step_action).and_call_original
    allow(stub_registry).to receive(:find_step_action).with("w_a").and_return(writer_a)
    allow(stub_registry).to receive(:find_step_action).with("w_b").and_return(writer_b)
    allow(stub_registry).to receive(:find_step_action).with("r").and_return(reader_c)
    allow(stub_registry).to receive(:find_step_action).with("u").and_return(unique_writer)
  end

  describe ".call" do
    it "returns empty rename_map when a pin has a single producer" do
      f = fc(
        elements: [
          { "id" => "s", "type" => "start" },
          process_element("p", steps: [step("a", action: "u"), step("b", action: "r")])
        ],
        connections: [{ "from" => "s", "to" => "p" }]
      )
      expect(described_class.call(f).rename_map).to be_empty
    end

    it "returns empty rename_map when multiple producers have no reader" do
      f = fc(
        elements: [
          { "id" => "s", "type" => "start" },
          process_element("p", steps: [step("a", action: "w_a"), step("b", action: "w_b")])
        ],
        connections: [{ "from" => "s", "to" => "p" }]
      )
      expect(described_class.call(f).rename_map).to be_empty
    end

    it "renames all producers when two are reachable to any single reader" do
      f = fc(
        elements: [
          { "id" => "s", "type" => "start" },
          process_element("p", steps: [
            step("a", action: "w_a"),
            step("b", action: "w_b"),
            step("c", action: "r")
          ])
        ],
        connections: [{ "from" => "s", "to" => "p" }]
      )
      rm = described_class.call(f).rename_map
      expect(rm["a"]).to eq("model" => a_string_matching(/\Amodel_[0-9a-f]{4}\z/))
      expect(rm["b"]).to eq("model" => a_string_matching(/\Amodel_[0-9a-f]{4}\z/))
    end

    it "does NOT rename across an isolateCtx process boundary" do
      f = fc(
        elements: [
          { "id" => "s", "type" => "start" },
          process_element("p_out", steps: [step("a", action: "w_a")]),
          process_element("p_iso", steps: [
            step("b", action: "w_b"),
            step("c", action: "r")
          ], properties: { "isolateCtx" => "true" })
        ],
        connections: [
          { "from" => "s", "to" => "p_out" },
          { "from" => "p_out", "to" => "p_iso" }
        ]
      )
      expect(described_class.call(f).rename_map).to be_empty
    end

    it "is deterministic: same flowchart ⇒ identical rename map" do
      f = fc(
        elements: [
          { "id" => "s", "type" => "start" },
          process_element("p", steps: [step("a", action: "w_a"), step("b", action: "w_b"), step("c", action: "r")])
        ],
        connections: [{ "from" => "s", "to" => "p" }]
      )
      r1 = described_class.call(f).rename_map
      r2 = described_class.call(f).rename_map
      expect(r1).to eq(r2)
    end
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/services/code_generators/conflict_resolver_spec.rb
```

- [ ] **Step 3: Implement ConflictResolver**

```ruby
# app/services/code_generators/conflict_resolver.rb
# frozen_string_literal: true

require "digest"

module CodeGenerators
  class ConflictResolver
    Result = Struct.new(:rename_map, :producer_outputs, :reader_inputs, :reachability, keyword_init: true)

    def self.call(flowchart)
      new(flowchart).call
    end

    def initialize(flowchart)
      @flowchart = flowchart
    end

    def call
      steps = collect_step_actions(@flowchart)
      producer_outputs = {}
      reader_inputs = {}
      steps.each do |step|
        pins = IoExtractor.call(action: step["action"], config: step["config"] || {})
        producer_outputs[step["id"]] = pins[:outputs].map { |o| o[:pin] }
        reader_inputs[step["id"]]    = pins[:inputs].map { |i| i[:pin] }
      end

      reachability = ReachabilityIndex.build(@flowchart)
      rename_map = compute_rename_map(producer_outputs, reader_inputs, reachability)

      Result.new(rename_map: rename_map, producer_outputs: producer_outputs,
                 reader_inputs: reader_inputs, reachability: reachability)
    end

    private

    def collect_step_actions(flowchart)
      result = []
      (flowchart.elements || []).each do |el|
        Array(el.dig("properties", "steps")).each { |s| result << s }
      end
      result
    end

    # Builds: { pin => [step_id, ...] } limited to multi-producer pins.
    def multi_producer_pins(producer_outputs)
      by_pin = Hash.new { |h, k| h[k] = [] }
      producer_outputs.each do |step_id, pins|
        pins.each { |pin| by_pin[pin] << step_id }
      end
      by_pin.select { |_pin, producers| producers.size >= 2 }
    end

    def compute_rename_map(producer_outputs, reader_inputs, reachability)
      rename_map = Hash.new { |h, k| h[k] = {} }
      pin_to_producers = multi_producer_pins(producer_outputs)

      pin_to_producers.each do |pin, producer_ids|
        readers = reader_inputs.select { |_rid, pins| pins.include?(pin) }.keys
        triggers_rename = readers.any? do |reader_id|
          reachable = producer_ids.select { |pid|
            reachability.reachable_predecessors(reader_id).include?(pid) &&
              reachability.same_universe?(reader_id, pid)
          }
          reachable.size >= 2
        end
        next unless triggers_rename

        producer_ids.each do |pid|
          suffix = unique_suffix(pid, pin, rename_map)
          rename_map[pid][pin] = "#{pin}_#{suffix}"
        end
      end

      rename_map
    end

    def unique_suffix(step_id, pin, rename_map)
      hex = Digest::SHA1.hexdigest("#{step_id}:#{pin}")
      candidate = hex[0, 4]
      assigned = rename_map.values.flat_map(&:values)
      return candidate unless assigned.include?("#{pin}_#{candidate}")
      hex[0, 6]
    end
  end
end
```

- [ ] **Step 4: Run, confirm pass**

```
bundle exec rspec spec/services/code_generators/conflict_resolver_spec.rb
```

- [ ] **Step 5: Commit**

```
git add app/services/code_generators/conflict_resolver.rb \
        spec/services/code_generators/conflict_resolver_spec.rb
git commit -m "feat(codegen): add ConflictResolver for ctx pin rename maps"
```

---

## Task 5: EmissionRewriter — splice ctx reads and writes in step bodies

**Files:**
- Create: `app/services/code_generators/emission_rewriter.rb`
- Test: `spec/services/code_generators/emission_rewriter_spec.rb`

**Design contract:**

```ruby
CodeGenerators::EmissionRewriter.call(
  body: body,
  step_id: step_id,
  io_bindings: step["io_bindings"] || [],
  rename_map: rename_map_hash,
  reachability: reachability_index,
  producer_outputs: producer_outputs_hash
)  # => rewritten body String
```

- [ ] **Step 1: Write failing specs**

```ruby
# spec/services/code_generators/emission_rewriter_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::EmissionRewriter do
  # A stub ReachabilityIndex that returns pre-canned nearest-predecessor answers.
  def stub_reachability(nearest_by_reader = {})
    idx = Object.new
    idx.define_singleton_method(:nearest_predecessor) do |step_id, producing:, producer_outputs:|
      (nearest_by_reader[step_id] || {})[producing]
    end
    idx
  end

  it "rewrites writes that match the rename map" do
    body = "ctx[:model] = 1"
    out = described_class.call(
      body: body, step_id: "s1", io_bindings: [],
      rename_map: { "s1" => { "model" => "model_ab12" } },
      reachability: stub_reachability, producer_outputs: {}
    )
    expect(out).to eq("ctx[:model_ab12] = 1")
  end

  it "leaves writes untouched when no rename applies" do
    body = "ctx[:ok] = 1"
    out = described_class.call(
      body: body, step_id: "s1", io_bindings: [],
      rename_map: {}, reachability: stub_reachability, producer_outputs: {}
    )
    expect(out).to eq("ctx[:ok] = 1")
  end

  it "rewrites reads to bound producer's renamed key" do
    body = "x = ctx[:model]"
    bindings = [{ "pin" => "model", "producer_step_id" => "prod1", "producer_pin" => "model" }]
    out = described_class.call(
      body: body, step_id: "s1", io_bindings: bindings,
      rename_map: { "prod1" => { "model" => "model_cd34" } },
      reachability: stub_reachability, producer_outputs: { "prod1" => ["model"] }
    )
    expect(out).to eq("x = ctx[:model_cd34]")
  end

  it "falls back to nearest producer when binding is null" do
    body = "x = ctx[:model]"
    out = described_class.call(
      body: body, step_id: "r1",
      io_bindings: [{ "pin" => "model", "producer_step_id" => nil }],
      rename_map: { "prod1" => { "model" => "model_ef56" } },
      reachability: stub_reachability("r1" => { "model" => "prod1" }),
      producer_outputs: { "prod1" => ["model"] }
    )
    expect(out).to eq("x = ctx[:model_ef56]")
  end

  it "rewrites op-assigns on both sides consistently" do
    body = "ctx[:count] ||= 0"
    out = described_class.call(
      body: body, step_id: "s1", io_bindings: [],
      rename_map: { "s1" => { "count" => "count_1111" } },
      reachability: stub_reachability, producer_outputs: {}
    )
    expect(out).to eq("ctx[:count_1111] ||= 0")
  end

  it "leaves dynamic access untouched" do
    body = "ctx[config['k'].to_sym] = 1"
    out = described_class.call(
      body: body, step_id: "s1", io_bindings: [],
      rename_map: { "s1" => { "count" => "count_1111" } },
      reachability: stub_reachability, producer_outputs: {}
    )
    expect(out).to eq("ctx[config['k'].to_sym] = 1")
  end

  it "preserves ctx inside comments" do
    body = "# ctx[:notreal]\nctx[:real] = 1"
    out = described_class.call(
      body: body, step_id: "s1", io_bindings: [],
      rename_map: { "s1" => { "real" => "real_2222" } },
      reachability: stub_reachability, producer_outputs: {}
    )
    expect(out).to eq("# ctx[:notreal]\nctx[:real_2222] = 1")
  end

  it "rewrites multiple non-adjacent occurrences in one body" do
    body = "x = ctx[:a]\nctx[:b] = x\ny = ctx[:a]"
    out = described_class.call(
      body: body, step_id: "s1",
      io_bindings: [{ "pin" => "a", "producer_step_id" => "p1", "producer_pin" => "a" }],
      rename_map: { "p1" => { "a" => "a_xxxx" }, "s1" => { "b" => "b_yyyy" } },
      reachability: stub_reachability, producer_outputs: { "p1" => ["a"] }
    )
    expect(out).to eq("x = ctx[:a_xxxx]\nctx[:b_yyyy] = x\ny = ctx[:a_xxxx]")
  end
end
```

- [ ] **Step 2: Run, confirm failure**

```
bundle exec rspec spec/services/code_generators/emission_rewriter_spec.rb
```

- [ ] **Step 3: Implement EmissionRewriter**

```ruby
# app/services/code_generators/emission_rewriter.rb
# frozen_string_literal: true

require_relative "io_extractor/body_analyzer"

module CodeGenerators
  # EmissionRewriter
  #
  # Rewrites `ctx[:x]` read and write occurrences in a step body string
  # based on a rename map (for writes) and io_bindings + reachability
  # (for reads). Source-position splice rather than AST regeneration so
  # non-ctx source is preserved character-for-character.
  class EmissionRewriter
    def self.call(body:, step_id:, io_bindings:, rename_map:, reachability:, producer_outputs:)
      new(body, step_id, io_bindings, rename_map, reachability, producer_outputs).call
    end

    def initialize(body, step_id, io_bindings, rename_map, reachability, producer_outputs)
      @body = body
      @step_id = step_id
      @bindings = io_bindings || []
      @rename_map = rename_map || {}
      @reachability = reachability
      @producer_outputs = producer_outputs || {}
    end

    def call
      return @body if @body.nil? || @body.empty?

      ast = IoExtractor::BodyAnalyzer.call(@body)
      edits = []
      ast[:writes].each { |w| edits << { start: w[:start], length: w[:length], replacement: rewrite_write(w[:pin]) } }
      ast[:reads].each  { |r| edits << { start: r[:start], length: r[:length], replacement: rewrite_read(r[:pin]) } }
      apply_edits(edits)
    end

    private

    def rewrite_write(pin)
      renamed = @rename_map.dig(@step_id, pin)
      "ctx[:#{renamed || pin}]"
    end

    def rewrite_read(pin)
      binding_entry = @bindings.find { |b| b["pin"] == pin }
      producer_id = binding_entry && binding_entry["producer_step_id"]
      producer_pin = (binding_entry && binding_entry["producer_pin"]) || pin

      if producer_id.nil?
        producer_id = @reachability.nearest_predecessor(
          @step_id, producing: pin, producer_outputs: @producer_outputs
        )
      end

      key = (producer_id && @rename_map.dig(producer_id, producer_pin)) || pin
      "ctx[:#{key}]"
    end

    def apply_edits(edits)
      # Dedupe by start position (reads + writes for op-assigns point to the
      # same span; one rewrite is sufficient because both produce identical
      # output — write uses own rename map, read uses same pin to same rename).
      # When write and read differ, prefer write (safer: it's the definitive
      # decision for that position).
      by_start = {}
      edits.each do |e|
        existing = by_start[e[:start]]
        by_start[e[:start]] = e if existing.nil?
      end
      sorted = by_start.values.sort_by { |e| -e[:start] }
      result = @body.dup
      sorted.each { |e| result[e[:start], e[:length]] = e[:replacement] }
      result
    end
  end
end
```

- [ ] **Step 4: Run, confirm pass**

```
bundle exec rspec spec/services/code_generators/emission_rewriter_spec.rb
```

- [ ] **Step 5: Commit**

```
git add app/services/code_generators/emission_rewriter.rb \
        spec/services/code_generators/emission_rewriter_spec.rb
git commit -m "feat(codegen): add EmissionRewriter for ctx read/write splicing"
```

---

## Task 6: Integrate EmissionRewriter into ActivityGenerator

**Files:**
- Modify: `app/services/activity_generator.rb` (around lines 30-45 and 689-710)
- Test: `spec/services/activity_generator_spec.rb` (add new `describe` block)

- [ ] **Step 1: Read the integration points to confirm the edit shape**

```
bundle exec ruby -e 'puts File.readlines("app/services/activity_generator.rb")[30..45]'
bundle exec ruby -e 'puts File.readlines("app/services/activity_generator.rb")[685..715]'
```

- [ ] **Step 2: Add an integration spec exercising rename + rewrite through the full generator**

Append to `spec/services/activity_generator_spec.rb` (or create the file if it doesn't exist; check first):

```ruby
describe "ctx conflict rewriting" do
  let(:flowchart) do
    instance_double(
      "Flowchart",
      id: 1,
      name: "demo",
      entity: nil,
      elements: [
        { "id" => "start1", "type" => "start", "properties" => {} },
        { "id" => "p1", "type" => "process", "properties" => { "steps" => [
          { "id" => "s_w1", "action" => "w_a", "config" => {}, "io_bindings" => [] },
          { "id" => "s_w2", "action" => "w_b", "config" => {}, "io_bindings" => [] },
          { "id" => "s_r",  "action" => "r",   "config" => {}, "io_bindings" => [
            { "pin" => "model", "producer_step_id" => "s_w1", "producer_pin" => "model" }
          ] }
        ] } },
        { "id" => "end1", "type" => "end", "properties" => {} }
      ],
      connections: [
        { "from" => "start1", "to" => "p1" },
        { "from" => "p1",     "to" => "end1" }
      ]
    )
  end

  before do
    registry = CodeGenerators::GeneratorRegistry.instance
    writer_a = Class.new { def initialize(_e,_c); end; def generate_body; "ctx[:model] = 1"; end
                           def derive_step_name; "s_w1"; end
                           def self.generator_name; "w_a"; end }
    writer_b = Class.new { def initialize(_e,_c); end; def generate_body; "ctx[:model] = 2"; end
                           def derive_step_name; "s_w2"; end
                           def self.generator_name; "w_b"; end }
    reader   = Class.new { def initialize(_e,_c); end; def generate_body; "x = ctx[:model]"; end
                           def derive_step_name; "s_r"; end
                           def self.generator_name; "r"; end }
    allow(registry).to receive(:find_step_action).and_call_original
    allow(registry).to receive(:find_step_action).with("w_a").and_return(writer_a)
    allow(registry).to receive(:find_step_action).with("w_b").and_return(writer_b)
    allow(registry).to receive(:find_step_action).with("r").and_return(reader)
    # apply_wrappers is a private on BaseGenerator; stub to pass-through
    [writer_a, writer_b, reader].each do |klass|
      klass.send(:define_method, :apply_wrappers) { |code| code }
    end
  end

  it "renames colliding writes and binds reader to the chosen producer's renamed key" do
    code = ActivityGenerator.new(flowchart).generate
    expect(code).to match(/ctx\[:model_[0-9a-f]{4}\] = 1/)
    expect(code).to match(/ctx\[:model_[0-9a-f]{4}\] = 2/)
    # Reader bound to s_w1 -> must reference s_w1's rename
    w1_match = code.match(/ctx\[:(model_[0-9a-f]{4})\] = 1/)
    expect(code).to include("ctx[:#{w1_match[1]}]") if w1_match  # reader uses w1's renamed key
  end
end
```

- [ ] **Step 3: Run the new integration spec and confirm failure**

```
bundle exec rspec spec/services/activity_generator_spec.rb -e "ctx conflict rewriting"
```
Expected: FAIL — current ActivityGenerator emits plain `ctx[:model]` in both writers.

- [ ] **Step 4: Modify `ActivityGenerator#generate` to compute conflict result once**

Open `app/services/activity_generator.rb`, change the body of `generate` (around line 32) to:

```ruby
def generate
  return nil if flowchart.name.blank? || elements.empty?

  validation_errors = validate_structure
  if validation_errors.any?
    log_warn "Flowchart validation failed for #{flowchart.id}: #{validation_errors.join(', ')}"
    return nil
  end

  @conflict_result = CodeGenerators::ConflictResolver.call(flowchart)
  steps = dfs_collect_steps
  class_def = class_definition_with_steps(steps)
  [header(steps), class_def].compact.join("\n")
end
```

- [ ] **Step 5: Modify `generate_step_code` to run EmissionRewriter on the body**

Replace the body of `generate_step_code` (line 689-710) with:

```ruby
def generate_step_code(step, ctx)
  action = step["action"]
  return nil if action.blank?

  generator_class = @registry.find_step_action(action) || @registry.find_step_action(action.downcase)
  unless generator_class
    Rails.logger.warn("[ActivityGenerator] Unknown step action '#{action}'; emitting TODO marker") if defined?(Rails)
    return "# TODO: unknown step action '#{action}'"
  end

  generator = generator_class.new(step, ctx)
  code = generator.generate_body
  return nil unless code

  rewritten = CodeGenerators::EmissionRewriter.call(
    body: code,
    step_id: step["id"],
    io_bindings: step["io_bindings"] || [],
    rename_map: @conflict_result&.rename_map || {},
    reachability: @conflict_result&.reachability,
    producer_outputs: @conflict_result&.producer_outputs || {}
  )

  generator.send(:apply_wrappers, rewritten)
end
```

- [ ] **Step 6: Run the integration spec, confirm pass**

```
bundle exec rspec spec/services/activity_generator_spec.rb -e "ctx conflict rewriting"
```

- [ ] **Step 7: Run the full activity_generator_spec to catch regressions**

```
bundle exec rspec spec/services/activity_generator_spec.rb
```
Expected: all pre-existing examples still pass.

- [ ] **Step 8: Commit**

```
git add app/services/activity_generator.rb spec/services/activity_generator_spec.rb
git commit -m "feat(codegen): splice EmissionRewriter through ActivityGenerator"
```

---

## Task 7: IoParamsController — JSON endpoint for extraction

**Files:**
- Create: `app/controllers/code_generators/io_params_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/controllers/code_generators/io_params_controller_spec.rb`

- [ ] **Step 1: Write failing controller spec**

```ruby
# spec/controllers/code_generators/io_params_controller_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::IoParamsController, type: :controller do
  describe "POST #show" do
    it "returns inputs and outputs for a known action" do
      post :show, params: {
        action_name: "api_call",
        config: { httpMethod: "GET", url: '"https://example.com"', resultVar: "resp", responseFormat: "json" }
      }, as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["outputs"].map { |o| o["pin"] }).to include("resp")
      expect(json["inputs"]).to be_an(Array)
    end

    it "returns empty pins with 200 for unknown action" do
      post :show, params: { action_name: "definitely_not_a_real_action", config: {} }, as: :json
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq("inputs" => [], "outputs" => [])
    end

    it "returns empty pins with 200 for malformed config" do
      post :show, params: { action_name: "api_call", config: "not-a-hash" }, as: :json
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["inputs"]).to eq([])
      expect(json["outputs"]).to eq([])
    end
  end
end
```

- [ ] **Step 2: Add route**

Edit `config/routes.rb`, add after the admin `namespace :admin do ... end` block (before the catch-all):

```ruby
namespace :code_generators do
  post ":action_name/io_params", to: "io_params#show", constraints: { action_name: /[A-Za-z0-9_]+/ }
end
```

- [ ] **Step 3: Implement controller**

```ruby
# app/controllers/code_generators/io_params_controller.rb
# frozen_string_literal: true

module CodeGenerators
  class IoParamsController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :set_current_customer, raise: false
    skip_before_action :authenticate_user!, raise: false

    def show
      config = params[:config].is_a?(ActionController::Parameters) ? params[:config].to_unsafe_h : {}
      pins = CodeGenerators::IoExtractor.call(action: params[:action_name].to_s, config: config.stringify_keys)
      render json: {
        inputs: pins[:inputs],
        outputs: pins[:outputs]
      }
    end
  end
end
```

- [ ] **Step 4: Run the controller spec, confirm pass**

```
bundle exec rspec spec/controllers/code_generators/io_params_controller_spec.rb
```

- [ ] **Step 5: Smoke-test the route via curl**

Expected the Rails dev server is running; if not:
```
RAILS_ENV=development bin/rails server -b 0.0.0.0 -p 3000 > /tmp/rails_server.log 2>&1 &
sleep 5
```
Then:
```
curl -s -X POST http://localhost:3000/code_generators/api_call/io_params \
  -H 'Content-Type: application/json' \
  -d '{"config":{"httpMethod":"GET","url":"\"https://example.com\"","resultVar":"resp","responseFormat":"json"}}'
```
Expected: `{"inputs":[...],"outputs":[{"pin":"resp","ctx_key":"resp"}]}` (200 OK).

- [ ] **Step 6: Commit**

```
git add app/controllers/code_generators/io_params_controller.rb \
        spec/controllers/code_generators/io_params_controller_spec.rb \
        config/routes.rb
git commit -m "feat(codegen): add /code_generators/:action_name/io_params endpoint"
```

---

## Task 8: canvas.stepPins — cache + bulk prime on canvas ready

**Files:**
- Modify: `app/javascript/flowchart/canvas.js`
- Create: `app/javascript/controllers/property_editor/step_io/io_params_client.js`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js`

- [ ] **Step 1: Add the `stepPins` field and helpers on FlowchartCanvas**

In `app/javascript/flowchart/canvas.js`, inside the constructor (after `this.elementSchemas = ELEMENT_SCHEMAS` on line 41), add:

```javascript
    // I/O pin cache: step_id -> { inputs: [...], outputs: [...] }
    this.stepPins = {}
```

Then add two methods to the `FlowchartCanvas` class (near the bottom of the class body, before the closing `}` at ~line 1870):

```javascript
  setStepPins(stepId, pins) {
    this.stepPins = { ...this.stepPins, [stepId]: pins }
  }

  getStepPins(stepId) {
    return this.stepPins[stepId] || { inputs: [], outputs: [] }
  }

  iterateStepActions(callback) {
    for (const el of this.elements) {
      const steps = el?.properties?.steps || []
      for (const step of steps) {
        callback(step, el)
      }
    }
  }
```

- [ ] **Step 2: Create `io_params_client.js` — minimal fetch wrapper**

```javascript
// app/javascript/controllers/property_editor/step_io/io_params_client.js

/**
 * Fetch extracted pins for a single step action + config.
 * Always resolves with { inputs: [...], outputs: [...] }; network / server
 * errors are swallowed and logged (the step modal must still open cleanly).
 */
export async function fetchStepPins(action, config) {
  if (!action) return { inputs: [], outputs: [] }

  try {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""
    const response = await fetch(`/code_generators/${encodeURIComponent(action)}/io_params`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({ config: config || {} })
    })
    if (!response.ok) return { inputs: [], outputs: [] }
    return await response.json()
  } catch (e) {
    console.warn("[step_io] io_params fetch failed:", e)
    return { inputs: [], outputs: [] }
  }
}

/** Bulk prime: fetch pins for every step action on the canvas. */
export async function primeAllStepPins(canvas) {
  const jobs = []
  canvas.iterateStepActions((step) => {
    jobs.push(
      fetchStepPins(step.action, step.config || {}).then((pins) => canvas.setStepPins(step.id, pins))
    )
  })
  await Promise.all(jobs)
}
```

- [ ] **Step 3: Prime on canvas ready**

In `app/javascript/controllers/flowchart_canvas_controller.js`, find `_onCanvasReady` (search for the string). If it's called after `_initializeCanvas`, add a call to prime pins from the new helper. Open the file, locate `_initializeCanvas` (around line 102 today), and at the end of the method, add:

```javascript
    // Prime the step I/O pin cache for all existing steps so the step modal
    // can render the I/O tab without waiting for a per-open fetch.
    import("controllers/property_editor/step_io/io_params_client").then(({ primeAllStepPins }) => {
      primeAllStepPins(this.canvas).catch(() => {})
    })
```

- [ ] **Step 4: Manual browser check**

Load any flowchart containing at least one process with one step action. Open DevTools network tab → you should see one POST per step action to `/code_generators/:action/io_params`. In the console:

```
document.querySelector("[data-controller~=flowchart-canvas]").__controller // or wherever canvas is held
// verify canvas.stepPins has entries keyed by step id
```

- [ ] **Step 5: Commit**

```
git add app/javascript/flowchart/canvas.js \
        app/javascript/controllers/property_editor/step_io/io_params_client.js \
        app/javascript/controllers/flowchart_canvas_controller.js
git commit -m "feat(step-io): add canvas stepPins cache and prime on canvas ready"
```

---

## Task 9: JS reachability — predecessor sets, isolateCtx-aware

**Files:**
- Create: `app/javascript/controllers/property_editor/step_io/reachability.js`

- [ ] **Step 1: Implement reachability module**

This is a direct JS port of `ReachabilityIndex` from Task 3. Same semantics.

```javascript
// app/javascript/controllers/property_editor/step_io/reachability.js

export class Reachability {
  constructor(canvas) {
    this.elements = canvas.elements || []
    this.connections = canvas.connections || []
    this.predecessors = new Map()   // stepId -> Set(stepId)
    this.universeOf = new Map()     // stepId -> :root | processId
    this._build()
  }

  reachablePredecessors(stepId) {
    return this.predecessors.get(stepId) || new Set()
  }

  sameUniverse(a, b) {
    const ua = this.universeOf.get(a)
    const ub = this.universeOf.get(b)
    return ua && ub && ua === ub
  }

  /** Walk predecessors in reverse-topological order, first hit wins. */
  nearestPredecessor(stepId, pinName, producerOutputs) {
    const preds = [...(this.predecessors.get(stepId) || [])]
    // Sort by predecessor-set size so "earliest" steps come first; reverse for nearest-first
    preds.sort((a, b) => (this.predecessors.get(a)?.size || 0) - (this.predecessors.get(b)?.size || 0))
    for (let i = preds.length - 1; i >= 0; i--) {
      const outs = producerOutputs[preds[i]] || []
      if (outs.includes(pinName)) return preds[i]
    }
    return null
  }

  _build() {
    this._assignUniverses()
    this._computePredecessors()
  }

  _universeForElement(el) {
    if (el.type !== "process") return "__root__"
    const iso = String(el.properties?.isolateCtx || "") === "true"
    return iso ? el.id : "__root__"
  }

  _assignUniverses() {
    for (const el of this.elements) {
      const u = this._universeForElement(el)
      const steps = el.properties?.steps || []
      for (const s of steps) this.universeOf.set(s.id, u)
    }
  }

  _elementTopoOrder() {
    const inDeg = new Map()
    for (const el of this.elements) inDeg.set(el.id, 0)
    for (const c of this.connections) if (inDeg.has(c.to)) inDeg.set(c.to, inDeg.get(c.to) + 1)
    const queue = []
    for (const [id, d] of inDeg) if (d === 0) queue.push(id)
    const order = []
    while (queue.length) {
      const id = queue.shift()
      order.push(id)
      for (const c of this.connections) {
        if (c.from !== id || !inDeg.has(c.to)) continue
        inDeg.set(c.to, inDeg.get(c.to) - 1)
        if (inDeg.get(c.to) === 0) queue.push(c.to)
      }
    }
    for (const el of this.elements) if (!order.includes(el.id)) order.push(el.id)
    return order
  }

  _computePredecessors() {
    const elementLastSteps = new Map()
    const elementSteps = new Map()
    for (const el of this.elements) {
      elementSteps.set(el.id, (el.properties?.steps || []).map((s) => s.id))
    }

    const order = this._elementTopoOrder()
    for (const elId of order) {
      const feeders = this.connections.filter((c) => c.to === elId).map((c) => c.from)
      const entry = new Set()
      for (const f of feeders) {
        for (const s of elementLastSteps.get(f) || []) entry.add(s)
      }
      const steps = elementSteps.get(elId) || []
      const running = new Set(entry)
      for (const sid of steps) {
        const preds = new Set()
        for (const p of running) {
          if (this.universeOf.get(p) === this.universeOf.get(sid)) preds.add(p)
        }
        this.predecessors.set(sid, preds)
        running.add(sid)
      }
      elementLastSteps.set(elId, steps.length ? [steps[steps.length - 1]] : [...entry])
    }
  }
}
```

- [ ] **Step 2: Browser smoke check**

Load a flowchart with two processes connected, one of which has two steps. In the console:

```javascript
import("controllers/property_editor/step_io/reachability").then(({ Reachability }) => {
  const r = new Reachability(window.canvas) // adjust accessor
  console.log("preds of step_2:", [...r.reachablePredecessors("step_2")])
})
```
Expected: preds includes the preceding step id.

- [ ] **Step 3: Commit**

```
git add app/javascript/controllers/property_editor/step_io/reachability.js
git commit -m "feat(step-io): JS port of ReachabilityIndex for the step modal"
```

---

## Task 10: JS conflict detector — mirrors server resolver

**Files:**
- Create: `app/javascript/controllers/property_editor/step_io/conflict_detector.js`

- [ ] **Step 1: Implement**

```javascript
// app/javascript/controllers/property_editor/step_io/conflict_detector.js

import { Reachability } from "controllers/property_editor/step_io/reachability"

/**
 * Compute a rename map matching the server ConflictResolver.
 * Input: canvas (with stepPins already primed), returns { renameMap, reachability }.
 * Uses SHA1(step_id:pin) first 4 hex chars via SubtleCrypto, falls back to 6 on
 * within-map collision.
 */
export async function computeConflicts(canvas) {
  const reachability = new Reachability(canvas)

  const producerOutputs = {}    // stepId -> [pin]
  const readerInputs = {}       // stepId -> [pin]
  canvas.iterateStepActions((step) => {
    const pins = canvas.getStepPins(step.id)
    producerOutputs[step.id] = pins.outputs.map((o) => o.pin)
    readerInputs[step.id]    = pins.inputs.map((i) => i.pin)
  })

  const byPin = {}
  for (const [sid, pins] of Object.entries(producerOutputs)) {
    for (const pin of pins) {
      byPin[pin] = byPin[pin] || []
      byPin[pin].push(sid)
    }
  }

  const renameMap = {}
  for (const [pin, producers] of Object.entries(byPin)) {
    if (producers.length < 2) continue
    const readers = Object.entries(readerInputs).filter(([_rid, pins]) => pins.includes(pin)).map(([rid]) => rid)
    const triggers = readers.some((rid) => {
      const preds = reachability.reachablePredecessors(rid)
      const inScope = producers.filter((p) => preds.has(p) && reachability.sameUniverse(rid, p))
      return inScope.length >= 2
    })
    if (!triggers) continue

    for (const pid of producers) {
      const suffix4 = await shortHash(`${pid}:${pin}`, 4)
      let suffix = suffix4
      const assigned = new Set(Object.values(renameMap).flatMap((m) => Object.values(m)))
      if (assigned.has(`${pin}_${suffix4}`)) suffix = await shortHash(`${pid}:${pin}`, 6)
      renameMap[pid] = renameMap[pid] || {}
      renameMap[pid][pin] = `${pin}_${suffix}`
    }
  }

  return { renameMap, reachability, producerOutputs, readerInputs }
}

async function shortHash(input, length) {
  const data = new TextEncoder().encode(input)
  const digest = await crypto.subtle.digest("SHA-1", data)
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("")
  return hex.slice(0, length)
}
```

- [ ] **Step 2: Browser smoke check**

Load a flowchart with two step actions that both write `ctx[:model]` and a third that reads it. In console:

```javascript
import("controllers/property_editor/step_io/conflict_detector").then(({ computeConflicts }) => {
  computeConflicts(window.canvas).then(({ renameMap }) => console.log(renameMap))
})
```
Expected: rename map entries for both producer step ids, each mapping `model` to `model_xxxx` matching the server's Ruby output for the same flowchart.

- [ ] **Step 3: Commit**

```
git add app/javascript/controllers/property_editor/step_io/conflict_detector.js
git commit -m "feat(step-io): JS ConflictDetector mirroring server resolver"
```

---

## Task 11: StepIoManager — wire step modal I/O tab

**Files:**
- Create: `app/javascript/controllers/property_editor/step_io_manager.js`
- Modify: `app/javascript/controllers/property_editor_controller.js`
- Modify: `app/javascript/controllers/property_editor/step_manager.js`

- [ ] **Step 1: Read the existing step modal template**

```
Glob "app/views/**/_step_modal*.html.erb"
Glob "app/components/**/step_modal*"
```

Open the step modal template file and locate the I/O tab pane (`[data-tab-pane-io]` or similar). If there's no existing tab pane inside the step modal (only a single-pane step modal today), add one by reading `app/javascript/controllers/property_editor/step_manager.js` — specifically the method that opens the modal — and finding where tabs are rendered.

- [ ] **Step 2: Create StepIoManager**

```javascript
// app/javascript/controllers/property_editor/step_io_manager.js

import { escapeHtml } from "utils"
import { fetchStepPins } from "controllers/property_editor/step_io/io_params_client"
import { computeConflicts } from "controllers/property_editor/step_io/conflict_detector"

export class StepIoManager {
  constructor(controller) {
    this.controller = controller
    this.debounceTimer = null
    this._currentStep = null
    this._currentPanel = null
  }

  /** Called when the step modal opens for a given step. */
  async openForStep(step, panelElement) {
    this._currentStep = step
    this._currentPanel = panelElement
    await this._refresh()
  }

  /** Called on any config field change inside the step modal. */
  onStepConfigChanged(step) {
    if (!this._currentStep || this._currentStep.id !== step.id) return
    this._currentStep = step
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this._refresh(), 300)
  }

  async _refresh() {
    if (!this._currentStep || !this._currentPanel) return
    const pins = await fetchStepPins(this._currentStep.action, this._currentStep.config || {})
    this.controller.canvas.setStepPins(this._currentStep.id, pins)

    const { renameMap } = await computeConflicts(this.controller.canvas)
    this._currentPanel.innerHTML = this._render(pins, renameMap)
    this._bindEventListeners()
  }

  _render(pins, renameMap) {
    const stepId = this._currentStep.id
    const currentBindings = this._currentStep.io_bindings || []

    const inputsHTML = pins.inputs.length
      ? pins.inputs.map((pin) => this._renderInputRow(pin, currentBindings)).join("")
      : `<div class="text-xs text-slate-400 italic py-2">This step reads no ctx values</div>`

    const outputsHTML = pins.outputs.length
      ? pins.outputs.map((pin) => this._renderOutputRow(pin, renameMap[stepId] || {})).join("")
      : `<div class="text-xs text-slate-400 italic py-2">This step writes no ctx values</div>`

    return `
      <section class="space-y-3">
        <div>
          <h4 class="text-xs font-semibold text-slate-700 mb-1.5">Inputs</h4>
          <div class="space-y-1">${inputsHTML}</div>
        </div>
        <div>
          <h4 class="text-xs font-semibold text-slate-700 mb-1.5">Outputs</h4>
          <div class="space-y-1">${outputsHTML}</div>
        </div>
      </section>
    `
  }

  _renderInputRow(pin, currentBindings) {
    const producers = this._producersFor(pin.pin)
    const binding = currentBindings.find((b) => b.pin === pin.pin) || { pin: pin.pin, producer_step_id: null }
    const ambiguous = producers.length >= 2 && !binding.producer_step_id

    const options = [
      `<option value="">— nearest upstream —</option>`,
      ...producers.map((p) => {
        const selected = binding.producer_step_id === p.step.id ? " selected" : ""
        return `<option value="${escapeHtml(p.step.id)}"${selected}>${escapeHtml(p.step.label || p.step.id)} • pin: ${escapeHtml(p.pin)}</option>`
      })
    ].join("")

    const warnClass = ambiguous ? " ring-2 ring-red-500" : ""
    const warnTip = ambiguous ? ` title="Multiple producers exist. Pick one."` : ""

    return `
      <div class="flex items-center gap-2 text-xs" data-step-io-input-row data-pin="${escapeHtml(pin.pin)}">
        <span class="w-32 truncate">${escapeHtml(pin.pin)}</span>
        <select class="flex-1 px-2 py-1 border border-slate-200 rounded-md${warnClass}" data-step-io-producer${warnTip}>
          ${options}
        </select>
        <span class="text-[10px] text-slate-400">(${escapeHtml(pin.source)})</span>
      </div>
    `
  }

  _renderOutputRow(pin, renameEntry) {
    const renamed = renameEntry[pin.pin]
    const badge = renamed
      ? `<span class="text-[10px] text-amber-600 ml-2">⚠ renamed → ${escapeHtml(renamed)}</span>`
      : ""
    return `
      <div class="flex items-center gap-2 text-xs" data-step-io-output-row data-pin="${escapeHtml(pin.pin)}">
        <span class="w-32 truncate">${escapeHtml(pin.pin)}</span>
        ${badge}
      </div>
    `
  }

  _producersFor(pinName) {
    const reader = this._currentStep
    const result = []
    this.controller.canvas.iterateStepActions((step) => {
      if (step.id === reader.id) return
      const outs = this.controller.canvas.getStepPins(step.id).outputs || []
      outs.forEach((o) => {
        if (o.pin === pinName) result.push({ step, pin: o.pin })
      })
    })
    return result
  }

  _bindEventListeners() {
    const selects = this._currentPanel.querySelectorAll("[data-step-io-producer]")
    selects.forEach((sel) => {
      sel.addEventListener("change", (e) => {
        const row = e.target.closest("[data-step-io-input-row]")
        const pin = row.dataset.pin
        const producer_step_id = e.target.value || null
        this._updateBinding(pin, producer_step_id)
      })
    })
  }

  _updateBinding(pin, producer_step_id) {
    const step = this._currentStep
    step.io_bindings = step.io_bindings || []
    const existing = step.io_bindings.find((b) => b.pin === pin)
    if (existing) {
      existing.producer_step_id = producer_step_id
    } else {
      step.io_bindings.push({ pin, producer_step_id, producer_pin: pin })
    }
    // Re-render to update ambiguity highlight.
    this._refresh()
  }
}

export default StepIoManager
```

- [ ] **Step 3: Instantiate StepIoManager in property_editor_controller**

In `app/javascript/controllers/property_editor_controller.js`, find the `connect()` or initialization area (search for `ioManager`) and add:

```javascript
import { StepIoManager } from "controllers/property_editor/step_io_manager"

// In the manager-init block where ioManager is set up:
this.stepIoManager = new StepIoManager(this)
```

- [ ] **Step 4: Hook into step_manager step-modal open + config-change**

Open `app/javascript/controllers/property_editor/step_manager.js`. Locate the method that opens the step modal (search for `openStepModal`, `showStepModal`, or the place `data-step-modal` is populated). At the end of the open flow, add:

```javascript
const ioPanel = this.controller.stepModalContainerTarget.querySelector("[data-step-modal-io-pane]")
if (ioPanel) {
  this.controller.stepIoManager.openForStep(step, ioPanel)
}
```

Locate the step config-change handler (look for `data-step-modal-*` listeners) and at the end, add:

```javascript
this.controller.stepIoManager.onStepConfigChanged(step)
```

If the step modal template does not yet have an I/O tab panel, add one: inside the step modal (search `data-step-modal` in `.erb`/template files), add the tab header and pane:

```erb
<button type="button" data-action="click->property-editor#switchStepModalTab" data-tab="io"
        class="px-2 py-1 text-xs ...">I/O</button>
<div data-step-modal-io-pane class="hidden p-2"></div>
```

If the step modal already has tabs, just add the I/O button + pane following the existing pattern. Read the template first; do not guess.

- [ ] **Step 5: Manual browser test**

Open a flowchart, double-click a process element, double-click a step → step modal opens. The I/O tab must show inputs and outputs populated from the generator. Change a config field → after ~300ms the I/O tab refreshes. Verify the panel renders without console errors.

- [ ] **Step 6: Commit**

```
git add app/javascript/controllers/property_editor/step_io_manager.js \
        app/javascript/controllers/property_editor_controller.js \
        app/javascript/controllers/property_editor/step_manager.js \
        app/views/**/_step_modal*.html.erb
git commit -m "feat(step-io): populate step modal I/O tab with extracted pins and producer bindings"
```

---

## Task 12: Block save when unresolved bindings exist

**Files:**
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` (or wherever save is dispatched)
- Modify: `app/javascript/controllers/property_editor/step_io_manager.js` (add `unresolvedBindings(canvas)` export)

- [ ] **Step 1: Add `unresolvedBindings` helper**

Add to `app/javascript/controllers/property_editor/step_io/conflict_detector.js`:

```javascript
/**
 * Returns an array of { step, pin, producers } for every reader whose
 * pin has ≥2 reachable producers in the same universe but no explicit
 * producer_step_id binding.
 */
export async function unresolvedBindings(canvas) {
  const { reachability, producerOutputs } = await computeConflicts(canvas)
  const unresolved = []
  canvas.iterateStepActions((step) => {
    const pins = canvas.getStepPins(step.id).inputs || []
    for (const pin of pins) {
      const bindings = step.io_bindings || []
      const entry = bindings.find((b) => b.pin === pin.pin)
      const hasExplicit = entry && entry.producer_step_id
      if (hasExplicit) continue

      const preds = reachability.reachablePredecessors(step.id)
      const producers = [...preds].filter((p) =>
        (producerOutputs[p] || []).includes(pin.pin) && reachability.sameUniverse(step.id, p)
      )
      if (producers.length >= 2) {
        unresolved.push({ step, pin: pin.pin, producers })
      }
    }
  })
  return unresolved
}
```

- [ ] **Step 2: Call before save**

In `app/javascript/controllers/flowchart_canvas_controller.js`, locate the save handler (search `save(` or the method dispatched by the save button; this controller's constructor shows `_beforeUnload` handling, the save method is likely near there). Before dispatching the save request, add:

```javascript
const { unresolvedBindings } = await import("controllers/property_editor/step_io/conflict_detector")
const unresolved = await unresolvedBindings(this.canvas)
if (unresolved.length > 0) {
  const names = unresolved.map((u) => `${u.step.label || u.step.id}:${u.pin}`).join(", ")
  alert(`Cannot save: resolve producer bindings for these inputs: ${names}`)
  return
}
```

(If there is a project-native toast helper — there was a reference to `onToast` in canvas.js — prefer it over `alert`.)

- [ ] **Step 3: Manual browser test**

Build a flowchart with two producer steps writing `ctx[:model]` and one reader reading `ctx[:model]`. Do NOT pick a producer in the reader's I/O tab. Click Save → expect block with a message listing the unresolved pin.

- [ ] **Step 4: Commit**

```
git add app/javascript/controllers/property_editor/step_io/conflict_detector.js \
        app/javascript/controllers/flowchart_canvas_controller.js
git commit -m "feat(step-io): block save when input bindings are ambiguous"
```

---

## Task 13: System spec for the step modal I/O tab

**Files:**
- Create: `spec/system/property_editor/step_io_tab_spec.rb`

- [ ] **Step 1: Write the system spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Step modal I/O tab", type: :system, js: true do
  let(:customer) { Customer.create!(id: 12345678, name: "Acme") }

  before do
    driven_by(:selenium_chrome_headless)
    # Stub auth here if required; follow existing system-spec conventions.
  end

  it "populates inputs/outputs from the generator when a step modal opens" do
    flowchart = Flowchart.create!(
      customer: customer, name: "I/O demo",
      elements: [
        { "id" => "start1", "type" => "start", "properties" => {} },
        { "id" => "p1", "type" => "process", "properties" => { "steps" => [
          { "id" => "s1", "action" => "api_call",
            "config" => { "httpMethod" => "GET", "url" => '"https://example.com"', "resultVar" => "resp" },
            "io_bindings" => [] }
        ] } },
        { "id" => "end1", "type" => "end", "properties" => {} }
      ],
      connections: [{ "from" => "start1", "to" => "p1" }, { "from" => "p1", "to" => "end1" }]
    )

    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"
    # Open process, open step, switch to I/O tab — concrete selectors depend on
    # the project's existing system specs; match their patterns.
    find("[data-element-id='p1']").double_click
    find("[data-step-id='s1']").double_click
    click_on "I/O"
    expect(page).to have_text("resp")
  end
end
```

NOTE: this spec depends on existing system-spec setup (auth, driver, element selectors). If the project has no js-enabled system specs yet, skip this task and rely on Tasks 1-12 + manual browser verification. Mark the step with `skip` rather than writing a broken spec.

- [ ] **Step 2: Run**

```
bundle exec rspec spec/system/property_editor/step_io_tab_spec.rb
```

- [ ] **Step 3: Commit**

```
git add spec/system/property_editor/step_io_tab_spec.rb
git commit -m "test(step-io): system spec for step modal I/O tab population"
```

---

## Task 14: Full regression pass

- [ ] **Step 1: Run the full generator suite**

```
bundle exec rspec spec/services/code_generators/
```
Expected: pre-existing ~4300 examples still pass plus the new specs from Tasks 1-5.

- [ ] **Step 2: Run activity_generator spec**

```
bundle exec rspec spec/services/activity_generator_spec.rb
```

- [ ] **Step 3: Run controller spec**

```
bundle exec rspec spec/controllers/code_generators/io_params_controller_spec.rb
```

- [ ] **Step 4: Manual smoke in browser**

Load a flowchart with `ctx[:model]` collision (two writer steps, one reader in a third process). Verify:
- Reader's I/O tab shows both writer options in the `model` producer dropdown.
- Saving without picking a producer is blocked.
- Picking a writer and saving succeeds.
- Generate code → emitted `ctx[:model_xxxx] = ...` keys match for writer/reader pair.
- Flowcharts without conflicts generate identical code to the previous version (diff a before/after on a known non-conflict flowchart).

- [ ] **Step 5: No final commit** (commits happen per-task; this is just a verification pass)

---

## Self-Review

**Spec coverage:**
- "Empty I/O tab" problem → Tasks 2, 7, 8, 11 (extractor, endpoint, cache, UI).
- "Ctx key collisions" problem → Tasks 3, 4, 5, 6 (reachability, resolver, rewriter, integration).
- Flowchart save format `io_bindings` addition → Task 11 populates it via user dropdown selection; no separate schema migration because the flowchart elements field is a free-form JSON column.
- Rename key format (SHA1[0..3], fallback 6) → Task 4 + Task 10 (both sides).
- Backward compat (missing `io_bindings` = `[]`) → Task 5 (EmissionRewriter treats absent bindings as null).
- Save-time validation on ambiguous bindings → Task 12.
- Client/server resolver parity → same algorithm in Task 4 (Ruby) and Task 10 (JS) with matching SHA1 suffix derivation.

**Placeholder scan:** none — every code step has complete code. "NOTE" in Task 13 flags a skip condition but includes the fallback path.

**Type consistency:**
- `ConflictResolver.call` returns a `Result` with `rename_map`, `producer_outputs`, `reader_inputs`, `reachability` — same names used in Task 5 (EmissionRewriter) and Task 6 (ActivityGenerator splice).
- `IoExtractor` return shape `{inputs: [...], outputs: [...]}` matches the JSON endpoint response in Task 7 and cache shape in Task 8.
- `stepPins[stepId]` shape matches `IoExtractor` output: `{inputs, outputs}`.
- `io_bindings` entry shape `{pin, producer_step_id, producer_pin}` is consistent across Tasks 5, 11, 12.
- `Reachability#reachablePredecessors` in JS (Task 9) mirrors `ReachabilityIndex#reachable_predecessors` in Ruby (Task 3).

Review complete. No fixes needed inline.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-20-step-io-tab-and-ctx-conflict-resolution.md`.

Proceeding to execute autonomously per standing instruction.
