# Code Generator I/O Fix & Validation

**Date:** 2026-04-14
**Status:** Approved

## Problem

The code generation system has two categories of issues:

### A. Independent Bug Fixes (4 bugs, already applied)

1. **ConditionBuilder double-conversion** (`condition_builder.rb:62-63`): `matches_regex` and `in_range` operators called `condition_operand_to_ruby(right)` on an already-converted `right` variable, corrupting operands.
2. **Join element bypassing JoinGenerator** (`activity_generator.rb:414`): Hardcoded `return "true"` for join elements before the registry lookup, so the registered `JoinGenerator` was never invoked.
3. **Missing gte/lte operators** (`find_in_collection_generator.rb:49-59`): `OPERATORS` constant declared `gte` and `lte` but `build_item_condition` had no `when` clauses for them, falling through to equality.
4. **Invalid ctx.each** (`ai_inference_generator.rb:35`): Generated code used `ctx.each` which is not a valid method on Trailblazer ctx. Should be `ctx.to_h.each`.

### B. Systematic sample_input / Expression Conversion Issue (14 generators)

The property editor sends ctx references as `ctx.xxx` format. `OperandConverter.condition_operand_to_ruby` converts this to valid Ruby:
- `ctx.status` becomes `ctx.dig(:status)`
- `ctx.model.name` becomes `ctx.dig(:model, :name)`

Two sub-problems:
- **Wrong sample_input format**: Some generators used `ctx[:xxx]` in `sample_input` instead of `ctx.xxx`. The OperandConverter treats `ctx[:xxx]` as a plain string (wraps in `.inspect`), breaking CodeIntrospector I/O detection.
- **Missing OperandConverter**: Some generators embedded config expression values directly into generated code without calling `condition_operand_to_ruby`, producing invalid `ctx.xxx` dot-method calls on Trailblazer ctx.

## Affected Generators

### Tier 1 — Already use OperandConverter, need sample_input fix only

| Generator | File | Change |
|---|---|---|
| decision | `element_types/decision/decision_generator.rb` | `ctx[:status]` → `ctx.status` in sample_input |
| end | `element_types/end/end_generator.rb` | `ctx[:result]` → `ctx.result` in sample_input |
| loop | `element_types/loop/loop_generator.rb` | `ctx[:items]` → `ctx.items` in sample_input |

### Tier 2 — Have OperandConverter but miss one expression

| Generator | File | Change |
|---|---|---|
| calculate | `process/data_operations/calculate_generator.rb` | Wire `condition_operand_to_ruby` on `collectionExpression` config value |

### Tier 3 — Need OperandConverter added + sample_input fix

| Generator | File | Expression configs needing conversion |
|---|---|---|
| enqueue_job | `process/background/enqueue_job_generator.rb` | `jobArgs` |
| cache_fetch | `process/caching/cache_fetch_generator.rb` | `fallbackExpression` |
| notify | `process/communication/notify_generator.rb` | `recipientExpression` |
| send_email | `process/communication/send_email_generator.rb` | `toExpression` |
| generate_file | `process/file_operations/generate_file_generator.rb` | `dataExpression` |
| upload_file | `process/file_operations/upload_file_generator.rb` | `sourceExpression`, `recordExpression` |
| publish_event | `process/realtime/publish_event_generator.rb` | `payloadExpression` |
| authorize | `process/security/authorize_generator.rb` | `userExpression`, `recordExpression` |

Note: notify, calculate, and generate_file also had their `sample_input` fixed from `ctx[:xxx]` to `ctx.xxx` as part of their respective tier fixes.

## Fix Pattern

For each affected generator:

```ruby
# 1. Add include (if not present)
class SomeGenerator < BaseGenerator
  include CodeGenerators::Shared::OperandConverter

# 2. Use ctx.xxx in sample_input
def self.sample_input
  { "someExpression" => "ctx.field_name" }  # NOT "ctx[:field_name]"
end

# 3. Convert expression configs before embedding
def generate_body
  expr = condition_operand_to_ruby(config["someExpression"] || "ctx.default")
  # expr is now "ctx.dig(:field_name)" — valid Trailblazer ctx access
  "ctx[:result] = #{expr}"
end
```

## Current State

- Bug fixes (Issue A): All 4 applied and passing
- Tier 1 (decision, end, loop): Applied and passing
- Tier 3, 6 of 8 (enqueue_job, send_email, upload_file, publish_event, authorize, cache_fetch): Applied and passing
- **Remaining**: calculate (Tier 2), generate_file + notify (Tier 3)

## Validation Criteria

1. `bundle exec rspec spec/services/` — 2597 examples, 0 failures
2. Zero raw `ctx.xxx` dot calls in any generator output (verified via scanner)
3. All generators with expression configs produce `ctx.dig(:xxx)` or `ctx[:xxx]` notation
4. CodeIntrospector correctly detects inputs/outputs for all generators with sample_input

## Testing

Run the full-scan script to verify no remaining invalid patterns:

```ruby
registry = CodeGenerators::GeneratorRegistry.instance
(registry.element_type_generators.to_a + registry.step_action_generators.to_a).each do |name, klass|
  element = { "config" => klass.sample_input, "properties" => klass.sample_input, "label" => "test_step" }
  body = klass.new(element, {}).generate_body rescue nil
  next unless body.present?
  raw = body.scan(/ctx\.(?!dig|to_h|fetch|each|dup|merge|slice|except|include|is_a|respond_to|present|blank|nil|freeze|inspect|class|key|has_key|store|values|keys|delete|size|length|count|empty|any|all|none|map|select|reject|flat_map|reduce|first|last|min|max)(\w+)/).flatten
  raise "#{name}: invalid ctx.#{raw.first}" if raw.any?
end
```
