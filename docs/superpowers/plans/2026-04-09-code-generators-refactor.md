# Code Generator Infrastructure Refactoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-implement all code generator infrastructure with clean separation of concerns — `CodeIntrospector`, `TestRunner`, purge deprecated stubs, add `sample_input` to all generators, smart auto-versioning, and developer-focused dark UI.

**Architecture:** Extract I/O introspection into standalone `CodeIntrospector` service, extract test execution into `TestRunner` service, strip `GeneratorInterface` to a thin concern. All deprecated methods (`example_output`, `input_schema`, `output_schema`, `derived_io`, `dry_run`, `generate` alias) fully removed. UI restyled with dark dev-focused aesthetic.

**Tech Stack:** Ruby on Rails 8.1.2, RSpec, TailwindCSS, StimulusJS, ViewComponent, Rouge (syntax highlighting)

---

## File Map

### New files
- `app/services/code_generators/code_introspector.rb` — standalone I/O analysis service
- `app/services/code_generators/test_runner.rb` — standalone test execution service
- `spec/services/code_generators/code_introspector_spec.rb` — CodeIntrospector unit tests
- `spec/services/code_generators/test_runner_spec.rb` — TestRunner unit tests

### Modified files (infrastructure)
- `app/services/code_generators/generator_interface.rb` — strip to thin concern
- `app/services/code_generators/base_generator.rb` — remove `generate` alias
- `app/services/code_generators/source_assembler.rb` — add `sample_input` stub
- `app/services/code_generators/generator_validator.rb` — remove deprecated method checks

### Modified files (all 125 generators)
- All files under `app/services/code_generators/element_types/` — add `self.sample_input`

### Modified files (UI)
- `app/components/admin/code_generators/index_component.rb` — dark theme helpers
- `app/components/admin/code_generators/index_component.html.erb` — dark tree + cards
- `app/components/admin/code_generators/show_component.rb` — use TestRunner
- `app/components/admin/code_generators/show_component.html.erb` — dark dev UI
- `app/components/admin/code_generators/detail_panel_component.rb` — use TestRunner
- `app/components/admin/code_generators/detail_panel_component.html.erb` — dark dev UI
- `app/components/admin/code_generators/form_component.html.erb` — dark code textarea
- `app/controllers/admin/code_generators_controller.rb` — TestRunner delegation, smart versioning
- `app/javascript/controllers/generator_test_runner_controller.js` — sample pre-fill, dark theme
- `app/javascript/controllers/generator_nav_controller.js` — dark active styling
- `app/javascript/controllers/generator_search_controller.js` — unchanged functionally

### Modified files (specs)
- `spec/support/shared_examples/code_generator_interface.rb` — rewrite with TestRunner
- `spec/services/code_generators/generator_interface_spec.rb` — update for stripped interface
- `spec/services/code_generators/derived_io_spec.rb` — replace with CodeIntrospector tests
- `spec/controllers/admin/code_generators_controller_spec.rb` — smart versioning tests

---

## Task 1: Create CodeIntrospector with TDD

**Files:**
- Create: `spec/services/code_generators/code_introspector_spec.rb`
- Create: `app/services/code_generators/code_introspector.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/code_generators/code_introspector_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::CodeIntrospector do
  describe ".analyze" do
    it "returns hash with inputs and outputs arrays" do
      result = described_class.analyze("ctx[:result] = ctx[:input]")
      expect(result).to be_a(Hash)
      expect(result[:inputs]).to be_an(Array)
      expect(result[:outputs]).to be_an(Array)
    end

    it "detects ctx[:key] = as output" do
      result = described_class.analyze("ctx[:result] = User.find(1)")
      expect(result[:outputs]).to eq(["result"])
    end

    it "detects ctx[:key] read as input" do
      result = described_class.analyze("name = ctx[:user_name]")
      expect(result[:inputs]).to eq(["user_name"])
    end

    it "detects ctx.dig(:key, ...) as input (top-level key only)" do
      result = described_class.analyze("val = ctx.dig(:config, :timeout)")
      expect(result[:inputs]).to eq(["config"])
    end

    it "detects ctx.fetch(:key) as input" do
      result = described_class.analyze("val = ctx.fetch(:model)")
      expect(result[:inputs]).to eq(["model"])
    end

    it "detects ctx.fetch(:key, default) as input" do
      result = described_class.analyze("val = ctx.fetch(:retries, 3)")
      expect(result[:inputs]).to eq(["retries"])
    end

    it "excludes keys starting with _" do
      result = described_class.analyze("ctx[:_internal] = 1\nval = ctx[:_route]")
      expect(result[:inputs]).to be_empty
      expect(result[:outputs]).to be_empty
    end

    it "lists key in both inputs and outputs when read and written" do
      result = described_class.analyze("ctx[:counter] = ctx[:counter] + 1")
      expect(result[:inputs]).to include("counter")
      expect(result[:outputs]).to include("counter")
    end

    it "excludes keys inside string literals" do
      code = '"ctx[:not_real] = something"'
      result = described_class.analyze(code)
      expect(result[:inputs]).to be_empty
      expect(result[:outputs]).to be_empty
    end

    it "excludes keys inside single-quoted strings" do
      code = "'ctx[:not_real] = something'"
      result = described_class.analyze(code)
      expect(result[:inputs]).to be_empty
      expect(result[:outputs]).to be_empty
    end

    it "excludes keys inside comments" do
      code = "# ctx[:commented] = something\nctx[:real] = 1"
      result = described_class.analyze(code)
      expect(result[:outputs]).to eq(["real"])
      expect(result[:inputs]).to be_empty
    end

    it "deduplicates keys" do
      code = "x = ctx[:model]\ny = ctx[:model]\nctx[:result] = x"
      result = described_class.analyze(code)
      expect(result[:inputs]).to eq(["model"])
      expect(result[:outputs]).to eq(["result"])
    end

    it "returns empty arrays for nil input" do
      result = described_class.analyze(nil)
      expect(result).to eq({ inputs: [], outputs: [] })
    end

    it "returns empty arrays for empty string" do
      result = described_class.analyze("")
      expect(result).to eq({ inputs: [], outputs: [] })
    end

    it "handles heredoc strings" do
      code = <<~'RUBY'
        sql = <<~SQL
          SELECT ctx[:not_real] FROM users
        SQL
        ctx[:result] = ActiveRecord::Base.connection.execute(sql)
      RUBY
      result = described_class.analyze(code)
      expect(result[:outputs]).to eq(["result"])
      expect(result[:inputs]).not_to include("not_real")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/code_introspector_spec.rb`
