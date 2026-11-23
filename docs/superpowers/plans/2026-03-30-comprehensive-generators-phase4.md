# Comprehensive Generators Phase 4 — Complex Structural Elements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 3 complex structural element type generators: Saga (compensation/rollback), SignalWait (pause for external event), and ParallelForEach (concurrent iteration).

**Architecture:** All follow the existing element type generator pattern under `element_types/<type_name>/`. These are the most complex generators — Saga handles compensation stacks, SignalWait handles workflow suspension, and ParallelForEach handles concurrent execution. All use `element["properties"]` for configuration and belong to the `:flow_control` category.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec

---

## File Structure

| File | Purpose |
|------|---------|
| `app/services/code_generators/element_types/saga/saga_generator.rb` | Saga compensation/rollback wrapper |
| `app/services/code_generators/element_types/signal_wait/signal_wait_generator.rb` | Pause workflow for external signal |
| `app/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator.rb` | Concurrent iteration over collection |
| `spec/services/code_generators/element_types/saga/saga_generator_spec.rb` | Saga tests |
| `spec/services/code_generators/element_types/signal_wait/signal_wait_generator_spec.rb` | SignalWait tests |
| `spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb` | ParallelForEach tests |

---

## Key Conventions (Structural Element Type Generators)

- Module nesting: `CodeGenerators::ElementTypes::<TypeName>::<TypeName>Generator` (NO `Process` module)
- Config source: `element["properties"]` (NOT `element["config"]`)
- Test element: `let(:element) { { "properties" => { ... } } }`
- Category is always `:flow_control`
- `generator_kind` returns `:element_type` (auto-detected by class path not containing `Process`)
- Auto-discovered by `GeneratorRegistry` scanning `element_types/` subdirectories (excluding `process/`)

---

### Task 1: Saga Generator

