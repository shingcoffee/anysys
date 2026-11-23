# Zero-Coding Platform Features Design

**Date:** 2026-04-06
**Project:** anysys
**Inspiration:** fw (CiviCore) zero-coding platform

---

## Overview

This design adds real zero-coding business logic capabilities to `anysys`, transforming it from a visual editor with stub implementations into a fully functional, configuration-driven business logic platform. The primary inspiration is the `fw` (CiviCore) platform's configuration-driven module dispatch, query-based conditional branching, numbered parameter collections, and field polymorphism.

The user explicitly excluded: security/authorization functionality.

---

## 1. Conditional / Configuration-Driven Branching (Highest Priority)

### Problem
Decision and Switch elements exist in the flowchart canvas but generate no meaningful code. Conditions on outgoing connections are unconfigured — there is no way to express "if field X equals Y, take this path."

### Design

**Connection Condition Config** (stored in `connections[].condition` JSON within flowchart configuration):

```json
{
  "id": "conn_2",
  "from": "decision_1",
  "to": "approve_step",
  "label": "Approved",
  "condition": {
    "operator": "AND",
    "rules": [
      { "field": "ctx.status",   "op": "==", "value": "approved" },
      { "field": "ctx.amount",   "op": "<=", "value": "10000" }
    ]
  }
}
```

**Supported operators per rule:** `==`, `!=`, `>`, `<`, `>=`, `<=`, `blank?`, `present?`, `includes?`, `matches?` (regex).

**Compound logic:** Top-level `operator` can be `AND` or `OR`. Rules can be nested for compound conditions.

**Special condition values:**
- `"$true"` — always-true default branch (else)
- `"$false"` — never (disabled branch)
- Context variable references: `ctx.field_name` resolved at runtime

**Code Generator for Decision Elements:**

For a Decision element with outgoing connections, generate:

```ruby
# Decision: <<label>>
if ctx[:status] == "approved" && ctx[:amount].to_i <= 10000
  # Trailblazer signal → approved path
  return Trailblazer::Activity::Right
elsif ctx[:status] == "rejected"
  return Trailblazer::Activity::Left
else
  return Trailblazer::Activity::End(:default)
end
```

Signals map outgoing connections to Trailblazer outputs. Each connection condition becomes a signal class or uses the built-in `Right`/`Left` for binary decisions.

**Switch elements** (multiple cases): Same pattern, generates case/when for cleaner multi-branch code.

### UI Changes

- **Connection properties panel**: When editing a connection from a Decision/Switch, show a Condition Builder:
  - Add/remove rules
  - Select field (context variable picker from entity schema)
  - Select operator
  - Set value (literal, or pick another context variable)
  - Toggle AND/OR at top level

---

## 2. Process Step Code Generator Implementations

### Problem
40+ step types in Process elements are stubs. Code generation produces placeholder comments. The platform cannot execute any real business logic.

### Design

Each step type gets a real code template. The `Flowcharts::CodeGenerators::ActivityGenerator` service is extended to produce actual Ruby code per step type.

**Category: Model Operations**

| Step | Generated Code Pattern |
|------|----------------------|
| `find_model` | `ctx[:record] = EntityEntry.for_customer(ctx[:customer_id]).where(entity_id: ENTITY_ID, "data->>field": ctx[:lookup_value]).first` |
| `query_models` | `ctx[:records] = EntityEntry.for_customer(ctx[:customer_id]).where(entity_id: ENTITY_ID).where(build_where_clause(ctx, config))` |
| `save_model` | `entry = EntityEntry.new(entity_id: ENTITY_ID, customer_id: ctx[:customer_id], data: ctx[:form_data]); ctx[:saved] = entry.save` |
| `update_model` | `ctx[:record].data = ctx[:record].data.merge(ctx[:updates]); ctx[:record].save!` |
| `destroy_model` | `ctx[:record].destroy!; ctx[:deleted] = true` |
| `check_existence` | `ctx[:exists] = EntityEntry.for_customer(ctx[:customer_id]).where(entity_id: ENTITY_ID, ...).exists?` |
| `count_records` | `ctx[:count] = EntityEntry.for_customer(ctx[:customer_id]).where(...).count` |
| `aggregate_query` | `ctx[:result] = EntityEntry.for_customer(ctx[:customer_id]).where(...).pluck("data->>field").map(&:to_f).sum` |
| `batch_operation` | Generates loop + per-record operation |
| `transition_state` | `ctx[:record].data = ctx[:record].data.merge("state" => config[:to_state]); ctx[:record].save!` |

**Category: Data Operations**

