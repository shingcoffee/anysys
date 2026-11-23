# Remove Skip Validation, Customer Scoped, and Step-tab I/O Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strip three obsolete concepts from the flowchart property editor and code generators: the `skipValidation` toggle + its `.valid?` emission; the `customerScoped` / `scopeByCustomerId` toggles across 6 model-operation actions (making customer scoping unconditional); and the per-step "I/O" pane on the process Step tab (removing `step.io_overrides` plumbing end-to-end).

**Architecture:** Three independent tasks, each TDD'd: update RSpec expectations first (they fail), then delete the JS UI fields / generator branches / backend plumbing, confirm tests pass, then regenerate the UI-schema mirror. Task 2 and Task 3 touch several files each; we split them into sub-tasks by file so each commit is bite-sized. The `step_io/io_params_client.js` module stays (still powers autocomplete).

**Tech Stack:** Rails 8.1 / Ruby 3.2 / StimulusJS / RSpec / rake `config_schemas:mirror`.

**Ref spec:** `docs/superpowers/specs/2026-04-22-remove-skip-validation-customer-scoped-step-io-design.md`

---

## Order of Execution

1. **Task 1** — Skip Validation (smallest, self-contained).
2. **Task 2** — Customer Scoped (6 generators + broad spec fan-out).
3. **Task 3** — Step-tab I/O section (UI + backend plumbing).

Tasks 1 and 2 both touch `new_model_generator.rb` and its spec; running them sequentially avoids merge thrash. After each task, run the UI-schema mirror regeneration and verify specs.

Each task ends with one or more commits. Do **not** auto-run any destructive git operation or `git push`.

---

## Task 1: Remove Skip Validation from `new_model`

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/model_actions.js:26-35`
- Modify: `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb:25,32,43,56`
- Modify: `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb:77-93,166-173`
- Regenerate: `spec/support/config_schemas.rb` (via `rake config_schemas:mirror`)

### Step 1.1: Update the spec expectations first (TDD — tests will fail)

- [ ] **Step 1.1.1: Rewrite the `skipValidation` describe block to assert the new behavior**

Open `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`. **Delete** the existing `describe "skipValidation"` block at lines 77–93 and **replace** it with a single regression test at the same location that asserts `.valid?` is NEVER emitted:

```ruby
  describe "no .valid? emission" do
    it "never emits ctx[:result_var].valid? in generated code" do
      expect(described_class.new(element, context).generate_body).not_to include(".valid?")
    end

    it "never emits .valid? even when legacy skipValidation config is present" do
      el = { "config" => { "skipValidation" => "false" } }
      expect(described_class.new(el, {}).generate_body).not_to include(".valid?")
    end
  end
```

- [ ] **Step 1.1.2: Remove `skipValidation` references from the `#validate_config` describe block**

In the same file, inside `describe "#validate_config"` (starting around line 158), delete:
- Line 166: `expect(instance.validate_config("skipValidation" => "true",  "customerScoped" => "false")).to eq([])`
- Line 167: `expect(instance.validate_config("skipValidation" => "false", "customerScoped" => "true")).to eq([])`
- The `it "rejects invalid skipValidation values"` test block at lines 170–173.

Keep the `"returns no errors for default config"` and `"rejects invalid customerScoped values"` tests — those will be handled in Task 2.

Since we removed both `eq([])` lines, replace them with a single consolidated test that still exercises the accept path for `customerScoped` (until Task 2 removes it entirely):

```ruby
    it "accepts valid boolean-enum strings" do
      expect(instance.validate_config("customerScoped" => "false")).to eq([])
      expect(instance.validate_config("customerScoped" => "true")).to eq([])
    end
```

- [ ] **Step 1.1.3: Run spec to verify new-behavior tests fail**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`
Expected: The two new tests under `"no .valid? emission"` **FAIL** (generator still emits `.valid?`). All other tests pass.

### Step 1.2: Delete the UI field

- [ ] **Step 1.2.1: Remove the `skipValidation` field entry from `new_model`**

Open `app/javascript/flowchart/constants/action_configs/model_actions.js`. Locate the `new_model` action's `configSchema` array. Delete lines 26–35 (inclusive) — the entire `{ key: "skipValidation", ... }` object and the trailing comma before the next entry.

The `configSchema` array must remain valid JavaScript: ensure the `associations` entry (lines 20–25) ends with `},` and the next surviving entry (`customerScoped`, to be removed in Task 2) follows immediately.

### Step 1.3: Delete the generator branch

- [ ] **Step 1.3.1: Remove `skipValidation` from `new_model_generator.rb`**

Open `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb`. Make these exact edits:

1. Line 25 — inside `def self.sample_input`, delete the `"skipValidation"  => "false",` entry. The surrounding hash should remain valid (keep the trailing comma on the preceding line intact; the `"customerScoped"` entry on line 26 becomes the last entry once Task 2 removes it, but for now it stays).

2. Line 32 — delete the entire line:
```ruby
            skip_validation  = fetch_enum("skipValidation", BOOL_VALUES, default: "false") == "true"
```

3. Line 43 — delete the entire line:
```ruby
            lines << "ctx[:#{result_var}].valid?" unless skip_validation
```

4. Line 56 — inside `validate_config`, change:
```ruby
%w[skipValidation customerScoped].each do |key|
```
to:
```ruby
%w[customerScoped].each do |key|
```
(Task 2 will delete the whole method; for now we just drop `skipValidation`.)

- [ ] **Step 1.3.2: Run generator spec to verify tests pass**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`
Expected: All tests PASS, including the two new `"no .valid? emission"` tests.

### Step 1.4: Regenerate the UI schema mirror

- [ ] **Step 1.4.1: Regenerate `spec/support/config_schemas.rb`**

Run: `bundle exec rake config_schemas:mirror`
Expected: `spec/support/config_schemas.rb` is updated. Verify no `skipValidation` occurrences remain in it:
```
grep -n "skipValidation" spec/support/config_schemas.rb
```
Expected: no output.

- [ ] **Step 1.4.2: Run the generator audit script**

Run: `bundle exec ruby scripts/audit_generator_ui.rb`
Expected: passes; no warnings about `new_model` config fields.

- [ ] **Step 1.4.3: Run the full model-operations spec directory**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/`
Expected: all PASS.

### Step 1.5: Commit

- [ ] **Step 1.5.1: Stage and commit the Task 1 changes**

```bash
git add app/javascript/flowchart/constants/action_configs/model_actions.js \
        app/services/code_generators/element_types/process/model_operations/new_model_generator.rb \
        spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb \
        spec/support/config_schemas.rb