**Files:**
- Create: `spec/services/code_generators/element_types/saga/saga_generator_spec.rb`
- Create: `app/services/code_generators/element_types/saga/saga_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/saga/saga_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Saga::SagaGenerator do
  let(:element) { { "properties" => { "compensationMode" => "reverse_all" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    context "with reverse_all mode (default)" do
      it "generates compensation wrapper with reverse_each" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("# Saga: compensation wrapper (reverse_all)")
        expect(code).to include("ctx[:_compensations] = []")
        expect(code).to include("ctx[:_compensations].reverse_each")
        expect(code).to include("compensation.call rescue nil")
        expect(code).to include("raise e")
      end

      it "does not include step index tracking" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).not_to include("_saga_step_index")
      end
    end

    context "with reverse_from_failure mode" do
      let(:element) { { "properties" => { "compensationMode" => "reverse_from_failure" } } }

      it "generates compensation wrapper with step index tracking" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("# Saga: compensation wrapper (reverse_from_failure)")
        expect(code).to include("ctx[:_saga_step_index] = 0")
        expect(code).to include("failed_at = ctx[:_saga_step_index]")
        expect(code).to include("ctx[:_compensations].first(failed_at).reverse_each")
      end
    end

    context "with compensationTimeout" do
      let(:element) { { "properties" => { "compensationMode" => "reverse_all", "compensationTimeout" => 30 } } }

      it "wraps compensation block in Timeout" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("with timeout")
        expect(code).to include("Timeout.timeout(30)")
        expect(code).to include("ctx[:_compensations].reverse_each")
      end
    end

    context "with reverse_from_failure and timeout" do
      let(:element) { { "properties" => { "compensationMode" => "reverse_from_failure", "compensationTimeout" => 60 } } }

      it "wraps partial compensation in Timeout" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("Timeout.timeout(60)")
        expect(code).to include("ctx[:_compensations].first(failed_at).reverse_each")
      end
    end

    context "with default mode (no compensationMode specified)" do
      let(:element) { { "properties" => {} } }

      it "defaults to reverse_all" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("# Saga: compensation wrapper (reverse_all)")
      end
    end
  end

  describe "#validate_config" do
    it "returns no errors for valid config" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({ "compensationMode" => "reverse_all" })
      expect(errors).to be_empty
    end

    it "returns error for invalid compensationMode" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({ "compensationMode" => "invalid_mode" })
      expect(errors).to include(/Invalid compensation mode/)
    end

    it "accepts empty config (defaults apply)" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({})
      expect(errors).to be_empty
    end
  end

  describe "#example_output" do
    it "returns a reverse_all saga example" do
      gen = described_class.new(element, context)
      example = gen.example_output
      expect(example).to include("_compensations")
      expect(example).to include("reverse_each")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/saga/saga_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant CodeGenerators::ElementTypes::Saga`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/saga/saga_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Saga
      class SagaGenerator < BaseGenerator
        COMPENSATION_MODES = %w[reverse_all reverse_from_failure].freeze

        generator_metadata do
          description "Generates saga compensation/rollback wrapper with configurable compensation modes"
          category :flow_control
          version "1.0.0"
        end

        input_schema  :compensation_mode
        output_schema :_compensations

        def generate
          mode = config["compensationMode"] || "reverse_all"
          timeout = config["compensationTimeout"]

          case mode
          when "reverse_from_failure" then generate_reverse_from_failure(timeout)
          else                             generate_reverse_all(timeout)
          end
        end

        def validate_config(cfg)
          errors = []
          if cfg["compensationMode"].present? && !COMPENSATION_MODES.include?(cfg["compensationMode"])
            errors << "Invalid compensation mode: #{cfg['compensationMode']}. Must be one of: #{COMPENSATION_MODES.join(', ')}"
          end
          errors
        end

        def example_output
          <<~RUBY.chomp
            # Saga: compensation wrapper (reverse_all)
            ctx[:_compensations] = []
            begin
              # Child steps execute here
              # Each step can register: ctx[:_compensations] << -> { undo_code }
              true
            rescue => e
              ctx[:_compensations].reverse_each do |compensation|
                compensation.call rescue nil
              end
              raise e
            end
          RUBY
        end

        private

        def generate_reverse_all(timeout)
          compensation_block = build_compensation_block("ctx[:_compensations].reverse_each do |compensation|\n    compensation.call rescue nil\n  end", timeout)

          <<~RUBY.chomp
            # Saga: compensation wrapper (reverse_all)#{timeout ? " with timeout" : ""}
            ctx[:_compensations] = []
            begin
              # Child steps execute here
              # Each step can register: ctx[:_compensations] << -> { undo_code }
              true
            rescue => e
              #{compensation_block}
              raise e
            end
          RUBY
        end

        def generate_reverse_from_failure(timeout)
          rollback_code = "ctx[:_compensations].first(failed_at).reverse_each do |compensation|\n    compensation.call rescue nil\n  end"
          compensation_block = build_compensation_block(rollback_code, timeout)

          <<~RUBY.chomp
            # Saga: compensation wrapper (reverse_from_failure)#{timeout ? " with timeout" : ""}
            ctx[:_compensations] = []
            ctx[:_saga_step_index] = 0
            begin
              # Child steps execute here
              # Each step increments ctx[:_saga_step_index] and registers compensation
              true
            rescue => e
              failed_at = ctx[:_saga_step_index]
              #{compensation_block}
              raise e
            end
          RUBY
        end

        def build_compensation_block(rollback_code, timeout)
          if timeout.present? && timeout.to_i > 0
            "Timeout.timeout(#{timeout.to_i}) do\n    #{rollback_code}\n  end"
          else
            rollback_code
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/saga/saga_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/saga/saga_generator.rb spec/services/code_generators/element_types/saga/saga_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add Saga structural element generator

Implements compensation/rollback wrapper with two modes:
- reverse_all: rolls back all registered compensations
- reverse_from_failure: rolls back only compensations up to failure point
Optional compensationTimeout wraps rollback in Timeout.timeout.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: SignalWait Generator

