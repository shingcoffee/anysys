# Part 1: Infrastructure — GeneratorInterface, MetadataDSL, BaseGenerator

## Task 1: GeneratorInterface + MetadataDSL

**Files:**
- Create: `app/services/code_generators/generator_interface.rb`
- Test: `spec/services/code_generators/generator_interface_spec.rb`
- Test: `spec/support/shared_examples/code_generator_interface.rb`

- [ ] **Step 1: Create shared example group for code generators**

```ruby
# spec/support/shared_examples/code_generator_interface.rb
# frozen_string_literal: true

RSpec.shared_examples "a code generator" do
  let(:generator) { described_class.new(element, context) }

  it "implements #generate" do
    expect(generator).to respond_to(:generate)
    result = generator.generate
    expect(result).to be_a(String).or be_nil
  end

  it "implements #validate_config" do
    expect(generator).to respond_to(:validate_config)
    result = generator.validate_config(element.fetch("config", element.fetch("properties", {})))
    expect(result).to be_an(Array)
  end

  it "implements #example_output" do
    expect(generator).to respond_to(:example_output)
  end

  it "implements #dependencies" do
    expect(generator).to respond_to(:dependencies)
    expect(generator.dependencies).to be_an(Array)
  end

  it "declares metadata with description, category, and version" do
    metadata = described_class._metadata
    expect(metadata).to be_a(Hash)
    expect(metadata[:description]).to be_a(String)
    expect(metadata[:category]).to be_a(Symbol)
    expect(metadata[:version]).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "declares input and output schemas as arrays" do
    expect(described_class._input_keys).to be_an(Array)
    expect(described_class._output_keys).to be_an(Array)
  end

  it "has a generator_name derived from class name" do
    expect(described_class.generator_name).to be_a(String)
    expect(described_class.generator_name).not_to be_empty
  end

  it "has a generator_kind of :element_type or :step_action" do
    expect(described_class.generator_kind).to be_in([:element_type, :step_action])
  end
end
```

- [ ] **Step 2: Create GeneratorInterface module**

```ruby
# app/services/code_generators/generator_interface.rb
# frozen_string_literal: true

module CodeGenerators
  module GeneratorInterface
    extend ActiveSupport::Concern

    class InterfaceError < StandardError; end

    included do
      class_attribute :_metadata, default: {}
      class_attribute :_input_keys, default: []
      class_attribute :_output_keys, default: []
    end

    class_methods do
      def generator_metadata(&block)
        dsl = MetadataDSL.new
        dsl.instance_eval(&block)
        self._metadata = dsl.to_h
      end

      def input_schema(*keys)
        self._input_keys = keys
      end

      def output_schema(*keys)
        self._output_keys = keys
      end

      def generator_name
        name.demodulize.sub(/Generator$/, "").underscore
      end

      def generator_kind
        if name.include?("ElementTypes")
          :element_type
        elsif name.include?("StepActions")
          :step_action
        else
          :unknown
        end
      end

      # Override in subclass to register under additional action names
      # e.g., ValidateContractGenerator registers as ["validate_contract", "validate"]
      def registered_names
        [generator_name]
      end

      def dry_run(sample_config = {})
        element = { "config" => sample_config, "properties" => sample_config }
        gen = new(element, {})
        {
          code: gen.generate,
          input_keys: _input_keys,
          output_keys: _output_keys,
          example: gen.example_output
        }
      end
    end

    # --- Required methods (raise if not implemented) ---

    def generate
      raise InterfaceError, "#{self.class.name} must implement #generate"
    end

    def validate_config(config)
      raise InterfaceError, "#{self.class.name} must implement #validate_config"
    end

    # --- Optional methods with sensible defaults ---

    def example_output
      nil
    end

    def dependencies
      []
    end
  end
end
```

- [ ] **Step 3: Create MetadataDSL class**

Add to the same file (below GeneratorInterface) or as a separate file. Keeping it in the same module namespace:

```ruby
# app/services/code_generators/metadata_dsl.rb
# frozen_string_literal: true

module CodeGenerators
  class MetadataDSL
    FIELDS = %i[description category version].freeze

    def initialize
      @data = {}
    end

    FIELDS.each do |field|
      define_method(field) { |val| @data[field] = val }
    end

    def to_h
      @data.freeze
    end
  end
end
```

