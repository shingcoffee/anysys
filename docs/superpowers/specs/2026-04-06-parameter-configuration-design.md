# Parameter / Configuration System Design

**Date:** 2026-04-06
**Gap Reference:** Gap #2 from gap-analysis-anysys-vs-fw.md
**Status:** Draft

---

## Overview

Add a runtime configuration resolution layer where step configurations adapt based on user role, device type, and custom conditions. Overrides are defined inline on step configs as an `"overrides"` array, resolved at runtime by a ConfigResolver service using enriched context (last-write-wins). No new database tables needed.

---

## 1. ConfigResolver Service

### New service: `FlowchartRuntime::ConfigResolver`

Takes a step's static config hash, evaluates the `"overrides"` array against enriched runtime context, and returns the resolved config with matching overrides merged in.

```ruby
FlowchartRuntime::ConfigResolver.resolve(step_config, ctx)
```

### Resolution algorithm

1. Start with base config (minus `"overrides"` key)
2. Iterate overrides in array order
3. For each, evaluate `"when"` clause against ctx
4. If all conditions in `"when"` match (AND logic), deep-merge `"apply"` onto result
5. Return resolved config

### Override format

```json
{
  "overrides": [
    {
      "when": { "role": "admin" },
      "apply": { "pageSize": 100 }
    },
    {
      "when": { "device": "mobile" },
      "apply": { "pageSize": 10 }
    },
    {
      "when": { "condition": "ctx.vip_customer == true" },
      "apply": { "pageSize": 50 }
    }
  ]
}
```

### When clause evaluation

- `{ "role": "admin" }` → `ctx[:current_user_role] == "admin"`
- `{ "device": "mobile" }` → `ctx[:device_type] == "mobile"`
- `{ "condition": "ctx.vip" }` → ContextResolver evaluates to truthy value
- `{ "role": "admin", "device": "mobile" }` → both must match (AND)

Multiple overrides can match — they are applied in order, last-write-wins for conflicting keys.

---

## 2. Enriched Runtime Context

The DynamicController enriches ctx before execution:

```ruby
ctx[:current_user_id] = current_user&.id
ctx[:current_user_role] = current_user&.role
ctx[:device_type] = detect_device_type(request.user_agent)
```

### Device detection

Simple User-Agent check:
- Contains "Mobile" or "Android" → `"mobile"`
- Contains "Tablet" or "iPad" → `"tablet"`
- Otherwise → `"desktop"`

---

## 3. Generator Integration

For steps that have overrides, generated code calls ConfigResolver.resolve before using step config. For steps WITHOUT overrides, no change (backward compatible).

---

## 4. File Changes

### New files

| File | Purpose |
|---|---|
| `app/services/flowchart_runtime/config_resolver.rb` | Evaluates overrides against ctx, returns resolved config |
| `spec/services/flowchart_runtime/config_resolver_spec.rb` | Unit tests |
| `spec/integration/config_overrides_integration_spec.rb` | End-to-end test |

### Modified files

| File | Change |
|---|---|
| `app/controllers/dynamic_controller.rb` | Enrich ctx with current_user_role, device_type, current_user_id |

### No database migration needed

---

## 5. Testing Strategy

- **ConfigResolver specs:** Base config without overrides returns unchanged. Single override matches and merges. Multiple overrides with last-write-wins. Role matching. Device matching. Condition matching. Combined when clause (AND). No matching overrides. Deep merge of nested config.
- **DynamicController specs:** Verify ctx enrichment with user role and device type.
- **Integration:** End-to-end with step config containing overrides, verify different behavior per role.