git status
```

Inspect `git status` — these four files should be the only ones staged. Then:

```bash
git commit -m "$(cat <<'EOF'
refactor: remove skipValidation from new_model action

Delete the "Skip Validation" UI select and the conditional .valid?
emission in NewModelGenerator. Generated code no longer calls
ctx[:result_var].valid? — validation is now the caller's responsibility
(e.g. a downstream validate_contract step).

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Remove Customer Scoped (modern + legacy) across 6 generators

Customer scoping becomes unconditional. Six UI fields are removed; five generators have their `scopeByCustomerId` branches deleted; one (`query_models`) only used the flag in its `scope`-type branch via `scope_customer?`.

### Task 2 decomposition

- **2A** — `new_model` generator (finishes what Task 1 started)
- **2B** — `find_model` generator
- **2C** — `query_models` generator
- **2D** — `check_existence` generator
- **2E** — `count_records` generator
- **2F** — `pluck_fields` generator
- **2G** — Remove all UI fields in one commit + regenerate mirror + run audits

Each sub-task follows the same pattern: update spec → confirm fail → edit generator → confirm pass → commit.

---

### Task 2A: `new_model` — finish Customer Scoped removal

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`

- [ ] **Step 2A.1: Update specs**

Open `spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`.

1. Delete the legacy test at lines 28–31:
```ruby
  it "omits customer_id when scopeByCustomerId is false" do
    el = { "config" => { "scopeByCustomerId" => false } }
    expect(described_class.new(el, {}).generate_body).not_to include("customer_id: ctx[:customer_id]")
  end
```

2. Delete the entire `describe "customerScoped"` block (lines 60–75).

3. Delete the entire `describe "#validate_config"` block (starting ~line 158) — the method itself is being removed.

4. Add one new test near the existing customer_id test (around line 24) to pin the unconditional behavior:

```ruby
  it "always includes customer_id (customer scoping is unconditional)" do
    el1 = { "config" => { "scopeByCustomerId" => false } }
    el2 = { "config" => { "customerScoped" => "false" } }
    expect(described_class.new(el1, {}).generate_body).to include("customer_id: ctx[:customer_id]")
    expect(described_class.new(el2, {}).generate_body).to include("customer_id: ctx[:customer_id]")
  end
```

- [ ] **Step 2A.2: Run specs — expect failures**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`
Expected: the new `"always includes customer_id"` test FAILS for `el2` (generator still honors `customerScoped => "false"`). All other remaining tests pass.

- [ ] **Step 2A.3: Remove `customerScoped` / `scopeByCustomerId` logic from `new_model_generator.rb`**

Open `app/services/code_generators/element_types/process/model_operations/new_model_generator.rb`. After Task 1, the file should currently look like the version shown in the spec doc minus `skipValidation`. Apply these edits:

1. In `sample_input`, delete the `"customerScoped"  => "true"` entry (and tidy trailing comma on the previous line).

2. In `generate_body`, delete this line:
```ruby
customer_scoped  = customer_scoped?
```

3. Replace:
```ruby
attr_pairs.unshift("customer_id: ctx[:customer_id]") if customer_scoped
```
with:
```ruby
attr_pairs.unshift("customer_id: ctx[:customer_id]")
```

4. Delete the `validate_config` method entirely (the `def validate_config(cfg) ... end` block).

5. Delete the `private` `customer_scoped?` method entirely.

6. Delete the `BOOL_VALUES = %w[true false].freeze` constant at line 11.

The resulting file should contain only: metadata block, `sample_input`, `generate_body`, `dependencies`, and the private helpers `attribute_pairs`, `association_pairs`, `normalize_pairs`. It should not import or reference `fetch_enum`.

Verify no stray references remain:
```
grep -n "customerScoped\|skipValidation\|scopeByCustomerId\|customer_scoped\|BOOL_VALUES" app/services/code_generators/element_types/process/model_operations/new_model_generator.rb
```
Expected: no output.

- [ ] **Step 2A.4: Run specs — expect all pass**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb`
Expected: all PASS.

- [ ] **Step 2A.5: Commit Task 2A**

```bash
git add app/services/code_generators/element_types/process/model_operations/new_model_generator.rb \
        spec/services/code_generators/element_types/process/model_operations/new_model_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor: new_model always customer-scopes

Remove the customerScoped / scopeByCustomerId branches and the
validate_config method. Generated code always prepends
customer_id: ctx[:customer_id] to attributes.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2B: `find_model` — unconditional customer scoping

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/find_model_generator.rb:30,37`
- Modify: `spec/services/code_generators/element_types/process/model_operations/find_model_generator_spec.rb`

- [ ] **Step 2B.1: Update specs**

Open `spec/services/code_generators/element_types/process/model_operations/find_model_generator_spec.rb`. Find all tests that pass `"scopeByCustomerId" => false` and assert customer_id omission (lines 21, 59, 67, 74 per explore output). For each such test, **either delete it** if its sole purpose is to prove omission, **or** update the assertion to expect `.where(customer_id: ctx[:customer_id])` to be present.

Add one regression test near the top of the file:

```ruby
  it "always includes .where(customer_id: ctx[:customer_id]) (unconditional)" do
    el = { "config" => { "scopeByCustomerId" => false, "findStrategy" => "find_by", "findField" => "email", "findValue" => "ctx[:email]" } }
    expect(described_class.new(el, {}).generate_body).to include(".where(customer_id: ctx[:customer_id])")
  end
```

- [ ] **Step 2B.2: Run specs — expect failure on the new test**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/find_model_generator_spec.rb`
Expected: the new `"always includes .where(customer_id: ctx[:customer_id])"` test FAILS.

- [ ] **Step 2B.3: Remove the `scopeByCustomerId` branch**

Open `app/services/code_generators/element_types/process/model_operations/find_model_generator.rb`.

1. Delete line 30: `scope_customer = config["scopeByCustomerId"] != false`.
2. Change line 37 from:
```ruby
base = "#{base}.where(customer_id: ctx[:customer_id])" if scope_customer
```
to:
```ruby
base = "#{base}.where(customer_id: ctx[:customer_id])"
```

Verify:
```
grep -n "scopeByCustomerId\|scope_customer" app/services/code_generators/element_types/process/model_operations/find_model_generator.rb
```
Expected: no output.