Expected: FAIL — `uninitialized constant CodeGenerators::CodeIntrospector`

- [ ] **Step 3: Write the implementation**

```ruby
# app/services/code_generators/code_introspector.rb
# frozen_string_literal: true

module CodeGenerators
  class CodeIntrospector
    OUTPUT_PATTERN = /ctx\[:(\w+)\]\s*=[^=]/
    READ_BRACKET  = /ctx\[:(\w+)\]/
    READ_DIG      = /ctx\.dig\(:(\w+)/
    READ_FETCH    = /ctx\.fetch\(:(\w+)/

    class << self
      def analyze(code_string)
        return { inputs: [], outputs: [] } if code_string.to_s.strip.empty?

        cleaned = strip_non_code(code_string)

        outputs = cleaned.scan(OUTPUT_PATTERN).flatten.uniq
        all_reads = cleaned.scan(READ_BRACKET).flatten
        all_reads += cleaned.scan(READ_DIG).flatten
        all_reads += cleaned.scan(READ_FETCH).flatten
        inputs = all_reads.uniq

        inputs.reject! { |k| k.start_with?("_") }
        outputs.reject! { |k| k.start_with?("_") }

        # Keys that are only written (not read) are pure outputs — remove from inputs
        # Keys that are both read and written stay in both
        pure_outputs = outputs - inputs
        mixed = outputs & inputs
        pure_inputs = inputs - outputs

        {
          inputs: (pure_inputs + mixed).uniq.sort,
          outputs: (pure_outputs + mixed).uniq.sort
        }
      end

      private

      def strip_non_code(code)
        # Remove heredoc strings
        result = code.gsub(/<<~\w+.*?^\s*\w+$/m, "")
        # Remove double-quoted strings (handle escaped quotes)
        result = result.gsub(/"(?:[^"\\]|\\.)*"/, '""')
        # Remove single-quoted strings
        result = result.gsub(/'(?:[^'\\]|\\.)*'/, "''")
        # Remove comments
        result = result.gsub(/#.*$/, "")
        result
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/code_introspector_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add spec/services/code_generators/code_introspector_spec.rb app/services/code_generators/code_introspector.rb
git commit -m "feat: add CodeIntrospector service with TDD for robust ctx I/O analysis"
```

---

## Task 2: Create TestRunner with TDD

**Files:**
- Create: `spec/services/code_generators/test_runner_spec.rb`
- Create: `app/services/code_generators/test_runner.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/code_generators/test_runner_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::TestRunner do
  describe ".run" do
    let(:generator_class) { CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator }
    let(:config) { { "targetVar" => "result", "valueType" => "string", "stringValue" => "hello" } }

    it "returns a hash with code, body, inputs, outputs, validation_errors" do
      result = described_class.run(generator_class, config: config)
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(:code, :body, :inputs, :outputs, :validation_errors)
    end

    it "body contains ctx references" do
      result = described_class.run(generator_class, config: config)
      expect(result[:body]).to include("ctx[")
    end

    it "code wraps body with def step(ctx, **)" do
      result = described_class.run(generator_class, config: config)
      expect(result[:code]).to include("(ctx, **)")
      expect(result[:code]).to match(/\Adef /)
      expect(result[:code].strip).to end_with("end")
    end

    it "outputs includes the target variable" do
      result = described_class.run(generator_class, config: config)
      expect(result[:outputs]).to include("result")
    end

    it "validation_errors is an array" do
      result = described_class.run(generator_class, config: config)
      expect(result[:validation_errors]).to be_an(Array)
    end

    context "with a generator that returns nil body" do
      let(:start_class) { CodeGenerators::ElementTypes::Start::StartGenerator }

      it "returns nil body and nil code" do
        result = described_class.run(start_class, config: {})
        expect(result[:body]).to be_nil
        expect(result[:code]).to be_nil
        expect(result[:inputs]).to eq([])
        expect(result[:outputs]).to eq([])
      end
    end

    context "with validation errors" do
      it "passes through validation errors from the generator" do
        result = described_class.run(generator_class, config: {})
        expect(result[:validation_errors]).to be_an(Array)
      end
    end

    context "with default config from sample_input" do
      it "uses empty hash when no config provided" do
        result = described_class.run(generator_class)
        expect(result).to be_a(Hash)
        expect(result[:body]).to be_a(String).or be_nil
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/test_runner_spec.rb`
Expected: FAIL — `uninitialized constant CodeGenerators::TestRunner`

- [ ] **Step 3: Write the implementation**

```ruby
# app/services/code_generators/test_runner.rb
# frozen_string_literal: true

module CodeGenerators
  class TestRunner
    class << self
      def run(generator_class, config: {})
        element = {
          "config" => config,
          "properties" => config,
          "label" => "test_step"
        }

        generator = generator_class.new(element, {})
        body = generator.generate_body
        code = generator.generate_step_method
        io = CodeIntrospector.analyze(body)
        validation_errors = generator.validate_config(config)

        {
          body: body,
          code: code,
          inputs: io[:inputs],
          outputs: io[:outputs],
          validation_errors: validation_errors
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/test_runner_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add spec/services/code_generators/test_runner_spec.rb app/services/code_generators/test_runner.rb
git commit -m "feat: add TestRunner service — single entry point for generator test execution"
```

---

## Task 3: Strip GeneratorInterface and BaseGenerator

**Files:**
- Modify: `app/services/code_generators/generator_interface.rb`
- Modify: `spec/services/code_generators/generator_interface_spec.rb`

- [ ] **Step 1: Rewrite GeneratorInterface**

Replace the entire contents of `app/services/code_generators/generator_interface.rb` with:

```ruby
# frozen_string_literal: true

require_relative "metadata_dsl"

module CodeGenerators
  module GeneratorInterface
    extend ActiveSupport::Concern

    class InterfaceError < StandardError; end

    class_methods do
      def generator_metadata(&block)
        dsl = CodeGenerators::MetadataDSL.new
        dsl.instance_eval(&block)
        self._metadata = dsl.to_h
      end

      def generator_name
        name.demodulize.sub(/Generator$/, "").underscore
      end

      def generator_kind
        if name.include?("ElementTypes::Process")
          :step_action
        elsif name.include?("ElementTypes")
          :element_type
        else
          :unknown
        end
      end

      def registered_names
        [generator_name]
      end

      def sample_input
        {}
      end
    end

    included do
      class_attribute :_metadata, default: {}
    end

    def initialize(element, context)
      @element = element
      @context = context
    end

    def generate_step_method
      body = generate_body
      return nil unless body

      step_name = derive_step_name
      <<~RUBY.chomp
        def #{step_name}(ctx, **)
        #{body.gsub(/^/, "  ")}
        end
      RUBY
    end

    def generate_body
      raise InterfaceError, "#{self.class.name} must implement #generate_body"
    end

    def validate_config(config)
      raise InterfaceError, "#{self.class.name} must implement #validate_config"
    end

    def dependencies
      []
    end

    private

    def derive_step_name
      label = @element.is_a?(Hash) ? (@element["label"] || @element["name"]) : nil
      if label.present?
        label.to_s.parameterize(separator: "_").gsub(/\A\d+/, "step_\\0")
      else
        self.class.generator_name
      end
    end
  end
end
```

- [ ] **Step 2: Update GeneratorInterface spec**

Replace the entire contents of `spec/services/code_generators/generator_interface_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::GeneratorInterface do
  let(:test_class) do
    Class.new do
      include CodeGenerators::GeneratorInterface

      def self.name
        "CodeGenerators::ElementTypes::Process::Test::TestGenerator"
      end

      generator_metadata do
        description "Test generator"
        category :test
        version "1.0.0"
      end

      def generate_body
        'ctx[:result] = ctx[:input_value].to_s'
      end

      def validate_config(config)
        []
      end
    end
  end

  describe "class-level DSL" do
    it "stores metadata" do
      expect(test_class._metadata[:description]).to eq("Test generator")
      expect(test_class._metadata[:category]).to eq(:test)
      expect(test_class._metadata[:version]).to eq("1.0.0")
    end

    it "derives generator_name from class name" do
      expect(test_class.generator_name).to eq("test")
    end

    it "derives generator_kind from namespace" do
      expect(test_class.generator_kind).to eq(:step_action)
    end

    it "defaults registered_names to [generator_name]" do
      expect(test_class.registered_names).to eq(["test"])
    end

    it "returns sample_input as empty hash by default" do
      expect(test_class.sample_input).to eq({})
    end
  end

  describe "instance methods" do
    let(:element) { { "label" => "My Step" } }
    let(:instance) { test_class.new(element, {}) }

    it "#generate_body returns the code body" do
      expect(instance.generate_body).to eq('ctx[:result] = ctx[:input_value].to_s')
    end

    it "#generate_step_method wraps body with def step(ctx, **)" do
      result = instance.generate_step_method
      expect(result).to include("def my_step(ctx, **)")
      expect(result).to include('ctx[:result] = ctx[:input_value].to_s')
    end

    it "#generate_step_method uses generator_name when no label" do
      instance = test_class.new({}, {})
      result = instance.generate_step_method
      expect(result).to include("def test(ctx, **)")
    end

    it "#generate_step_method sanitizes labels with leading digits" do
      instance = test_class.new({ "label" => "123 start" }, {})
      result = instance.generate_step_method
      expect(result).to include("def step_123_start(ctx, **)")
    end
  end

  describe "interface enforcement" do
    let(:bare_class) do
      Class.new do
        include CodeGenerators::GeneratorInterface
        def self.name = "CodeGenerators::ElementTypes::Process::Test::BareGenerator"
      end
    end

    it "raises InterfaceError for unimplemented #generate_body" do
      instance = bare_class.new({}, {})
      expect { instance.generate_body }.to raise_error(CodeGenerators::GeneratorInterface::InterfaceError)
    end

    it "raises InterfaceError for unimplemented #validate_config" do
      instance = bare_class.new({}, {})
      expect { instance.validate_config({}) }.to raise_error(CodeGenerators::GeneratorInterface::InterfaceError)
    end

    it "provides default #dependencies as empty array" do
      instance = bare_class.new({}, {})
      expect(instance.dependencies).to eq([])
    end
  end
end
```

- [ ] **Step 3: Run specs to verify**

Run: `bundle exec rspec spec/services/code_generators/generator_interface_spec.rb spec/services/code_generators/code_introspector_spec.rb spec/services/code_generators/test_runner_spec.rb`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/generator_interface.rb spec/services/code_generators/generator_interface_spec.rb
git commit -m "refactor: strip GeneratorInterface to thin concern — remove all deprecated methods"
```

---

## Task 4: Update SourceAssembler and GeneratorValidator

**Files:**
- Modify: `app/services/code_generators/source_assembler.rb`
- Modify: `app/services/code_generators/generator_validator.rb`

- [ ] **Step 1: Update SourceAssembler to include sample_input stub**

In `app/services/code_generators/source_assembler.rb`, in the `class_body` method, add a `sample_input` stub after the metadata block. Find the lines:

```ruby
      parts << "  end"

      # methods body
```

And insert between them:

```ruby
      # sample_input
      parts << ""
      parts << "  def self.sample_input"
      parts << "    {}"
      parts << "  end"
```

- [ ] **Step 2: Update GeneratorValidator — tighten interface check**

In `app/services/code_generators/generator_validator.rb`, in the `check_interface` method, replace:

```ruby
        unless source.match?(/def\s+generate_body\b/) || source.match?(/def\s+generate\b/)
```

With:

```ruby
        unless source.match?(/def\s+generate_body\b/)
