# Logging Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ad-hoc `Rails.logger` calls with a consistent, tenant-aware tagged logging framework.

**Architecture:** `AppLogger` module provides the core tagged-logging implementation. `Loggable` concern wraps it for inclusion in controllers/services. Generated Trailblazer code references `AppLogger` directly.

**Tech Stack:** Ruby 3.2, Rails 8.1, ActiveSupport::TaggedLogging, RSpec

---

## File Structure

| File | Purpose |
|------|---------|
| `app/services/app_logger.rb` | Core logging module — builds tags, delegates to `Rails.logger.tagged(...)` |
| `app/models/concerns/loggable.rb` | Concern providing `log_info`/`log_warn`/`log_error`/`log_debug` instance methods |
| `spec/services/app_logger_spec.rb` | AppLogger specs |
| `spec/models/concerns/loggable_spec.rb` | Loggable concern specs |

### Files modified (refactored to use Loggable)

| File | Change |
|------|--------|
| `app/controllers/dynamic_controller.rb` | Add `include Loggable`, remove custom `log_info`/`log_error` methods |
| `app/services/activity_tracer.rb` | Add `include Loggable`, replace 7 `Rails.logger` calls |
| `app/services/concerns/activity_class_builder.rb` | Add `include Loggable`, replace 3 `Rails.logger` calls |
| `app/services/dynamic_class_loader.rb` | Add `include Loggable`, replace 2 `Rails.logger` calls |
| `app/services/activity_diagram_generator.rb` | Add `include Loggable`, replace 1 `Rails.logger` call |
| `app/services/calculation_evaluator.rb` | Add `include Loggable`, replace 1 `Rails.logger` call |
| `app/services/context_sanitizer.rb` | Add `include Loggable`, replace 1 `Rails.logger` call |
| `app/services/code_generators/generator_registry.rb` | Add `include Loggable`, replace 1 `Rails.logger` call |
| `app/services/activity_generator.rb` | Add `include Loggable`, replace 1 `Rails.logger` call |
| `config/initializers/feature_modules.rb` | Use `AppLogger.warn(...)` directly |

### Files modified (generated code output)

| File | Change |
|------|--------|
| `app/services/code_generators/element_types/error_handler/error_handler_generator.rb` | Output `AppLogger.error(...)` instead of `Rails.logger.error(...)` |
| `app/services/code_generators/element_types/process/data_operations/log_generator.rb` | Output `AppLogger.#{level}(...)` instead of `Rails.logger.#{level}(...)` |

### Test files updated

| File | Change |
|------|--------|
| `spec/services/activity_diagram_generator_spec.rb` | Update `expect(Rails.logger)` to `expect(AppLogger)` |
| `spec/services/activity_generator_spec.rb` | Update `include('Rails.logger...')` to `include('AppLogger...')` |
| `spec/services/code_generators/element_types/process/data_operations/log_generator_spec.rb` | Update expected output strings |
| `spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb` | Update expected output strings |

---

### Task 1: Create AppLogger module with tests

**Files:**
- Create: `spec/services/app_logger_spec.rb`
- Create: `app/services/app_logger.rb`

- [ ] **Step 1: Write failing AppLogger specs**

```ruby
# spec/services/app_logger_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppLogger do
  let(:logger) { ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(StringIO.new)) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
  end

  describe ".info" do
    it "logs at info level" do
      expect(logger).to receive(:info).with("hello").and_call_original
      described_class.info("hello", source: "Test")
    end
  end

  describe ".warn" do
    it "logs at warn level" do
      expect(logger).to receive(:warn).with("warning").and_call_original
      described_class.warn("warning", source: "Test")
    end
  end

  describe ".error" do
    it "logs at error level" do
      expect(logger).to receive(:error).with("bad").and_call_original
      described_class.error("bad", source: "Test")
    end
  end

  describe ".debug" do
    it "logs at debug level" do
      expect(logger).to receive(:debug).with("trace").and_call_original
      described_class.debug("trace", source: "Test")
    end
  end

  describe "tagging" do
    let(:output) { StringIO.new }
    let(:logger) { ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output)) }

    it "tags with source when provided" do
      described_class.info("msg", source: "MyService")
      expect(output.string).to include("[MyService]")
    end

    it "tags with customer ID when Current.customer is set" do
      customer = create(:customer)
      Current.customer = customer

      described_class.info("msg", source: "MyService")
      expect(output.string).to include("[customer:#{customer.id}]")
      expect(output.string).to include("[MyService]")
    end

    it "omits customer tag when no current customer" do
      Current.customer = nil
      described_class.info("msg", source: "MyService")
      expect(output.string).not_to include("[customer:")
    end

    it "works with no source and no customer" do
      Current.customer = nil
      described_class.info("bare message")
      expect(output.string).to include("bare message")
      expect(output.string).not_to include("[]")
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/services/app_logger_spec.rb`
Expected: FAIL — `uninitialized constant AppLogger`