- [ ] **Step 2B.4: Run specs — all pass**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/find_model_generator_spec.rb`
Expected: all PASS.

- [ ] **Step 2B.5: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/find_model_generator.rb \
        spec/services/code_generators/element_types/process/model_operations/find_model_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor: find_model always customer-scopes

Remove the scopeByCustomerId branch. Generated code always wraps the
base query with .where(customer_id: ctx[:customer_id]).

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2C: `query_models` — unconditional customer scoping in scope branch

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/query_models_generator.rb:58-60,168`
- Modify: `spec/services/code_generators/element_types/process/model_operations/query_models_generator_spec.rb`

Note: only the `scope`-type branch (in `generate_scope_query`) uses `scope_customer?`. The `where`-type branch uses `QueryBuilder.for_entity(..., customer_id: ctx[:customer_id])` which is already unconditional.

- [ ] **Step 2C.1: Update specs**

Open `spec/services/code_generators/element_types/process/model_operations/query_models_generator_spec.rb`. Find the test at line 80 that sets `"scopeByCustomerId" => false` and asserts omission (per explore). Update that test (or delete it) so the expectation becomes: "the scope-type query always includes `.where(customer_id: ctx[:customer_id])`".

Add this new test:

```ruby
  it "always customer-scopes the scope-type query (unconditional)" do
    el = { "config" => { "queryType" => "scope", "scopeName" => "recent", "scopeByCustomerId" => false } }
    expect(described_class.new(el, {}).generate_body).to include(".where(customer_id: ctx[:customer_id]).send(:recent)")
  end
```

- [ ] **Step 2C.2: Run specs — expect failure on the new test**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/query_models_generator_spec.rb`
Expected: new test FAILS.

- [ ] **Step 2C.3: Remove the `scope_customer?` helper and its branch**

Open `app/services/code_generators/element_types/process/model_operations/query_models_generator.rb`.

1. Delete the private method `scope_customer?` (lines 58–60):
```ruby
def scope_customer?
  config["scopeByCustomerId"] != false
end
```

2. Change line 168 from:
```ruby
base = "#{base}.where(customer_id: ctx[:customer_id])" if scope_customer?
```
to:
```ruby
base = "#{base}.where(customer_id: ctx[:customer_id])"
```

Verify:
```
grep -n "scopeByCustomerId\|scope_customer" app/services/code_generators/element_types/process/model_operations/query_models_generator.rb
```
Expected: no output.

- [ ] **Step 2C.4: Run specs — all pass**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/query_models_generator_spec.rb`
Expected: all PASS.

- [ ] **Step 2C.5: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/query_models_generator.rb \
        spec/services/code_generators/element_types/process/model_operations/query_models_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor: query_models always customer-scopes the scope branch

The where/sql branches were already unconditional. Remove the
scopeByCustomerId opt-out from the scope branch as well.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2D: `check_existence` — unconditional customer scoping

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb:61-65`
- Modify: `spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb`

- [ ] **Step 2D.1: Update specs**

Open `spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb`. Find the test around line 51 that uses `"scopeByCustomerId" => false`. Update it or delete it; add:

```ruby
  it "always customer-scopes (unconditional)" do
    el = { "config" => { "resultVar" => "found", "scopeByCustomerId" => false } }
    expect(described_class.new(el, {}).generate_body).to include(".where(customer_id: ctx[:customer_id])")
  end
```

- [ ] **Step 2D.2: Run specs — expect failure**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb`
Expected: new test FAILS.

- [ ] **Step 2D.3: Remove the conditional**

Open `app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb`. Replace the `base_query` method (lines 61–65):

```ruby
def base_query
  scope = config["scopeByCustomerId"] != false
  base = "EntityEntry.build_for(ctx[:bound_entity])"
  scope ? "#{base}.where(customer_id: ctx[:customer_id])" : base
end
```

with:

```ruby
def base_query
  "EntityEntry.build_for(ctx[:bound_entity]).where(customer_id: ctx[:customer_id])"
end
```

Verify:
```
grep -n "scopeByCustomerId" app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb
```
Expected: no output.

- [ ] **Step 2D.4: Run specs — all pass**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb`
Expected: all PASS.

- [ ] **Step 2D.5: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/check_existence_generator.rb \
        spec/services/code_generators/element_types/process/model_operations/check_existence_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor: check_existence always customer-scopes

Remove the scopeByCustomerId branch from base_query.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2E: `count_records` — unconditional customer scoping

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/count_records_generator.rb:72-76`
- Modify: `spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb`

- [ ] **Step 2E.1: Update specs**

Open `spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb`. Find the test at line 53 that uses `"scopeByCustomerId" => false`. Update/delete it; add:

```ruby
  it "always customer-scopes (unconditional)" do
    el = { "config" => { "resultVar" => "count", "scopeByCustomerId" => false } }
    expect(described_class.new(el, {}).generate_body).to include(".where(customer_id: ctx[:customer_id])")
  end
```

- [ ] **Step 2E.2: Run specs — expect failure**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb`
Expected: new test FAILS.

- [ ] **Step 2E.3: Remove the conditional**

Open `app/services/code_generators/element_types/process/model_operations/count_records_generator.rb`. Replace the `base_query` method (lines 72–76):

```ruby
def base_query
  scope = config["scopeByCustomerId"] != false
  base = "EntityEntry.build_for(ctx[:bound_entity])"
  scope ? "#{base}.where(customer_id: ctx[:customer_id])" : base
end
```

with:

```ruby
def base_query
  "EntityEntry.build_for(ctx[:bound_entity]).where(customer_id: ctx[:customer_id])"
end
```

Verify:
```
grep -n "scopeByCustomerId" app/services/code_generators/element_types/process/model_operations/count_records_generator.rb
```
Expected: no output.

- [ ] **Step 2E.4: Run specs — all pass**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb`
Expected: all PASS.

- [ ] **Step 2E.5: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/count_records_generator.rb \
        spec/services/code_generators/element_types/process/model_operations/count_records_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor: count_records always customer-scopes

Remove the scopeByCustomerId branch from base_query.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2F: `pluck_fields` — unconditional customer scoping

**Files:**
- Modify: `app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb:91-95`
- Modify: `spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb`

- [ ] **Step 2F.1: Update specs**

Open `spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb`. Find the test around line 111 that uses `"scopeByCustomerId" => false`. Update/delete it; add:

```ruby
  it "always customer-scopes (unconditional)" do
    el = { "config" => { "resultVar" => "emails", "fields" => ["email"], "scopeByCustomerId" => false } }
    expect(described_class.new(el, {}).generate_body).to include(".where(customer_id: ctx[:customer_id])")
  end
```

