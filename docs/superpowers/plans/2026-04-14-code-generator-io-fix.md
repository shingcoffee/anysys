# Code Generator I/O Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 3 remaining generators that produce invalid `ctx.xxx` dot calls on Trailblazer ctx, and validate all 118 generators produce correct output.

**Architecture:** Each affected generator needs `OperandConverter` included and `condition_operand_to_ruby()` wired on expression-type config values. This converts `ctx.xxx` property editor format to `ctx.dig(:xxx)` valid Trailblazer access. Existing specs need updating where they pass `ctx[:xxx]` in test config (the old format that bypasses conversion).

**Tech Stack:** Ruby, Rails, RSpec, Trailblazer, CodeGenerators framework

**Spec:** `docs/superpowers/specs/2026-04-14-code-generator-io-fix-design.md`

---

### Task 1: Fix CalculateGenerator — wire OperandConverter on collectionExpression

**Files:**
- Modify: `app/services/code_generators/element_types/process/data_operations/calculate_generator.rb:22`
- Modify: `spec/services/code_generators/element_types/process/data_operations/calculate_generator_spec.rb:16,21`

- [ ] **Step 1: Update the generator to convert collectionExpression**

In `app/services/code_generators/element_types/process/data_operations/calculate_generator.rb`, line 22 currently reads:

```ruby
collection = config["collectionExpression"] || "ctx[:items]"
```

Change to:

```ruby
collection = condition_operand_to_ruby(config["collectionExpression"] || "ctx.items")
```

The class already has `include CodeGenerators::Shared::OperandConverter` at line 8 — no need to add it.

- [ ] **Step 2: Update specs to use ctx.xxx format in test data**

In `spec/services/code_generators/element_types/process/data_operations/calculate_generator_spec.rb`, update two test elements:

Line 16 — change:
```ruby
el = { "config" => { "operation" => "sum", "fieldName" => "price", "collectionExpression" => "ctx[:orders]" } }
```
To:
```ruby
el = { "config" => { "operation" => "sum", "fieldName" => "price", "collectionExpression" => "ctx.orders" } }
```

Line 21 — change:
```ruby
el = { "config" => { "operation" => "avg", "collectionExpression" => "ctx[:items]" } }
```
To:
```ruby
el = { "config" => { "operation" => "avg", "collectionExpression" => "ctx.items" } }
```

- [ ] **Step 3: Run tests to verify**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/data_operations/calculate_generator_spec.rb -v`

Expected: All examples pass. The generated code now uses `ctx.dig(:orders)` instead of `ctx.orders`.

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/element_types/process/data_operations/calculate_generator.rb spec/services/code_generators/element_types/process/data_operations/calculate_generator_spec.rb
git commit -m "fix: wire OperandConverter on CalculateGenerator collectionExpression"
```

---

### Task 2: Fix GenerateFileGenerator — add OperandConverter + wire on dataExpression

**Files:**
- Modify: `app/services/code_generators/element_types/process/file_operations/generate_file_generator.rb:7,20`
- Test: `spec/services/code_generators/element_types/process/file_operations/generate_file_generator_spec.rb`

- [ ] **Step 1: Add OperandConverter and convert dataExpression**

In `app/services/code_generators/element_types/process/file_operations/generate_file_generator.rb`:

Add after line 7 (`class GenerateFileGenerator < BaseGenerator`):
```ruby
          include CodeGenerators::Shared::OperandConverter
```

Change line 20 from:
```ruby
            data = config["dataExpression"] || "ctx[:data]"
```
To:
```ruby
            data = condition_operand_to_ruby(config["dataExpression"] || "ctx.data")
```

- [ ] **Step 2: Run tests to verify**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/file_operations/generate_file_generator_spec.rb -v`

Expected: All examples pass. The generated CSV/PDF/Excel code now uses `ctx.dig(:data)` instead of `ctx.data`.

- [ ] **Step 3: Commit**

```bash
git add app/services/code_generators/element_types/process/file_operations/generate_file_generator.rb
git commit -m "fix: add OperandConverter to GenerateFileGenerator for dataExpression"
```

---

### Task 3: Fix NotifyGenerator — add OperandConverter + wire on recipientExpression

**Files:**
- Modify: `app/services/code_generators/element_types/process/communication/notify_generator.rb:7,20`
- Test: `spec/services/code_generators/element_types/process/communication/notify_generator_spec.rb`

- [ ] **Step 1: Add OperandConverter and convert recipientExpression**

In `app/services/code_generators/element_types/process/communication/notify_generator.rb`:

Add after line 7 (`class NotifyGenerator < BaseGenerator`):
```ruby
          include CodeGenerators::Shared::OperandConverter