- [ ] **Step 3: Implement AppLogger**

```ruby
# app/services/app_logger.rb
# frozen_string_literal: true

module AppLogger
  module_function

  def info(message, source: nil)  = log(:info, message, source: source)
  def warn(message, source: nil)  = log(:warn, message, source: source)
  def error(message, source: nil) = log(:error, message, source: source)
  def debug(message, source: nil) = log(:debug, message, source: source)

  def log(level, message, source: nil)
    tags = build_tags(source)
    if tags.any?
      Rails.logger.tagged(*tags) { Rails.logger.public_send(level, message) }
    else
      Rails.logger.public_send(level, message)
    end
  end

  def build_tags(source)
    tags = []
    tags << "customer:#{Current.customer_id}" if Current.customer?
    tags << source if source
    tags
  end
end
```

- [ ] **Step 4: Run specs to verify they pass**

Run: `bundle exec rspec spec/services/app_logger_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/app_logger.rb spec/services/app_logger_spec.rb
git commit -m "feat: add AppLogger module for tagged tenant-aware logging"
```

---

### Task 2: Create Loggable concern with tests

**Files:**
- Create: `spec/models/concerns/loggable_spec.rb`
- Create: `app/models/concerns/loggable.rb`

- [ ] **Step 1: Write failing Loggable specs**

```ruby
# spec/models/concerns/loggable_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Loggable do
  let(:test_class) do
    Class.new do
      include Loggable

      def self.name
        "SomeModule::TestService"
      end

      def do_logging
        log_info "info message"
        log_warn "warn message"
        log_error "error message"
        log_debug "debug message"
      end
    end
  end

  let(:instance) { test_class.new }

  describe "log methods" do
    it "delegates log_info to AppLogger with auto-derived source" do
      expect(AppLogger).to receive(:info).with("info message", source: "TestService")
      instance.send(:log_info, "info message")
    end

    it "delegates log_warn to AppLogger" do
      expect(AppLogger).to receive(:warn).with("warn message", source: "TestService")
      instance.send(:log_warn, "warn message")
    end

    it "delegates log_error to AppLogger" do
      expect(AppLogger).to receive(:error).with("error message", source: "TestService")
      instance.send(:log_error, "error message")
    end

    it "delegates log_debug to AppLogger" do
      expect(AppLogger).to receive(:debug).with("debug message", source: "TestService")
      instance.send(:log_debug, "debug message")
    end
  end

  describe "#log_source" do
    it "demodulizes the class name" do
      expect(instance.send(:log_source)).to eq("TestService")
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/models/concerns/loggable_spec.rb`
Expected: FAIL — `uninitialized constant Loggable`

- [ ] **Step 3: Implement Loggable concern**

```ruby
# app/models/concerns/loggable.rb
# frozen_string_literal: true

module Loggable
  extend ActiveSupport::Concern

  private

  def log_info(message)  = AppLogger.info(message, source: log_source)
  def log_warn(message)  = AppLogger.warn(message, source: log_source)
  def log_error(message) = AppLogger.error(message, source: log_source)
  def log_debug(message) = AppLogger.debug(message, source: log_source)

  def log_source
    self.class.name.demodulize
  end
end
```

- [ ] **Step 4: Run specs to verify they pass**

Run: `bundle exec rspec spec/models/concerns/loggable_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/models/concerns/loggable.rb spec/models/concerns/loggable_spec.rb
git commit -m "feat: add Loggable concern wrapping AppLogger"
```

---

### Task 3: Refactor DynamicController

**Files:**
- Modify: `app/controllers/dynamic_controller.rb`

- [ ] **Step 1: Add `include Loggable` and remove custom log methods**

In `app/controllers/dynamic_controller.rb`, add `include Loggable` after `skip_forgery_protection` (line 6), and delete the two custom methods at the bottom (lines 167-168):

```ruby
# Line 6 — add after skip_forgery_protection:
  include Loggable

# Delete lines 167-168:
  def log_info(message)  = Rails.logger.info("[DynamicController] #{message}")
  def log_error(message) = Rails.logger.error("[DynamicController] #{message}")
```