- [ ] **Step 4: Write GeneratorInterface spec**

```ruby
# spec/services/code_generators/generator_interface_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::GeneratorInterface do
  let(:test_class) do
    Class.new do
      include CodeGenerators::GeneratorInterface

      # Simulate being in StepActions namespace
      def self.name
        "CodeGenerators::StepActions::TestGenerator"
      end

      generator_metadata do
        description "Test generator"
        category :test
        version "1.0.0"
      end

      input_schema :input_key
      output_schema :output_key

      def generate
        "test code"
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

    it "stores input/output schemas" do
      expect(test_class._input_keys).to eq([:input_key])
      expect(test_class._output_keys).to eq([:output_key])
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

    it "supports dry_run" do
      result = test_class.dry_run
      expect(result[:code]).to eq("test code")
      expect(result[:input_keys]).to eq([:input_key])
      expect(result[:output_keys]).to eq([:output_key])
    end
  end

  describe "interface enforcement" do
    let(:bare_class) do
      Class.new do
        include CodeGenerators::GeneratorInterface
        def self.name = "CodeGenerators::StepActions::BareGenerator"
      end
    end

    it "raises InterfaceError for unimplemented #generate" do
      instance = bare_class.new({}, {})
      expect { instance.generate }.to raise_error(CodeGenerators::GeneratorInterface::InterfaceError)
    end

    it "raises InterfaceError for unimplemented #validate_config" do
      instance = bare_class.new({}, {})
      expect { instance.validate_config({}) }.to raise_error(CodeGenerators::GeneratorInterface::InterfaceError)
    end

    it "provides default #example_output as nil" do
      instance = bare_class.new({}, {})
      expect(instance.example_output).to be_nil
    end

    it "provides default #dependencies as empty array" do
      instance = bare_class.new({}, {})
      expect(instance.dependencies).to eq([])
    end
  end
end
```

- [ ] **Step 5: Run tests**

Run: `bundle exec rspec spec/services/code_generators/generator_interface_spec.rb -fd`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/services/code_generators/generator_interface.rb \
        app/services/code_generators/metadata_dsl.rb \
        spec/services/code_generators/generator_interface_spec.rb \
        spec/support/shared_examples/code_generator_interface.rb