```

Change line 20 from:
```ruby
            recipient = config["recipientExpression"] || "ctx[:recipient]"
```
To:
```ruby
            recipient = condition_operand_to_ruby(config["recipientExpression"] || "ctx.recipient")
```

- [ ] **Step 2: Run tests to verify**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/communication/notify_generator_spec.rb -v`

Expected: All examples pass. Slack/SMS generated code now uses `ctx.dig(:recipient)` instead of raw expression.

- [ ] **Step 3: Commit**

```bash
git add app/services/code_generators/element_types/process/communication/notify_generator.rb
git commit -m "fix: add OperandConverter to NotifyGenerator for recipientExpression"
```

---

### Task 4: Full validation scan — verify zero invalid ctx.xxx patterns

**Files:**
- None (validation only)

- [ ] **Step 1: Run the full ctx.xxx scanner across all 118 generators**

```bash
bundle exec rails runner '
registry = CodeGenerators::GeneratorRegistry.instance
issues = []
(registry.element_type_generators.to_a + registry.step_action_generators.to_a).each do |name, klass|
  element = { "config" => klass.sample_input, "properties" => klass.sample_input, "label" => "test_step" }
  body = klass.new(element, {}).generate_body rescue nil
  next unless body.present?
  raw = body.scan(/ctx\.(?!dig|to_h|fetch|each|dup|merge|slice|except|include|is_a|respond_to|present|blank|nil|freeze|inspect|class|key|has_key|store|values|keys|delete|size|length|count|empty|any|all|none|map|select|reject|flat_map|reduce|first|last|min|max)(\w+)/).flatten
  issues << "#{name}: invalid ctx.#{raw.first}" if raw.any?
end
if issues.any?
  puts "FAIL: #{issues.size} generators with raw ctx.xxx:"
  issues.each { |i| puts "  #{i}" }
  exit 1
else
  puts "PASS: all generators produce valid ctx access patterns"
end
'
```

Expected output: `PASS: all generators produce valid ctx access patterns`

- [ ] **Step 2: Run CodeIntrospector I/O check on all generators**

```bash
bundle exec rails runner '
registry = CodeGenerators::GeneratorRegistry.instance
empty_io = []
(registry.element_type_generators.to_a + registry.step_action_generators.to_a).each do |name, klass|
  element = { "config" => klass.sample_input, "properties" => klass.sample_input, "label" => "test_step" }
  body = klass.new(element, {}).generate_body rescue nil
  next unless body.present?
  io = CodeGenerators::CodeIntrospector.analyze(body)
  all_writes = body.scan(/ctx\[:(\w+)\]\s*=[^=]/).flatten.uniq.reject { |k| k.start_with?("_") }
  all_reads = (body.scan(/ctx\[:(\w+)\](?!\s*=[^=])/).flatten + body.scan(/ctx\.dig\(:(\w+)/).flatten).uniq.reject { |k| k.start_with?("_") }
  missing_out = all_writes - io[:outputs]
  missing_in = (all_reads - io[:inputs] - io[:outputs])
  if missing_out.any? || missing_in.any?
    empty_io << "#{name}: missed_outputs=#{missing_out} missed_inputs=#{missing_in}"
  end
end
if empty_io.any?
  puts "WARN: #{empty_io.size} generators with undetected I/O:"
  empty_io.each { |i| puts "  #{i}" }
else
  puts "PASS: CodeIntrospector detects all ctx I/O correctly"
end
'
```

Expected: `PASS` or only warnings for generators that legitimately have no ctx I/O (e.g., log, schedule_job).

---

### Task 5: Run full spec suite

**Files:**
- None (validation only)

- [ ] **Step 1: Run all service specs**

Run: `bundle exec rspec spec/services/ --format progress`

Expected: `2597 examples, 0 failures`

- [ ] **Step 2: Verify no regressions in activity generator integration**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb spec/services/flowchart_topology_analyzer_spec.rb --format documentation`

Expected: `115 examples, 0 failures`