The existing `log_info` and `log_error` calls throughout the controller (lines 86, 89, 93, 94, 159, 163) remain unchanged — they now resolve to the `Loggable` concern methods.

- [ ] **Step 2: Run existing tests**

Run: `bundle exec rspec spec/requests/dynamic_spec.rb spec/routing/dynamic_routing_spec.rb`
Expected: All 40 tests pass

- [ ] **Step 3: Commit**

```bash
git add app/controllers/dynamic_controller.rb
git commit -m "refactor: DynamicController uses Loggable concern"
```

---

### Task 4: Refactor ActivityTracer

**Files:**
- Modify: `app/services/activity_tracer.rb`

- [ ] **Step 1: Add `include Loggable` and replace all `Rails.logger` calls**

In `app/services/activity_tracer.rb`:

Add `include Loggable` after `include ActivityClassBuilder` (line 19).

Replace all `Rails.logger` calls:

```ruby
# Line 38-39 — replace:
    Rails.logger.debug "[ActivityTracer] Built activity class: #{activity_class.name || activity_class.to_s}"
    Rails.logger.debug "[ActivityTracer] Input context keys: #{input.keys}"
# With:
    log_debug "Built activity class: #{activity_class.name || activity_class.to_s}"
    log_debug "Input context keys: #{input.keys}"

# Lines 43-44 — replace:
    Rails.logger.error "[ActivityTracer] Execution error: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
# With:
    log_error "Execution error: #{e.class}: #{e.message}"
    log_error e.backtrace.first(10).join("\n")

# Line 51 — replace:
    Rails.logger.debug "[ActivityTracer] Starting traced execution..."
# With:
    log_debug "Starting traced execution..."

# Line 59 — replace:
    Rails.logger.debug "[ActivityTracer] Execution completed with signal: #{signal.class.name}"
# With:
    log_debug "Execution completed with signal: #{signal.class.name}"

# Lines 66-67 — replace:
    Rails.logger.debug "[ActivityTracer] Trace nodes count: #{trace_nodes.size}"
    Rails.logger.debug "[ActivityTracer] Final ctx keys: #{ctx.keys}" if ctx.is_a?(Hash)
# With:
    log_debug "Trace nodes count: #{trace_nodes.size}"
    log_debug "Final ctx keys: #{ctx.keys}" if ctx.is_a?(Hash)
```

- [ ] **Step 2: Run existing tests**

Run: `bundle exec rspec spec/requests/dynamic_spec.rb`
Expected: All 26 tests pass (ActivityTracer is exercised through DynamicController integration tests)

- [ ] **Step 3: Commit**

```bash
git add app/services/activity_tracer.rb
git commit -m "refactor: ActivityTracer uses Loggable concern"
```

---

### Task 5: Refactor ActivityClassBuilder concern

**Files:**
- Modify: `app/services/concerns/activity_class_builder.rb`

- [ ] **Step 1: Add `include Loggable` in the `included` block and replace `Rails.logger` calls**

In `app/services/concerns/activity_class_builder.rb`:

Add `include Loggable` inside the concern's `included` block. Since `ActivityClassBuilder` is itself a concern using `extend ActiveSupport::Concern`, add it as a dependency:

```ruby
# After line 16 (extend ActiveSupport::Concern), add:
  included do
    include Loggable
  end
```

Replace all `Rails.logger` calls:

```ruby
# Line 54 — replace:
    Rails.logger.error("ActivityClassBuilder: Failed to build activity class - #{e.class}: #{e.message}")
# With:
    log_error "Failed to build activity class - #{e.class}: #{e.message}"

# Line 76 — replace:
    Rails.logger.warn("ActivityClassBuilder: Failed to load dynamic classes - #{e.message}")
# With:
    log_warn "Failed to load dynamic classes - #{e.message}"

# Line 110 — replace:
    Rails.logger.warn("ActivityClassBuilder: Failed to load subflow activity #{subflow_flowchart.name} - #{e.message}")
# With:
    log_warn "Failed to load subflow activity #{subflow_flowchart.name} - #{e.message}"
```

- [ ] **Step 2: Update activity_diagram_generator_spec expectation**

In `spec/services/activity_diagram_generator_spec.rb`, line 65 expects `Rails.logger` to receive `:error`. Since ActivityClassBuilder now uses Loggable → AppLogger, update the expectation:

```ruby
# Line 65 — replace:
        expect(Rails.logger).to receive(:error).with(/ActivityClassBuilder/)
# With:
        expect(AppLogger).to receive(:error).with(/Failed to build activity class/, source: "ActivityDiagramGenerator")
```

Note: The source is "ActivityDiagramGenerator" because `log_source` derives from the including class (`ActivityDiagramGenerator`), not the concern name.

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/services/activity_diagram_generator_spec.rb spec/requests/dynamic_spec.rb`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add app/services/concerns/activity_class_builder.rb spec/services/activity_diagram_generator_spec.rb
git commit -m "refactor: ActivityClassBuilder uses Loggable concern"
```

---

### Task 6: Refactor remaining services

**Files:**
- Modify: `app/services/dynamic_class_loader.rb`
- Modify: `app/services/activity_diagram_generator.rb`
- Modify: `app/services/calculation_evaluator.rb`
- Modify: `app/services/context_sanitizer.rb`
- Modify: `app/services/code_generators/generator_registry.rb`
- Modify: `app/services/activity_generator.rb`
- Modify: `config/initializers/feature_modules.rb`

- [ ] **Step 1: Refactor DynamicClassLoader**

In `app/services/dynamic_class_loader.rb`, add `include Loggable` after the constant declarations (after line 29):

```ruby
  include Loggable
```

Replace:
```ruby
# Line 111:
    Rails.logger.warn("DynamicClassLoader: Failed to build entity model - #{e.message}")
# With:
    log_warn "Failed to build entity model - #{e.message}"

# Line 126:
    Rails.logger.warn("DynamicClassLoader: Failed to build entity contract - #{e.message}")
# With:
    log_warn "Failed to build entity contract - #{e.message}"
```

- [ ] **Step 2: Refactor ActivityDiagramGenerator**

In `app/services/activity_diagram_generator.rb`, add `include Loggable` after `include ActivityClassBuilder` (line 18):

```ruby
  include Loggable
```

Replace:
```ruby
# Line 61:
    Rails.logger.error("ActivityDiagramGenerator: #{e.message}")
# With:
    log_error e.message
```

- [ ] **Step 3: Refactor CalculationEvaluator**

In `app/services/calculation_evaluator.rb`, add `include Loggable` after the constant (after line 4):

```ruby
  include Loggable
```

Replace:
```ruby
# Line 17:
      Rails.logger.error("CalculationEvaluator error: #{e.message}")
# With:
      log_error e.message
```

- [ ] **Step 4: Refactor ContextSanitizer**

In `app/services/context_sanitizer.rb`, add `include Loggable` inside the class (line 3):

```ruby
class ContextSanitizer
  include Loggable
```

Replace:
```ruby
# Line 17:
    Rails.logger.warn("ContextSanitizer#sanitize: #{e.class} - #{e.message}")
# With:
    log_warn "#{e.class} - #{e.message}"
```

- [ ] **Step 5: Refactor GeneratorRegistry**

In `app/services/code_generators/generator_registry.rb`, add `include Loggable` inside the class.

Replace:
```ruby
# Line 88:
      Rails.logger.warn("CodeGeneratorRegistry: Failed to load #{file}: #{e.message}")
# With:
      log_warn "Failed to load #{file}: #{e.message}"
```

- [ ] **Step 6: Refactor ActivityGenerator**

In `app/services/activity_generator.rb`, add `include Loggable` inside the class.

Replace:
```ruby
# Line 35:
      Rails.logger.warn("Flowchart validation failed for #{flowchart.id}: #{validation_errors.join(', ')}")
# With:
      log_warn "Flowchart validation failed for #{flowchart.id}: #{validation_errors.join(', ')}"
```

- [ ] **Step 7: Refactor feature_modules initializer**

In `config/initializers/feature_modules.rb`, replace:
```ruby
# Line 35:
  Rails.logger.warn("Feature module registration skipped: #{e.message}")
# With:
  AppLogger.warn("Feature module registration skipped: #{e.message}", source: "FeatureModules")
```

- [ ] **Step 8: Run full test suite to verify nothing is broken**

Run: `bundle exec rspec spec/requests/dynamic_spec.rb spec/services/activity_diagram_generator_spec.rb spec/services/dynamic_class_loader_spec.rb`
Expected: All pass

- [ ] **Step 9: Commit**

```bash
git add app/services/dynamic_class_loader.rb app/services/activity_diagram_generator.rb \
  app/services/calculation_evaluator.rb app/services/context_sanitizer.rb \
  app/services/code_generators/generator_registry.rb app/services/activity_generator.rb \
  config/initializers/feature_modules.rb
git commit -m "refactor: remaining services use Loggable/AppLogger"
```

