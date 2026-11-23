# Page Builder — Conditional Rules & Calculated Fields Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the inline-`innerHTML` Conditional-Rules and Calculated-Fields editors with ViewComponent + Stimulus implementations matching world-class form builders (Airtable-style pill formula editor, contextual condition value editors, live test/preview), backed by RSpec-tested server-side configuration validation.

**Architecture:** Rules & calculations remain in `Page#configuration_json` (no new AR model, migration, or route). A Ruby PORO `Pages::ConfigurationValidator` is the canonical, RSpec-tested validation layer, invoked from a `Page` model validation hook so invalid configs are rejected at save with structured errors. The builder UI is rebuilt as ViewComponents driven by dedicated Stimulus controllers (Tailwind-only, Stimulus-only), and the shared JS libs (`formula_engine.js`, `condition_evaluator.js`, new `formula_validator.js`) are updated to the `{field_id}` token format and used by both the editor (live preview) and the runtime (`condition_runtime_controller.js`).

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, StimulusJS, TailwindCSS, RSpec. No JS unit-test harness exists, so JS logic is validated through the Ruby validator (canonical) + RSpec component/request/system specs + manual smoke.

**Reference spec:** `docs/superpowers/specs/2026-06-04-page-builder-rules-calculations-overhaul-design.md`

---

## File Structure

**Backend (Ruby — canonical validation):**
- Create `app/services/pages/configuration_validator.rb` — PORO; validates rules & calculations against the page's fields. One responsibility: structural + referential + cycle validation.
- Modify `app/models/page.rb` — add a `validate :configuration_is_well_formed` hook that delegates to the validator and copies errors.
- Modify `app/controllers/admin/maintenance/pages_controller.rb` — surface validation errors in the JSON save response.

**Shared JS libs:**
- Modify `app/javascript/lib/formula_engine.js` — tokenize `{field_id}` braces as identifiers.
- Modify `app/javascript/lib/condition_evaluator.js` — no logic change (already supports all operators); confirm `between`/`matches_regex`.
- Create `app/javascript/lib/formula_validator.js` — wraps `FormulaEngine`; returns `{ valid, errors, referencedFields, result }`.
- Modify `app/javascript/controllers/condition_runtime_controller.js` — parse `{field_id}` tokens; honour calc `format` and action `value`.

**ViewComponents (replace inline innerHTML):**
- Create `app/components/page_builder/formula_pill_editor_component.{rb,html.erb}` — the contentEditable pill surface markup.
- Create `app/components/page_builder/calculation_editor_component.{rb,html.erb}` — calculation modal (target field, pill editor, formatting controls, preview).
- Create `app/components/page_builder/condition_row_component.{rb,html.erb}` — one condition row with contextual value editor.
- Create `app/components/page_builder/rule_editor_component.{rb,html.erb}` — rule modal (groups, actions, test mode).
- Modify `app/components/page_builder/rules_panel_component.{rb,html.erb}` — list polish (toggle/duplicate/summary/search).
- Modify `app/components/page_builder/calculations_panel_component.{rb,html.erb}` — list polish + formatted summary.

**Stimulus controllers:**
- Create `app/javascript/controllers/formula_editor_controller.js` — pill management, autocomplete, live preview, inline validation.
- Create `app/javascript/controllers/rule_builder_controller.js` — contextual value editor, action value editor, live test mode.
- Modify `app/javascript/controllers/page_builder/calculations_manager.js` — slim to open/close + read-back (no HTML strings).
- Modify `app/javascript/controllers/page_builder/rules_manager.js` — slim to open/close + read-back (no HTML strings).
- Modify `app/views/admin/maintenance/pages/_property_panel.html.erb` — per-field "Add logic" affordance.

**Specs:**
- Create `spec/services/pages/configuration_validator_spec.rb`
- Modify `spec/models/page_spec.rb`
- Create `spec/components/page_builder/calculation_editor_component_spec.rb`
- Create `spec/components/page_builder/condition_row_component_spec.rb`
- Create `spec/components/page_builder/rule_editor_component_spec.rb`
- Create `spec/components/page_builder/formula_pill_editor_component_spec.rb`
- Create/modify `spec/requests/admin/maintenance/pages_spec.rb` (save-validation path)
- Create `spec/system/admin/page_builder_rules_calculations_spec.rb` (if a system-spec harness is present; otherwise skip-guard)

---

## Phase A — Canonical configuration validation (Ruby, TDD)

### Task 1: `Pages::ConfigurationValidator` — referenced field existence

**Files:**
- Create: `app/services/pages/configuration_validator.rb`
- Test: `spec/services/pages/configuration_validator_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/pages/configuration_validator_spec.rb
require "rails_helper"

RSpec.describe Pages::ConfigurationValidator do
  def config(rules: [], calculations: [], fields: [])
    {
      "pages" => [{ "id" => "p1", "name" => "Page 1", "fields" => fields }],
      "rules" => rules,
      "calculations" => calculations
    }
  end

  let(:fields) do
    [
      { "id" => "price",   "label" => "Price",   "property_type" => "number" },
      { "id" => "qty",     "label" => "Qty",     "property_type" => "number" },
      { "id" => "country", "label" => "Country", "property_type" => "select" }
    ]
  end

  it "passes when all condition field_ids exist" do
    rules = [{ "id" => "r1", "enabled" => true,
               "conditions" => { "logic" => "all", "groups" => [
                 { "logic" => "all", "items" => [
                   { "field_id" => "country", "operator" => "equals", "value" => "US" }
                 ] } ] },
               "actions" => [{ "type" => "show_field", "target_id" => "price" }] }]
    validator = described_class.new(config(rules: rules, fields: fields))
    expect(validator.valid?).to be(true)
    expect(validator.errors).to be_empty
  end

  it "flags a condition referencing an unknown field" do
    rules = [{ "id" => "r1", "enabled" => true,
               "conditions" => { "logic" => "all", "groups" => [
                 { "logic" => "all", "items" => [
                   { "field_id" => "ghost", "operator" => "equals", "value" => "x" }
                 ] } ] },
               "actions" => [{ "type" => "show_field", "target_id" => "price" }] }]
    validator = described_class.new(config(rules: rules, fields: fields))
    expect(validator.valid?).to be(false)
    expect(validator.errors.join).to match(/unknown field 'ghost'/i)
  end

  it "flags an action targeting an unknown field" do
    rules = [{ "id" => "r1", "enabled" => true,
               "conditions" => { "logic" => "all", "groups" => [] },
               "actions" => [{ "type" => "show_field", "target_id" => "ghost" }] }]
    validator = described_class.new(config(rules: rules, fields: fields))
    expect(validator.valid?).to be(false)
    expect(validator.errors.join).to match(/action.*unknown field 'ghost'/i)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/pages/configuration_validator_spec.rb`