- [ ] **Step 2F.2: Run specs — expect failure**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb`
Expected: new test FAILS.

- [ ] **Step 2F.3: Remove the conditional**

Open `app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb`. Replace the `base_query` method (lines 91–95):

```ruby
def base_query
  scope = config["scopeByCustomerId"] != false
  base = "EntityEntry.build_for(ctx[:bound_entity])"
  scope ? "#{base}.where(customer_id: ctx[:customer_id])" : base
end
```

with:

```ruby
def base_query
  "EntityEntry.build_for(ctx[:bound_entity]).where(customer_id: ctx[:customer_id])"
end
```

Verify:
```
grep -n "scopeByCustomerId" app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb
```
Expected: no output.

- [ ] **Step 2F.4: Run specs — all pass**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb`
Expected: all PASS.

- [ ] **Step 2F.5: Commit**

```bash
git add app/services/code_generators/element_types/process/model_operations/pluck_fields_generator.rb \
        spec/services/code_generators/element_types/process/model_operations/pluck_fields_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor: pluck_fields always customer-scopes

Remove the scopeByCustomerId branch from base_query.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2G: Delete UI fields, fix activity_generator_spec, regenerate mirror

**Files:**
- Modify: `app/javascript/flowchart/constants/action_configs/model_actions.js` (6 deletions)
- Modify: `spec/services/activity_generator_spec.rb:2074`
- Regenerate: `spec/support/config_schemas.rb`

- [ ] **Step 2G.1: Delete all six UI fields**

Open `app/javascript/flowchart/constants/action_configs/model_actions.js`. Delete each of the following field objects. Line numbers refer to the state of the file **after Task 1's deletion of `skipValidation`**; shifts downward for later deletions.

After Task 1, the `new_model` `configSchema` has (in order) `attributes`, `associations`, `customerScoped`, `resultVar`, `scopeByCustomerId`. Delete:
1. The `customerScoped` object (currently lines 26–35 post-Task-1).
2. The `scopeByCustomerId` object (currently lines 41–45 post-Task-1).

Then, in each of the following actions, locate the `{ key: "scopeByCustomerId", ... }` block in the `configSchema` and delete it (including any `visibleWhen` clause):
3. `check_existence` (was line 136 pre-edits).
4. `find_model` (was line 517).
5. `pluck_model_fields` (was line 768).
6. `query_models` (was line 833).
7. `count_records` (was line 877).

Verify none remain:
```
grep -n "customerScoped\|scopeByCustomerId" app/javascript/flowchart/constants/action_configs/model_actions.js
```
Expected: no output.

- [ ] **Step 2G.2: Fix the activity_generator test fixture**

Open `spec/services/activity_generator_spec.rb`. Find the `'generates code with find_model config'` test around line 2068. The fixture at line 2074 contains:

```ruby
'config' => { 'findStrategy' => 'find_by!', 'findField' => 'email', 'findValue' => 'ctx[:email]', 'resultVar' => 'user', 'scopeByCustomerId' => false }
```

Remove `'scopeByCustomerId' => false,` from the hash. The remaining assertions (`expect(code).to include('find_by!(email: ctx[:email])')` and `expect(code).to include('ctx[:user]')`) still hold because they don't test scoping.

Add a new assertion to this same test that pins the unconditional behavior:

```ruby
expect(code).to include('.where(customer_id: ctx[:customer_id])')
```

- [ ] **Step 2G.3: Regenerate the UI schema mirror**

Run: `bundle exec rake config_schemas:mirror`
Verify:
```
grep -n "customerScoped\|scopeByCustomerId" spec/support/config_schemas.rb
```
Expected: no output.

- [ ] **Step 2G.4: Run full generator + activity specs**

Run:
```
bundle exec rspec spec/services/code_generators/ spec/services/activity_generator_spec.rb
```
Expected: all PASS.

- [ ] **Step 2G.5: Run the generator audit script**

Run: `bundle exec ruby scripts/audit_generator_ui.rb`
Expected: passes with no warnings.

- [ ] **Step 2G.6: Commit Task 2G**

```bash
git add app/javascript/flowchart/constants/action_configs/model_actions.js \
        spec/services/activity_generator_spec.rb \
        spec/support/config_schemas.rb
git commit -m "$(cat <<'EOF'
refactor: remove customerScoped / scopeByCustomerId UI fields

Drop the Customer Scoped select from new_model and the legacy
scopeByCustomerId text field from all six model-operation actions.
Regenerate spec/support/config_schemas.rb and adjust the
activity_generator_spec fixture accordingly.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Remove Process Step-tab I/O section

### Task 3 decomposition

- **3A** — Remove backend step-level `io_overrides` plumbing
- **3B** — Remove frontend Step-tab I/O pane + `StepIoManager` wiring
- **3C** — Remove step-level `io_overrides` collection in `step_manager.js`
- **3D** — Remove step override lookup in `context_variable_provider.js`
- **3E** — Delete dead JS modules

Frontend and backend can go in the same PR but must be committed in the right order (backend first, then frontend) so the in-between states are runnable.

---

### Task 3A: Remove step-level `io_overrides` from backend

**Files:**
- Modify: `app/services/activity_generator.rb:719,849-852`
- Modify: `app/services/code_generators/emission_rewriter.rb:1-112`
- Modify: `spec/services/code_generators/emission_rewriter_spec.rb:5-111`
- Modify: `spec/services/activity_generator_spec.rb` (any test that sets step `io_overrides`)

- [ ] **Step 3A.1: Trim the emission_rewriter spec to element-level only**

Open `spec/services/code_generators/emission_rewriter_spec.rb`. Delete the first `RSpec.describe CodeGenerators::EmissionRewriter do ... end` block (lines 5–111 — the step-level `.call` tests). Keep only the `RSpec.describe CodeGenerators::EmissionRewriter, ".call_element" do` block at line 113 onwards.

The file should start with `require "rails_helper"` followed directly by the `.call_element` describe block.

- [ ] **Step 3A.2: Search for any other step-level call users in specs**

Run:
```
grep -rn 'EmissionRewriter\.call\b\|EmissionRewriter\.call([^_]' spec/ 2>/dev/null
```
Expected: no matches (or only matches that are clearly `call_element`). If any step-level `call` usage is found outside the file edited above, delete that usage — it's dead once the API is gone.

- [ ] **Step 3A.3: Run the spec — expect it to pass unchanged**