```

- [ ] **Step 3: Run existing specs**

Run: `bundle exec rspec spec/services/code_generators/source_assembler_spec.rb spec/services/code_generators/generator_validator_spec.rb`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/source_assembler.rb app/services/code_generators/generator_validator.rb
git commit -m "refactor: update SourceAssembler with sample_input stub, tighten GeneratorValidator"
```

---

## Task 5: Update shared example and derived_io spec

**Files:**
- Modify: `spec/support/shared_examples/code_generator_interface.rb`
- Modify: `spec/services/code_generators/derived_io_spec.rb`

- [ ] **Step 1: Rewrite shared example**

Replace the entire contents of `spec/support/shared_examples/code_generator_interface.rb` with:

```ruby
# frozen_string_literal: true

RSpec.shared_examples "a code generator" do
  let(:generator) { described_class.new(element, context) }

  it "implements #generate_body returning String or nil" do
    expect(generator).to respond_to(:generate_body)
    result = generator.generate_body
    expect(result).to be_a(String).or be_nil
  end

  it "implements #generate_step_method wrapping body with def step(ctx, **)...end" do
    expect(generator).to respond_to(:generate_step_method)
    result = generator.generate_step_method
    if result
      expect(result).to include("(ctx, **)")
      expect(result).to match(/\Adef /)
      expect(result.strip).to end_with("end")
    end
  end

  it "implements #validate_config returning Array" do
    expect(generator).to respond_to(:validate_config)
    result = generator.validate_config(element.fetch("config", element.fetch("properties", {})))
    expect(result).to be_an(Array)
  end

  it "implements #dependencies returning Array" do
    expect(generator).to respond_to(:dependencies)
    expect(generator.dependencies).to be_an(Array)
  end

  it "implements .sample_input returning Hash" do
    expect(described_class.sample_input).to be_a(Hash)
  end

  it "declares metadata with description, category (Symbol), and version (semver)" do
    metadata = described_class._metadata
    expect(metadata).to be_a(Hash)
    expect(metadata[:description]).to be_a(String)
    expect(metadata[:category]).to be_a(Symbol)
    expect(metadata[:version]).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "has a generator_name derived from class name" do
    expect(described_class.generator_name).to be_a(String)
    expect(described_class.generator_name).not_to be_empty
  end

  it "has a generator_kind of :element_type or :step_action" do
    expect(described_class.generator_kind).to be_in([:element_type, :step_action])
  end

  it "TestRunner.run succeeds with sample_input" do
    result = CodeGenerators::TestRunner.run(described_class, config: described_class.sample_input)
    expect(result).to be_a(Hash)
    expect(result.keys).to contain_exactly(:code, :body, :inputs, :outputs, :validation_errors)
    expect(result[:inputs]).to be_an(Array)
    expect(result[:outputs]).to be_an(Array)
    expect(result[:validation_errors]).to be_an(Array)
  end
end
```

- [ ] **Step 2: Rewrite derived_io_spec to use CodeIntrospector and TestRunner**

Replace the entire contents of `spec/services/code_generators/derived_io_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Code generator I/O and test pipeline" do
  let(:generator_class) { CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator }

  describe "CodeIntrospector integration with real generators" do
    it "derives output keys from ctx[:key] = assignments" do
      config = { "targetVar" => "result", "valueType" => "string", "stringValue" => "hello" }
      element = { "config" => config, "properties" => config }
      body = generator_class.new(element, {}).generate_body
      result = CodeGenerators::CodeIntrospector.analyze(body)
      expect(result[:outputs]).to include("result")
    end

    it "filters out internal keys prefixed with _" do
      loop_class = CodeGenerators::ElementTypes::Loop::LoopGenerator
      element = { "properties" => {} }
      body = loop_class.new(element, {}).generate_body
      result = CodeGenerators::CodeIntrospector.analyze(body)
      result[:outputs].each do |key|
        expect(key).not_to start_with("_")
      end
    end
  end

  describe "TestRunner integration" do
    it "runs assign_value generator with sample config" do
      config = { "targetVar" => "result", "valueType" => "string", "stringValue" => "hello" }
      result = CodeGenerators::TestRunner.run(generator_class, config: config)
      expect(result[:code]).to include("(ctx, **)")
      expect(result[:body]).to include("ctx[:result]")
      expect(result[:outputs]).to include("result")
    end
  end

  describe "#generate_step_method" do
    it "returns a complete step method with (ctx, **) signature" do
      element = { "config" => { "targetVar" => "result", "valueType" => "string", "stringValue" => "hello" } }
      gen = generator_class.new(element, {})
      code = gen.generate_step_method
      expect(code).to include("def ")
      expect(code).to include("(ctx, **)")
      expect(code).to include("ctx[:result]")
      expect(code).to end_with("end")
    end

    it "uses element label for step name when available" do
      element = { "config" => { "targetVar" => "x" }, "label" => "Set Result" }
      gen = generator_class.new(element, {})
      code = gen.generate_step_method
      expect(code).to include("def set_result(ctx, **)")
    end

    it "falls back to generator_name when no label" do
      element = { "config" => { "targetVar" => "x" } }
      gen = generator_class.new(element, {})
      code = gen.generate_step_method
      expect(code).to include("def assign_value(ctx, **)")
    end
  end

  describe "MetadataDSL.bump_patch" do
    it "increments the patch version" do
      expect(CodeGenerators::MetadataDSL.bump_patch("1.0.0")).to eq("1.0.1")
      expect(CodeGenerators::MetadataDSL.bump_patch("2.3.5")).to eq("2.3.6")
    end

    it "handles nil/empty gracefully" do
      expect(CodeGenerators::MetadataDSL.bump_patch(nil)).to eq("1.0.1")
      expect(CodeGenerators::MetadataDSL.bump_patch("")).to eq("1.0.1")
    end
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/services/code_generators/derived_io_spec.rb spec/support/shared_examples/code_generator_interface.rb`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add spec/support/shared_examples/code_generator_interface.rb spec/services/code_generators/derived_io_spec.rb
git commit -m "refactor: update shared example and derived_io spec to use CodeIntrospector and TestRunner"
```

---

## Task 6: Add sample_input to all element type generators (14 generators)

**Files:**
- Modify: All 14 files under `app/services/code_generators/element_types/` (non-process)

For each generator, add a `self.sample_input` class method right after the `generator_metadata` block.

- [ ] **Step 1: Add sample_input to each element type generator**

Insert `self.sample_input` after the `generator_metadata` block in each file:

| File | sample_input |
|------|-------------|
| `start/start_generator.rb` | `{}` |
| `end/end_generator.rb` | `{ "responseType" => "value", "returnValue" => "ctx[:result]" }` |
| `decision/decision_generator.rb` | `{ "condition" => { "leftOperand" => "ctx[:status]", "operator" => "==", "rightOperand" => "approved" } }` |
| `loop/loop_generator.rb` | `{ "loopType" => "for_each", "collection" => "ctx[:items]", "itemVariable" => "item" }` |
| `timer/timer_generator.rb` | `{ "delayType" => "fixed", "duration" => 5, "durationUnit" => "seconds" }` |
| `error_handler/error_handler_generator.rb` | `{ "errorTypes" => "all errors", "fallbackAction" => "log_and_continue" }` |
| `subflow/subflow_generator.rb` | `{}` |
| `fork/fork_generator.rb` | `{}` |
| `join/join_generator.rb` | `{ "mergeStrategy" => "wait_all" }` |
| `saga/saga_generator.rb` | `{ "compensationMode" => "reverse_all", "compensationTimeout" => 60 }` |
| `signal_wait/signal_wait_generator.rb` | `{ "signalName" => "approval_signal", "waitMode" => "pause_and_resume", "timeoutSeconds" => 3600, "timeoutAction" => "fail" }` |
| `switch/switch_generator.rb` | `{ "sourceVariable" => "status", "cases" => [{ "value" => "pending" }, { "value" => "approved" }] }` |
| `transaction/transaction_generator.rb` | `{ "isolationLevel" => "serializable", "requiresNew" => false }` |
| `parallel_for_each/parallel_for_each_generator.rb` | `{ "sourceVariable" => "items", "itemVariable" => "item", "concurrency" => 5, "resultVariable" => "results" }` |

- [ ] **Step 2: Run element type generator specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/`
Expected: All PASS (shared example now checks `sample_input` returns Hash and TestRunner.run succeeds)

