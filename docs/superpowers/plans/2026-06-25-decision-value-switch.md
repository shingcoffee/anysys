# Decision Value-Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the Decision element so its single Condition section computes a subject value and each branch routes by a Match Value (value → `case/when`, boolean → ternary), deleting the per-branch condition UI.

**Architecture:** The flowchart compiles to Ruby. The element-level `condition` (a group of field / query-count rows with per-join AND/OR) yields a subject; `subject_kind` (`:value` | `:boolean`) selects the generated form. Branch routing moves from per-branch `condition` to per-branch `matchValue`, carried on the connection through `FlowchartTopologyAnalyzer` → `ActivityGenerator` → `DecisionGenerator`. The JS property editor is updated to author the new shapes.

**Tech Stack:** Ruby 3.2 / Rails 8.1, RSpec; StimulusJS property-editor controllers; Tailwind. Spec: `docs/superpowers/specs/2026-06-25-decision-value-switch-design.md`.

---

## Naming contract (use these exact names across all tasks)

**Ruby — `CodeGenerators::Shared::ConditionBuilder`:**
`subject_kind(condition)`, `build_subject_value(condition)`, `build_condition_group(group)`, `build_group_member(member)`, `ruby_join_operator(join)`, `group_conditions(condition)`.

**Ruby — `DecisionGenerator`:**
`connection_match_values`, `build_value_switch(route_var, subject_code, match_values)`, `build_boolean_switch(route_var, cond_code, match_values)`, `branch_for_bool(match_values, bool)`, `default_branch_key(match_values)`, `default_branch_index`, `no_condition_body(route_var)`.

**JSON shapes:**
- Condition group: `{ "type":"group", "joins":["AND","OR"], "conditions":[ {"kind":"field","leftOperand":…,"operator":…,"rightOperand":…} | {"kind":"query_count","queryConfig":…,"countOperator":…,"countValue":…} ] }`
- Per-branch injected: `{ "branch":"branch_0", "matchValue":"active" }` under `_connection_match_values`.
- Branch object: `{ "name","matchValue","description","branchKey","elementId" }`.

**JS data-attributes / actions:**
- Condition row: `[data-condition-row]`, type toggle `[data-condition-row-type-toggle]` (buttons `data-row-type="field|query_count"`), join `[data-condition-join]` (button `data-join-operator="AND|OR"`).
- Actions: `switchConditionRowType`, `toggleConditionJoin`, `addConditionRow`, `removeConditionRow` (existing names reused where present).
- Branch modal: `[data-branch-match-value]` (free-text input), `[data-branch-match-value-select]` (true/false select), action `syncBranchNameFromMatchValue`.

---

## File Structure

**Ruby (modify):**
- `app/services/code_generators/shared/condition_builder.rb` — per-join `joins`, query-count members, `subject_kind`, `build_subject_value`.
- `app/services/code_generators/element_types/decision/decision_generator.rb` — dual-shape body; drop `firstMatchOnly`/fan-out/if-elsif.
- `app/services/flowchart_topology_analyzer.rb` — per-branch `match_value` (was `condition`).
- `app/services/activity_generator.rb` — inject `_connection_match_values` (was `_connection_conditions`).

**JS (modify):**
- `app/javascript/flowchart/constants/schemas.js` — Decision schema.
- `app/javascript/controllers/property_editor/branch_manager/condition_builder.js` — per-row type toggle, per-join toggles, value mode, new collect shape, `_conditionSubjectKind`.
- `app/javascript/controllers/property_editor/branch_manager/query_count.js` — generalize QC row build for condition rows.
- `app/javascript/controllers/property_editor/templates/branch.js` — modal (drop condition/presets, add Match Value), branch item subtitle.
- `app/javascript/controllers/property_editor/branch_manager/modal_lifecycle.js` — Match Value collect/prefill, name auto-fill, adaptive input; strip condition.
- `app/javascript/controllers/property_editor/branch_manager.js` — `collectBranches` matchValue, drop presets/branch-condition helpers, write `conn.matchValue`.
- `app/javascript/controllers/property_editor/branch_manager/canvas_operations.js` — `conn.matchValue`.
- `app/javascript/controllers/property_editor/templates/conditions.js` — match-value summary.
- `app/javascript/controllers/property_editor_controller.js` — new/removed action delegations.

**Specs (modify/create):**
- `spec/services/code_generators/shared/condition_builder_spec.rb`
- `spec/services/code_generators/element_types/decision/decision_generator_spec.rb`
- `spec/services/flowchart_topology_analyzer_spec.rb`
- `spec/services/activity_generator_spec.rb`

---

## PHASE A — Backend contract + generator (TDD)

### Task 1: `ConditionBuilder` — per-join joins, query-count members, subject kind

**Files:**
- Modify: `app/services/code_generators/shared/condition_builder.rb`
- Test: `spec/services/code_generators/shared/condition_builder_spec.rb`

- [ ] **Step 1: Write failing tests**

