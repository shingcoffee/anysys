# JotForm-Style Conditional Logic System Design

**Date:** 2026-02-16
**Status:** Approved
**Author:** Copilot

## Overview

This document describes the design for an enriched conditional logic system for the page builder, inspired by JotForm's implementation. The system introduces a rule-based architecture that separates conditions from actions, supports complex nested logic, calculated fields with a full formula engine, and both field-level and centralized rule management UI.

## Requirements

### Functional Requirements

1. **Actions:**
   - Show/hide fields, pages, and sections
   - Enable/disable fields
   - Make fields required/optional dynamically
   - Set field values
   - Skip to specific pages (wizard forms)
   - Calculate field values using formulas

2. **Formula Engine:**
   - Full formula support with math, string, date, and conditional functions
   - Field references in formulas
   - Nested expressions and operator precedence
   - Error handling for edge cases

3. **Runtime:**
   - Client-side JavaScript evaluation for instant feedback
   - No server round-trips during form filling

4. **UI:**
   - Quick conditions on field property panel (simple use cases)
   - Centralized rules panel for complex rules and overview
   - Formula editor with field picker and function reference

### Non-Functional Requirements

- Backward compatible with existing field-level conditions
- Auto-migration of legacy data format
- Performant evaluation (debounced, cached field references)
- Accessible (ARIA attributes for dynamic state changes)

---

## Data Model

### Configuration JSON Structure

The page's `configuration` field extends with three new top-level keys:

```json
{
  "pages": [...],
  "metadata": {...},
  "settings": {...},

  "rules": [
    {
      "id": "rule_abc123",
      "name": "Show shipping address",
      "enabled": true,
      "conditions": {
        "logic": "all",
        "groups": [
          {
            "logic": "any",
            "items": [
              { "field_id": "field_1", "operator": "equals", "value": "shipping" },
              { "field_id": "field_2", "operator": "is_not_empty" }
            ]
          }
        ]
      },
      "actions": [
        { "type": "show_field", "target_id": "field_3" },
        { "type": "set_required", "target_id": "field_3", "value": true }
      ]
    }
  ],

  "calculations": [
    {
      "id": "calc_xyz789",
      "target_field_id": "total_field",
      "formula": "SUM(price, tax) * quantity",
      "format": { "type": "currency", "decimals": 2 }
    }
  ]
}
```

### Condition Operators

| Operator | Description | Applicable Types |
|----------|-------------|------------------|
| `equals` | Exact match | All |
| `not_equals` | Not exact match | All |
| `contains` | Contains substring | String, Text |
| `not_contains` | Doesn't contain | String, Text |
| `starts_with` | Starts with | String, Text |
| `ends_with` | Ends with | String, Text |
| `greater_than` | > | Number, Date |
| `less_than` | < | Number, Date |
| `greater_or_equal` | >= | Number, Date |
| `less_or_equal` | <= | Number, Date |
| `between` | In range (inclusive) | Number, Date |
| `is_empty` | No value | All |
| `is_not_empty` | Has value | All |
| `is_selected` | Option checked | Checkbox, Radio, Select |
| `is_not_selected` | Option not checked | Checkbox, Radio, Select |
| `matches_regex` | Regex match | String, Text |

### Action Types

| Action Type | Target | Parameters |
|-------------|--------|------------|
| `show_field` | Field ID | - |
| `hide_field` | Field ID | - |
| `show_page` | Page ID | - |
| `hide_page` | Page ID | - |
| `skip_to_page` | Page ID | - |
| `enable_field` | Field ID | - |
| `disable_field` | Field ID | - |
| `set_required` | Field ID | `value: boolean` |
| `set_value` | Field ID | `value: any` |
| `set_options` | Field ID | `options: array` |

### Nested Condition Logic

Supports grouped conditions with mixed AND/OR:

```
(A AND B) OR (C AND D)
```

Represented as:

```json
{
  "logic": "any",
  "groups": [
    { "logic": "all", "items": [A, B] },
    { "logic": "all", "items": [C, D] }
  ]
}
```

---

## Formula Engine

### Syntax

Formulas use spreadsheet-like syntax:

```
field_slug + 10                        // Basic arithmetic
SUM(price, tax, shipping)              // Function with field references
IF(quantity > 10, price * 0.9, price)  // Conditional
CONCAT(first_name, " ", last_name)     // String concatenation
```

### Supported Functions

**Math Functions:**

| Function | Example | Description |
|----------|---------|-------------|
| `SUM(...)` | `SUM(a, b, c)` | Add values |
| `SUBTRACT(a, b)` | `SUBTRACT(total, discount)` | a - b |
| `MULTIPLY(...)` | `MULTIPLY(qty, price)` | Multiply values |
| `DIVIDE(a, b)` | `DIVIDE(total, count)` | a / b (returns 0 if b=0) |
| `MIN(...)` | `MIN(a, b, c)` | Smallest value |
| `MAX(...)` | `MAX(a, b, c)` | Largest value |
| `AVERAGE(...)` | `AVERAGE(score1, score2)` | Mean |
| `ROUND(n, decimals)` | `ROUND(price, 2)` | Round to decimals |
| `FLOOR(n)` | `FLOOR(3.7)` → 3 | Round down |
| `CEIL(n)` | `CEIL(3.2)` → 4 | Round up |
| `ABS(n)` | `ABS(-5)` → 5 | Absolute value |
| `MOD(a, b)` | `MOD(10, 3)` → 1 | Remainder |

**Conditional Functions:**

| Function | Example | Description |
|----------|---------|-------------|
| `IF(cond, then, else)` | `IF(age >= 18, "Adult", "Minor")` | Conditional |
| `AND(...)` | `AND(a > 0, b > 0)` | All true |
| `OR(...)` | `OR(a > 0, b > 0)` | Any true |
| `NOT(cond)` | `NOT(is_member)` | Negate |
| `SWITCH(val, case1, result1, ...)` | `SWITCH(tier, "gold", 20, "silver", 10, 0)` | Multi-case |

**String Functions:**

| Function | Example | Description |
|----------|---------|-------------|
| `CONCAT(...)` | `CONCAT(first, " ", last)` | Join strings |
| `UPPER(s)` | `UPPER(name)` | Uppercase |
| `LOWER(s)` | `LOWER(email)` | Lowercase |
| `TRIM(s)` | `TRIM(input)` | Remove whitespace |
| `LENGTH(s)` | `LENGTH(comment)` | Character count |
| `LEFT(s, n)` | `LEFT(phone, 3)` | First n chars |
| `RIGHT(s, n)` | `RIGHT(phone, 4)` | Last n chars |

**Date Functions:**

| Function | Example | Description |
|----------|---------|-------------|
| `TODAY()` | `TODAY()` | Current date |
| `NOW()` | `NOW()` | Current datetime |
| `DATE_DIFF(a, b, unit)` | `DATE_DIFF(end, start, "days")` | Difference |
| `DATE_ADD(date, n, unit)` | `DATE_ADD(start, 7, "days")` | Add to date |
| `YEAR(date)` | `YEAR(birth_date)` | Extract year |
| `MONTH(date)` | `MONTH(date)` | Extract month |
| `DAY(date)` | `DAY(date)` | Extract day |

### Implementation

```javascript
// app/javascript/lib/formula_engine.js
export class FormulaEngine {
  constructor(fieldValues = {}) {
    this.values = fieldValues
    this.functions = this.registerFunctions()
  }

  evaluate(formula) {
    if (!formula?.trim()) return null
    const resolved = this.resolveFieldReferences(formula)
    const tokens = this.tokenize(resolved)
    const ast = this.parse(tokens)
    return this.execute(ast)
  }

  tokenize(formula) { /* Break into tokens */ }
  parse(tokens) { /* Build AST with operator precedence */ }
  execute(node) { /* Walk AST and compute */ }
  registerFunctions() { /* Return function implementations */ }
}
```

### Error Handling

| Error | Behavior |
|-------|----------|
| Division by zero | Returns `0` |
| Missing field | Returns `null`, formula returns `null` |
| Type mismatch | Attempts coercion, returns `null` if impossible |
| Syntax error | Returns `null`, logs warning to console |
| Circular reference | Detected at save time, prevented |

---

## UI Components

### Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Page Builder                                                │
│  ┌──────────────┐  ┌─────────────────────┐  ┌────────────┐ │
│  │ Left Sidebar │  │ Canvas              │  │ Right      │ │
│  │              │  │                     │  │ Sidebar    │ │
│  │ • Components │  │                     │  │            │ │
│  │ • Fields     │  │                     │  │ • Props    │ │
│  │ ─────────────│  │                     │  │ • Quick    │ │
│  │ • Rules      │  │                     │  │   Conds    │ │
│  │ • Calcs      │  │                     │  │            │ │
│  └──────────────┘  └─────────────────────┘  └────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### New ViewComponents

| Component | File | Purpose |
|-----------|------|---------|
| `RulesPanelComponent` | `app/components/page_builder/rules_panel_component.rb` | List all rules in left sidebar |
| `RuleEditorComponent` | `app/components/page_builder/rule_editor_component.rb` | Full rule editor modal |
| `CalculationsPanelComponent` | `app/components/page_builder/calculations_panel_component.rb` | List calculated fields |
| `FormulaEditorComponent` | `app/components/page_builder/formula_editor_component.rb` | Formula editor modal with field picker |
| `QuickConditionsComponent` | `app/components/page_builder/quick_conditions_component.rb` | Simple conditions in field properties |
| `ConditionGroupComponent` | `app/components/page_builder/condition_group_component.rb` | Reusable condition group renderer |

### Refactored Component

`ConditionBuilderComponent` splits into:
- `QuickConditionsComponent` - Simple inline conditions
- `ConditionGroupComponent` - Reusable condition group renderer
- `RuleEditorComponent` - Full modal editor

---

## JavaScript Architecture

### Stimulus Controllers

**1. Extend `page_builder_controller.js`**

New targets:
```javascript
static targets = [
  // ... existing ...
  "rulesPanel", "rulesList", "calculationsPanel", "calculationsList",
  "ruleEditorModal", "formulaEditorModal"
]
```

New methods:
- `openRuleEditor()` / `closeRuleEditor()` / `saveRule()` / `deleteRule()` / `toggleRule()`
- `addConditionGroup()` / `removeConditionGroup()`
- `addAction()` / `removeAction()`
- `openFormulaEditor()` / `closeFormulaEditor()` / `saveCalculation()` / `deleteCalculation()`
- `insertFieldReference()` / `insertFunction()`
- `renderRulesPanel()` / `renderCalculationsPanel()`

**2. New `formula_engine_controller.js`**

Handles live formula preview in the editor.

**3. New `condition_runtime_controller.js`**

Evaluates conditions at form runtime when end-user fills the form.

### Standalone Libraries

| File | Purpose |
|------|---------|
| `app/javascript/lib/formula_engine.js` | Formula parser and evaluator |
| `app/javascript/lib/condition_evaluator.js` | Condition tree evaluator |

---

## Runtime Integration

### Generated Form Output

`PageContentGenerator` embeds rules and calculations as data attributes:

```erb
<div data-controller="condition-runtime"
     data-condition-runtime-rules-value="<%= @rules.to_json %>"
     data-condition-runtime-calculations-value="<%= @calculations.to_json %>">

  <div data-field-id="address_field" class="field-wrapper">
    <%= render FormFields::TextFieldComponent.new(...) %>
  </div>
</div>
```

### Event Flow

```
User types in field
       ↓
input event fires
       ↓
condition_runtime_controller#fieldChanged
       ↓
1. Collect all field values
2. Evaluate each enabled rule
3. Apply matching actions
4. Evaluate all calculations
5. Update calculated field values
       ↓
DOM updates (show/hide/enable/disable/set values)
```

### CSS Classes for State

```css
.field-wrapper.hidden { display: none; }
.field-wrapper.disabled input { opacity: 0.5; pointer-events: none; }
```

### Accessibility

- Hidden fields get `aria-hidden="true"`
- Disabled fields get proper `disabled` attribute
- Required changes update `aria-required`
- Screen readers announce dynamic changes via `aria-live` regions

### Performance

- Debounce rapid input changes (100ms)
- Cache field element references on connect

---

## Migration & Backward Compatibility

### Migration Strategy

Auto-migrate on read, persist on next save.