---

### Task 7: Update code generators to output AppLogger

**Files:**
- Modify: `app/services/code_generators/element_types/error_handler/error_handler_generator.rb`
- Modify: `app/services/code_generators/element_types/process/data_operations/log_generator.rb`
- Modify: `spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb`
- Modify: `spec/services/code_generators/element_types/process/data_operations/log_generator_spec.rb`
- Modify: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Update ErrorHandlerGenerator output**

In `app/services/code_generators/element_types/error_handler/error_handler_generator.rb`, replace all three occurrences of `Rails.logger.error` in the generated code strings:

```ruby
# Lines 24, 31, 37 — replace each:
              Rails.logger.error("Activity error: \#{ctx['contract.default']&.errors&.full_messages}")
# With:
              AppLogger.error("Activity error: \#{ctx['contract.default']&.errors&.full_messages}", source: "Activity")
```

Update `example_output` (line 48):
```ruby
        def example_output
          "# Error handler (all errors): log and continue\nAppLogger.error(\"Activity error: \#{ctx['contract.default']&.errors&.full_messages}\", source: \"Activity\")\ntrue"
        end
```

Update `description` (line 9) — no change needed (describes purpose, not implementation).

- [ ] **Step 2: Update LogGenerator output**

In `app/services/code_generators/element_types/process/data_operations/log_generator.rb`, replace:

```ruby
# Line 9 — update description:
            description "Writes log entries via AppLogger or audit trail"

# Lines 29-32 — replace:
              <<~RUBY.chomp
                Rails.logger.#{level}(#{message.inspect})
                true
              RUBY
# With:
              <<~RUBY.chomp
                AppLogger.#{level}(#{message.inspect}, source: "Activity")
                true
              RUBY

# Lines 45-46 — update example_output:
          def example_output
            "AppLogger.info(\"Log entry\", source: \"Activity\")\ntrue"
          end
```

- [ ] **Step 3: Update ErrorHandlerGenerator spec**

In `spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb`, replace:

```ruby
# Line 15 — replace:
      expect(code).to include("Rails.logger.error")
# With:
      expect(code).to include("AppLogger.error")
```

- [ ] **Step 4: Update LogGenerator spec**

In `spec/services/code_generators/element_types/process/data_operations/log_generator_spec.rb`, replace:

```ruby
# Line 11-12 — replace:
  it "defaults to Rails.logger.info" do
    expect(described_class.new(element, context).generate).to include("Rails.logger.info")
# With:
  it "defaults to AppLogger.info" do
    expect(described_class.new(element, context).generate).to include("AppLogger.info")

# Line 22 — replace:
    expect(described_class.new(el, {}).generate).to include("Rails.logger.error")
# With:
    expect(described_class.new(el, {}).generate).to include("AppLogger.error")
```

- [ ] **Step 5: Update ActivityGenerator spec**

In `spec/services/activity_generator_spec.rb`:

```ruby
# Line 1647 — replace:
        expect(code).to include('Rails.logger.error')
# With:
        expect(code).to include('AppLogger.error')

# Line 1881 — replace:
        expect(code).to include('Rails.logger.warn')
# With:
        expect(code).to include('AppLogger.warn')
```

- [ ] **Step 6: Run all affected specs**

Run: `bundle exec rspec spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb spec/services/code_generators/element_types/process/data_operations/log_generator_spec.rb spec/services/activity_generator_spec.rb`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add app/services/code_generators/element_types/error_handler/error_handler_generator.rb \
  app/services/code_generators/element_types/process/data_operations/log_generator.rb \
  spec/services/code_generators/element_types/error_handler/error_handler_generator_spec.rb \
  spec/services/code_generators/element_types/process/data_operations/log_generator_spec.rb \
  spec/services/activity_generator_spec.rb
git commit -m "refactor: code generators output AppLogger instead of Rails.logger"
```

---

### Task 8: Final verification

- [ ] **Step 1: Verify no remaining ad-hoc Rails.logger calls in app code**

Run: `grep -rn "Rails\.logger" app/ --include="*.rb" | grep -v "node_modules"`

Expected: Zero matches. All app code should now use `Loggable` or `AppLogger`.

If any remain, refactor them following the same pattern.

- [ ] **Step 2: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests pass

- [ ] **Step 3: Commit if any stragglers were fixed**

```bash
git add -A
git commit -m "chore: final cleanup — no remaining Rails.logger calls in app/"
```