Add to `spec/services/code_generators/shared/condition_builder_spec.rb` (inside a class that `include CodeGenerators::Shared::ConditionBuilder`; reuse the existing harness in that file):

```ruby
describe "value subject" do
  let(:cond) { { "type" => "group", "joins" => [],
                 "conditions" => [{ "kind" => "field", "leftOperand" => "ctx.model.status", "operator" => "", "rightOperand" => "" }] } }

  it "classifies a single bare field as :value" do
    expect(subject.subject_kind(cond)).to eq(:value)
  end

  it "builds the operand value" do
    expect(subject.build_subject_value(cond)).to eq("ctx.dig(:model, :status)")
  end
end

describe "boolean subject" do
  it "classifies a comparison as :boolean" do
    cond = { "type" => "group", "joins" => [],
             "conditions" => [{ "kind" => "field", "leftOperand" => "ctx.status", "operator" => "==", "rightOperand" => "approved" }] }
    expect(subject.subject_kind(cond)).to eq(:boolean)
  end

  it "classifies a query-count row as :boolean" do
    cond = { "type" => "group", "joins" => [],
             "conditions" => [{ "kind" => "query_count", "queryConfig" => { "entityId" => 3 }, "countOperator" => ">", "countValue" => 0 }] }
    expect(subject.subject_kind(cond)).to eq(:boolean)
  end

  it "classifies multiple rows as :boolean" do
    cond = { "type" => "group", "joins" => ["AND"],
             "conditions" => [{ "kind" => "field", "leftOperand" => "ctx.a", "operator" => "", "rightOperand" => "" },
                              { "kind" => "field", "leftOperand" => "ctx.b", "operator" => "==", "rightOperand" => "1" }] }
    expect(subject.subject_kind(cond)).to eq(:boolean)
  end
end

describe "per-join groups" do
  it "folds left-to-right with explicit parens and per-join operators" do
    cond = { "type" => "group", "joins" => ["AND", "OR"],
             "conditions" => [
               { "kind" => "field", "leftOperand" => "ctx.a", "operator" => "==", "rightOperand" => "1" },
               { "kind" => "field", "leftOperand" => "ctx.b", "operator" => "==", "rightOperand" => "2" },
               { "kind" => "field", "leftOperand" => "ctx.c", "operator" => "==", "rightOperand" => "3" }
             ] }
    expect(subject.build_structured_condition(cond))
      .to eq('((ctx.dig(:a) == 1 && ctx.dig(:b) == 2) || ctx.dig(:c) == 3)')
  end

  it "includes a query-count member inside a group" do
    cond = { "type" => "group", "joins" => ["AND"],
             "conditions" => [
               { "kind" => "field", "leftOperand" => "ctx.a", "operator" => "==", "rightOperand" => "1" },
               { "kind" => "query_count", "queryConfig" => { "entityId" => 7 }, "countOperator" => ">", "countValue" => 0 }
             ] }
    code = subject.build_structured_condition(cond)
    expect(code).to start_with("(ctx.dig(:a) == 1 && ")
    expect(code).to include("FlowchartRuntime::QueryBuilder.for_entity(Entity.find(7)")
    expect(code).to include(".execute.total_count > 0")
  end
end
```

- [ ] **Step 2: Run and verify failure**

Run: `bundle exec rspec spec/services/code_generators/shared/condition_builder_spec.rb -e "value subject" -e "boolean subject" -e "per-join groups"`
Expected: FAIL (`NoMethodError: subject_kind` / wrong group string).

- [ ] **Step 3: Implement**

In `condition_builder.rb`, **replace** `build_condition_group` (lines ~49-58) and **add** the new public helpers. Final state of the relevant region:

```ruby
def build_structured_condition(condition)
  return "true" if condition.blank?

  if condition["type"] == "group"
    build_condition_group(condition)
  else
    build_single_condition(condition)
  end
end

# :value iff the condition is a single bare field row (no operator); else :boolean.
def subject_kind(condition)
  conds = group_conditions(condition)
  if conds.length == 1
    only = conds.first
    is_field = only["kind"] != "query_count" && only["conditionType"] != "query_count"
    blank_op = only["operator"].to_s.strip.empty?
    return :value if is_field && blank_op
  end
  :boolean
end

# Ruby code for the raw operand value of a :value subject.
def build_subject_value(condition)
  only = group_conditions(condition).first || {}
  condition_operand_to_ruby(only["leftOperand"])
end

def group_conditions(condition)
  return [] unless condition.is_a?(Hash)
  condition["type"] == "group" ? (condition["conditions"] || []) : [condition]
end
```

Then **replace** the private `build_condition_group` with:

```ruby
def build_condition_group(group)
  conditions = group["conditions"] || []
  return "true" if conditions.empty?

  joins = group["joins"]
  joins = [] unless joins.is_a?(Array)

  parts = conditions.map { |c| build_group_member(c) }.reject(&:blank?)
  return "true" if parts.empty?

  expr = parts.first
  parts.each_with_index do |part, i|
    next if i.zero?
    expr = "(#{expr} #{ruby_join_operator(joins[i - 1])} #{part})"
  end
  expr
end

def build_group_member(member)
  if member["kind"] == "query_count" || member["conditionType"] == "query_count"
    build_query_count_condition(member)
  elsif member["type"] == "group"
    build_condition_group(member)
  else
    build_single_condition(member)
  end
end

def ruby_join_operator(join)
  join.to_s.upcase == "OR" ? "||" : "&&"
end
```

Move `subject_kind`, `build_subject_value`, `group_conditions` to the public area (above `private`); keep `build_condition_group`, `build_group_member`, `ruby_join_operator` under `private`.

- [ ] **Step 4: Run and verify pass**

Run: `bundle exec rspec spec/services/code_generators/shared/condition_builder_spec.rb`
Expected: PASS (fix any pre-existing group-string assertions that used the old single-`operator` format — update them to the parenthesized per-join output).

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/shared/condition_builder.rb spec/services/code_generators/shared/condition_builder_spec.rb
git commit -m "feat(flowchart): condition builder per-join joins + subject kind"
```

---

### Task 2: `DecisionGenerator` — dual-shape body

**Files:**
- Modify: `app/services/code_generators/element_types/decision/decision_generator.rb`
- Test: `spec/services/code_generators/element_types/decision/decision_generator_spec.rb`

- [ ] **Step 1: Write failing tests**

Replace the routing-related examples in the decision spec with:

```ruby
def gen(config) = described_class.new(config)

describe "#generate_body" do
  let(:value_cond) do
    { "type" => "group", "joins" => [],
      "conditions" => [{ "kind" => "field", "leftOperand" => "ctx.model.status", "operator" => "", "rightOperand" => "" }] }
  end
  let(:bool_cond) do
    { "type" => "group", "joins" => [],
      "conditions" => [{ "kind" => "field", "leftOperand" => "ctx.status", "operator" => "==", "rightOperand" => "approved" }] }
  end

  it "emits case/when for a value subject" do
    body = gen("condition" => value_cond, "_route_index" => 0,
               "_connection_match_values" => [
                 { "branch" => "branch_0", "matchValue" => "active" },
                 { "branch" => "branch_1", "matchValue" => "pending" },
                 { "branch" => "branch_2", "matchValue" => "" }
               ]).generate_body
    expect(body).to eq(<<~RUBY.chomp)
      ctx[:_route_0] = case ctx.dig(:model, :status).to_s
      when "active" then :branch_0
      when "pending" then :branch_1
      else :branch_2
      end
      true
    RUBY
  end

  it "emits a ternary for a boolean subject, indices by true/false match value" do
    body = gen("condition" => bool_cond, "_route_index" => 0,
               "_connection_match_values" => [
                 { "branch" => "branch_0", "matchValue" => "true" },
                 { "branch" => "branch_1", "matchValue" => "false" }
               ]).generate_body
    expect(body).to eq(<<~RUBY.chomp)
      ctx[:_route_0] = (ctx.dig(:status) == "approved") ? :branch_0 : :branch_1
      true
    RUBY
  end

  it "routes a missing boolean arm to the default branch" do
    body = gen("condition" => bool_cond, "_route_index" => 0, "defaultBranchIndex" => "1",
               "_connection_match_values" => [
                 { "branch" => "branch_0", "matchValue" => "true" },
                 { "branch" => "branch_1", "matchValue" => "" }
               ]).generate_body
    expect(body).to include("? :branch_0 : :branch_1")
  end

  it "defaults to branch_0 when no condition" do
    expect(gen("condition" => nil, "_route_index" => 0).generate_body)
      .to include("ctx[:_route_0] = :branch_0")
  end
end

describe "#validate_config" do
  it "requires a condition" do
    expect(gen({}).validate_config({})).to include("No condition configured")
  end
end
```

- [ ] **Step 2: Run and verify failure**

Run: `bundle exec rspec spec/services/code_generators/element_types/decision/decision_generator_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

Replace the body of `decision_generator.rb` from `def self.sample_input` through the end of `generate_body` plus the private helpers, with:

```ruby
def self.sample_input
  {
    "condition" => { "type" => "group", "joins" => [],
                     "conditions" => [{ "kind" => "field", "leftOperand" => "ctx.status", "operator" => "", "rightOperand" => "" }] },
    "_connection_match_values" => [
      { "branch" => "branch_0", "matchValue" => "approved" },
      { "branch" => "branch_1", "matchValue" => "rejected" }
    ]
  }
end

def generate_body
  condition   = config["condition"]
  route_index = config["_route_index"] || 0
  route_var   = :"_route_#{route_index}"

  return no_condition_body(route_var) if condition.blank?

  match_values = connection_match_values
  if subject_kind(condition) == :value
    build_value_switch(route_var, build_subject_value(condition), match_values)
  else
    build_boolean_switch(route_var, build_structured_condition(condition), match_values)
  end
end

private

def connection_match_values
  raw = config["_connection_match_values"]
  raw.is_a?(Array) ? raw : []
end

def no_condition_body(route_var)
  <<~RUBY.chomp
    # Decision: no condition configured — default to branch_0
    ctx[:#{route_var}] = :branch_0
    true
  RUBY
end

def build_value_switch(route_var, subject_code, match_values)
  with_values    = match_values.reject { |cc| cc["matchValue"].to_s.strip.empty? }
  default_branch = default_branch_key(match_values)
  when_clauses   = with_values.map { |cc| "when #{cc['matchValue'].to_s.inspect} then :#{cc['branch']}" }

  <<~RUBY.chomp
    ctx[:#{route_var}] = case #{subject_code}.to_s
    #{when_clauses.join("\n")}
    else :#{default_branch}
    end
    true
  RUBY
end

def build_boolean_switch(route_var, cond_code, match_values)
  default_branch = default_branch_key(match_values)
  truthy = branch_for_bool(match_values, true)  || default_branch
  falsy  = branch_for_bool(match_values, false) || default_branch

  <<~RUBY.chomp
    ctx[:#{route_var}] = (#{cond_code}) ? :#{truthy} : :#{falsy}
    true
  RUBY
end

def branch_for_bool(match_values, bool)
  wanted = bool ? "true" : "false"
  cc = match_values.find { |c| c["matchValue"].to_s.strip.casecmp?(wanted) }
  cc && cc["branch"]
end

def default_branch_index
  raw = config["defaultBranchIndex"]
  return -1 if raw.nil? || raw.to_s.strip.empty?
  raw.to_i
end

# Resolution order: explicit defaultBranchIndex → the empty-match-value
# ("Otherwise") branch → the trailing branch_N (Switch convention).
def default_branch_key(match_values)
  idx = default_branch_index
  if idx >= 0 && match_values[idx]
    match_values[idx]["branch"] || "branch_#{idx}"
  else
    empty = match_values.find { |c| c["matchValue"].to_s.strip.empty? }
    empty&.dig("branch") || "branch_#{match_values.length}"
  end
end

public

def validate_config(cfg)
  errors = []
  errors << "No condition configured" if cfg["condition"].blank?

  if cfg.key?("defaultBranchIndex") && cfg["defaultBranchIndex"].present?
    raw = cfg["defaultBranchIndex"]
    if raw.to_i < -1 || (raw.is_a?(String) && raw !~ /\A-?\d+\z/)
      errors << "defaultBranchIndex must be >= -1"
    end
  end

  errors
end
```

Delete the now-unused methods: `first_match_only?`, `fallback_branch`, `generate_multi_branch`, `generate_fan_out_branch`, `build_connection_condition`, `build_rules_condition`, and the `FIRST_MATCH_MODES` constant.

- [ ] **Step 4: Run and verify pass**

Run: `bundle exec rspec spec/services/code_generators/element_types/decision/decision_generator_spec.rb`
Expected: PASS. Delete/rewrite any leftover examples asserting the old if/elsif or `firstMatchOnly` behavior.

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/element_types/decision/decision_generator.rb spec/services/code_generators/element_types/decision/decision_generator_spec.rb
git commit -m "feat(flowchart): decision generator value/boolean dual-shape routing"
```

---

### Task 3: `FlowchartTopologyAnalyzer` — carry match value

**Files:**
- Modify: `app/services/flowchart_topology_analyzer.rb` (~lines 43-48)
- Test: `spec/services/flowchart_topology_analyzer_spec.rb`

- [ ] **Step 1: Write failing test**

```ruby
it "carries per-branch matchValue from the connection" do
  elements = [{ "id" => "d1", "type" => "decision" }, { "id" => "a", "type" => "process" }]
  connections = [{ "from" => "d1", "to" => "a", "label" => "Active", "matchValue" => "active" }]
  result = described_class.new(elements, connections).analyze
  branch = result.branch_groups["d1"][:branches][:branch_0]
  expect(branch[:match_value]).to eq("active")
end
```

- [ ] **Step 2: Run and verify failure**

Run: `bundle exec rspec spec/services/flowchart_topology_analyzer_spec.rb -e "matchValue"`
Expected: FAIL (`match_value` key absent).

- [ ] **Step 3: Implement**

In `flowchart_topology_analyzer.rb`, in the branch-building block, replace the `condition:` line:

```ruby
# before
condition:     conn["condition"]
# after
match_value:   conn["matchValue"]
```

- [ ] **Step 4: Run and verify pass**

Run: `bundle exec rspec spec/services/flowchart_topology_analyzer_spec.rb`
Expected: PASS (update any existing example referencing `:condition` here to `:match_value`).

- [ ] **Step 5: Commit**

```bash
git add app/services/flowchart_topology_analyzer.rb spec/services/flowchart_topology_analyzer_spec.rb
git commit -m "feat(flowchart): topology analyzer carries branch matchValue"
```

---

### Task 4: `ActivityGenerator` — inject `_connection_match_values`

**Files:**
- Modify: `app/services/activity_generator.rb` (~lines 336-342)
- Test: `spec/services/activity_generator_spec.rb`

- [ ] **Step 1: Write failing test**

Add an example asserting the injected key (adapt to the spec file's existing setup for building a decision element + topology):

```ruby
it "injects _connection_match_values for decision elements" do
  # build a decision 'd1' with two labelled, matchValue'd outgoing connections,
  # generate, and assert the produced source contains the case/when arms.
  expect(generated_source).to include("case").and include("when")