git commit -m "feat: add GeneratorInterface, MetadataDSL, and shared examples for code generator contract"
```

---

## Task 2: BaseGenerator

**Files:**
- Create: `app/services/code_generators/base_generator.rb`
- Test: `spec/services/code_generators/base_generator_spec.rb`

- [ ] **Step 1: Write BaseGenerator spec**

```ruby
# spec/services/code_generators/base_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::BaseGenerator do
  # Concrete subclass for testing — simulates a step action
  let(:step_action_class) do
    Class.new(CodeGenerators::BaseGenerator) do
      def self.name = "CodeGenerators::StepActions::TestStepGenerator"

      generator_metadata do
        description "Test step"
        category :test
        version "1.0.0"
      end

      input_schema :input
      output_schema :output

      def generate
        "step code: #{config[:testKey]}"
      end

      def validate_config(cfg)
        []
      end
    end
  end

  # Concrete subclass for testing — simulates an element type
  let(:element_type_class) do
    Class.new(CodeGenerators::BaseGenerator) do
      def self.name = "CodeGenerators::ElementTypes::TestElementGenerator"

      generator_metadata do
        description "Test element"
        category :test
        version "1.0.0"
      end

      input_schema :input
      output_schema :output

      def generate
        "element code: #{config[:propKey]}"
      end

      def validate_config(cfg)
        []
      end
    end
  end

  describe "#initialize" do
    it "extracts config from element['config'] for step actions" do
      element = { "config" => { "testKey" => "hello" } }
      gen = step_action_class.new(element, {})
      expect(gen.generate).to eq("step code: hello")
    end

    it "extracts config from element['properties'] for element types" do
      element = { "properties" => { "propKey" => "world" } }
      gen = element_type_class.new(element, {})
      expect(gen.generate).to eq("element code: world")
    end

    it "provides indifferent access to config keys" do
      element = { "config" => { "testKey" => "value" } }
      gen = step_action_class.new(element, {})
      # Both string and symbol access should work
      expect(gen.generate).to include("value")
    end

    it "defaults to empty hash when config key is missing" do
      gen = step_action_class.new({}, {})
      expect(gen.generate).to eq("step code: ")
    end
  end

  describe "#apply_wrappers" do
    it "wraps with timeout when timeout > 0" do
      element = { "config" => {}, "timeout" => 5 }
      gen = step_action_class.new(element, {})
      code = gen.send(:apply_wrappers, "inner_code")
      expect(code).to include("Timeout.timeout(5)")
      expect(code).to include("inner_code")
    end

    it "wraps with retry when retryCount > 0" do
      element = { "config" => {}, "retryCount" => 3, "retryBackoff" => "exponential" }
      gen = step_action_class.new(element, {})
      code = gen.send(:apply_wrappers, "inner_code")
      expect(code).to include("retry_count = 3")
      expect(code).to include("sleep(2**attempt)")
    end

    it "wraps with guard when guardCondition present" do
      element = { "config" => {}, "guardCondition" => "ctx[:ready]" }
      gen = step_action_class.new(element, {})
      code = gen.send(:apply_wrappers, "inner_code")
      expect(code).to include("if ctx[:ready]")
      expect(code).to include("inner_code")
    end

    it "applies wrappers in order: guard -> retry -> timeout" do
      element = {
        "config" => {},
        "timeout" => 5,
        "retryCount" => 2,
        "guardCondition" => "ctx[:go]"
      }
      gen = step_action_class.new(element, {})
      code = gen.send(:apply_wrappers, "inner")
      # Guard is outermost
      guard_pos = code.index("if ctx[:go]")
      retry_pos = code.index("retry_count = 2")
      timeout_pos = code.index("Timeout.timeout(5)")
      expect(guard_pos).to be < retry_pos
      expect(retry_pos).to be < timeout_pos
    end

    it "returns code unchanged when no wrappers configured" do
      gen = step_action_class.new({ "config" => {} }, {})
      expect(gen.send(:apply_wrappers, "plain")).to eq("plain")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/base_generator_spec.rb -fd`
Expected: FAIL — `uninitialized constant CodeGenerators::BaseGenerator`

- [ ] **Step 3: Create BaseGenerator**

```ruby
# app/services/code_generators/base_generator.rb
# frozen_string_literal: true

module CodeGenerators
  class BaseGenerator
    include GeneratorInterface

    def initialize(element, context)
      @element = element
      @context = context
      @config = extract_config
    end

    protected

    attr_reader :element, :context, :config

    def apply_wrappers(code)
      code = wrap_with_timeout(code)
      code = wrap_with_retry(code)
      wrap_with_guard(code)
    end

    private

    def extract_config
      raw = if self.class.generator_kind == :element_type
              element.fetch("properties", {})
            else
              element.fetch("config", {})
            end
      (raw || {}).with_indifferent_access
    end

    def wrap_with_timeout(code)
      timeout = element["timeout"].to_i
      return code unless timeout > 0

      <<~RUBY.chomp
        Timeout.timeout(#{timeout}) do
        #{code.indent(2)}
        end
      RUBY
    end

    def wrap_with_retry(code)
      retry_count = element["retryCount"].to_i
      return code unless retry_count > 0

      backoff = element["retryBackoff"] || "none"
      sleep_line = case backoff
                   when "linear"      then "\n    sleep(attempt)"
                   when "exponential" then "\n    sleep(2**attempt)"
                   else ""
                   end

      <<~RUBY.chomp
        retry_count = #{retry_count}
        attempt = 0
        begin
        #{code.indent(2)}
        rescue => e
          attempt += 1
          if attempt <= retry_count#{sleep_line}
            retry
          else
            raise e
          end
        end
      RUBY
    end

    def wrap_with_guard(code)
      guard = element["guardCondition"].to_s.strip
      return code if guard.empty?

      <<~RUBY.chomp
        if #{guard}
        #{code.indent(2)}
        else
          true
        end
      RUBY
    end
  end
end
```

- [ ] **Step 4: Run spec**

Run: `bundle exec rspec spec/services/code_generators/base_generator_spec.rb -fd`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/base_generator.rb \
        spec/services/code_generators/base_generator_spec.rb
git commit -m "feat: add BaseGenerator with config extraction and wrapper pipeline"
```