| Step | Generated Code Pattern |
|------|----------------------|
| `assign_value` | `ctx[:target_field] = resolve_value(ctx, config[:value])` |
| `calculate` | `ctx[:result] = evaluate_expression(ctx, config[:expression])` |
| `transform` | `ctx[:output] = ctx[:input].then { |v| apply_transform(v, config[:transform_type], config[:options]) }` |
| `format_string` | `ctx[:output] = config[:template].gsub(/\{\{(\w+)\}\}/) { |m| ctx[$1.to_sym].to_s }` |
| `map_value` | `ctx[:output] = config[:map_table].fetch(ctx[:input].to_s, config[:default])` |
| `parse_data` | `ctx[:parsed] = JSON.parse(ctx[:raw_data])` (or CSV/XML per format) |
| `filter_collection` | `ctx[:filtered] = ctx[:collection].select { |item| evaluate_filter(item, config[:filter]) }` |
| `sort_collection` | `ctx[:sorted] = ctx[:collection].sort_by { |item| item[config[:sort_field]] }` |
| `map_collection` | `ctx[:mapped] = ctx[:collection].map { |item| apply_mapping(item, config[:mapping]) }` |
| `group_collection` | `ctx[:grouped] = ctx[:collection].group_by { |item| item[config[:group_by]] }` |
| `uniq_collection` | `ctx[:unique] = ctx[:collection].uniq { |item| item[config[:unique_by]] }` |
| `merge_data` | `ctx[:merged] = ctx[:base].merge(ctx[:override])` |
| `date_time_calc` | `ctx[:result] = ctx[:date].send(config[:operation], config[:amount].send(config[:unit]))` |
| `regex_extract` | `ctx[:match] = ctx[:input].match(Regexp.new(config[:pattern])).try(:[], config[:group] || 0)` |
| `serialize_data` | `ctx[:serialized] = ctx[:data].to_json` |
| `log` | `Rails.logger.info "[Flowchart #{ctx[:flowchart_id]}] #{config[:message].gsub(/\{\{(\w+)\}\}/) { ctx[$1.to_sym] }}"` |

**Category: Validation**

| Step | Generated Code Pattern |
|------|----------------------|
| `build_contract` | `ctx[:contract] = EntityContractFactory.build(ctx[:entity_id], ctx[:record])` |
| `validate_contract` | `ctx[:valid] = ctx[:contract].validate(ctx[:params]); ctx[:errors] = ctx[:contract].errors.to_h unless ctx[:valid]` |

**Category: Communication (stubs with real interfaces)**

| Step | Generated Code Pattern |
|------|----------------------|
| `send_email` | `FlowchartMailer.configured_email(config, ctx).deliver_later` |
| `api_call` | `ctx[:response] = FlowchartApiClient.call(config[:method], config[:url], headers: resolve_headers(ctx, config), body: resolve_body(ctx, config))` |
| `send_webhook` | `FlowchartApiClient.call("POST", config[:url], body: ctx.to_h.slice(*config[:fields]))` |
| `notify` | `FlowchartNotifier.notify(config[:channel], ctx[:message], ctx)` |

**Category: Collection / Loop**

| Step | Generated Code Pattern |
|------|----------------------|
| `parallel_for_each` | `ctx[:results] = Parallel.map(ctx[:collection]) { |item| process_item(item, ctx) }` |

### Supporting Services

These services support the generated code at runtime (not generated, but called by generated code):