- [ ] **Step 3: Commit**

```bash
git add app/services/code_generators/element_types/
git commit -m "feat: add sample_input to all 14 element type generators"
```

---

## Task 7: Add sample_input to all process step action generators (111 generators)

**Files:**
- Modify: All files under `app/services/code_generators/element_types/process/`

This is the largest mechanical task. For each generator, read its `generate_body` method to identify what config keys it uses, then add a `self.sample_input` method after the `generator_metadata` block with realistic values.

- [ ] **Step 1: Add sample_input to all step action generators**

The implementing agent should:
1. Read each generator file
2. Identify config keys used in `generate_body` (look for `config["key"]` or `config[:key]` patterns)
3. Add `self.sample_input` after the `generator_metadata` block with realistic values

Reference values for key generators:

| Generator | sample_input |
|-----------|-------------|
| `model_operations/find_model_generator.rb` | `{ "findStrategy" => "findBy", "resultVar" => "user", "findField" => "email", "findValue" => "user@example.com" }` |
| `data_operations/assign_value_generator.rb` | `{ "targetVar" => "count", "valueType" => "integer", "integerValue" => 42 }` |
| `communication/api_call_generator.rb` | `{ "httpMethod" => "POST", "url" => "https://api.example.com/users", "responseVar" => "api_response", "authType" => "none", "headers" => [] }` |
| `security/authenticate_generator.rb` | `{ "authMethod" => "jwt", "sourceVariable" => "auth_token", "targetVariable" => "decoded_user", "failAction" => "fail_track", "secretVariable" => "jwt_secret", "algorithm" => "HS256" }` |
| `background/enqueue_job_generator.rb` | `{ "jobClass" => "SendEmailJob", "jobArgs" => "ctx[:user_id]", "queueName" => "mailers", "priority" => 10 }` |
| `caching/cache_read_generator.rb` | `{ "cacheKey" => "user_data", "targetVariable" => "cached_user" }` |
| `resilience/retry_with_backoff_generator.rb` | `{ "maxAttempts" => 3, "backoffType" => "exponential", "baseDelay" => 1.0, "maxDelay" => 60.0, "outputKey" => "retry_result" }` |
| `scheduling_time/timezone_convert_generator.rb` | `{ "sourceKey" => "timestamp", "toTimezone" => "America/New_York", "outputKey" => "converted_time" }` |
| `utility/template_render_generator.rb` | `{ "template" => "Hello {{ name }}", "engine" => "liquid", "variables" => { "greeting" => "name" }, "outputKey" => "rendered" }` |
| `validation/build_contract_generator.rb` | `{}` |
| `validation/validate_contract_generator.rb` | `{ "permissionType" => "policy_check", "policyClass" => "PostPolicy", "policyAction" => "show?", "userExpression" => "ctx[:current_user]", "recordExpression" => "ctx[:model]" }` |

For every other generator not listed above, the agent MUST read the file, identify config keys from `generate_body`, and provide appropriate sample values. Every generator MUST get a `self.sample_input` method.

- [ ] **Step 2: Run ALL generator specs to verify**

Run: `bundle exec rspec spec/services/code_generators/element_types/`
Expected: All PASS — every generator's shared example now runs TestRunner with sample_input

- [ ] **Step 3: Commit**

```bash
git add app/services/code_generators/element_types/process/
git commit -m "feat: add sample_input to all 111 step action generators"
```

---

## Task 8: Update controller with TestRunner delegation and smart versioning

**Files:**
- Modify: `app/controllers/admin/code_generators_controller.rb`
- Modify: `spec/controllers/admin/code_generators_controller_spec.rb`

- [ ] **Step 1: Update the controller**

Key changes to `app/controllers/admin/code_generators_controller.rb`:

1. **`#test_run` action** — delegate to `TestRunner.run` instead of manual introspection:

Replace the body of `test_run` (after JSON parsing) with:
```ruby
      if @registry_entry
        result = ::CodeGenerators::TestRunner.run(@registry_entry, config: sample_config)
        render json: {
          body: result[:body],
          code: result[:code],
          code_highlighted: result[:code] ? highlight_ruby(result[:code]) : nil,
          inputs: result[:inputs],
          outputs: result[:outputs],
          validation_errors: result[:validation_errors]
        }
      else
        render json: { error: "Generator not found" }, status: :not_found
      end
```

2. **`#update` action** — smart versioning (only bump when body changes):

Replace the entire `update` method with:
```ruby
    def update
      old_body = capture_body(@registry_entry)
      source = assemble_source

      save_generator(@file_path, source) do
        new_class = reload_and_find_generator
        new_body = capture_body(new_class)

        if old_body != new_body && new_class
          current_version = new_class._metadata[:version] || "1.0.0"
          new_version = ::CodeGenerators::MetadataDSL.bump_patch(current_version)
          bump_version_in_file(@file_path, current_version, new_version)
          Rails.autoloaders.main.reload
          ::CodeGenerators::GeneratorRegistry.instance.reload!
          redirect_to admin_code_generator_path(path: relative_path(@file_path)),
                      notice: "Generator updated (v#{new_version})"
        else
          redirect_to admin_code_generator_path(path: relative_path(@file_path)),
                      notice: "Generator updated"
        end
      end
    end
```

3. **Add three new private methods:**

```ruby
    def capture_body(generator_class)
      return nil unless generator_class
      sample = generator_class.sample_input
      element = { "config" => sample, "properties" => sample, "label" => "version_check" }
      generator_class.new(element, {}).generate_body
    rescue StandardError
      nil
    end

    def reload_and_find_generator
      basename = File.basename(params[:path].to_s).sub(/_generator$/, "")
      ::CodeGenerators::GeneratorRegistry.instance.all_generators[basename]
    end

    def bump_version_in_file(file_path, old_version, new_version)
      source = File.read(file_path)
      updated = source.sub(/version\s+["']#{Regexp.escape(old_version)}["']/, "version \"#{new_version}\"")
      File.write(file_path, updated)
    end
```

4. **Update `extract_methods_body`** — skip `self.sample_input` lines (add after the `self.registered_names` skip):

```ruby
        next if stripped.match?(/^def self\.sample_input/)
```

- [ ] **Step 2: Update controller spec**

In `spec/controllers/admin/code_generators_controller_spec.rb`, update the `POST #preview_source` test to expect `sample_input` in the assembled source:

```ruby
      expect(json["source"]).to include("sample_input")
```

- [ ] **Step 3: Run controller spec**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/controllers/admin/code_generators_controller.rb spec/controllers/admin/code_generators_controller_spec.rb
git commit -m "refactor: controller uses TestRunner, smart auto-versioning on body change only"
```

---

## Task 9: Restyle Index page ViewComponent (dark developer aesthetic)

**Files:**
- Modify: `app/components/admin/code_generators/index_component.rb`
- Modify: `app/components/admin/code_generators/index_component.html.erb`

- [ ] **Step 1: Update IndexComponent Ruby — use TestRunner for I/O**

In `app/components/admin/code_generators/index_component.rb`, replace the `generator_io` method:

```ruby
      def generator_io(klass)
        result = CodeGenerators::TestRunner.run(klass, config: klass.sample_input)
        { inputs: result[:inputs], outputs: result[:outputs] }
      rescue StandardError
        { inputs: [], outputs: [] }
      end
```

- [ ] **Step 2: Rewrite the index template with dark developer aesthetic**

Replace the entire contents of `app/components/admin/code_generators/index_component.html.erb`. The implementing agent must create a dark-themed template following the design spec:

- **Outer container:** `bg-gray-950 min-h-screen`
- **Header bar:** `bg-gray-900 border-b border-gray-800`, title in white, subtitle in `text-gray-400`
- **Left sidebar:** `bg-gray-900 rounded-xl border border-gray-800`, search input with `bg-gray-800 border-gray-700 text-gray-200 placeholder-gray-500`
- **Tree items:** generator names in `font-mono text-sm text-gray-400`, no `.titleize` — use raw snake_case. Hover: `hover:bg-gray-800 hover:text-cyan-400`. Count badges: `bg-gray-800 text-gray-500`
- **Right card grid:** cards with `bg-gray-800 border-gray-700`, generator name in `font-mono text-gray-200`, description in `text-gray-500`, version in `text-gray-600`. Hover: `hover:border-cyan-500/50 hover:shadow-lg hover:shadow-cyan-500/5`
- **I/O counts on cards:** `text-amber-400` for inputs, `text-emerald-400` for outputs, monospace

All existing Stimulus data attributes (`data-controller`, `data-*-target`, `data-action`) and turbo-frame must be preserved exactly.

- [ ] **Step 3: Verify page renders**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add app/components/admin/code_generators/index_component.rb app/components/admin/code_generators/index_component.html.erb
git commit -m "feat: restyle index page with dark developer-focused aesthetic"
```

---

## Task 10: Restyle Show and DetailPanel components (dark developer aesthetic)

**Files:**
- Modify: `app/components/admin/code_generators/show_component.rb`
- Modify: `app/components/admin/code_generators/show_component.html.erb`
- Modify: `app/components/admin/code_generators/detail_panel_component.rb`
- Modify: `app/components/admin/code_generators/detail_panel_component.html.erb`

- [ ] **Step 1: Rewrite ShowComponent Ruby**

Replace the entire contents of `app/components/admin/code_generators/show_component.rb` with:

```ruby
# frozen_string_literal: true

module Admin
  module CodeGenerators
    class ShowComponent < ApplicationComponent
      ELEMENT_TYPE_COLORS = IndexComponent::ELEMENT_TYPE_COLORS
      ELEMENT_TYPE_ICONS = IndexComponent::ELEMENT_TYPE_ICONS

      def initialize(generator_class:, source_code:, path:)
        @generator_class = generator_class
        @source_code = source_code
        @path = path
      end

      def metadata
        @generator_class&._metadata || {}
      end

      def test_result
        @test_result ||= begin
          config = @generator_class&.sample_input || {}
          ::CodeGenerators::TestRunner.run(@generator_class, config: config)
        rescue StandardError
          { code: nil, body: nil, inputs: [], outputs: [], validation_errors: [] }
        end
      end

      def input_keys
        test_result[:inputs]
      end

      def output_keys
        test_result[:outputs]
      end

      def deps
        @generator_class ? @generator_class.new({}, {}).dependencies : []
      end

      def generator_name
        @generator_class&.generator_name || "unknown"
      end

      def generator_kind
        @generator_class&.generator_kind
      end

      def kind_label
        generator_kind == :element_type ? "Element Type" : "Step Action"
      end

      def edit_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}/edit"
      end

      def delete_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}"
      end

      def category_colors
        ELEMENT_TYPE_COLORS[metadata[:category]] || { bg: "bg-gray-50", text: "text-gray-700", border: "border-gray-200", dot: "bg-gray-400" }
      end

      def category_icon
        ELEMENT_TYPE_ICONS[metadata[:category]] || "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
      end

      def line_count
        @source_code.lines.count
      end

      def test_run_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}/test_run"
      end

      def sample_json
        (@generator_class&.sample_input || {}).to_json
      end

      def sample_code
        test_result[:code]
      end
    end
  end
end
```

- [ ] **Step 2: Rewrite show template with dark developer aesthetic**

Replace `app/components/admin/code_generators/show_component.html.erb`. The implementing agent must create a dark-themed template:

- **Outer:** `bg-gray-950 min-h-screen`
- **Header:** `bg-gray-900 border-b border-gray-800`. Generator name in `font-mono text-xl text-white`. Category/version/kind as small pills. Edit/Delete buttons right-aligned.
- **I/O Panel:** two dark cards side-by-side. Inputs: `ctx[:key]` pills in `bg-amber-900/20 text-amber-400 border-amber-800/30 font-mono`. Outputs: same but `emerald`. Dependencies in `indigo` if present.
- **Test Runner:** dark panel with `bg-gray-900 border-gray-800`. Textarea: `bg-gray-800 text-gray-200 font-mono`, pre-filled via `sample_json`. "Run" button: `bg-cyan-600 hover:bg-cyan-700 text-white`. Results: dark code panel, I/O badges.
- **Source Code:** `CodeBlockComponent` with full source.

Key: test runner must have `data-controller="generator-test-runner"` with `data-generator-test-runner-url-value="<%= test_run_path %>"` and `data-generator-test-runner-sample-value="<%= sample_json %>"`. All Stimulus targets preserved.

- [ ] **Step 3: Rewrite DetailPanelComponent Ruby**

Replace `app/components/admin/code_generators/detail_panel_component.rb` with:

```ruby
# frozen_string_literal: true

module Admin
  module CodeGenerators
    class DetailPanelComponent < ApplicationComponent
      def initialize(generator_class:, source_code:, path:)
        @generator_class = generator_class
        @source_code = source_code
        @path = path
      end

      def metadata
        @generator_class&._metadata || {}
      end

      def test_result
        @test_result ||= begin
          config = @generator_class&.sample_input || {}
          ::CodeGenerators::TestRunner.run(@generator_class, config: config)
        rescue StandardError
          { code: nil, body: nil, inputs: [], outputs: [], validation_errors: [] }
        end
      end

      def input_keys
        test_result[:inputs]
      end

      def output_keys
        test_result[:outputs]
      end

      def deps
        @generator_class ? @generator_class.new({}, {}).dependencies : []
      end

      def generator_name
        @generator_class&.generator_name || "unknown"
      end

      def kind_label
        @generator_class&.generator_kind == :element_type ? "Element Type" : "Step Action"
      end

      def edit_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}/edit"
      end

      def delete_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}"
      end

      def test_run_path
        "/admin/code_generators/#{@path.gsub('/', '%2F')}/test_run"
      end

      def sample_json
        (@generator_class&.sample_input || {}).to_json
      end

      def sample_code
        test_result[:code]
      end

      def line_count
        @source_code.lines.count
      end
    end
  end
end
```

- [ ] **Step 4: Rewrite detail_panel template with dark theme**

Replace `app/components/admin/code_generators/detail_panel_component.html.erb`. Same dark aesthetic as show but more compact (inline in turbo-frame). Same Stimulus bindings and targets.

- [ ] **Step 5: Verify**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/components/admin/code_generators/show_component.rb app/components/admin/code_generators/show_component.html.erb app/components/admin/code_generators/detail_panel_component.rb app/components/admin/code_generators/detail_panel_component.html.erb
git commit -m "feat: restyle show and detail panel with dark developer-focused aesthetic"
```

---

## Task 11: Restyle Form component

**Files:**
- Modify: `app/components/admin/code_generators/form_component.html.erb`

- [ ] **Step 1: Update form template styling**

In `app/components/admin/code_generators/form_component.html.erb`, make these targeted changes:

1. Change outer `bg-gray-50` to `bg-gray-950`
2. Change header `bg-white border-b border-gray-200` to `bg-gray-900 border-b border-gray-800`
3. Change header text colors: `text-gray-900` → `text-white`, `text-gray-500` → `text-gray-400`
4. Change section cards `bg-white rounded-xl border border-gray-200` to `bg-gray-900 rounded-xl border border-gray-800`
5. Change section titles `text-gray-700` → `text-gray-200`
6. Change methods textarea: `bg-gray-50 text-gray-800` → `bg-gray-950 text-gray-100 border-gray-800`
7. Change source preview panel: `bg-gray-50` → `bg-gray-950`
8. Change buttons to match dark theme (keep ButtonComponent variants)

Do NOT change structural HTML or Stimulus bindings.

- [ ] **Step 2: Verify form still renders**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb`
Expected: PASS (new and edit actions)

- [ ] **Step 3: Commit**

```bash
git add app/components/admin/code_generators/form_component.html.erb
git commit -m "feat: restyle form with dark code editor panel"
```

