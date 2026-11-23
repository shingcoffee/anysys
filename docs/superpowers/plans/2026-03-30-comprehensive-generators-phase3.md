# Comprehensive Generators Phase 3 — Switch & Transaction Structural Elements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 2 new structural element type generators: Switch (multi-way branching) and Transaction (DB transaction wrapper).

**Architecture:** Both follow the existing element type generator pattern under `element_types/<type_name>/`. Switch extends the branching pattern established by Decision. Transaction extends the wrapping pattern established by Loop. Both use `element["properties"]` for configuration and belong to the `:flow_control` category.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec

---

## File Structure

| File | Purpose |
|------|---------|
| `app/services/code_generators/element_types/switch/switch_generator.rb` | Multi-way branching via case/when |
| `app/services/code_generators/element_types/transaction/transaction_generator.rb` | DB transaction wrapper with isolation options |
| `spec/services/code_generators/element_types/switch/switch_generator_spec.rb` | Switch tests |
| `spec/services/code_generators/element_types/transaction/transaction_generator_spec.rb` | Transaction tests |

---

### Task 1: Switch generator

**Files:**
- Create: `spec/services/code_generators/element_types/switch/switch_generator_spec.rb`
- Create: `app/services/code_generators/element_types/switch/switch_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/switch/switch_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Switch::SwitchGenerator do
  let(:element) do
    {
      "properties" => {
        "sourceVariable" => "status",
        "cases" => [
          { "value" => "active", "label" => "handle_active" },
          { "value" => "pending", "label" => "handle_pending" }
        ],
        "defaultLabel" => "handle_unknown"
      }
    }
  end
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates a case/when statement with all cases and default" do
      gen = described_class.new(element, context)
      code = gen.generate
      expect(code).to include('_switch_val = ctx[:status].to_s')
      expect(code).to include('case _switch_val')
      expect(code).to include('when "active" then :handle_active')
      expect(code).to include('when "pending" then :handle_pending')
      expect(code).to include('else :handle_unknown')
    end

    it "generates else true when no defaultLabel" do
      el = {
        "properties" => {
          "sourceVariable" => "role",
          "cases" => [
            { "value" => "admin", "label" => "admin_path" }
          ]
        }
      }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include('_switch_val = ctx[:role].to_s')
      expect(code).to include('when "admin" then :admin_path')
      expect(code).to include('else true')
      expect(code).not_to include('else :')
    end

    it "generates fallback comment when no cases configured" do
      el = { "properties" => { "sourceVariable" => "x", "cases" => [] } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("no cases configured")
      expect(code).to include("true")
    end

    it "generates fallback comment when cases is nil" do
      el = { "properties" => { "sourceVariable" => "x" } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("no cases configured")
    end

    it "handles multiple cases correctly" do
      el = {
        "properties" => {
          "sourceVariable" => "priority",
          "cases" => [
            { "value" => "low", "label" => "low_priority" },
            { "value" => "medium", "label" => "medium_priority" },
            { "value" => "high", "label" => "high_priority" },
            { "value" => "critical", "label" => "critical_priority" }
          ],
          "defaultLabel" => "normal_priority"
        }
      }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include('when "low" then :low_priority')
      expect(code).to include('when "medium" then :medium_priority')
      expect(code).to include('when "high" then :high_priority')
      expect(code).to include('when "critical" then :critical_priority')
      expect(code).to include('else :normal_priority')
    end
  end

  describe "#validate_config" do
    it "returns no errors for valid config" do
      gen = described_class.new(element, context)
      errors = gen.validate_config(element["properties"])
      expect(errors).to be_empty
    end

    it "returns error when sourceVariable is blank" do
      errors = described_class.new(element, {}).validate_config({ "cases" => [{ "value" => "a", "label" => "b" }] })
      expect(errors).to include("sourceVariable is required")
    end

    it "returns error when cases is empty" do
      errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "x", "cases" => [] })
      expect(errors).to include("cases must be a non-empty array")
    end

    it "returns error when cases is missing" do
      errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "x" })
      expect(errors).to include("cases must be a non-empty array")
    end

    it "returns error when cases is not an array" do
      errors = described_class.new(element, {}).validate_config({ "sourceVariable" => "x", "cases" => "not_array" })
      expect(errors).to include("cases must be a non-empty array")
    end
  end

  describe "#example_output" do
    it "returns a sample switch statement" do
      gen = described_class.new(element, context)
      example = gen.example_output
      expect(example).to include("case _switch_val")
      expect(example).to include("when")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/switch/switch_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant CodeGenerators::ElementTypes::Switch`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/switch/switch_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Switch
      class SwitchGenerator < BaseGenerator
        generator_metadata do
          description "Generates multi-way branching via case/when on a source variable"
          category :flow_control
          version "1.0.0"
        end

        input_schema  :source_variable, :cases
        output_schema # none — routes via return symbol

        def generate
          source = config["sourceVariable"] || "value"
          cases = config["cases"]
          default_label = config["defaultLabel"]

          return "# Switch: no cases configured\ntrue" if cases.blank?

          when_clauses = cases.map { |c| "when #{c['value'].to_s.inspect} then :#{c['label']}" }
          else_clause = default_label.present? ? "else :#{default_label}" : "else true"

          <<~RUBY.chomp
            _switch_val = ctx[:#{source}].to_s
            case _switch_val
            #{when_clauses.join("\n")}
            #{else_clause}
            end
          RUBY
        end

        def validate_config(cfg)
          errors = []
          errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
          cases = cfg["cases"]
          if !cases.is_a?(Array) || cases.empty?
            errors << "cases must be a non-empty array"
          end
          errors
        end

        def example_output
          <<~RUBY.chomp
            _switch_val = ctx[:status].to_s
            case _switch_val
            when "active" then :handle_active
            when "inactive" then :handle_inactive
            else true
            end
          RUBY
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/switch/switch_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/switch/switch_generator.rb \
  spec/services/code_generators/element_types/switch/switch_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add Switch structural element generator

Multi-way branching via case/when on a source variable.
Reads sourceVariable, cases array, and optional defaultLabel
from element properties. Returns routing symbols.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Transaction generator

**Files:**
- Create: `spec/services/code_generators/element_types/transaction/transaction_generator_spec.rb`
- Create: `app/services/code_generators/element_types/transaction/transaction_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/transaction/transaction_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Transaction::TransactionGenerator do
  let(:element) { { "properties" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    it "generates a basic transaction with no options" do
      gen = described_class.new(element, context)
      code = gen.generate
      expect(code).to include("ActiveRecord::Base.transaction do")
      expect(code).to include("# Child steps execute within this transaction")
      expect(code).to include("end")
      expect(code.strip).to end_with("true")
      expect(code).not_to include("isolation:")
      expect(code).not_to include("requires_new:")
    end

    it "generates a transaction with isolation level" do
      el = { "properties" => { "isolationLevel" => "serializable" } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("ActiveRecord::Base.transaction(isolation: :serializable) do")
      expect(code).to include("# Child steps execute within this transaction")
      expect(code.strip).to end_with("true")
      expect(code).not_to include("requires_new:")
    end

    it "generates a transaction with requires_new" do
      el = { "properties" => { "requiresNew" => true } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("ActiveRecord::Base.transaction(requires_new: true) do")
      expect(code).to include("# Child steps execute within this transaction")
      expect(code.strip).to end_with("true")
      expect(code).not_to include("isolation:")
    end

    it "generates a transaction with both isolation level and requires_new" do
      el = { "properties" => { "isolationLevel" => "repeatable_read", "requiresNew" => true } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("ActiveRecord::Base.transaction(isolation: :repeatable_read, requires_new: true) do")
      expect(code).to include("# Child steps execute within this transaction")
      expect(code.strip).to end_with("true")
    end

    it "generates a transaction with read_committed isolation" do
      el = { "properties" => { "isolationLevel" => "read_committed" } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("ActiveRecord::Base.transaction(isolation: :read_committed) do")
    end

    it "ignores requires_new when false" do
      el = { "properties" => { "requiresNew" => false } }
      gen = described_class.new(el, {})
      code = gen.generate
      expect(code).to include("ActiveRecord::Base.transaction do")
      expect(code).not_to include("requires_new:")
    end
  end

  describe "#validate_config" do
    it "returns no errors for empty config" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({})
      expect(errors).to be_empty
    end

    it "returns no errors for valid isolation level" do
      gen = described_class.new(element, context)
      %w[read_committed repeatable_read serializable].each do |level|
        errors = gen.validate_config({ "isolationLevel" => level })
        expect(errors).to be_empty, "Expected no errors for isolation level '#{level}'"
      end
    end

    it "returns error for invalid isolation level" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({ "isolationLevel" => "read_uncommitted" })
      expect(errors).to include(/Invalid isolation level/)
    end
  end

  describe "#example_output" do
    it "returns a simple transaction example" do
      gen = described_class.new(element, context)
      example = gen.example_output
      expect(example).to include("ActiveRecord::Base.transaction do")
      expect(example).to include("true")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/transaction/transaction_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant CodeGenerators::ElementTypes::Transaction`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/transaction/transaction_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Transaction
      class TransactionGenerator < BaseGenerator
        ISOLATION_LEVELS = %w[read_committed repeatable_read serializable].freeze

        generator_metadata do
          description "Wraps child steps in an ActiveRecord database transaction with optional isolation level"
          category :flow_control
          version "1.0.0"
        end

        input_schema  :isolation_level
        output_schema # none

        def generate
          isolation = config["isolationLevel"].presence
          requires_new = config["requiresNew"] == true

          opts = build_options(isolation, requires_new)
          transaction_call = opts.empty? ? "ActiveRecord::Base.transaction do" : "ActiveRecord::Base.transaction(#{opts}) do"

          <<~RUBY.chomp
            #{transaction_call}
              # Child steps execute within this transaction
            end
            true
          RUBY
        end

        def validate_config(cfg)
          errors = []
          isolation = cfg["isolationLevel"]
          if isolation.present? && !ISOLATION_LEVELS.include?(isolation)
            errors << "Invalid isolation level: #{isolation}. Must be one of: #{ISOLATION_LEVELS.join(', ')}"
          end
          errors
        end

        def example_output
          <<~RUBY.chomp
            ActiveRecord::Base.transaction do
              # Child steps execute within this transaction
            end
            true
          RUBY
        end

        private

        def build_options(isolation, requires_new)
          parts = []
          parts << "isolation: :#{isolation}" if isolation.present?
          parts << "requires_new: true" if requires_new
          parts.join(", ")
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/transaction/transaction_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add \
  app/services/code_generators/element_types/transaction/transaction_generator.rb \
  spec/services/code_generators/element_types/transaction/transaction_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add Transaction structural element generator

Wraps child steps in ActiveRecord::Base.transaction with optional
isolation level (read_committed, repeatable_read, serializable)
and requires_new flag. Reads config from element properties.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Final verification

- [ ] **Step 1: Run all new structural element specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/switch/ spec/services/code_generators/element_types/transaction/ --format documentation`
Expected: All pass

- [ ] **Step 2: Run all existing structural element specs to verify no regressions**

Run: `bundle exec rspec spec/services/code_generators/element_types/decision/ spec/services/code_generators/element_types/loop/ spec/services/code_generators/element_types/fork/ spec/services/code_generators/element_types/start/ spec/services/code_generators/element_types/end/ spec/services/code_generators/element_types/timer/ spec/services/code_generators/element_types/subflow/ spec/services/code_generators/element_types/error_handler/ --format documentation`
Expected: All pass — no regressions

- [ ] **Step 3: Verify generators are auto-discovered by registry**

Run: `bundle exec rails runner "CodeGenerators::GeneratorRegistry.reload!; puts CodeGenerators::GeneratorRegistry.element_type_generators.keys.sort.join(', ')"`
Expected: Output includes `switch` and `transaction` among the existing element type generator names (decision, end, error_handler, fork, join, loop, start, subflow, timer)

- [ ] **Step 4: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass, no regressions