- `FlowchartRuntime::ContextResolver` — resolves `ctx.field` references in config values
- `FlowchartRuntime::ExpressionEvaluator` — safely evaluates math/string expressions
- `FlowchartRuntime::WhereClauseBuilder` — builds ActiveRecord where chains from condition config (mirrors fw's WhereClause)
- `FlowchartRuntime::TransformApplier` — applies named transforms (upcase, downcase, strip, to_i, to_f, etc.)
- `EntityContractFactory` — builds Reform contracts from Entity property schema at runtime
- `FlowchartMailer` — ActionMailer with template rendering from config
- `FlowchartApiClient` — Faraday-based HTTP client for external API calls

---

## 3. Form Rules Execution Engine

### Problem
Pages have `rules` and `calculations` in their JSON configuration but these are only persisted, never executed. The public form (`/f/:token`) shows all fields regardless of rules.

### Design

**Rules Format** (already in `configuration.rules[]`):

```json
{
  "id": "rule_1",
  "trigger_field": "employment_type",
  "conditions": [
    { "field": "employment_type", "op": "==", "value": "employed" }
  ],
  "operator": "AND",
  "actions": [
    { "type": "show", "target": "employer_name" },
    { "type": "show", "target": "salary" }
  ]
}
```

**Calculations Format** (already in `configuration.calculations[]`):

```json
{
  "id": "calc_1",
  "result_field": "total_cost",
  "expression": "quantity * unit_price",
  "variables": ["quantity", "unit_price"]
}
```

**Implementation:**

1. **StimulusJS Controller** (`rules-engine_controller.js`): Pure client-side execution of rules and calculations on the public form. Reads `data-rules` and `data-calculations` JSON attributes from the form element.
   - On field change: evaluate all rules where `trigger_field` matches
   - Show/hide target fields based on rule actions
   - Recalculate computed fields using safe math evaluation

2. **Server-side validation mirror**: When form submits, the Rails `Pages::RulesEngine` service re-evaluates rules server-side to validate that hidden fields are not submitted (prevents form field injection).

3. **Calculation Engine**: Supports expressions with `+`, `-`, `*`, `/`, `()`, field references. Uses a simple recursive descent parser (no eval) for security.

---

## 4. Loop / Iteration Support

### Problem
Loop elements exist in the canvas but generate no iteration code.

### Design

**Loop element configuration** (in `element.properties`):

```json
{
  "loop_type": "for_each",
  "collection_field": "ctx.records",
  "item_variable": "current_record",
  "max_iterations": 1000,
  "break_condition": {
    "field": "ctx.found",
    "op": "==",
    "value": true
  }
}
```

**Generated code:**

```ruby
# Loop: for each in records
ctx[:records].each_with_index do |current_record, idx|
  break if idx >= 1000  # safety limit
  ctx[:current_record] = current_record

  # ... inner steps ...

  break if ctx[:found] == true
end
```

For `while` loops:

```ruby
iteration_count = 0
while evaluate_condition(ctx, config[:while_condition]) && iteration_count < 1000
  iteration_count += 1
  # ... inner steps ...
end
```

The code generator traverses the flowchart graph to identify nodes "inside" the loop (between the Loop element and its back-edge or Join element).

---

## 5. Runtime Data Persistence

### Problem
Flowchart execution (via DynamicController) doesn't auto-persist data. Entity records must be created manually.

### Design

- `save_model` and `update_model` step types (from section 2) handle persistence explicitly
- The `DynamicController` pre-loads the relevant `EntityEntry` into `ctx[:record]` when `entity_entry_id` is present
- After activity execution, the controller checks `ctx[:record]` for dirty state and saves if configured
- Transactional safety: wrap the activity call in `ActiveRecord::Base.transaction`

---

## 6. Condition Builder UI Component

### Design

A new ViewComponent `ConditionBuilderComponent` renders in the flowchart property panel for:
- Connection conditions (from Decision/Switch)
- Loop break conditions
- Display rules on Pages

**UI structure:**

```
[AND / OR toggle]
┌─────────────────────────────────────────┐
│ [field picker▼] [operator▼] [value input] [×] │
│ [field picker▼] [operator▼] [value input] [×] │
│ [+ Add rule]                              │
└─────────────────────────────────────────┘
```

Field picker lists context variables from the bound Entity's property schema plus system variables (`customer_id`, `current_user_id`, etc.).

---

## 7. Entity Contract Factory

### Design

`EntityContractFactory.build(entity_id, record)` dynamically constructs a Reform contract from the Entity's `property_schema`. This replaces the static generated contract code with a runtime-built contract, making validation automatically reflect schema changes without code regeneration.

```ruby
module EntityContractFactory
  def self.build(entity_id, record = nil)
    entity = Entity.find(entity_id)
    schema = entity.property_schema

    Class.new(Reform::Form) do
      schema.each do |field_def|
        property field_def["name_slug"].to_sym
        field_def["validators"].each do |v|
          validates field_def["name_slug"].to_sym, **build_validation(v)
        end
      end
    end.new(record || OpenStruct.new)
  end
end
```

---

## Implementation Scope

**In scope (to implement):**
- Connection condition config schema + UI builder
- Decision/Switch code generation with real if/elsif/else
- Process step code generator for ~25 key step types (model ops, data ops, validation, communication stubs)
- Supporting runtime services (ContextResolver, ExpressionEvaluator, WhereClauseBuilder, TransformApplier)
- Form rules engine (StimulusJS + server-side validation)
- Loop element code generation
- EntityContractFactory for runtime validation
- FlowchartMailer and FlowchartApiClient shells
- DynamicController transaction wrapping and pre-loading

**Out of scope (excluded per user):**
- Security/authorization step implementations
- encrypt_data, hash_data, generate_token, authorize, authenticate steps

**Not in scope for this iteration:**
- Trigger system (HTTP/Event/Schedule route creation)
- Background job integration
- File operations
- Caching
- Real-time/WebSocket events

---

## Files to Create/Modify

### New Files
- `app/javascript/controllers/rules_engine_controller.js`
- `app/javascript/controllers/condition_builder_controller.js`
- `app/services/flowchart_runtime/context_resolver.rb`
- `app/services/flowchart_runtime/expression_evaluator.rb`
- `app/services/flowchart_runtime/where_clause_builder.rb`
- `app/services/flowchart_runtime/transform_applier.rb`
- `app/services/entity_contract_factory.rb`
- `app/mailers/flowchart_mailer.rb`
- `app/services/flowchart_api_client.rb`
- `app/services/pages/rules_engine.rb`
- `app/components/condition_builder_component.rb`
- `app/components/condition_builder_component.html.erb`
- `spec/services/flowchart_runtime/*_spec.rb`
- `spec/services/entity_contract_factory_spec.rb`

### Modified Files
- `app/services/flowcharts/code_generators/activity_generator.rb` — major extension for all step types + decision branching
- `app/controllers/dynamic_controller.rb` — transaction wrapping, record pre-loading
- `app/views/pages/show.html.erb` (public form) — attach rules engine controller
- `app/views/flowcharts/edit.html.erb` — condition builder in property panel
- `app/models/flowchart.rb` — add connection condition validation helpers