---

## Task 12: Update Stimulus controllers

**Files:**
- Modify: `app/javascript/controllers/generator_test_runner_controller.js`
- Modify: `app/javascript/controllers/generator_nav_controller.js`

- [ ] **Step 1: Update test runner controller with sample pre-fill**

Replace the entire contents of `app/javascript/controllers/generator_test_runner_controller.js` with:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "configInput", "runButton", "resultsPanel", "codeOutput",
    "inputBadges", "outputBadges", "validationErrors", "spinner"
  ]
  static values = { url: String, sample: String }

  connect() {
    if (this.hasConfigInputTarget) {
      const sample = this.hasSampleValue ? this.sampleValue : "{}"
      if (!this.configInputTarget.value || this.configInputTarget.value === "{}") {
        try {
          const parsed = JSON.parse(sample)
          this.configInputTarget.value = JSON.stringify(parsed, null, 2)
        } catch {
          this.configInputTarget.value = sample
        }
      }
    }
  }

  async run() {
    if (this.hasRunButtonTarget) this.runButtonTarget.disabled = true
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("hidden")

    const config = this.hasConfigInputTarget ? this.configInputTarget.value : "{}"

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
          "Accept": "application/json"
        },
        body: JSON.stringify({ sample_config: config })
      })

      const data = await response.json()

      if (data.error) {
        this.showError(data.error)
        return
      }

      this.displayResults(data)
    } catch (e) {
      this.showError("Request failed: " + e.message)
    } finally {
      if (this.hasRunButtonTarget) this.runButtonTarget.disabled = false
      if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("hidden")
    }
  }

  displayResults(data) {
    if (this.hasResultsPanelTarget) this.resultsPanelTarget.classList.remove("hidden")

    if (this.hasCodeOutputTarget) {
      if (data.code_highlighted) {
        this.codeOutputTarget.innerHTML = `<pre class="text-sm leading-relaxed"><code class="highlight">${data.code_highlighted}</code></pre>`
      } else {
        this.codeOutputTarget.innerHTML = `<pre class="text-sm text-gray-500 italic">No code generated (nil)</pre>`
      }
    }

    if (this.hasInputBadgesTarget) {
      this.inputBadgesTarget.innerHTML = this.renderBadges(data.inputs || [], "amber")
    }

    if (this.hasOutputBadgesTarget) {
      this.outputBadgesTarget.innerHTML = this.renderBadges(data.outputs || [], "emerald")
    }

    if (this.hasValidationErrorsTarget) {
      if (data.validation_errors && data.validation_errors.length > 0) {
        this.validationErrorsTarget.innerHTML = data.validation_errors
          .map(e => `<div class="text-sm text-red-400 flex items-center gap-1.5"><svg class="w-3.5 h-3.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01"/></svg>${this.escapeHtml(e)}</div>`)
          .join("")
        this.validationErrorsTarget.classList.remove("hidden")
      } else {
        this.validationErrorsTarget.classList.add("hidden")
      }
    }
  }

  showError(message) {
    if (this.hasResultsPanelTarget) this.resultsPanelTarget.classList.remove("hidden")
    if (this.hasCodeOutputTarget) {
      this.codeOutputTarget.innerHTML = `<div class="text-sm text-red-400">${this.escapeHtml(message)}</div>`
    }
  }

  renderBadges(keys, color) {
    if (keys.length === 0) return `<span class="text-xs text-gray-500 italic">none detected</span>`
    return keys.map(k =>
      `<span class="inline-flex items-center px-2 py-0.5 text-[10px] font-mono bg-${color}-900/20 text-${color}-400 rounded border border-${color}-800/30">ctx[:${this.escapeHtml(k)}]</span>`
    ).join(" ")
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
```

- [ ] **Step 2: Update nav controller for dark sidebar styling**

Replace the entire contents of `app/javascript/controllers/generator_nav_controller.js` with:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  activate(event) {
    this.linkTargets.forEach(link => {
      link.classList.remove("bg-cyan-900/20", "text-cyan-400", "border-l-2", "border-cyan-400", "font-semibold")
      link.classList.add("text-gray-400")
    })

    const clicked = event.currentTarget
    clicked.classList.remove("text-gray-400")
    clicked.classList.add("bg-cyan-900/20", "text-cyan-400", "border-l-2", "border-cyan-400", "font-semibold")
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/generator_test_runner_controller.js app/javascript/controllers/generator_nav_controller.js
git commit -m "feat: update Stimulus controllers for dark theme and sample_input pre-fill"
```

---

## Task 13: Run full test suite and fix any failures

**Files:** Any files with test failures

- [ ] **Step 1: Run all code generator specs**

Run: `bundle exec rspec spec/services/code_generators/ spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All PASS

- [ ] **Step 2: Fix any failures**

If any tests fail, read the error messages, identify the cause, and fix. Common issues:
- Generators that reference `derived_io` or `dry_run` directly
- Generators where `sample_input` produces code that causes `TestRunner.run` to error
- Shared example failures for generators missing `sample_input`

- [ ] **Step 3: Run full test suite once more**

Run: `bundle exec rspec spec/services/code_generators/ spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All PASS — zero failures

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test failures from code generator refactoring"
```

---

## Task 14: Clean up obsolete code

**Files:** Any files with remaining deprecated references

- [ ] **Step 1: Search for remaining deprecated references**

Run these grep searches:
```
grep -rn "example_output\|input_schema\|output_schema\|_input_keys\|_output_keys" app/services/code_generators/ app/components/ app/controllers/
grep -rn "\.derived_io\|\.dry_run" app/components/ app/controllers/
```

Remove any remaining references found.

- [ ] **Step 2: Search in specs**

Run:
```
grep -rn "example_output\|input_schema\|output_schema" spec/
grep -rn "\.derived_io\|\.dry_run" spec/
```

Update any remaining references in spec files (except the new CodeIntrospector/TestRunner specs).

- [ ] **Step 3: Verify no regressions**

Run: `bundle exec rspec spec/services/code_generators/ spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove all remaining deprecated code generator references"
```