Run: `bundle exec rspec spec/services/code_generators/emission_rewriter_spec.rb`
Expected: all remaining tests PASS (we only deleted tests for an API that still exists — it'll keep working until 3A.5).

- [ ] **Step 3A.4: Remove step-level `io_overrides` from activity_generator.rb**

Open `app/services/activity_generator.rb`. Two edits:

1. `step_effective_keys` method (around lines 708–724). Replace:

```ruby
  def step_effective_keys(process_el)
    out = {}
    steps = process_el.dig("properties", "steps") || []
    steps.each do |step|
      action = step["action"]
      next if action.blank?

      pins = CodeGenerators::IoExtractor.call(
        action: action,
        config: step["config"] || {}
      )
      overrides = (step["io_overrides"] || {})["outputs"] || []
      rename_index = overrides.each_with_object({}) { |o, h| h[o["pin"]] = o["renamed_to"] if o["renamed_to"] }
      out[step["id"]] = (pins[:outputs] || []).map { |o| rename_index[o[:pin]] || o[:pin] }
    end
    out
  end
```

with:

```ruby
  def step_effective_keys(process_el)
    out = {}
    steps = process_el.dig("properties", "steps") || []
    steps.each do |step|
      action = step["action"]
      next if action.blank?

      pins = CodeGenerators::IoExtractor.call(
        action: action,
        config: step["config"] || {}
      )
      out[step["id"]] = (pins[:outputs] || []).map { |o| o[:pin] }
    end
    out
  end
```

2. The step-body rewrite callsite (around lines 845–855). Replace:

```ruby
    generator = generator_class.new(step, ctx)
    code = generator.generate_body
    return nil unless code

    rewritten = CodeGenerators::EmissionRewriter.call(
      body: code,
      io_overrides: step["io_overrides"] || {}
    )

    generator.send(:apply_wrappers, rewritten)
```

with:

```ruby
    generator = generator_class.new(step, ctx)
    code = generator.generate_body
    return nil unless code

    generator.send(:apply_wrappers, code)
```

Verify:
```
grep -n 'step\["io_overrides"\]\|io_overrides.*step' app/services/activity_generator.rb
```
Expected: no output.

- [ ] **Step 3A.5: Remove the step-level `call` API from EmissionRewriter**

Open `app/services/code_generators/emission_rewriter.rb`. Delete:

1. `self.call` class method (lines 84–86):
```ruby
def self.call(body:, io_overrides:)
  new(body, io_overrides).call
end
```

2. `initialize` and `call` instance methods (lines 88–112):
```ruby
def initialize(body, io_overrides)
  @body = body
  @io_overrides = io_overrides || {}
end

def call
  return @body if @body.nil? || @body.empty?

  input_map  = index_overrides(@io_overrides["inputs"] || @io_overrides[:inputs],  "producer_key")
  output_map = index_overrides(@io_overrides["outputs"] || @io_overrides[:outputs], "renamed_to")

  return @body if input_map.empty? && output_map.empty?

  ast = IoExtractor::BodyAnalyzer.call(@body)
  edits = []
  ast[:writes].each do |w|
    target = output_map[w[:pin]]
    edits << edit(w, target) if target
  end
  ast[:reads].each do |r|
    target = input_map[r[:pin]]
    edits << edit(r, target) if target
  end
  apply_edits(@body, edits)
end
```

3. Update the top-of-file docstring (lines 6–39) — delete the step-level examples and keep only the element-level section (lines 40+). Simplify to:

```ruby
# EmissionRewriter: element-level body source rewriter that applies
# io_overrides to generated Ruby bodies.
#
# .call_element resolves reads through three precedence tiers:
#
#   1. Explicit input override (inputs entry with non-empty override_key).
#   2. Tombstone ("" override_key) — read stays as ctx[:pin].
#   3. Nearest reachable producer whose producer_outputs include the pin.
#      If that producer renamed the pin via its own outputs override, the
#      rename is followed through rename_map.
#
# Additional inputs:
#   * element_id       — the id of the consuming element (reader).
#   * rename_map       — { producer_id => { pin => renamed_to } } from
#                        each producer's outputs overrides.
#   * reachability     — { element_id => [ancestor_ids_in_flow_order] }
#                        where the LAST id is the NEAREST producer.
#   * producer_outputs — { producer_id => [pins_that_producer_writes] }.
```

The class should now contain: the `Splicer` module, `include Splicer`, `self.call_element`, the shared `index_overrides` helper, and the private `ElementCall` class (below line 156). `initialize`, `call`, and `self.call` are gone.

- [ ] **Step 3A.6: Check for any other call sites of step-level `call`**

```
grep -rn 'EmissionRewriter\.call\b' app/ spec/ 2>/dev/null | grep -v 'call_element'
```
Expected: no matches.

- [ ] **Step 3A.7: Run backend specs**

Run:
```
bundle exec rspec spec/services/code_generators/emission_rewriter_spec.rb spec/services/activity_generator_spec.rb
```
Expected: all PASS. (Some activity_generator tests that implicitly relied on `io_overrides` being applied to step bodies may need adjustment. If any tests fail, remove the `io_overrides` from the input fixtures in those tests and update expected output to drop rewrites.)

- [ ] **Step 3A.8: Check flowchart_input_output_validator behavior**

Run: `bundle exec rspec spec/services/flowchart_input_output_validator_spec.rb`
Expected: all PASS. (This validator only reads element-level `io_overrides`, which we are NOT removing. Any failure here indicates a test that was cross-contaminated — investigate.)

- [ ] **Step 3A.9: Commit Task 3A**

```bash
git add app/services/activity_generator.rb \
        app/services/code_generators/emission_rewriter.rb \
        spec/services/code_generators/emission_rewriter_spec.rb \
        spec/services/activity_generator_spec.rb
git commit -m "$(cat <<'EOF'
refactor: drop step-level io_overrides in code generators

Delete EmissionRewriter.call (step-level) and its instance state.
ActivityGenerator.step_effective_keys no longer applies per-step rename
overrides; step bodies are emitted as-is (element-level rewrites still
apply via call_element). Element-level io_overrides are untouched.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3B: Remove Step-tab I/O pane + `StepIoManager` wiring

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js:8,71,477-488`
- Modify: `app/javascript/controllers/property_editor/templates.js:502-600`

- [ ] **Step 3B.1: Remove `StepIoManager` wiring from the controller**

Open `app/javascript/controllers/property_editor_controller.js`.

1. Line 8 — delete:
```js
import { StepIoManager } from "controllers/property_editor/step_io_manager"
```

2. Line 71 — delete:
```js
this.stepIoManager = new StepIoManager(this)
```

3. Lines 477–488 — delete the entire `handleStepIoProducerChange` method (including its JSDoc block):
```js
  /**
   * Producer dropdown change inside a step's I/O pane. Delegates to
   * StepIoManager which persists the override on both the live step object
   * and the hidden [data-step-io-overrides] input, then re-renders.
   */
  handleStepIoProducerChange(event) {
    const select = event.target
    const stepId = select.dataset.stepId
    const pinName = select.dataset.pinName
    if (!stepId || !pinName || !this.stepIoManager) return
    this.stepIoManager.updateProducer(stepId, pinName, select.value || "")
  }
```

Verify:
```
grep -n "StepIoManager\|stepIoManager" app/javascript/controllers/property_editor_controller.js
```
Expected: no output.

- [ ] **Step 3B.2: Remove the I/O pane + hidden input from the step item template**

Open `app/javascript/controllers/property_editor/templates.js`.

1. Inside `buildStepItemTemplate` (around line 502), delete the `ioOverrides` parameter from the destructuring block:

Change lines 503–519 from:
```js
  const {
    id = "",
    index,
    action,
    description,
    actionOptionData,
    selectionLabels,
    suboption,
    keywordParams = [],
    retryCount = 0,
    retryBackoff = "none",
    timeout = 0,
    guardCondition = "",
    configFieldsHTML = "",
    currentConfig = {},
    ioOverrides = { inputs: [], outputs: [] }
  } = params
```

to:
```js
  const {
    id = "",
    index,
    action,
    description,
    actionOptionData,
    selectionLabels,
    suboption,
    keywordParams = [],
    retryCount = 0,
    retryBackoff = "none",
    timeout = 0,
    guardCondition = "",
    configFieldsHTML = "",
    currentConfig = {}
  } = params
```

2. Lines 526–540 — replace the block of comments explaining the I/O pane with a single short comment. Change:

```js
  // The details panel is always rendered (even without config fields) so the
  // I/O pane has a home. Previously we hid the panel entirely when no config
  // fields existed; now every step with an id can surface per-step I/O, so
  // the container is unconditional.
  const hasDetails = true

  // Build keyword params display
  const keywordParamsHTML = keywordParams.length > 0
    ? `<div class="text-[10px] text-slate-400">Params: ${keywordParams.map(p => escapeHtml(p)).join(", ")}</div>`
    : ""

  // Build expandable details section. The I/O pane is an empty container
  // that StepIoManager fills when the step is expanded — keeping it in the
  // template means the manager never has to create DOM structure, only
  // populate an already-mounted slot.
  const detailsHTML = hasDetails
    ? `<div data-step-details class="hidden pl-6 mt-1.5 pt-1.5 border-t border-slate-100 space-y-2">
        ${configFieldsHTML}
        <div data-step-io-pane></div>
        ${description ? `<div class="text-[10px] text-slate-400">${escapeHtml(description)}</div>` : ""}
        ${keywordParamsHTML}
      </div>`
    : ""
```

to:
```js
  const keywordParamsHTML = keywordParams.length > 0
    ? `<div class="text-[10px] text-slate-400">Params: ${keywordParams.map(p => escapeHtml(p)).join(", ")}</div>`
    : ""

  const detailsHTML = `<div data-step-details class="hidden pl-6 mt-1.5 pt-1.5 border-t border-slate-100 space-y-2">
        ${configFieldsHTML}
        ${description ? `<div class="text-[10px] text-slate-400">${escapeHtml(description)}</div>` : ""}
        ${keywordParamsHTML}
      </div>`
```

3. Delete the `ioOverrides` hidden input. Line 597:
```js
<input type="hidden" name="steps[${index}][ioOverrides]" value="${escapeHtml(JSON.stringify(ioOverrides || { inputs: [], outputs: [] }))}" data-step-io-overrides>
```
Delete this entire line.

Verify:
```
grep -n "data-step-io\|ioOverrides" app/javascript/controllers/property_editor/templates.js
```
Expected: no output.

- [ ] **Step 3B.3: Build assets and sanity-check the browser**

Run: `bin/rails assets:precompile` (or if the repo uses a dev build script, run that). Then manually:
1. Start the Rails server: `bin/rails s`
2. Open the flowchart edit page in the browser.
3. Pick a process element, go to the Step tab, expand a step.
4. Confirm no "I/O" section renders inside the expanded step.
5. Confirm no JS errors in the browser console.
6. Confirm the Element I/O tab still works on non-process elements.

If a JS error appears, it's likely because `step_io_manager.js` is still being imported elsewhere — grep and fix before committing.

Since this is a UI change, type-checks / spec suites alone don't verify it; the manual check is required.

- [ ] **Step 3B.4: Commit Task 3B**

```bash
git add app/javascript/controllers/property_editor_controller.js \
        app/javascript/controllers/property_editor/templates.js
git commit -m "$(cat <<'EOF'
refactor: remove Step-tab I/O pane from the property editor

Drop the <div data-step-io-pane> slot, the [data-step-io-overrides]
hidden input, and the StepIoManager wiring from the property editor
controller. Expanded steps now show only config fields, keyword
params, and description.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3C: Remove step-level `io_overrides` collection in `step_manager.js`

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_manager.js:399-427,773-788,938-1061`

- [ ] **Step 3C.1: Remove the step-expand → I/O pane hook**

Open `app/javascript/controllers/property_editor/step_manager.js`.

1. In the step-toggle flow around lines 395–405, delete the `_notifyStepIoExpanded` call:

```js
    // Populate the step I/O pane on expansion. The live step object comes
    // from canvas.findStepById so StepIoManager can mutate step.io_overrides
    // directly and the same reference round-trips through the hidden input
    // + collectSteps on save.
    if (willExpand) {
      this._notifyStepIoExpanded(stepItem)
    }
  }
```

becomes:
```js
  }
```
(The comment and the `if (willExpand)` block go away. Watch for correct closing braces.)

2. Delete the `_notifyStepIoExpanded` method entirely (lines 408–427):

```js
  /**
   * Locate the live step object for a DOM item and ask StepIoManager to
   * populate its I/O pane. Quiet no-op when the manager or canvas isn't
   * available (e.g. in tests that bypass the controller).
   * @private
   */
  _notifyStepIoExpanded(stepItem) {
    const manager = this.controller.stepIoManager
    if (!manager) return

    const pane = stepItem.querySelector("[data-step-io-pane]")
    if (!pane) return

    const canvas = this.controller.canvas
    const stepId = stepItem.dataset.stepId
    const found = canvas?.findStepById?.(stepId)
    if (!found) return

    manager.openForStep(found.step, pane)
  }
```

- [ ] **Step 3C.2: Remove the `ioOverrides` read in `collectSteps`**

Still in `step_manager.js`, find the `collectSteps` method around lines 773–788. Delete the block:

```js
        // Read io_overrides from the hidden input mirror. StepIoManager
        // writes both the in-memory step.io_overrides and this hidden input,
        // but reading the input makes us resilient to out-of-band DOM
        // rehydration (e.g. reopening the editor on the same element).
        const ioOverridesInput = item.querySelector("[data-step-io-overrides]")
        if (ioOverridesInput?.value) {
          try {
            const parsed = JSON.parse(ioOverridesInput.value)
            const inputs = Array.isArray(parsed?.inputs) ? parsed.inputs : []
            const outputs = Array.isArray(parsed?.outputs) ? parsed.outputs : []
            if (inputs.length > 0 || outputs.length > 0) {
              stepData.io_overrides = { inputs, outputs }
            }
          } catch { /* ignore */ }
        }
```

The preceding `stepData.config` assignment and the trailing `steps.push(stepData)` should now be adjacent.

- [ ] **Step 3C.3: Remove `ioOverrides` parsing and propagation in step rendering**

Still in `step_manager.js`, find the step-rendering loop around lines 938–975. Delete these lines:

```js
      // Parse io_overrides if stored. Support both the canonical snake_case
      // server key and the camelCase form any UI round-trip might emit.
      let ioOverrides = { inputs: [], outputs: [] }
      const storedIoOverrides = step.io_overrides ?? step.ioOverrides
      if (storedIoOverrides) {
        try {
          const parsed = typeof storedIoOverrides === "string" ? JSON.parse(storedIoOverrides) : storedIoOverrides
          ioOverrides = {
            inputs: Array.isArray(parsed?.inputs) ? parsed.inputs : [],
            outputs: Array.isArray(parsed?.outputs) ? parsed.outputs : []
          }
        } catch {
          ioOverrides = { inputs: [], outputs: [] }
        }
      }
```

Then remove the `ioOverrides` argument from the `this.buildStepItemHTML(...)` call (currently line 973 in the 17-argument list). The resulting call should have 16 args, ending with `step.id || generateStepId()`.

- [ ] **Step 3C.4: Update `buildStepItemHTML` signature and body**

Around line 1019, change the signature:

```js
buildStepItemHTML(index, action, description, actionOptions = null, collapsed = false, suboption = "", actionOptionData = null, selectionLabels = null, keywordParams = [], retryCount = 0, retryBackoff = "none", timeout = 0, guardCondition = "", currentConfig = {}, id = "", ioOverrides = { inputs: [], outputs: [] }) {
```

to:
```js
buildStepItemHTML(index, action, description, actionOptions = null, collapsed = false, suboption = "", actionOptionData = null, selectionLabels = null, keywordParams = [], retryCount = 0, retryBackoff = "none", timeout = 0, guardCondition = "", currentConfig = {}, id = "") {
```

Then, inside the method around line 1060, remove the `ioOverrides` property from the `buildStepItemTemplate({ ... })` call object:

```js
    return buildStepItemTemplate({
      id: resolvedId,
      index,
      action,
      description,
      actionOptionData,
      selectionLabels,
      suboption,
      keywordParams,
      retryCount,
      retryBackoff,
      timeout,
      guardCondition,
      configFieldsHTML,
      currentConfig,
      ioOverrides   // <-- DELETE THIS LINE
    })
```

Also revise the comment at lines 1038–1041:

```js
    // Every step DOM item must carry a stable id in data-step-id so it
    // survives DOM round-trips (collectSteps reads it back) and so the
    // canvas stepPins cache/conflict resolver can key bindings off it.
    // Callers generate an id once at creation; backfill here if missing.
```
becomes:
```js
    // Every step DOM item must carry a stable id in data-step-id so it
    // survives DOM round-trips (collectSteps reads it back).
    // Callers generate an id once at creation; backfill here if missing.
```

Verify:
```
grep -n "io_overrides\|ioOverrides\|data-step-io" app/javascript/controllers/property_editor/step_manager.js
```
Expected: no output.

- [ ] **Step 3C.5: Browser check**

Restart the dev server, open the flowchart edit page, expand a process step, and:
1. Confirm no console errors.
2. Confirm step save/load still works (click Save, reopen element).

- [ ] **Step 3C.6: Commit Task 3C**

```bash
git add app/javascript/controllers/property_editor/step_manager.js
git commit -m "$(cat <<'EOF'
refactor: stop collecting step-level io_overrides in step_manager

Drop the _notifyStepIoExpanded hook, the ioOverrides hidden-input
parse in collectSteps, and the ioOverrides parameter threading
through buildStepItemHTML / buildStepItemTemplate.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3D: Remove step override lookup in `context_variable_provider.js`

**Files:**
- Modify: `app/javascript/flowchart/context_variable_provider.js:67-88`

- [ ] **Step 3D.1: Simplify `getStepEffectiveOutputs`**

Open `app/javascript/flowchart/context_variable_provider.js`. Replace the `getStepEffectiveOutputs` function (around lines 67–88):

```js
/**
 * Get effective output keys for a step, honoring io_overrides renames.
 */
function getStepEffectiveOutputs(canvas, stepId) {
  const pins = canvas.getStepPins?.(stepId) || { outputs: [] }
  const outputPins = pins.outputs || []
  const located = canvas.findStepById?.(stepId)
  const overrides = located?.step?.io_overrides?.outputs || []

  const overrideMap = new Map()
  for (const o of overrides) {
    overrideMap.set(o.pin, o.renamed_to)
  }

  const effectiveKeys = []
  for (const pin of outputPins) {
    const effective = overrideMap.get(pin.pin) || pin.pin
    effectiveKeys.push(effective)
  }

  return effectiveKeys
}
```

with:
```js
function getStepEffectiveOutputs(canvas, stepId) {
  const pins = canvas.getStepPins?.(stepId) || { outputs: [] }
  return (pins.outputs || []).map((p) => p.pin)
}
```

Note: the `getElementEffectiveOutputs` function just above (lines 38–65 per explore) uses **element-level** `io_overrides.outputs`, which we ARE keeping — do NOT touch it.

Verify:
```
grep -n "io_overrides\|ioOverrides" app/javascript/flowchart/context_variable_provider.js
```
Expected: matches only inside `getElementEffectiveOutputs` (element-level, kept).

- [ ] **Step 3D.2: Run any related JS specs if present**

Run: `bundle exec rspec spec/system/property_editor/ spec/system/flowchart*.rb 2>/dev/null || true`
Expected: pass (or the folder doesn't exist — that's fine).

- [ ] **Step 3D.3: Commit Task 3D**

```bash
git add app/javascript/flowchart/context_variable_provider.js
git commit -m "$(cat <<'EOF'
refactor: drop step-level io_overrides in context_variable_provider

getStepEffectiveOutputs now returns raw pin names. Element-level
io_overrides.outputs lookup in getElementEffectiveOutputs is kept.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3E: Delete dead JS modules

Now that nothing imports them, remove the three obsolete JS files.

**Files:**
- Delete: `app/javascript/controllers/property_editor/step_io_manager.js`
- Delete: `app/javascript/controllers/property_editor/step_io/override_computer.js`
- Delete: `app/javascript/controllers/property_editor/step_io/reachability.js`

**Files to KEEP (do NOT delete):**
- `app/javascript/controllers/property_editor/step_io/io_params_client.js` — feeds autocomplete via `primeAllStepPins` / `primeUnfetchedStepPins` and `fetchStepPins`.

- [ ] **Step 3E.1: Confirm no imports remain**

Run:
```
grep -rn "step_io_manager\|StepIoManager\|step_io/override_computer\|step_io/reachability" --include="*.js" app/javascript/
```
Expected: no output.

- [ ] **Step 3E.2: Delete the files**

```
rm app/javascript/controllers/property_editor/step_io_manager.js
rm app/javascript/controllers/property_editor/step_io/override_computer.js
rm app/javascript/controllers/property_editor/step_io/reachability.js
```

- [ ] **Step 3E.3: Confirm `io_params_client.js` is still in place and still imported**

```
ls app/javascript/controllers/property_editor/step_io/
grep -rn "io_params_client\|primeAllStepPins\|primeUnfetchedStepPins\|fetchStepPins" --include="*.js" app/javascript/
```
Expected: `io_params_client.js` is the only file in `step_io/`. `primeAllStepPins` is imported by `flowchart_canvas_controller.js`. `primeUnfetchedStepPins` and `fetchStepPins` are no longer used (they were imported only by `step_io_manager.js`); keep them in the module for now since `primeAllStepPins` lives there too — removing the unused exports is a YAGNI cleanup for another day.

Actually re-check: `primeAllStepPins` is the primary export still used. Verify the file doesn't define anything else that's now dead:

```
grep -n "^export" app/javascript/controllers/property_editor/step_io/io_params_client.js
```

If `primeUnfetchedStepPins` and `fetchStepPins` are ONLY referenced inside the file itself (as helpers of `primeAllStepPins`) plus by now-deleted `step_io_manager.js`, they are dead exports. Simplify the file to export only `primeAllStepPins`, inlining `fetchStepPins` as a local helper and deleting `primeUnfetchedStepPins` entirely.

Rewrite `app/javascript/controllers/property_editor/step_io/io_params_client.js` to:

```js
/**
 * Fetch pins for every step action on the canvas and seed canvas.stepPins
 * for autocomplete.
 */
async function fetchStepPins(action, config) {
  if (!action) return { inputs: [], outputs: [] }

  try {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""
    const response = await fetch(`/code_generators/${encodeURIComponent(action)}/io_params`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({ config: config || {} })
    })
    if (!response.ok) return { inputs: [], outputs: [] }
    return await response.json()
  } catch (e) {
    console.warn("[step_io] io_params fetch failed:", e)
    return { inputs: [], outputs: [] }
  }
}

export async function primeAllStepPins(canvas) {
  const jobs = []
  canvas.iterateStepActions((step) => {
    if (!step.action) return
    jobs.push(
      fetchStepPins(step.action, step.config || {}).then((pins) => canvas.setStepPins(step.id, pins))
    )
  })
  await Promise.all(jobs)
}
```

- [ ] **Step 3E.4: Browser verification**

Restart dev server. Reload the flowchart edit page.
1. Confirm autocomplete on config fields still lists upstream step outputs (test by dragging two process elements, connecting them, and typing in a config field on the second).
2. Confirm no JS errors in the console.
3. Confirm Element I/O tab still works.

- [ ] **Step 3E.5: Run full Rails test suite**

Run: `bundle exec rspec`
Expected: baseline 4331+ examples, 0 failures.

- [ ] **Step 3E.6: Commit Task 3E**

```bash
git add app/javascript/controllers/property_editor/step_io_manager.js \
        app/javascript/controllers/property_editor/step_io/override_computer.js \
        app/javascript/controllers/property_editor/step_io/reachability.js \
        app/javascript/controllers/property_editor/step_io/io_params_client.js
git status
```

Note the three deleted files should show as `deleted:` and `io_params_client.js` as `modified:`. Then:

```bash
git commit -m "$(cat <<'EOF'
refactor: delete dead Step-tab I/O JS modules

Remove step_io_manager.js, step_io/override_computer.js, and
step_io/reachability.js (no longer imported anywhere). Simplify
step_io/io_params_client.js to export only primeAllStepPins, which
still feeds canvas.stepPins for autocomplete.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Final Verification

- [ ] **Step F.1: Run every spec suite touched**

```
bundle exec rspec spec/services/code_generators/ \
                  spec/services/activity_generator_spec.rb \
                  spec/services/flowchart_input_output_validator_spec.rb \
                  spec/system/property_editor/
```
Expected: all PASS.

- [ ] **Step F.2: Run the full suite**

```
bundle exec rspec
```
Expected: baseline 4331+ examples, 0 failures. Note the exact number — if it dropped by more than the count of tests we deleted, investigate.

- [ ] **Step F.3: Run the UI↔generator audit**

```
bundle exec ruby scripts/audit_generator_ui.rb
```
Expected: passes with no warnings.

- [ ] **Step F.4: Manual browser smoke test**

Start `bin/rails s`, open the flowchart edit page, and confirm:
1. `new_model` action config shows: Attributes, Associations, Result Variable. No "Skip Validation", no "Customer Scoped", no "Scope By Customer Id".
2. The other 5 model-operation actions no longer show "Scope By Customer Id".
3. Process element Step tab: expanded steps show only config fields, keyword params, and description (no I/O section).
4. Element I/O tab still works (Inputs producer dropdowns, Outputs rename badges).
5. Autocomplete on config fields still lists upstream step outputs.
6. Create a simple flowchart (start → process with `new_model` → end), save, reload — the stored config should not include any of the removed keys; the saved flowchart loads without errors even if a hand-injected config includes them.

- [ ] **Step F.5: Report completion**

Summarize to the user: number of commits, verification status, any manual-check observations.

---

## Out of scope (do not implement)

- Data migration of saved flowcharts (stale keys silently ignored).
- Refactor of `ConflictResolver`.
- Renaming or removing the `step_io/` directory (`io_params_client.js` stays there).