```ruby
# app/models/page.rb
def configuration_json
  raw = JSON.parse(configuration || '{}')
  migrate_conditions_to_rules(raw)
end
```

Migration logic:
1. Find fields with `conditions` array
2. Create corresponding rule with `show_field` action
3. Convert flat condition list to nested group format
4. Remove `conditions` from field
5. Mark as migrated

### Migration Timing

| Trigger | Action |
|---------|--------|
| Page edit (builder opens) | Migrate in memory, save on user save |
| Page preview | Migrate in memory for rendering |
| Autosave | Persists migrated format |

### Validation

- Validate rule has `id`, `conditions`, `actions`
- Validate calculation has `target_field_id`, `formula`
- Detect circular formula references at save time

---

## Testing Strategy

### Test Coverage

| Area | Test Type | Location |
|------|-----------|----------|
| Formula Engine | Unit tests (Jest) | `spec/javascript/lib/formula_engine_spec.js` |
| Condition Evaluator | Unit tests (Jest) | `spec/javascript/lib/condition_evaluator_spec.js` |
| Migration logic | Model specs (RSpec) | `spec/models/page_spec.rb` |
| Rule validation | Model specs (RSpec) | `spec/models/page_spec.rb` |
| Content generation | Service specs (RSpec) | `spec/services/page_content_generator_spec.rb` |
| ViewComponents | Component specs (RSpec) | `spec/components/page_builder/*_spec.rb` |
| Runtime behavior | System specs (Capybara) | `spec/system/form_conditions_spec.rb` |

### Key Test Cases

**Formula Engine:**
- Basic arithmetic with operator precedence
- All function implementations
- Field reference resolution
- Error handling (division by zero, missing fields, syntax errors)

**Condition Evaluator:**
- All 16 operators
- Nested AND/OR logic
- Empty/null value handling

**Migration:**
- Legacy format detection and conversion
- Preserved behavior after migration

**Runtime:**
- Field visibility toggles
- Calculated field updates
- Page-level conditions in wizards

---

## File Structure

### New Files

```
app/
├── components/page_builder/
│   ├── rules_panel_component.rb
│   ├── rules_panel_component.html.erb
│   ├── rule_editor_component.rb
│   ├── rule_editor_component.html.erb
│   ├── calculations_panel_component.rb
│   ├── calculations_panel_component.html.erb
│   ├── formula_editor_component.rb
│   ├── formula_editor_component.html.erb
│   ├── quick_conditions_component.rb
│   ├── quick_conditions_component.html.erb
│   └── condition_group_component.rb
│   └── condition_group_component.html.erb
├── javascript/
│   ├── controllers/
│   │   ├── formula_engine_controller.js
│   │   └── condition_runtime_controller.js
│   └── lib/
│       ├── formula_engine.js
│       └── condition_evaluator.js
└── services/
    └── formula_validator.rb

spec/
├── javascript/lib/
│   ├── formula_engine_spec.js
│   └── condition_evaluator_spec.js
├── components/page_builder/
│   ├── rules_panel_component_spec.rb
│   ├── rule_editor_component_spec.rb
│   ├── calculations_panel_component_spec.rb
│   └── formula_editor_component_spec.rb
├── services/
│   └── formula_validator_spec.rb
└── system/
    └── form_conditions_spec.rb
```

### Modified Files

```
app/
├── models/page.rb                              # Add migration logic, validation
├── services/page_content_generator.rb          # Add runtime controller wrapper
├── javascript/controllers/
│   └── page_builder_controller.js              # Add rules/calculations methods
└── views/pages/_editor.html.erb                # Add rules/calculations panels
```

---

## Summary

This design introduces a rule-based conditional logic system that:

1. **Separates concerns** - Rules have conditions (when) and actions (what)
2. **Supports complexity** - Nested AND/OR groups, multiple actions per rule
3. **Adds calculations** - Full formula engine with 30+ functions
4. **Provides dual UI** - Quick conditions on fields + centralized rules panel
5. **Evaluates client-side** - Instant feedback, no server round-trips
6. **Migrates seamlessly** - Existing conditions auto-convert to new format
7. **Tests thoroughly** - Unit, component, and system test coverage