end
```

- [ ] **Step 2: Run and verify failure**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb -e "_connection_match_values"`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `activity_generator.rb#build_method`, replace the injection block:

```ruby
branch_group = @topology.branch_groups[element["id"]]
if branch_group
  match_values = branch_group[:branches].map do |branch_key, branch_info|
    { "branch" => branch_key.to_s, "matchValue" => branch_info[:match_value] }
  end
  element["properties"]["_connection_match_values"] = match_values
end
```

- [ ] **Step 4: Run and verify pass**

Run: `bundle exec rspec spec/services/activity_generator_spec.rb`
Expected: PASS. Fix any example asserting `_connection_conditions` or old if/elsif decision output.

- [ ] **Step 5: Commit**

```bash
git add app/services/activity_generator.rb spec/services/activity_generator_spec.rb
git commit -m "feat(flowchart): activity generator injects branch match values"
```

- [ ] **Step 6: Backend regression gate**

Run: `bundle exec rspec spec/services/code_generators spec/services/flowchart_topology_analyzer_spec.rb spec/services/activity_generator_spec.rb`
Expected: PASS. This proves the full compile path (condition → topology → activity → decision generator) before any JS work.

---

## PHASE B — Frontend: schema + condition section

> No JS unit harness exists (project memory). Verify each JS task in a real browser per the `flowchart-browser-debugging` technique: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`, open a flowchart with a Decision, and exercise the property editor in cached Chromium (playwright-core).

### Task 5: Decision schema

**Files:** Modify `app/javascript/flowchart/constants/schemas.js` (decision block, lines ~281-327)

- [ ] **Step 1: Edit schema**

In the `decision:` block: keep `label`, `condition` (label `"Condition"`, `required: true`, `tab: "steps"`), `branches`, `defaultBranchIndex`, `description`. **Remove** `firstMatchOnly` and `_connection_conditions`. Add a `_connection_match_values` internal entry mirroring the old `_connection_conditions` entry (type `text`, tab `advanced`, internal). Update the `condition` label help to "Value the branches switch on".

- [ ] **Step 2: Verify build**

Run: `rm -f public/assets/.manifest.json && bin/rails assets:precompile 2>&1 | tail -5`
Expected: precompile succeeds (no JS syntax error).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js
git commit -m "feat(flowchart): decision schema drops firstMatchOnly, adds match-value field"
```

---

### Task 6: Condition rows — Field/Query-count type toggle + value mode

**Files:** Modify `condition_builder.js`, `property_editor_controller.js`

- [ ] **Step 1: Add the row type toggle + value-mode operator option**

In `_buildConditionRowHTML(condition, index)` prepend a compact segmented control (same markup family as the branch modal's `data-condition-type-toggle`) bound to `data-condition-row-type-toggle` with two buttons `data-row-type="field"` / `data-row-type="query_count"`, each `data-action="click->property-editor#switchConditionRowType"`. Wrap the existing 3-column field grid in `<div data-condition-row-field-panel>` and add a sibling `<div data-condition-row-query-panel class="hidden">` (built by Task 7's `_buildQcRowPanelHTML`).