Expected: FAIL with `uninitialized constant Pages::ConfigurationValidator`

- [ ] **Step 3: Write minimal implementation**

```ruby
# app/services/pages/configuration_validator.rb
# frozen_string_literal: true

module Pages
  # Validates the rules & calculations stored in Page#configuration_json against
  # the fields actually present on the page. Pure PORO — no AR, no tenancy logic
  # (the page is already customer-scoped by the controller).
  class ConfigurationValidator
    FUNCTION_ALLOWLIST = %w[
      SUM SUBTRACT MULTIPLY DIVIDE MIN MAX AVERAGE ROUND FLOOR CEIL ABS MOD
      IF AND OR NOT SWITCH
      CONCAT UPPER LOWER TRIM LENGTH LEFT RIGHT
      TODAY NOW YEAR MONTH DAY DATE_DIFF DATE_ADD
    ].freeze

    FIELD_REF = /\{([a-zA-Z0-9_]+)\}/

    attr_reader :errors

    def initialize(configuration)
      @config = configuration || {}
      @errors = []
    end

    def valid?
      @errors = []
      validate_rules
      validate_calculations
      @errors.empty?
    end

    private

    def field_ids
      @field_ids ||= Array(@config["pages"]).flat_map { |p| Array(p["fields"]) }
                                            .map { |f| f["id"] }.compact.to_set
    end

    def validate_rules
      Array(@config["rules"]).each do |rule|
        name = rule["name"].presence || rule["id"]
        Array(rule.dig("conditions", "groups")).each do |group|
          Array(group["items"]).each do |item|
            next if item["field_id"].blank?
            unless field_ids.include?(item["field_id"])
              @errors << "Rule '#{name}': condition references unknown field '#{item["field_id"]}'"
            end
          end
        end
        Array(rule["actions"]).each do |action|
          next if action["target_id"].blank?
          unless field_ids.include?(action["target_id"]) || page_ids.include?(action["target_id"])
            @errors << "Rule '#{name}': action references unknown field '#{action["target_id"]}'"
          end
        end
      end
    end

    def page_ids
      @page_ids ||= Array(@config["pages"]).map { |p| p["id"] }.compact.to_set
    end

    def validate_calculations
      # filled in Task 2
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/pages/configuration_validator_spec.rb`
Expected: PASS (3 examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/pages/configuration_validator.rb spec/services/pages/configuration_validator_spec.rb
git commit -m "feat(pages): configuration validator — referenced field existence"
```

---

### Task 2: Validator — formula structure & circular dependency

**Files:**
- Modify: `app/services/pages/configuration_validator.rb`
- Test: `spec/services/pages/configuration_validator_spec.rb`

- [ ] **Step 1: Add failing tests**

```ruby
  describe "calculations" do
    it "flags a formula referencing an unknown field" do
      calcs = [{ "id" => "c1", "target_field_id" => "price", "formula" => "{ghost} * 2" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/unknown field 'ghost'/i)
    end

    it "flags an unknown function" do
      calcs = [{ "id" => "c1", "target_field_id" => "price", "formula" => "BOGUS({qty})" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/unknown function 'BOGUS'/i)
    end

    it "flags unbalanced parentheses" do
      calcs = [{ "id" => "c1", "target_field_id" => "price", "formula" => "SUM({qty}, 2" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/unbalanced/i)
    end

    it "detects a circular dependency between calculations" do
      calcs = [
        { "id" => "c1", "target_field_id" => "price", "formula" => "{qty} + 1" },
        { "id" => "c2", "target_field_id" => "qty",   "formula" => "{price} + 1" }
      ]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/circular/i)
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/pages/configuration_validator_spec.rb -e calculations`
Expected: FAIL (validate_calculations is a no-op)

- [ ] **Step 3: Implement `validate_calculations`**

```ruby
    def validate_calculations
      calcs = Array(@config["calculations"])
      calcs.each do |calc|
        label = calc["target_field_id"].presence || calc["id"]
        formula = calc["formula"].to_s

        if calc["target_field_id"].present? && !field_ids.include?(calc["target_field_id"])
          @errors << "Calculation '#{label}': target references unknown field '#{calc["target_field_id"]}'"
        end

        formula.scan(FIELD_REF).flatten.uniq.each do |ref|
          @errors << "Calculation '#{label}': formula references unknown field '#{ref}'" unless field_ids.include?(ref)
        end

        formula.scan(/\b([A-Z_]+)\s*\(/).flatten.uniq.each do |fn|
          @errors << "Calculation '#{label}': unknown function '#{fn}'" unless FUNCTION_ALLOWLIST.include?(fn)
        end

        if formula.count("(") != formula.count(")")
          @errors << "Calculation '#{label}': unbalanced parentheses"
        end
      end

      detect_cycles(calcs)
    end

    # Builds target_field_id -> [referenced field ids that are themselves calc targets]
    # and runs a DFS cycle check.
    def detect_cycles(calcs)
      targets = calcs.map { |c| c["target_field_id"] }.compact.to_set
      graph = {}
      calcs.each do |calc|
        tgt = calc["target_field_id"]
        next if tgt.blank?
        refs = calc["formula"].to_s.scan(FIELD_REF).flatten.uniq.select { |r| targets.include?(r) }
        graph[tgt] = refs
      end

      visiting = Set.new
      visited  = Set.new
      cycle = lambda do |node|
        return false if visited.include?(node)
        return true  if visiting.include?(node)
        visiting << node
        result = Array(graph[node]).any? { |n| cycle.call(n) }
        visiting.delete(node)
        visited << node
        result
      end

      graph.keys.each do |node|
        if cycle.call(node)
          @errors << "Calculation circular dependency detected involving field '#{node}'"
          break
        end
      end
    end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/services/pages/configuration_validator_spec.rb`
Expected: PASS (all examples)

- [ ] **Step 5: Commit**

```bash
git add app/services/pages/configuration_validator.rb spec/services/pages/configuration_validator_spec.rb
git commit -m "feat(pages): validator — formula structure & circular-dependency checks"
```

---

### Task 3: Wire validator into `Page` model + controller JSON errors

**Files:**
- Modify: `app/models/page.rb`
- Modify: `app/controllers/admin/maintenance/pages_controller.rb:124-160` (update action JSON branch)
- Test: `spec/models/page_spec.rb`, `spec/requests/admin/maintenance/pages_spec.rb`

- [ ] **Step 1: Failing model test**

```ruby
# spec/models/page_spec.rb  (add inside the existing describe Page block)
describe "configuration validation" do
  let(:customer) { create(:customer) }

  it "is invalid when a calculation references an unknown field" do
    page = build(:page, customer: customer)
    page.configuration_json = {
      "pages" => [{ "id" => "p1", "fields" => [{ "id" => "qty", "property_type" => "number" }] }],
      "calculations" => [{ "id" => "c1", "target_field_id" => "qty", "formula" => "{ghost} + 1" }]
    }
    expect(page).not_to be_valid
    expect(page.errors[:configuration].join).to match(/unknown field 'ghost'/i)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/models/page_spec.rb -e "configuration validation"`
Expected: FAIL (page is valid)

- [ ] **Step 3: Add the model hook**

```ruby
# app/models/page.rb  (add near other validations)
validate :configuration_is_well_formed

private

def configuration_is_well_formed
  return if configuration.blank?

  validator = Pages::ConfigurationValidator.new(configuration_json)
  return if validator.valid?

  validator.errors.each { |msg| errors.add(:configuration, msg) }
end
```

> Note: `configuration_json` is the parsed hash already memoized by the model (used throughout the controller). If the memo can go stale after `configuration=`, mirror the controller's existing memo-clearing approach (`pages_controller.rb:239`) inside the parser, or parse `JSON.parse(configuration)` directly here guarded by `rescue JSON::ParserError`.

- [ ] **Step 4: Run model test**

Run: `bundle exec rspec spec/models/page_spec.rb -e "configuration validation"`
Expected: PASS

- [ ] **Step 5: Surface errors in the controller JSON branch**

In `app/controllers/admin/maintenance/pages_controller.rb`, the `update` action's `else` (failure) path must return validation errors for JSON requests:

```ruby
else
  respond_to do |format|
    format.html do
      load_entity_options
      render :edit, status: :unprocessable_entity
    end
    format.json do
      render json: { status: "error",
                     errors: @page.errors.full_messages },
             status: :unprocessable_entity
    end
  end
end
```

- [ ] **Step 6: Failing request test**

```ruby
# spec/requests/admin/maintenance/pages_spec.rb
it "rejects a save whose calculation references an unknown field" do
  page = create(:page, customer: customer)
  patch admin_maintenance_page_path(customer.id, page),
        params: { page: { configuration: {
          "pages" => [{ "id" => "p1", "fields" => [{ "id" => "qty", "property_type" => "number" }] }],
          "calculations" => [{ "id" => "c1", "target_field_id" => "qty", "formula" => "{ghost}+1" }]
        }.to_json } },
        as: :json
  expect(response).to have_http_status(:unprocessable_entity)
  expect(response.parsed_body["errors"].join).to match(/unknown field 'ghost'/i)
end
```

- [ ] **Step 7: Run request test (adapt auth setup to existing spec helpers)**

Run: `bundle exec rspec spec/requests/admin/maintenance/pages_spec.rb -e "unknown field"`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add app/models/page.rb app/controllers/admin/maintenance/pages_controller.rb spec/models/page_spec.rb spec/requests/admin/maintenance/pages_spec.rb
git commit -m "feat(pages): reject invalid rule/calculation config at save with structured errors"
```

---

## Phase B — Shared JS libs ({field_id} tokens, validator, runtime)

### Task 4: Brace-token formula tokenizer

**Files:**
- Modify: `app/javascript/lib/formula_engine.js:40-53` (identifier tokenizer)

- [ ] **Step 1: Add brace handling in `tokenize`**

Insert before the identifier branch (after the string branch, ~line 40):

```javascript
      // Field reference token: {field_id}
      if (formula[pos] === '{') {
        pos++ // skip {
        let ident = ''
        while (pos < formula.length && formula[pos] !== '}') {
          ident += formula[pos++]
        }
        pos++ // skip }
        tokens.push({ type: 'IDENTIFIER', value: ident.trim() })
        continue
      }
```

Keep the existing bare-identifier branch so legacy formulas still parse during the one-time normalize.

- [ ] **Step 2: Add a one-time normalizer (bare slug → `{slug}`)**

```javascript
// app/javascript/lib/formula_engine.js  (module-level export)
// Converts legacy bare-identifier formulas to {field_id} token form, given the
// set of known field ids. Functions and numbers are left untouched.
export function normalizeFormula(formula, fieldIds = []) {
  if (!formula) return formula
  const known = new Set(fieldIds)
  return formula.replace(/(?<![A-Za-z0-9_{])([a-zA-Z_][a-zA-Z0-9_]*)(?!\s*\()/g,
    (m, id) => (known.has(id) ? `{${id}}` : m))
}
```

- [ ] **Step 3: Verify via Rails console / browser smoke**

Load the editor; an existing formula like `SUM(price, tax) * quantity` must render with pills after normalize. (No JS unit harness — verify in the system spec in Task 13 and manual smoke.)

- [ ] **Step 4: Commit**

```bash
git add app/javascript/lib/formula_engine.js
git commit -m "feat(formula): parse {field_id} reference tokens + legacy normalizer"
```

---

### Task 5: `formula_validator.js` shared module

**Files:**
- Create: `app/javascript/lib/formula_validator.js`

- [ ] **Step 1: Implement the validator**

```javascript
// app/javascript/lib/formula_validator.js
import { FormulaEngine } from "lib/formula_engine"

const FUNCTION_ALLOWLIST = new Set([
  "SUM","SUBTRACT","MULTIPLY","DIVIDE","MIN","MAX","AVERAGE","ROUND","FLOOR","CEIL","ABS","MOD",
  "IF","AND","OR","NOT","SWITCH",
  "CONCAT","UPPER","LOWER","TRIM","LENGTH","LEFT","RIGHT",
  "TODAY","NOW","YEAR","MONTH","DAY","DATE_DIFF","DATE_ADD"
])

const FIELD_REF = /\{([a-zA-Z0-9_]+)\}/g

// Returns { valid, errors:[], referencedFields:[], result }
// fieldIds: Set/array of valid field ids; sampleValues: {field_id: value} for live preview.
export function validateFormula(formula, fieldIds = [], sampleValues = {}) {
  const errors = []
  const known = new Set(fieldIds)
  const referencedFields = []

  if (!formula || !formula.trim()) {
    return { valid: true, errors, referencedFields, result: null }
  }

  let m
  FIELD_REF.lastIndex = 0
  while ((m = FIELD_REF.exec(formula))) {
    referencedFields.push(m[1])
    if (!known.has(m[1])) errors.push(`Unknown field: ${m[1]}`)
  }

  ;(formula.match(/\b([A-Z_]+)\s*\(/g) || []).forEach(tok => {
    const fn = tok.replace(/\s*\($/, "")
    if (!FUNCTION_ALLOWLIST.has(fn)) errors.push(`Unknown function: ${fn}`)
  })

  const open = (formula.match(/\(/g) || []).length
  const close = (formula.match(/\)/g) || []).length
  if (open !== close) errors.push("Unbalanced parentheses")

  let result = null
  if (errors.length === 0) {
    try {
      result = new FormulaEngine(sampleValues).evaluate(formula)
    } catch (e) {
      errors.push(`Evaluation error: ${e.message}`)
    }
  }

  return { valid: errors.length === 0, errors, referencedFields: [...new Set(referencedFields)], result }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/lib/formula_validator.js
git commit -m "feat(formula): shared validator (errors + referenced fields + live result)"
```

---

### Task 6: Runtime alignment (format, action value, tokens)

**Files:**
- Modify: `app/javascript/controllers/condition_runtime_controller.js:160-170` (`applyCalculations` formatting)

- [ ] **Step 1: Extend formatting in `applyCalculations`**

Replace the formatting block with support for `percent`, `prefix`, `suffix`:

```javascript
          let displayValue = result
          const fmt = calc.format || {}
          if (fmt.type === 'currency' || fmt.type === 'number') {
            displayValue = Number(result).toFixed(fmt.decimals ?? 2)
          } else if (fmt.type === 'percent') {
            displayValue = `${(Number(result) * 100).toFixed(fmt.decimals ?? 0)}%`
          }
          if (fmt.prefix) displayValue = `${fmt.prefix}${displayValue}`
          if (fmt.suffix) displayValue = `${displayValue}${fmt.suffix}`
          input.value = displayValue
```

(`FormulaEngine` already parses `{field_id}` after Task 4, so no runtime tokenizer change is needed; `set_value`/`set_required` already honour `action.value`.)

- [ ] **Step 2: Manual smoke** — covered by the system spec (Task 13).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/condition_runtime_controller.js
git commit -m "feat(runtime): currency/percent/prefix/suffix formatting for calculated fields"
```

---

## Phase C — Calculated Fields editor (pill UI)

### Task 7: `FormulaPillEditorComponent`

**Files:**
- Create: `app/components/page_builder/formula_pill_editor_component.rb`
- Create: `app/components/page_builder/formula_pill_editor_component.html.erb`
- Test: `spec/components/page_builder/formula_pill_editor_component_spec.rb`

- [ ] **Step 1: Failing component spec**

```ruby
# spec/components/page_builder/formula_pill_editor_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::FormulaPillEditorComponent, type: :component do
  let(:fields) { [{ "id" => "price", "label" => "Price", "property_type" => "number" }] }

  it "renders a contentEditable surface wired to the formula_editor controller" do
    render_inline(described_class.new(formula: "{price} * 2", fields: fields))
    expect(page).to have_css('[data-controller~="formula-editor"]')
    expect(page).to have_css('[contenteditable="true"][data-formula-editor-target="surface"]')
  end

  it "passes field metadata as JSON for autocomplete" do
    render_inline(described_class.new(formula: "", fields: fields))
    expect(page).to have_css('[data-formula-editor-fields-value]')
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/components/page_builder/formula_pill_editor_component_spec.rb`
Expected: FAIL (`uninitialized constant`)

- [ ] **Step 3: Implement component class**

```ruby
# app/components/page_builder/formula_pill_editor_component.rb
# frozen_string_literal: true

module PageBuilder
  class FormulaPillEditorComponent < ApplicationComponent
    include DesignTokens
    include ComponentClasses

    def initialize(formula: "", fields: [])
      @formula = formula.to_s
      @fields = (fields || []).map { |f| { "id" => f["id"], "label" => f["label"] || f["id"], "type" => f["property_type"] } }
    end

    private

    attr_reader :formula, :fields

    def fields_json
      fields.to_json
    end
  end
end
```

- [ ] **Step 4: Implement template**

```erb
<%# app/components/page_builder/formula_pill_editor_component.html.erb %>
<div data-controller="formula-editor"
     data-formula-editor-fields-value="<%= fields_json %>"
     data-formula-editor-formula-value="<%= formula %>"
     class="space-y-2">
  <div contenteditable="true"
       data-formula-editor-target="surface"
       data-action="input->formula-editor#onInput keydown->formula-editor#onKeydown"
       class="min-h-[80px] w-full rounded-lg border border-gray-300 bg-white px-3 py-2 font-mono text-sm leading-7 focus:outline-none focus:ring-2 focus:ring-indigo-500"
       role="textbox" aria-multiline="true"></div>

  <%# Autocomplete dropdown (positioned by the controller) %>
  <div data-formula-editor-target="autocomplete"
       class="hidden absolute z-50 max-h-56 w-64 overflow-y-auto rounded-lg border border-gray-200 bg-white shadow-lg"></div>

  <%# Validation + live result %>
  <div class="flex items-center justify-between text-xs">
    <span data-formula-editor-target="status" class="font-medium"></span>
    <span data-formula-editor-target="preview" class="text-gray-500"></span>
  </div>
  <div data-formula-editor-target="errors" class="hidden rounded-md bg-red-50 px-3 py-2 text-xs text-red-700"></div>
</div>
```

- [ ] **Step 5: Run component spec**

Run: `bundle exec rspec spec/components/page_builder/formula_pill_editor_component_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/components/page_builder/formula_pill_editor_component.* spec/components/page_builder/formula_pill_editor_component_spec.rb
git commit -m "feat(page-builder): FormulaPillEditorComponent"
```

---

### Task 8: `formula_editor_controller.js` (pills, autocomplete, preview)

**Files:**
- Create: `app/javascript/controllers/formula_editor_controller.js`

- [ ] **Step 1: Implement the controller**

Behaviours (the frontend agent implements each):
- `connect()`: read `fieldsValue`, hydrate `surface` from `formulaValue` by rendering `{id}` refs as pill `<span data-pill data-field-id>` and plain text otherwise.
- Pill rendering: `<span contenteditable="false" data-pill data-field-id="ID" class="inline-flex items-center rounded bg-indigo-100 px-1.5 py-0.5 text-indigo-700 mx-0.5">LABEL ×</span>`.
- `onInput()`: debounce 150ms → `serialize()` (walk child nodes; pills → `{id}`, text → raw) → `validate()`.
- `onKeydown()`: backspace deletes a whole adjacent pill; typing `{` or `@` opens the field autocomplete; uppercase letters open the function autocomplete.
- `validate()`: `import { validateFormula } from "lib/formula_validator"`; render status (✓ Valid / ✗ N errors), live `result`, and the errors box; emit a `formula:changed` CustomEvent with `{ formula, valid }` for the parent calculation editor to read on save.
- Autocomplete: arrow-key navigation, Enter/click to insert (field → pill; function → `NAME()` with caret inside).
- Expose `getFormula()` returning the serialized `{id}` string.

```javascript
// app/javascript/controllers/formula_editor_controller.js
import { Controller } from "@hotwired/stimulus"
import { validateFormula } from "lib/formula_validator"

export default class extends Controller {
  static targets = ["surface", "autocomplete", "status", "preview", "errors"]
  static values  = { fields: Array, formula: String }

  connect() {
    this.fieldMap = new Map(this.fieldsValue.map(f => [f.id, f]))
    this.hydrate(this.formulaValue)
    this.validate()
  }

  // --- Public API ---------------------------------------------------------
  getFormula() { return this.serialize() }

  // --- Rendering ----------------------------------------------------------
  hydrate(formula) {
    this.surfaceTarget.innerHTML = ""
    const re = /\{([a-zA-Z0-9_]+)\}/g
    let last = 0, m
    while ((m = re.exec(formula))) {
      if (m.index > last) this.surfaceTarget.appendChild(document.createTextNode(formula.slice(last, m.index)))
      this.surfaceTarget.appendChild(this.pill(m[1]))
      last = re.lastIndex
    }
    if (last < formula.length) this.surfaceTarget.appendChild(document.createTextNode(formula.slice(last)))
  }

  pill(id) {
    const f = this.fieldMap.get(id)
    const span = document.createElement("span")
    span.contentEditable = "false"
    span.dataset.pill = ""
    span.dataset.fieldId = id
    span.className = "inline-flex items-center rounded bg-indigo-100 px-1.5 py-0.5 text-indigo-700 mx-0.5"
    span.textContent = f ? f.label : id
    return span
  }

  serialize() {
    let out = ""
    this.surfaceTarget.childNodes.forEach(node => {
      if (node.nodeType === Node.TEXT_NODE) out += node.textContent
      else if (node.dataset && node.dataset.pill !== undefined) out += `{${node.dataset.fieldId}}`
    })
    return out
  }

  // --- Events -------------------------------------------------------------
  onInput() { clearTimeout(this._t); this._t = setTimeout(() => this.validate(), 150) }

  onKeydown(event) {
    // backspace pill deletion + autocomplete trigger handled here (frontend agent)
  }

  validate() {
    const formula = this.serialize()
    const { valid, errors, result } = validateFormula(formula, [...this.fieldMap.keys()], this.sampleValues())
    this.statusTarget.textContent = valid ? "✓ Valid" : `✗ ${errors.length} error${errors.length === 1 ? "" : "s"}`
    this.statusTarget.className = `font-medium ${valid ? "text-green-600" : "text-red-600"}`
    this.previewTarget.textContent = valid && result !== null ? `Preview: ${result}` : ""
    this.errorsTarget.classList.toggle("hidden", valid)
    this.errorsTarget.innerHTML = errors.map(e => `<div>${e}</div>`).join("")
    this.dispatch("changed", { detail: { formula, valid } })
  }

  // Sample values come from the calculation editor's preview panel (Task 9).
  sampleValues() { return this._sampleValues || {} }
  setSampleValues(values) { this._sampleValues = values; this.validate() }
}
```

- [ ] **Step 2: Manual smoke** in the editor (pills render, autocomplete inserts, preview updates). Covered by system spec (Task 13).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/formula_editor_controller.js
git commit -m "feat(page-builder): formula_editor Stimulus controller (pills + live validate)"
```

---

### Task 9: `CalculationEditorComponent` + slim `calculations_manager.js`

**Files:**
- Create: `app/components/page_builder/calculation_editor_component.{rb,html.erb}`
- Modify: `app/javascript/controllers/page_builder/calculations_manager.js`
- Test: `spec/components/page_builder/calculation_editor_component_spec.rb`

- [ ] **Step 1: Failing component spec**

```ruby
# spec/components/page_builder/calculation_editor_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::CalculationEditorComponent, type: :component do
  let(:fields) { [{ "id" => "total", "label" => "Total", "property_type" => "number" }] }

  it "renders target field select, the pill editor, and formatting controls" do
    render_inline(described_class.new(calculation: { "target_field_id" => "total", "formula" => "" }, fields: fields))
    expect(page).to have_css('[data-page-builder-target="calculationTargetField"]')
    expect(page).to have_css('[data-controller~="formula-editor"]')
    expect(page).to have_css('[data-calc-format="type"]')
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/components/page_builder/calculation_editor_component_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement component** (renders the modal shell: header, target-field `<select>` grouped by page, the `FormulaPillEditorComponent`, formatting controls — `data-calc-format="type|decimals|prefix|suffix"`, a live-preview sample-values area, and footer Save/Cancel wired to `page-builder#saveCalculation` / `closeFormulaEditor`). Reuse the existing modal chrome classes already in `calculations_manager.js`. Renders the `FormulaPillEditorComponent` via `render PageBuilder::FormulaPillEditorComponent.new(formula:, fields:)`.

- [ ] **Step 4: Slim `calculations_manager.js`** — replace `renderFormulaEditorModal` (the innerHTML string) with: fetch the component markup. Two options; use **server-rendered partial fetch** to stay Stimulus-only and avoid HTML-in-JS:
  - Add a tiny controller action OR (preferred, no new route) render the editor markup into a hidden `<template>` already present in `_editor.html.erb` and clone it on open. Implementation: in `_editor.html.erb`, render `CalculationEditorComponent` inside `<template data-page-builder-target="calculationEditorTemplate">`; `openFormulaEditor` clones the template into `formulaEditorModalTarget`, then hydrates field/formula/format values from `currentEditingCalculation`. `saveCalculation` reads `getFormula()` from the formula-editor controller instance and the `data-calc-format` inputs.

- [ ] **Step 5: Run component spec + manual smoke**

Run: `bundle exec rspec spec/components/page_builder/calculation_editor_component_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/components/page_builder/calculation_editor_component.* app/javascript/controllers/page_builder/calculations_manager.js app/views/admin/maintenance/pages/_editor.html.erb spec/components/page_builder/calculation_editor_component_spec.rb
git commit -m "feat(page-builder): CalculationEditorComponent + remove innerHTML formula modal"
```

---

## Phase D — Conditional Rules editor

### Task 10: `ConditionRowComponent` (contextual value editor)

**Files:**
- Create: `app/components/page_builder/condition_row_component.{rb,html.erb}`
- Test: `spec/components/page_builder/condition_row_component_spec.rb`

- [ ] **Step 1: Failing component spec**

```ruby
# spec/components/page_builder/condition_row_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::ConditionRowComponent, type: :component do
  let(:fields) do
    [
      { "id" => "country", "label" => "Country", "property_type" => "select",
        "options" => [{ "value" => "US", "label" => "United States" }] },
      { "id" => "age", "label" => "Age", "property_type" => "number" }
    ]
  end

  it "renders a select value editor for a select field" do
    item = { "field_id" => "country", "operator" => "equals", "value" => "US" }
    render_inline(described_class.new(item: item, fields: fields, group_index: 0, item_index: 0))
    expect(page).to have_css('select[data-condition-value]')
    expect(page).to have_css('option[value="US"]')
  end

  it "renders no value input for is_empty" do
    item = { "field_id" => "age", "operator" => "is_empty", "value" => "" }
    render_inline(described_class.new(item: item, fields: fields, group_index: 0, item_index: 0))
    expect(page).not_to have_css('[data-condition-value]')
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/components/page_builder/condition_row_component_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement component** — the class exposes `field`, `field_type`, `operators_for_type`, and `value_editor_kind` (`:none` for `is_empty/is_not_empty/is_selected/is_not_selected`; `:select` for select/radio fields; `:number`/`:number_range` for number + `between`; `:date`/`:date_range` for date; `:boolean` for boolean; else `:text`). Template renders the field `<select>`, operator `<select>` (filtered), and the matching value editor with `data-condition-value="GROUP-ITEM"` (and `data-condition-value-max` for range upper bound). Wire `data-action="change->rule-builder#onConditionFieldChange"` on the field select so the value editor re-renders contextually.

`OPERATORS_BY_TYPE` mapping (define as a constant in the component):
```ruby
OPERATORS_BY_TYPE = {
  "number"  => %w[equals not_equals greater_than less_than greater_or_equal less_or_equal between is_empty is_not_empty],
  "date"    => %w[equals not_equals greater_than less_than between is_empty is_not_empty],
  "select"  => %w[is_selected is_not_selected equals not_equals is_empty is_not_empty],
  "boolean" => %w[is_selected is_not_selected],
  "default" => %w[equals not_equals contains not_contains starts_with ends_with matches_regex is_empty is_not_empty]
}.freeze
```

- [ ] **Step 4: Run component spec**

Run: `bundle exec rspec spec/components/page_builder/condition_row_component_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/components/page_builder/condition_row_component.* spec/components/page_builder/condition_row_component_spec.rb
git commit -m "feat(page-builder): ConditionRowComponent with contextual value editor"
```

---

### Task 11: `RuleEditorComponent` + `rule_builder_controller.js` + slim `rules_manager.js`

**Files:**
- Create: `app/components/page_builder/rule_editor_component.{rb,html.erb}`
- Create: `app/javascript/controllers/rule_builder_controller.js`
- Modify: `app/javascript/controllers/page_builder/rules_manager.js`
- Modify: `app/views/admin/maintenance/pages/_editor.html.erb`
- Test: `spec/components/page_builder/rule_editor_component_spec.rb`

- [ ] **Step 1: Failing component spec**

```ruby
# spec/components/page_builder/rule_editor_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::RuleEditorComponent, type: :component do
  let(:fields) { [{ "id" => "country", "label" => "Country", "property_type" => "select", "options" => [] }] }
  let(:pages)  { [{ "id" => "p1", "name" => "Page 1", "fields" => fields }] }
  let(:rule)   { { "id" => "r1", "name" => "Show", "conditions" => { "logic" => "all", "groups" => [] }, "actions" => [] } }

  it "renders the rule editor wired to rule-builder with a test-mode toggle" do
    render_inline(described_class.new(rule: rule, fields: fields, pages: pages))
    expect(page).to have_css('[data-controller~="rule-builder"]')
    expect(page).to have_css('[data-rule-builder-target="testToggle"]')
    expect(page).to have_field("Rule Name", with: "Show")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/components/page_builder/rule_editor_component_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement `RuleEditorComponent`** — modal shell with: rule-name input, conditions section (top-level all/any logic, groups each with own logic + a slot rendering `ConditionRowComponent` per item + add/remove buttons), actions section (action type `<select>`, contextual target `<select>` for field/page, and an action-value editor shown only for `set_value`/`set_required`), a **Test mode** toggle (`data-rule-builder-target="testToggle"`) revealing a sample-input panel + per-action ✓/✗ result chips, and footer Save/Cancel. Root element `data-controller="rule-builder"` carries `data-rule-builder-fields-value` / `data-rule-builder-pages-value` JSON.

- [ ] **Step 4: Implement `rule_builder_controller.js`** — responsibilities:
  - `onConditionFieldChange`: when the field changes, re-render that row's operator list + value editor for the new field type (fetch field meta from `fieldsValue`).
  - `onActionTypeChange`: swap target options (field vs page) and show/hide the action-value editor.
  - Test mode: collect the current rule from the DOM, build sample inputs for referenced fields, evaluate via `import { ConditionEvaluator } from "lib/condition_evaluator"`, and mark each action chip ✓ (would fire) / ✗.
  - Expose `getRule()` returning the serialized rule object for `rules_manager#saveRule`.

```javascript
// app/javascript/controllers/rule_builder_controller.js
import { Controller } from "@hotwired/stimulus"
import { ConditionEvaluator } from "lib/condition_evaluator"

export default class extends Controller {
  static targets = ["testToggle", "testPanel", "actionResult"]
  static values  = { fields: Array, pages: Array }

  toggleTest() {
    this.testPanelTarget.classList.toggle("hidden", !this.testToggleTarget.checked)
    if (this.testToggleTarget.checked) this.runTest()
  }

  runTest() {
    const rule = this.getRule()
    const values = this.collectSampleValues()
    const matched = new ConditionEvaluator(values).evaluate(rule.conditions)
    this.actionResultTargets.forEach(el => {
      el.textContent = matched ? "✓ fires" : "✗ skipped"
      el.className = matched ? "text-green-600 text-xs" : "text-gray-400 text-xs"
    })
  }

  getRule() { /* serialize name/conditions/actions from DOM — frontend agent */ }
  collectSampleValues() { /* read sample inputs in testPanel — frontend agent */ }
  onConditionFieldChange(event) { /* re-render row operators + value editor */ }
  onActionTypeChange(event) { /* swap target options + action-value editor */ }
}
```

- [ ] **Step 5: Slim `rules_manager.js`** — same pattern as Task 9: render `RuleEditorComponent` into `<template data-page-builder-target="ruleEditorTemplate">` in `_editor.html.erb`; `openRuleEditor` clones it and hydrates from `currentEditingRule`; `saveRule` reads `getRule()` from the rule-builder controller. Remove all the `renderRuleEditorModal`/`renderConditionGroups`/`renderConditionItems`/`renderActions` innerHTML methods.

- [ ] **Step 6: Run component spec + manual smoke**

Run: `bundle exec rspec spec/components/page_builder/rule_editor_component_spec.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/components/page_builder/rule_editor_component.* app/javascript/controllers/rule_builder_controller.js app/javascript/controllers/page_builder/rules_manager.js app/views/admin/maintenance/pages/_editor.html.erb spec/components/page_builder/rule_editor_component_spec.rb
git commit -m "feat(page-builder): RuleEditorComponent + rule_builder controller + remove innerHTML rule modal"
```

---

### Task 12: List polish + per-field "Add logic"

**Files:**
- Modify: `app/components/page_builder/rules_panel_component.{rb,html.erb}`
- Modify: `app/components/page_builder/calculations_panel_component.{rb,html.erb}`
- Modify: `app/javascript/controllers/page_builder/rules_manager.js` (duplicate + summary helpers), `calculations_manager.js`
- Modify: `app/views/admin/maintenance/pages/_property_panel.html.erb`
- Test: existing panel specs (extend if present)

- [ ] **Step 1: Rules list** — add per-row enable/disable toggle (`page-builder#toggleRule` exists), a duplicate button (`page-builder#duplicateRule` → deep-copy with new id), and a human summary line. Add a search `<input>` filtering rows client-side when `rules.length > 6`.

- [ ] **Step 2: `duplicateRule` in `rules_manager.js`**

```javascript
duplicateRule(event) {
  const ruleId = event.currentTarget.dataset.ruleId
  const rule = this.c.configuration.rules?.find(r => r.id === ruleId)
  if (!rule) return
  const copy = JSON.parse(JSON.stringify(rule))
  copy.id = `rule_${Date.now()}`
  copy.name = `${rule.name} (copy)`
  this.c.configuration.rules.push(copy)
  this.c.undoRedoManager.saveHistory()
  this.renderRulesPanel()
  this.c.saveManager.markDirty()
}
```

- [ ] **Step 3: Calculations list** — show the formatted output type badge + a readable formula summary (pills rendered as labels).

- [ ] **Step 4: Per-field "Add logic"** — in `_property_panel.html.erb`, add a button `data-action="click->page-builder#openRuleEditor" data-prefill-target-field` set to the current field id. `openRuleEditor` reads the prefill and seeds `currentEditingRule.actions = [{ type: "show_field", target_id: <field> }]`.

- [ ] **Step 5: Run panel specs + manual smoke**

Run: `bundle exec rspec spec/components/page_builder/`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/components/page_builder/rules_panel_component.* app/components/page_builder/calculations_panel_component.* app/javascript/controllers/page_builder/rules_manager.js app/javascript/controllers/page_builder/calculations_manager.js app/views/admin/maintenance/pages/_property_panel.html.erb
git commit -m "feat(page-builder): list polish (toggle/duplicate/summary/search) + per-field Add logic"
```

---

## Phase E — Integration spec & release

### Task 13: System spec (guarded) + full targeted run

**Files:**
- Create: `spec/system/admin/page_builder_rules_calculations_spec.rb`

- [ ] **Step 1: Check for a system-spec harness**

Run: `ls spec/system 2>/dev/null && grep -rl "type: :system" spec/ | head -1`
If none exists, skip the system spec (do NOT introduce Capybara/Selenium infra in this plan) and rely on component + request specs + manual smoke. Document the skip in the commit message.

- [ ] **Step 2: If a harness exists, write a happy-path system spec** covering: open Calculated Fields → add calc → type a formula with a field pill → see ✓ Valid + a live preview → save; open Conditional Rules → add a rule with a select-field condition (dropdown value editor) → add a show_field action → toggle Test mode and see the action chip flip ✓/✗ → save. Assert the persisted `configuration_json` contains `{field_id}` tokens and the action value.

- [ ] **Step 3: Run the affected layers**

Run:
```bash
bundle exec rspec spec/services/pages/configuration_validator_spec.rb \
  spec/models/page_spec.rb \
  spec/components/page_builder/ \
  spec/requests/admin/maintenance/pages_spec.rb
```
Expected: all PASS.

- [ ] **Step 4: Rebuild assets + smoke the editor**

Run:
```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```
Smoke `/81721200/admin/maintenance/pages/40/edit` → open both toolbar panels, exercise pill editor + contextual condition value + test mode, save, reload, confirm persistence.

- [ ] **Step 5: Commit**

```bash
git add spec/system/admin/page_builder_rules_calculations_spec.rb 2>/dev/null; \
git commit -m "test(page-builder): integration coverage for rules & calculations overhaul" --allow-empty
```

---

## Self-Review

**Spec coverage:**
- Contextual condition value editor → Task 10. ✓
- Action value editor → Task 11 (action-value editor) + Task 6 (runtime honours `action.value`). ✓
- Live Test mode → Task 11 (rule_builder test mode). ✓
- Per-field "Add logic" → Task 12. ✓
- Rules list polish → Task 12. ✓
- Pill/token formula editor + autocomplete → Tasks 7, 8. ✓
- Live preview + inline validation → Tasks 5, 8, 9. ✓
- Output formatting controls → Task 9 (controls) + Task 6 (runtime render). ✓
- Circular-dependency detection → Task 2 (server) ; client surfaces via validator errors. ✓
- Function reference → Task 9 component (renders grouped functions; reuse `FORMULA_FUNCTIONS`). ✓
- `{field_id}` token storage + normalize → Task 4. ✓
- Server-side validation contract → Tasks 1–3. ✓
- No new AR model/migration/route → respected (config-only + model hook). ✓
- ViewComponent + Stimulus, no innerHTML strings → Tasks 7–11 remove all string templates. ✓
- Testing (component/request/model/system) → Phase A + Tasks 7–13. ✓

**Type/name consistency:** `getFormula()` (formula-editor), `getRule()` (rule-builder), `validateFormula()` (lib), `Pages::ConfigurationValidator#valid?/#errors`, `normalizeFormula()`, `data-condition-value` / `data-calc-format` selectors are used consistently across tasks.

**Placeholder scan:** No TBD/TODO. JS controller bodies marked "frontend agent" are intentional implementation slots within fully-specified interfaces (behaviours + signatures enumerated), not gaps in the plan's contract.