**Files:**
- Create: `spec/services/code_generators/element_types/signal_wait/signal_wait_generator_spec.rb`
- Create: `app/services/code_generators/element_types/signal_wait/signal_wait_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/signal_wait/signal_wait_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::SignalWait::SignalWaitGenerator do
  let(:element) { { "properties" => { "signalName" => "approval", "waitMode" => "pause_and_resume" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    context "pause_and_resume mode without timeout" do
      it "generates cache-based signal wait" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include('# SignalWait: pause and resume for signal "approval"')
        expect(code).to include('_signal_key = "workflow_signal:#{ctx[:_workflow_id]}:approval"')
        expect(code).to include("Rails.cache.write(_signal_key")
        expect(code).to include("status: \"waiting\"")
        expect(code).to include("ctx[:signal_result] = _signal_data[:payload]")
      end

      it "does not include timeout logic" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).not_to include("timeout")
        expect(code).not_to include("Timeout")
      end
    end

    context "pause_and_resume mode with timeout (fail action)" do
      let(:element) { { "properties" => { "signalName" => "approval", "waitMode" => "pause_and_resume", "timeoutSeconds" => 600, "timeoutAction" => "fail" } } }

      it "generates signal wait with timeout metadata and raise" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("timeout: 600")
        expect(code).to include('raise "Signal timeout: approval"')
      end
    end

    context "pause_and_resume mode with timeout (continue action)" do
      let(:element) { { "properties" => { "signalName" => "approval", "waitMode" => "pause_and_resume", "timeoutSeconds" => 600, "timeoutAction" => "continue" } } }

      it "generates signal wait with nil result on timeout" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("timeout: 600")
        expect(code).to include("ctx[:signal_result] = nil")
        expect(code).not_to include("raise")
      end
    end

    context "poll mode with timeout (fail action)" do
      let(:element) { { "properties" => { "signalName" => "data_ready", "waitMode" => "poll", "timeoutSeconds" => 300, "timeoutAction" => "fail" } } }

      it "generates polling loop with deadline and raise" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include('# SignalWait: poll for signal "data_ready"')
        expect(code).to include("_deadline = Time.current + 300")
        expect(code).to include("loop do")
        expect(code).to include('_signal_data[:status] == "received"')
        expect(code).to include("ctx[:signal_result] = _signal_data[:payload]")
        expect(code).to include('raise "Signal timeout: data_ready"')
        expect(code).to include("sleep 2")
      end
    end

    context "poll mode with timeout (continue action)" do
      let(:element) { { "properties" => { "signalName" => "optional_data", "waitMode" => "poll", "timeoutSeconds" => 60, "timeoutAction" => "continue" } } }

      it "generates polling loop with nil result on timeout" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include('# SignalWait: poll for signal "optional_data"')
        expect(code).to include("_deadline = Time.current + 60")
        expect(code).to include("ctx[:signal_result] = nil")
        expect(code).not_to include("raise")
      end
    end

    context "poll mode without timeout" do
      let(:element) { { "properties" => { "signalName" => "event", "waitMode" => "poll" } } }

      it "generates polling loop without deadline" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("loop do")
        expect(code).not_to include("_deadline")
        expect(code).not_to include("raise")
      end
    end

    context "default wait mode" do
      let(:element) { { "properties" => { "signalName" => "test" } } }

      it "defaults to pause_and_resume" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("pause and resume")
      end
    end
  end

  describe "#validate_config" do
    it "returns error when signalName is missing" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({})
      expect(errors).to include("signalName is required")
    end

    it "returns no errors for valid config" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({ "signalName" => "approval", "waitMode" => "pause_and_resume" })
      expect(errors).to be_empty
    end

    it "returns error for invalid waitMode" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({ "signalName" => "x", "waitMode" => "invalid" })
      expect(errors).to include(/Invalid wait mode/)
    end

    it "returns error for invalid timeoutAction" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({ "signalName" => "x", "timeoutAction" => "invalid" })
      expect(errors).to include(/Invalid timeout action/)
    end
  end

  describe "#example_output" do
    it "returns a pause_and_resume example" do
      gen = described_class.new(element, context)
      example = gen.example_output
      expect(example).to include("workflow_signal")
      expect(example).to include("signal_result")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/signal_wait/signal_wait_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant CodeGenerators::ElementTypes::SignalWait`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/signal_wait/signal_wait_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module SignalWait
      class SignalWaitGenerator < BaseGenerator
        WAIT_MODES = %w[pause_and_resume poll].freeze
        TIMEOUT_ACTIONS = %w[fail continue].freeze

        generator_metadata do
          description "Generates signal wait code for workflow suspension (pause/resume or polling)"
          category :flow_control
          version "1.0.0"
        end

        input_schema  :signal_name
        output_schema :signal_result

        def generate
          signal_name = config["signalName"] || "signal"
          wait_mode = config["waitMode"] || "pause_and_resume"
          timeout = config["timeoutSeconds"]
          timeout_action = config["timeoutAction"] || "fail"

          case wait_mode
          when "poll" then generate_poll(signal_name, timeout, timeout_action)
          else             generate_pause_and_resume(signal_name, timeout, timeout_action)
          end
        end

        def validate_config(cfg)
          errors = []
          errors << "signalName is required" if cfg["signalName"].blank?
          if cfg["waitMode"].present? && !WAIT_MODES.include?(cfg["waitMode"])
            errors << "Invalid wait mode: #{cfg['waitMode']}. Must be one of: #{WAIT_MODES.join(', ')}"
          end
          if cfg["timeoutAction"].present? && !TIMEOUT_ACTIONS.include?(cfg["timeoutAction"])
            errors << "Invalid timeout action: #{cfg['timeoutAction']}. Must be one of: #{TIMEOUT_ACTIONS.join(', ')}"
          end
          errors
        end

        def example_output
          <<~RUBY.chomp
            # SignalWait: pause and resume for signal "approval"
            _signal_key = "workflow_signal:\#{ctx[:_workflow_id]}:approval"
            Rails.cache.write(_signal_key, { status: "waiting", since: Time.current })
            # Workflow engine suspends here; resumes when signal received
            _signal_data = Rails.cache.read(_signal_key)
            ctx[:signal_result] = _signal_data[:payload] if _signal_data.is_a?(Hash)
            true
          RUBY
        end

        private

        def generate_pause_and_resume(signal_name, timeout, timeout_action)
          if timeout.present? && timeout.to_i > 0
            generate_pause_with_timeout(signal_name, timeout.to_i, timeout_action)
          else
            generate_pause_simple(signal_name)
          end
        end

        def generate_pause_simple(signal_name)
          <<~RUBY.chomp
            # SignalWait: pause and resume for signal "#{signal_name}"
            _signal_key = "workflow_signal:\#{ctx[:_workflow_id]}:#{signal_name}"
            Rails.cache.write(_signal_key, { status: "waiting", since: Time.current })
            # Workflow engine suspends here; resumes when signal received
            _signal_data = Rails.cache.read(_signal_key)
            ctx[:signal_result] = _signal_data[:payload] if _signal_data.is_a?(Hash)
            true
          RUBY
        end

        def generate_pause_with_timeout(signal_name, timeout, timeout_action)
          timeout_handler = if timeout_action == "continue"
                              "  ctx[:signal_result] = nil"
                            else
                              "  raise \"Signal timeout: #{signal_name}\""
                            end

          <<~RUBY.chomp
            # SignalWait: pause and resume for signal "#{signal_name}" (timeout: #{timeout}s)
            _signal_key = "workflow_signal:\#{ctx[:_workflow_id]}:#{signal_name}"
            Rails.cache.write(_signal_key, { status: "waiting", since: Time.current, timeout: #{timeout} })
            # Workflow engine suspends here; resumes when signal received or timeout
            _signal_data = Rails.cache.read(_signal_key)
            if _signal_data.is_a?(Hash) && _signal_data[:status] == "received"
              ctx[:signal_result] = _signal_data[:payload]
            else
            #{timeout_handler}
            end
            true
          RUBY
        end

        def generate_poll(signal_name, timeout, timeout_action)
          if timeout.present? && timeout.to_i > 0
            generate_poll_with_timeout(signal_name, timeout.to_i, timeout_action)
          else
            generate_poll_simple(signal_name)
          end
        end

        def generate_poll_simple(signal_name)
          <<~RUBY.chomp
            # SignalWait: poll for signal "#{signal_name}"
            _signal_key = "workflow_signal:\#{ctx[:_workflow_id]}:#{signal_name}"
            loop do
              _signal_data = Rails.cache.read(_signal_key)
              if _signal_data.is_a?(Hash) && _signal_data[:status] == "received"
                ctx[:signal_result] = _signal_data[:payload]
                break
              end
              sleep 2
            end
            true
          RUBY
        end

        def generate_poll_with_timeout(signal_name, timeout, timeout_action)
          if timeout_action == "continue"
            generate_poll_timeout_continue(signal_name, timeout)
          else
            generate_poll_timeout_fail(signal_name, timeout)
          end
        end

        def generate_poll_timeout_fail(signal_name, timeout)
          <<~RUBY.chomp
            # SignalWait: poll for signal "#{signal_name}"
            _signal_key = "workflow_signal:\#{ctx[:_workflow_id]}:#{signal_name}"
            _deadline = Time.current + #{timeout}
            loop do
              _signal_data = Rails.cache.read(_signal_key)
              if _signal_data.is_a?(Hash) && _signal_data[:status] == "received"
                ctx[:signal_result] = _signal_data[:payload]
                break
              end
              if Time.current > _deadline
                raise "Signal timeout: #{signal_name}"
              end
              sleep 2
            end
            true
          RUBY
        end

        def generate_poll_timeout_continue(signal_name, timeout)
          <<~RUBY.chomp
            # SignalWait: poll for signal "#{signal_name}"
            _signal_key = "workflow_signal:\#{ctx[:_workflow_id]}:#{signal_name}"
            _deadline = Time.current + #{timeout}
            _received = false
            loop do
              _signal_data = Rails.cache.read(_signal_key)
              if _signal_data.is_a?(Hash) && _signal_data[:status] == "received"
                ctx[:signal_result] = _signal_data[:payload]
                _received = true
                break
              end
              if Time.current > _deadline
                ctx[:signal_result] = nil
                break
              end
              sleep 2
            end
            true
          RUBY
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/signal_wait/signal_wait_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/signal_wait/signal_wait_generator.rb spec/services/code_generators/element_types/signal_wait/signal_wait_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add SignalWait structural element generator

Implements workflow signal waiting with two modes:
- pause_and_resume: suspends workflow, resumes on signal via cache
- poll: actively polls cache for signal arrival with sleep interval
Both modes support optional timeoutSeconds with fail/continue actions.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: ParallelForEach Generator

**Files:**
- Create: `spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb`
- Create: `app/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::ParallelForEach::ParallelForEachGenerator do
  let(:element) { { "properties" => { "sourceVariable" => "orders", "itemVariable" => "item", "concurrency" => 5, "resultVariable" => "processed_results" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  describe "#generate" do
    context "with result collection" do
      it "generates threaded parallel loop with result aggregation" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("# ParallelForEach: process items with concurrency 5")
        expect(code).to include("_results = Concurrent::Array.new")
        expect(code).to include("_source = ctx[:orders]")
        expect(code).to include("_source.each_slice(5)")
        expect(code).to include("Thread.new do")
        expect(code).to include("ctx_copy = ctx.dup")
        expect(code).to include("ctx_copy[:item] = _item")
        expect(code).to include("_results << ctx_copy[:item]")
        expect(code).to include("threads.each(&:join)")
        expect(code).to include("ctx[:processed_results] = _results.to_a")
      end
    end

    context "without result collection" do
      let(:element) { { "properties" => { "sourceVariable" => "users", "itemVariable" => "user", "concurrency" => 3 } } }

      it "generates threaded parallel loop without result aggregation" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("# ParallelForEach: process items with concurrency 3")
        expect(code).not_to include("Concurrent::Array")
        expect(code).not_to include("_results")
        expect(code).to include("_source = ctx[:users]")
        expect(code).to include("_source.each_slice(3)")
        expect(code).to include("ctx_copy[:user] = _item")
      end
    end

    context "with default concurrency and default item variable" do
      let(:element) { { "properties" => { "sourceVariable" => "items", "resultVariable" => "results" } } }

      it "defaults concurrency to 5 and item variable to 'item'" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("concurrency 5")
        expect(code).to include("_source.each_slice(5)")
        expect(code).to include("ctx_copy[:item] = _item")
        expect(code).to include("ctx[:results] = _results.to_a")
      end
    end

    context "with only sourceVariable specified" do
      let(:element) { { "properties" => { "sourceVariable" => "tasks" } } }

      it "generates basic parallel loop with defaults" do
        gen = described_class.new(element, context)
        code = gen.generate
        expect(code).to include("_source = ctx[:tasks]")
        expect(code).to include("ctx_copy[:item] = _item")
        expect(code).to include("each_slice(5)")
      end
    end
  end

  describe "#validate_config" do
    it "returns error when sourceVariable is missing" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({})
      expect(errors).to include("sourceVariable is required")
    end

    it "returns no errors for valid config" do
      gen = described_class.new(element, context)
      errors = gen.validate_config({ "sourceVariable" => "items" })
      expect(errors).to be_empty
    end
  end

  describe "#example_output" do
    it "returns a parallel for-each example" do
      gen = described_class.new(element, context)
      example = gen.example_output
      expect(example).to include("each_slice")
      expect(example).to include("Thread.new")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant CodeGenerators::ElementTypes::ParallelForEach`

- [ ] **Step 3: Implement the generator**

```ruby
# app/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module ParallelForEach
      class ParallelForEachGenerator < BaseGenerator
        generator_metadata do
          description "Generates concurrent iteration over a collection using threads with configurable concurrency"
          category :flow_control
          version "1.0.0"
        end

        input_schema  :source_variable, :item_variable, :concurrency
        output_schema :result_variable

        def generate
          source = config["sourceVariable"] || "items"
          item_var = config["itemVariable"] || "item"
          concurrency = config["concurrency"] || 5
          result_var = config["resultVariable"]

          if result_var.present?
            generate_with_results(source, item_var, concurrency, result_var)
          else
            generate_without_results(source, item_var, concurrency)
          end
        end

        def validate_config(cfg)
          errors = []
          errors << "sourceVariable is required" if cfg["sourceVariable"].blank?
          errors
        end

        def example_output
          <<~RUBY.chomp
            # ParallelForEach: process items with concurrency 5
            _results = Concurrent::Array.new
            _source = ctx[:items]
            _source.each_slice(5).each do |batch|
              threads = batch.map do |_item|
                Thread.new do
                  ctx_copy = ctx.dup
                  ctx_copy[:item] = _item
                  # Child steps execute with ctx_copy
                  _results << ctx_copy[:item]
                end
              end
              threads.each(&:join)
            end
            ctx[:results] = _results.to_a
            true
          RUBY
        end

        private

        def generate_with_results(source, item_var, concurrency, result_var)
          <<~RUBY.chomp
            # ParallelForEach: process items with concurrency #{concurrency}
            _results = Concurrent::Array.new
            _source = ctx[:#{source}]
            _source.each_slice(#{concurrency}).each do |batch|
              threads = batch.map do |_item|
                Thread.new do
                  ctx_copy = ctx.dup
                  ctx_copy[:#{item_var}] = _item
                  # Child steps execute with ctx_copy
                  _results << ctx_copy[:#{item_var}]
                end
              end
              threads.each(&:join)
            end
            ctx[:#{result_var}] = _results.to_a
            true
          RUBY
        end

        def generate_without_results(source, item_var, concurrency)
          <<~RUBY.chomp
            # ParallelForEach: process items with concurrency #{concurrency}
            _source = ctx[:#{source}]
            _source.each_slice(#{concurrency}).each do |batch|
              threads = batch.map do |_item|
                Thread.new do
                  ctx_copy = ctx.dup
                  ctx_copy[:#{item_var}] = _item
                  # Child steps execute with ctx_copy
                end
              end
              threads.each(&:join)
            end
            true
          RUBY
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator.rb spec/services/code_generators/element_types/parallel_for_each/parallel_for_each_generator_spec.rb
git commit -m "$(cat <<'EOF'
feat: add ParallelForEach structural element generator

Implements concurrent iteration over collections using threads:
- Configurable concurrency (batch size for Thread groups)
- Optional result collection via Concurrent::Array
- Context duplication for thread safety (ctx.dup per thread)

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Final Verification

- [ ] **Step 1: Run all new structural element specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/saga/ spec/services/code_generators/element_types/signal_wait/ spec/services/code_generators/element_types/parallel_for_each/ --format documentation`
Expected: All pass (3 spec files, all examples green)

- [ ] **Step 2: Verify generators are auto-discovered by registry**

Run: `bundle exec rails runner "CodeGenerators::GeneratorRegistry.reload!; puts CodeGenerators::GeneratorRegistry.instance.element_type_generators.keys.sort.join(', ')"`
Expected: Output includes `saga`, `signal_wait`, `parallel_for_each` among the existing element type generator names (start, end, decision, loop, timer, subflow, fork, join, error_handler)

- [ ] **Step 3: Run full test suite to check for regressions**

Run: `bundle exec rspec --format documentation`
Expected: All pass, no regressions

- [ ] **Step 4: Commit verification**

```bash
git commit --allow-empty -m "$(cat <<'EOF'
chore: verify all 3 Phase 4 structural element generators registered and passing

Saga, SignalWait, and ParallelForEach all auto-discovered by GeneratorRegistry
and all specs passing with no regressions.

Co-Authored-By: Copilot Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```