In the operator `<select>` (`[data-condition-operator]`), make the first option:
```html
<option value="">— (use value) —</option>
```
(replacing today's "Select operator..."). A blank operator = value mode for that row.

- [ ] **Step 2: Add `_conditionSubjectKind` + update `collectCondition`**

Add to `ConditionBuilderMixin`:

```js
_conditionSubjectKind(condition) {
  const conds = condition?.conditions || (condition ? [condition] : [])
  if (conds.length === 1) {
    const only = conds[0]
    const isField = only.kind !== "query_count"
    const blankOp = !only.operator
    if (isField && blankOp) return "value"
  }
  return "boolean"
}
```

Rewrite `collectCondition()` to emit the new shape. For each `[data-condition-row]`: read its active type (`[data-condition-row-type-toggle] button.bg-white`'s `data-row-type`, default `field`); if `field`, collect `{ kind:"field", leftOperand, operator, rightOperand }` (operator may be `""`); if `query_count`, collect via Task 7's `_collectQcRow(row)`. Collect `joins` from the ordered `[data-condition-join] button` `data-join-operator` values. Return `{ type:"group", joins, conditions }`. Drop the old single/group flat-vs-group branching and the `data-condition-group-operator` read.

- [ ] **Step 3: Controller delegation**

In `property_editor_controller.js` add:
```js
switchConditionRowType(event) { this.branchManager.switchConditionRowType(event) }
```
And implement `switchConditionRowType(event)` in `condition_builder.js` to toggle the clicked row's field/query panels + button styles (mirror `_applyConditionTypeToggle`, scoped to `event.target.closest("[data-condition-row]")`).

- [ ] **Step 4: Browser verify**

Restart dev server; open a Decision; confirm each condition row shows a Field/Query toggle; selecting blank operator keeps the row; `collectCondition()` (inspect via the saved element JSON after Save) yields `{type:"group",joins,conditions:[{kind:"field",…}]}`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager/condition_builder.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat(flowchart): condition rows gain field/query toggle + value mode"
```

---

### Task 7: Query-count rows inside the condition section

**Files:** Modify `query_count.js`, `condition_builder.js`

- [ ] **Step 1: Generalize QC row builders**

In `query_count.js` add condition-scoped builders that mirror the branch-modal ones but key off the condition row (not `data-branch-qc-*`):
- `_buildQcRowPanelHTML(rowIndex)` → entity select (`[data-cond-qc-entity]`), WHERE rows container (`[data-cond-qc-where-rows]`), count op/value (`[data-cond-qc-count-op]`, `[data-cond-qc-count-value]`); reuse the existing entity-fetch (`onQueryCountEntityChange` generalized to accept the row scope) and WHERE-row markup.
- `_collectQcRow(row)` → `{ kind:"query_count", queryConfig:{entityId,entityName,conditions:{rules}}, countOperator, countValue }` (mirror `_collectQueryCountCondition`, scoped to `row`).

Keep the existing branch-modal QC methods callable but they will be removed in Phase C; for now extract the shared inner logic into helpers both call.

- [ ] **Step 2: Wire panel into the condition row**

In `_buildConditionRowHTML`, render `_buildQcRowPanelHTML(index)` inside `[data-condition-row-query-panel]`. Add controller delegations for the condition-scoped QC actions (entity change, add/remove where row) pointing at the new row-scoped methods.

- [ ] **Step 3: Browser verify**

Open a Decision; on a condition row switch to Query Count; pick an entity; add a WHERE row; Save; confirm the saved `condition.conditions[i]` is `{kind:"query_count",…}` and that `subject_kind` (re-open → it stays Query Count and boolean-only branches).

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager/query_count.js app/javascript/controllers/property_editor/branch_manager/condition_builder.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat(flowchart): query-count rows available in the condition section"
```

---

### Task 8: Per-join independent AND/OR toggles

**Files:** Modify `condition_builder.js`, `property_editor_controller.js`

- [ ] **Step 1: Per-join markup with own state**

Replace `_buildConditionOperatorToggleHTML(groupOperator)` with `_buildJoinToggleHTML(joinOperator)` rendering one button carrying its own state:
```js
_buildJoinToggleHTML(joinOperator = "AND") {
  const accent = this._conditionAccent()
  const op = joinOperator === "OR" ? "OR" : "AND"
  const pill = op === "AND" ? accent.pillAnd : accent.pillOr
  return `
    <div data-condition-join class="flex items-center justify-center py-1">
      <button type="button" data-join-operator="${op}"
              data-action="click->property-editor#toggleConditionJoin"
              class="px-3 py-0.5 text-[10px] font-bold rounded-full transition-colors ${pill}">${op}</button>
    </div>`
}
```
Update `buildConditionFieldHTML` and `addConditionRow` to insert `_buildJoinToggleHTML(existingJoinOrAND)` between rows (default `"AND"`). Remove the `data-condition-group-operator` hidden input entirely.

- [ ] **Step 2: Toggle only the clicked join (req c)**

Replace `toggleConditionOperator` with:
```js
toggleConditionJoin(event) {
  event.preventDefault()
  const btn = event.currentTarget
  const next = btn.dataset.joinOperator === "AND" ? "OR" : "AND"
  btn.dataset.joinOperator = next
  btn.textContent = next
  const accent = this._conditionAccent()
  btn.classList.remove("bg-amber-200","text-amber-800","bg-purple-200","text-purple-800")
  btn.classList.add(...(next === "AND" ? accent.pillAnd : accent.pillOr).split(" "))
  this.controller._syncChangesToCanvas()
}
```
Update `removeConditionRow` to remove the adjacent `[data-condition-join]` (replacing the `[data-condition-operator-toggle]` lookups). In `collectCondition`, build `joins` by reading each `[data-condition-join] button`'s `data-join-operator` in DOM order. In `property_editor_controller.js`, replace the `toggleConditionOperator` delegation with `toggleConditionJoin`.

- [ ] **Step 3: Browser verify**

Add 3 condition rows; confirm there are 2 independent join pills; click the first → only it flips AND↔OR; the second is unchanged. Save and confirm `joins` reflects the mixed operators (e.g. `["OR","AND"]`).

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager/condition_builder.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat(flowchart): independent per-join AND/OR toggles in condition section"
```

---

## PHASE C — Frontend: branch editor → Match Value

### Task 9: Branch modal template — drop condition/presets, add Match Value

**Files:** Modify `app/javascript/controllers/property_editor/templates/branch.js`

- [ ] **Step 1: Replace the modal body**

In `buildBranchModalTemplate`, **delete** the Preset chips block (lines ~53-70) and the entire Condition Section (`<!-- Condition Section -->` through its closing `</div>`, lines ~83-201). **Add**, after Branch Name, a Match Value block with both representations (one shown at a time by Task 10):

```html
<!-- Match Value -->
<div>
  <label class="block text-[11px] font-medium text-slate-500 mb-1">
    Match Value <span class="text-slate-400 font-normal">(empty = default / otherwise)</span>
  </label>
  <input type="text" data-branch-match-value
         data-action="input->property-editor#syncBranchNameFromMatchValue"
         placeholder="e.g. active"
         class="w-full px-2 py-1.5 text-xs border border-slate-200 rounded-md shadow-sm placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
  <select data-branch-match-value-select
          data-action="change->property-editor#syncBranchNameFromMatchValue"
          class="hidden w-full px-2 py-1.5 text-xs bg-white border border-slate-200 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-400">
    <option value="true">true</option>
    <option value="false">false</option>
  </select>
</div>
```

Move the **Branch Name** input below Match Value (so the auto-fill reads naturally), keep `[data-branch-name]`.

- [ ] **Step 2: Branch item subtitle = match value**

In `buildBranchItemTemplate`, replace the condition-summary subtitle with the match value: when `matchValue` present → `<div class="text-[10px] font-mono text-slate-400 mt-0.5 truncate">= {escaped matchValue}</div>`; else the amber `default / otherwise` badge. Change the hidden inputs: drop `[condition]`, add `<input type="hidden" name="branches[${index}][matchValue]" value="${escapeHtml(matchValue||"")}">`. Update the function's param destructuring from `condition` to `matchValue`.

- [ ] **Step 3: Verify build**

Run: `rm -f public/assets/.manifest.json && bin/rails assets:precompile 2>&1 | tail -5`
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/templates/branch.js
git commit -m "feat(flowchart): branch modal replaces condition with Match Value"
```

---

### Task 10: Branch modal behavior — adaptive input, name auto-fill, collect/prefill

**Files:** Modify `modal_lifecycle.js`, `branch_manager.js`, `property_editor_controller.js`

- [ ] **Step 1: Name auto-fill**

Add to `branch_manager.js`:
```js
syncBranchNameFromMatchValue(event) {
  const modal = event.target.closest("[data-branch-modal]")
  if (!modal) return
  const nameInput = modal.querySelector("[data-branch-name]")
  if (!nameInput || nameInput.dataset.nameTouched === "true") return
  nameInput.value = event.target.value
}
```
Mark the name "touched" on manual edit: add `data-action="input->property-editor#markBranchNameTouched"` to `[data-branch-name]` (in Task 9 markup) and:
```js
markBranchNameTouched(event) { event.target.dataset.nameTouched = "true" }
```
Add both controller delegations in `property_editor_controller.js`.

- [ ] **Step 2: Adaptive Match Value on open**

In `_resetBranchModal(modal)` and `editBranch`'s `onOpen`, after reset, call a new `_applyMatchValueMode(modal)`:
```js
_applyMatchValueMode(modal) {
  const kind = this._conditionSubjectKind(this.collectCondition())
  const text = modal.querySelector("[data-branch-match-value]")
  const sel  = modal.querySelector("[data-branch-match-value-select]")
  if (!text || !sel) return
  if (kind === "boolean") { text.classList.add("hidden"); sel.classList.remove("hidden") }
  else { sel.classList.add("hidden"); text.classList.remove("hidden") }
}
```
Reset clears `data-branch-name` `data-nameTouched`, `[data-branch-match-value]` value, and `[data-branch-match-value-select]` to `"true"`. Remove the old condition/preset/left-operand reset lines.

- [ ] **Step 3: Collect + prefill match value**

In `branch_manager.js` add `_collectMatchValueFromModal(modal)`:
```js
_collectMatchValueFromModal(modal) {
  const sel = modal.querySelector("[data-branch-match-value-select]")
  if (sel && !sel.classList.contains("hidden")) return sel.value
  return modal.querySelector("[data-branch-match-value]")?.value?.trim() || ""
}
```
In `addBranchFromModal` and `saveBranchEdits`, replace `_collectBranchConditionFromModal` with `_collectMatchValueFromModal`, pass `matchValue` through `buildBranchItemHTML`, and set `conn.matchValue` (Task 11). In `_prefillBranchModal`, set the active Match Value control from the stored `matchValue` and mark the name touched (edit always preserves the saved name).

Remove now-dead code: `applyBranchPreset`, `_applyPresetValues`, `_setChipActive`, `handleBranchLeftOperandChange`, `swapLeftOperandToManual/Select`, `_resetLeftOperandSwap`, `_populateLeftOperandSelect`, and the branch-modal QC methods/prefill in `query_count.js`/`modal_lifecycle.js` (`_collectBranchConditionFromModal`, `_collectFieldCondition`, `_collectQueryCountCondition` branch-modal variants, `_prefillFieldCondition`, `_prefillQueryCountCondition`, `_applyConditionTypeToggle`, `switchBranchConditionType`).

- [ ] **Step 4: `buildBranchItemHTML` signature**

Change `buildBranchItemHTML(index, branchValue, description, branchElementId, matchValue)` and `buildBranchesFieldHTML`'s existing-branch loop to pass `branch.matchValue`. Update `collectBranches` to read `branches[${i}][matchValue]` and emit `{ name, matchValue, description, branchKey, elementId }`.

- [ ] **Step 5: Browser verify**

Value condition (`ctx.model.status`, no operator): Add Branch → Match Value is free text; typing "active" fills Name "active"; manual Name edit stops the sync. Boolean condition (`status == approved`): Add Branch → Match Value is a true/false select; Name auto "true"/"false". Save and re-open the Decision → branches round-trip their match values.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager/modal_lifecycle.js app/javascript/controllers/property_editor/branch_manager.js app/javascript/controllers/property_editor/branch_manager/query_count.js app/javascript/controllers/property_editor_controller.js
git commit -m "feat(flowchart): branch modal Match Value adaptive input + name auto-fill"
```

---

### Task 11: Connection persistence + condition summary cleanup

**Files:** Modify `canvas_operations.js`, `conditions.js`, `branch_manager.js`

- [ ] **Step 1: Store matchValue on the connection**

In `addBranchFromModal` / `saveBranchEdits` (branch_manager.js) and any `canvas_operations.js` connection-creation path, set `conn.matchValue = matchValue` (or `delete conn.matchValue` when empty) wherever `conn.condition` was previously set; keep `conn.label = branchName`. Ensure the created connection object includes `matchValue` so it serializes into the flowchart JSON the topology reads.

- [ ] **Step 2: conditions.js**

Replace `buildConditionSummaryText` usage for branch cards with a trivial match-value renderer (or inline in `buildBranchItemTemplate`, already done in Task 9). Keep `buildConditionSummaryText` only if still used elsewhere; otherwise delete it and its import.

- [ ] **Step 3: Browser verify**

Create two value branches; Save; reload the page; confirm connections retain labels and that generated code (via the code-generator preview UI, if available, or `Flowchart` → generate) shows `case … when "active" …`. For a boolean condition with true/false branches confirm the ternary form.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/branch_manager/canvas_operations.js app/javascript/controllers/property_editor/templates/conditions.js app/javascript/controllers/property_editor/branch_manager.js
git commit -m "feat(flowchart): connections carry matchValue; branch cards show it"
```

---

## PHASE D — Integration

### Task 12: Full verification

- [ ] **Step 1: Rebuild assets**

Run: `rm -f public/assets/.manifest.json && bin/rails assets:precompile 2>&1 | tail -5`
Expected: success.

- [ ] **Step 2: Full suite** (tremendous change per AGENTS.md)

Run: `bin/rails parallel:spec`
Expected: green. Triage any decision/switch/flowchart regressions against the new contract; rewrite stale specs (don't weaken assertions).

- [ ] **Step 3: End-to-end browser smoke**

`rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`. In cached Chromium: build a Decision with a value condition + 3 value branches (one empty = otherwise); a second Decision with a boolean group (per-join AND/OR mixed) + true/false branches. Generate code for both; confirm `case/when` and ternary forms respectively, and that mixed joins parenthesize left-to-right.

- [ ] **Step 4: Convention + auth audit**

Run the `audit-conventions` skill on the diff (tech-lead) and `audit-tenant` is N/A (no new models); confirm no `customer_id`/route changes. Address findings.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "test(flowchart): decision value-switch full-suite green + browser smoke"
```

---

## Self-review notes

- **Spec coverage:** req (a) field+query-count in condition = Tasks 6-7; (b) groups = Tasks 6,8; (c) independent per-join = Task 8; (d) Match Value + name auto-fill + remove branch condition = Tasks 9-11. Generator dual-shape = Tasks 1-2. Plumbing = Tasks 3-4. Schema = Task 5. Locked decisions 1-6 all map to Task 2 (default/ternary/case) + Task 10 (adaptive input) + Task 8 (parens/independent).
- **Type consistency:** `subject_kind`/`build_subject_value`/`build_condition_group`/`build_group_member`/`ruby_join_operator` (Task 1) reused in Task 2; `_conditionSubjectKind` (Task 6) reused in Task 10; `matchValue` JSON key consistent across Tasks 2,3,4,9,10,11; `_connection_match_values` consistent across Tasks 2,4.
