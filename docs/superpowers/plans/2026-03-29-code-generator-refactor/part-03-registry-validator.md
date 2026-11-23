# Part 3: GeneratorRegistry + GeneratorValidator

## Task 6: GeneratorRegistry

**Files:**
- Create: `app/services/code_generators/generator_registry.rb`
- Test: `spec/services/code_generators/generator_registry_spec.rb`

- [ ] **Step 1: Write GeneratorRegistry spec**

```ruby
# spec/services/code_generators/generator_registry_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::GeneratorRegistry do
  # Reset singleton between tests
  before { described_class.instance_variable_set(:@instance, nil) }
  after  { described_class.instance_variable_set(:@instance, nil) }

  describe ".instance" do
    it "returns a singleton" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe "#discover!" do
    it "discovers generator files from step_actions directory" do
      registry = described_class.instance
      # Will find generators once they exist; for now verify the registry initializes
      expect(registry.step_action_generators).to be_a(Hash)
    end

    it "discovers generator files from element_types directory" do
      registry = described_class.instance
      expect(registry.element_type_generators).to be_a(Hash)
    end
  end

  describe "#find_step_action" do
    it "returns nil for unknown action" do
      registry = described_class.instance
      expect(registry.find_step_action("nonexistent")).to be_nil
    end
  end

  describe "#find_element_type" do
    it "returns nil for unknown type" do
      registry = described_class.instance
      expect(registry.find_element_type("nonexistent")).to be_nil
    end
  end

  describe "#reload!" do
    it "clears and re-discovers generators" do
      registry = described_class.instance
      count_before = registry.all_generators.size
      registry.reload!
      expect(registry.all_generators.size).to eq(count_before)
    end
  end

  describe "registered_names support" do
    it "registers generators under all their registered_names" do
      # This test will be meaningful once generators with aliases exist
      # (e.g., ValidateContractGenerator with ["validate_contract", "validate"])
      registry = described_class.instance
      expect(registry).to respond_to(:find_step_action)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/generator_registry_spec.rb -fd`
Expected: FAIL — `uninitialized constant`

- [ ] **Step 3: Create GeneratorRegistry**

```ruby
# app/services/code_generators/generator_registry.rb
# frozen_string_literal: true

module CodeGenerators
  class GeneratorRegistry
    class << self
      def instance
        @instance ||= new
      end

      delegate :find_step_action, :find_element_type, :all_generators,
               :step_action_generators, :element_type_generators, :reload!, to: :instance
    end

    def initialize
      @step_actions = {}
      @element_types = {}
      discover!
    end

    def find_step_action(action_name)
      @step_actions[action_name.to_s]
    end

    def find_element_type(type_name)
      @element_types[type_name.to_s]
    end

    def all_generators
      @step_actions.merge(@element_types)
    end

    def step_action_generators
      @step_actions.dup
    end

    def element_type_generators
      @element_types.dup
    end

    def reload!
      @step_actions.clear
      @element_types.clear
      discover!
    end

    private

    STEP_ACTIONS_PATH = Rails.root.join("app/services/code_generators/step_actions")
    ELEMENT_TYPES_PATH = Rails.root.join("app/services/code_generators/element_types")

    def discover!
      scan_directory(STEP_ACTIONS_PATH, @step_actions)
      scan_directory(ELEMENT_TYPES_PATH, @element_types)
    end

    def scan_directory(dir, registry)
      return unless dir.exist?

      Dir[dir.join("*.rb")].each do |file|
        klass = class_from_file(file)
        next unless klass
        next unless klass.respond_to?(:registered_names)

        klass.registered_names.each do |name|
          registry[name] = klass
        end
      end
    end

    def class_from_file(file)
      relative = Pathname.new(file).relative_path_from(Rails.root.join("app/services"))
      relative.to_s
              .delete_suffix(".rb")
              .camelize
              .constantize
    rescue NameError, LoadError => e
      Rails.logger.warn("CodeGeneratorRegistry: Failed to load #{file}: #{e.message}")
      nil
    end
  end
end
```

- [ ] **Step 4: Run spec**

Run: `bundle exec rspec spec/services/code_generators/generator_registry_spec.rb -fd`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/generator_registry.rb \
        spec/services/code_generators/generator_registry_spec.rb
git commit -m "feat: add GeneratorRegistry with convention-based auto-discovery"
```

---

## Task 7: GeneratorValidator

**Files:**
- Create: `app/services/code_generators/generator_validator.rb`
- Test: `spec/services/code_generators/generator_validator_spec.rb`

- [ ] **Step 1: Write GeneratorValidator spec**

```ruby
# spec/services/code_generators/generator_validator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::GeneratorValidator do
  describe ".validate_source" do
    let(:valid_source) do
      <<~RUBY
        class CodeGenerators::StepActions::TestGenerator < CodeGenerators::BaseGenerator
          generator_metadata do
            description "Test"
            category :test
            version "1.0.0"
          end

          def generate
            "true"
          end

          def validate_config(config)
            []
          end
        end
      RUBY
    end

    it "returns empty array for valid source" do
      expect(described_class.validate_source(valid_source)).to eq([])
    end

    it "catches syntax errors" do
      errors = described_class.validate_source("def foo(")
      expect(errors.first).to start_with("Syntax error:")
    end

    it "rejects missing BaseGenerator inheritance" do
      source = valid_source.gsub("< CodeGenerators::BaseGenerator", "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Must inherit from CodeGenerators::BaseGenerator")
    end

    it "rejects missing generate method" do
      source = valid_source.gsub(/def generate.*?end/m, "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Missing required method: generate")
    end

    it "rejects missing validate_config method" do
      source = valid_source.gsub(/def validate_config.*?end/m, "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Missing required method: validate_config")
    end

    it "rejects missing generator_metadata block" do
      source = valid_source.gsub(/generator_metadata do.*?end/m, "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Missing generator_metadata block")
    end

    it "rejects missing metadata fields" do
      source = valid_source.gsub(/description "Test"/, "")
      errors = described_class.validate_source(source)
      expect(errors).to include("Missing metadata: description")
    end

    it "stops after syntax errors (does not check interface)" do
      errors = described_class.validate_source("def foo(")
      expect(errors.length).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/generator_validator_spec.rb -fd`
Expected: FAIL

- [ ] **Step 3: Create GeneratorValidator**

```ruby
# app/services/code_generators/generator_validator.rb
# frozen_string_literal: true

module CodeGenerators
  class GeneratorValidator
    REQUIRED_METHODS = %i[generate validate_config].freeze
    REQUIRED_METADATA = %i[description category version].freeze

    class << self
      def validate_source(source)
        errors = []
        errors.concat(check_syntax(source))
        return errors if errors.any?

        errors.concat(check_interface(source))
        errors.concat(check_metadata(source))
        errors
      end

      private

      def check_syntax(source)
        RubyVM::InstructionSequence.compile(source)
        []
      rescue SyntaxError => e
        ["Syntax error: #{e.message}"]
      end

      def check_interface(source)
        errors = []

        unless source.match?(/< CodeGenerators::BaseGenerator/)
          errors << "Must inherit from CodeGenerators::BaseGenerator"
        end

        REQUIRED_METHODS.each do |method|
          unless source.match?(/def\s+#{method}\b/)
            errors << "Missing required method: #{method}"
          end
        end

        errors
      end

      def check_metadata(source)
        errors = []

        unless source.match?(/generator_metadata/)
          errors << "Missing generator_metadata block"
          return errors
        end

        REQUIRED_METADATA.each do |field|
          unless source.match?(/^\s+#{field}\s+/)
            errors << "Missing metadata: #{field}"
          end
        end

        errors
      end
    end
  end
end
```

- [ ] **Step 4: Run spec**

Run: `bundle exec rspec spec/services/code_generators/generator_validator_spec.rb -fd`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/generator_validator.rb \
        spec/services/code_generators/generator_validator_spec.rb
git commit -m "feat: add GeneratorValidator with syntax and interface checks"
```

- [ ] **Step 6: Run all infrastructure specs**

Run: `bundle exec rspec spec/services/code_generators/ -fd`
Expected: All tests PASS (interface, base, 3 shared modules, registry, validator)
