# Enrich Process Step Actions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand process element step actions from 10 to 24 with per-action configuration that generates real Ruby code, backed by a searchable categorized dropdown and modular activity generator.

**Architecture:** JS Action Registry pattern with per-category config modules feeds a searchable dropdown UI and inline config fields in expanded step items. Ruby ActivityGenerator decomposed into per-category step generator modules that read config hashes to produce parameterized Trailblazer activity code. Backward compatible — existing flowcharts without config hashes produce identical output.

**Tech Stack:** Rails 8.1, StimulusJS, TailwindCSS, Trailblazer Activity, RSpec

**Spec:** `docs/superpowers/specs/2026-03-25-enrich-process-step-actions-design.md`

**Important Notes:**
- **JS Tests**: The codebase has no JS test framework. JS changes are verified via asset precompilation and manual testing. The spec's JS test requirements are documented for future implementation when a JS test framework is added.
- **subOption Casing**: Existing flowcharts store `suboption` (lowercase) in JSON. Ruby generators must include a fallback: `step.dig("subOption") || step.dig("suboption")` to handle both old and new data. The JS casing fix (Task 9) standardizes new writes to `subOption`.
- **Tailwind Dynamic Classes**: Never construct Tailwind classes dynamically (e.g., `text-${color}-500`). Always use the existing `getColorClasses()` helper from `templates.js` which maps color names to pre-defined class strings that survive CSS purging.
- **Color Change**: `notify` action color changes from `pink` (existing) to `amber` (per spec). This is an intentional visual change.

---

## File Map

### New JS Files
| File | Responsibility |
|---|---|
| `app/javascript/flowchart/constants/action_registry.js` | Central registry, ACTION_CATEGORIES, helper functions (getActionsByCategory, searchActions, etc.) |
| `app/javascript/flowchart/constants/action_configs/model_actions.js` | 6 model action definitions with configSchema |
| `app/javascript/flowchart/constants/action_configs/validation_actions.js` | 2 validation action definitions with configSchemaBySubOption |
| `app/javascript/flowchart/constants/action_configs/data_actions.js` | 4 data action definitions with configSchema |
| `app/javascript/flowchart/constants/action_configs/communication_actions.js` | 4 communication action definitions with configSchema |
| `app/javascript/flowchart/constants/action_configs/security_actions.js` | 1 security action definition with configSchema |
| `app/javascript/flowchart/constants/action_configs/background_actions.js` | 2 background action definitions with configSchema |
| `app/javascript/flowchart/constants/action_configs/file_actions.js` | 2 file action definitions with configSchema |
| `app/javascript/flowchart/constants/action_configs/realtime_actions.js` | 2 realtime action definitions with configSchema |
| `app/javascript/flowchart/constants/action_configs/response_actions.js` | 1 response action definition with configSchema |

### New Ruby Files
| File | Responsibility |
|---|---|
| `app/services/activity_generator/base_step_helpers.rb` | Shared helpers: wrap_with_retry, wrap_with_timeout, wrap_with_guard, condition_operand_to_ruby, build_headers_code |
| `app/services/activity_generator/model_steps.rb` | Generators: new_model, find_model, save_model, destroy_model, update_model, query_models |
| `app/services/activity_generator/validation_steps.rb` | Generators: build_contract, validate_contract |
| `app/services/activity_generator/data_steps.rb` | Generators: assign_value, transform, calculate, log |
| `app/services/activity_generator/communication_steps.rb` | Generators: api_call, send_email, send_webhook, notify |
| `app/services/activity_generator/security_steps.rb` | Generator: authorize |
| `app/services/activity_generator/background_steps.rb` | Generators: enqueue_job, schedule_job |
| `app/services/activity_generator/file_steps.rb` | Generators: generate_file_action, upload_file |
| `app/services/activity_generator/realtime_steps.rb` | Generators: publish_event, broadcast |
| `app/services/activity_generator/response_steps.rb` | Generator: render_response |

### New RSpec Files
| File | Responsibility |
|---|---|
| `spec/services/activity_generator/model_steps_spec.rb` | Tests for 6 model step generators with config variations |
| `spec/services/activity_generator/validation_steps_spec.rb` | Tests for 2 validation step generators |
| `spec/services/activity_generator/data_steps_spec.rb` | Tests for 4 data step generators with config variations |
| `spec/services/activity_generator/communication_steps_spec.rb` | Tests for 4 communication step generators with config variations |
| `spec/services/activity_generator/security_steps_spec.rb` | Tests for authorize generator |
| `spec/services/activity_generator/background_steps_spec.rb` | Tests for 2 background step generators |
| `spec/services/activity_generator/file_steps_spec.rb` | Tests for 2 file step generators |
| `spec/services/activity_generator/realtime_steps_spec.rb` | Tests for 2 realtime step generators |
| `spec/services/activity_generator/response_steps_spec.rb` | Tests for render_response generator |

### Modified JS Files
| File | Changes |
|---|---|
| `app/javascript/flowchart/constants/schemas.js` | Replace STEP_ACTIONS array with `getAllActions()` import from registry |
| `app/javascript/controllers/searchable_select_controller.js` | Add disabled item support, SVG icon rendering, description data attribute |
| `app/javascript/controllers/property_editor/step_manager.js` | Add buildStepConfigHTML, collectStepConfig, update collectSteps, fix subOption casing, replace SINGLE_USE_ACTIONS with getSingleUseActions(), update presets with config defaults |
| `app/javascript/controllers/property_editor/templates.js` | Update buildStepItemTemplate to include configFieldsHTML section in step-details |

### Modified Ruby Files
| File | Changes |
|---|---|
| `app/services/activity_generator.rb` | Include all step modules, update STEP_ACTIONS hash with 24 entries, remove step generator methods (moved to modules), keep orchestration logic |

---

## Task 1: Action Registry + Config Modules (JS)

**Files:**
- Create: `app/javascript/flowchart/constants/action_registry.js`
- Create: `app/javascript/flowchart/constants/action_configs/model_actions.js`
- Create: `app/javascript/flowchart/constants/action_configs/validation_actions.js`
- Create: `app/javascript/flowchart/constants/action_configs/data_actions.js`
- Create: `app/javascript/flowchart/constants/action_configs/communication_actions.js`
- Create: `app/javascript/flowchart/constants/action_configs/security_actions.js`
- Create: `app/javascript/flowchart/constants/action_configs/background_actions.js`
- Create: `app/javascript/flowchart/constants/action_configs/file_actions.js`
- Create: `app/javascript/flowchart/constants/action_configs/realtime_actions.js`
- Create: `app/javascript/flowchart/constants/action_configs/response_actions.js`

**Reference:** Spec sections "Architecture: Action Registry Pattern" and "Full Action Catalog" for every action's value, label, icon, color, category, singleUse, configSchema, and subOptions.

- [ ] **Step 1: Create the action_configs directory**

```bash
mkdir -p app/javascript/flowchart/constants/action_configs
```

- [ ] **Step 2: Create model_actions.js**

Define 6 actions: `new_model`, `find_model`, `save_model`, `destroy_model`, `update_model`, `query_models`. Each with full metadata (value, label, icon, color, category: "model", description, singleUse) and configSchema per spec. Use existing icons from `schemas.js` for the first 4; create new icons for `update_model` and `query_models`.

Export as: `export const MODEL_ACTIONS = [...]`

- [ ] **Step 3: Create validation_actions.js**

Define 2 actions: `build_contract`, `validate`. The `validate` action uses `configSchemaBySubOption` (not `configSchema`) with sub-option-scoped config for "contract" (empty array) and "permission" (permissionType, roleExpression, requiredRole, policyClass, policyAction with visibleWhen conditions).

Export as: `export const VALIDATION_ACTIONS = [...]`

- [ ] **Step 4: Create data_actions.js**

Define 4 actions: `assign_value`, `transform`, `calculate`, `log`. Each with configSchema per spec. `transform` has 4 transform types with visibleWhen conditions. `calculate` has 6 operations. `assign_value` has 4 value types. `log` has 2 log types.

Export as: `export const DATA_ACTIONS = [...]`

- [ ] **Step 5: Create communication_actions.js**

Define 4 actions: `API_call`, `send_email`, `send_webhook`, `notify`. `API_call` has the most complex configSchema (httpMethod, url, headers as key_value_list, bodyTemplate, authType with 4 auth sub-configs using visibleWhen). Use existing icon for `API_call` and `notify`.

Export as: `export const COMMUNICATION_ACTIONS = [...]`

- [ ] **Step 6: Create security_actions.js, background_actions.js, file_actions.js, realtime_actions.js, response_actions.js**

Define remaining 8 actions across 5 files, each with configSchema per spec. These are smaller files (1-2 actions each).

Export as: `export const SECURITY_ACTIONS = [...]`, etc.

- [ ] **Step 7: Create action_registry.js**

Import all 9 action config arrays. Define `ACTION_CATEGORIES` array. Implement 5 helper functions:

```javascript
import { MODEL_ACTIONS } from "./action_configs/model_actions"
// ... all 9 imports

const ALL_ACTIONS = [
  ...MODEL_ACTIONS, ...VALIDATION_ACTIONS, ...DATA_ACTIONS,
  ...COMMUNICATION_ACTIONS, ...SECURITY_ACTIONS, ...BACKGROUND_ACTIONS,
  ...FILE_ACTIONS, ...REALTIME_ACTIONS, ...RESPONSE_ACTIONS
]

export const ACTION_CATEGORIES = [ /* 9 categories */ ]

export function getActionsByCategory() {
  return ACTION_CATEGORIES.map(cat => ({
    category: cat,
    actions: ALL_ACTIONS.filter(a => a.category === cat.key)
  })).filter(g => g.actions.length > 0)
}

export function searchActions(query) {
  const q = query.toLowerCase()
  return ALL_ACTIONS.filter(a =>
    a.label.toLowerCase().includes(q) ||
    a.description.toLowerCase().includes(q) ||
    ACTION_CATEGORIES.find(c => c.key === a.category)?.label.toLowerCase().includes(q)
  )
}

export function getActionConfig(actionValue) {
  return ALL_ACTIONS.find(a => a.value === actionValue)
}

export function getSingleUseActions() {
  return ALL_ACTIONS.filter(a => a.singleUse).map(a => a.value)
}

export function getAllActions() {
  return ALL_ACTIONS
}
```

- [ ] **Step 8: Verify module loads**

```bash
cd /opt/ai_coding/anysys
node -e "
  // Quick syntax check - import would fail in Node without bundler
  // but we can at least verify no syntax errors
  const fs = require('fs');
  const files = [
    'app/javascript/flowchart/constants/action_registry.js',
    ...require('fs').readdirSync('app/javascript/flowchart/constants/action_configs').map(f => 'app/javascript/flowchart/constants/action_configs/' + f)
  ];
  files.forEach(f => { try { require('acorn').parse(fs.readFileSync(f, 'utf8'), {sourceType:'module',ecmaVersion:2022}); console.log('OK:', f); } catch(e) { console.error('FAIL:', f, e.message); } });
" 2>/dev/null || echo "Syntax check skipped (acorn not available) - verify via asset precompile"
```

- [ ] **Step 9: Commit**

```bash
git add app/javascript/flowchart/constants/action_registry.js app/javascript/flowchart/constants/action_configs/
git commit -m "feat: add action registry with 24 categorized actions and config schemas"
```

---

## Task 2: Wire Registry into schemas.js

**Files:**
- Modify: `app/javascript/flowchart/constants/schemas.js`

**Reference:** Spec section "Registry Entry Identifier" — `getAllActions()` returns entries with `value` field matching existing format.

- [ ] **Step 1: Update schemas.js**

Replace the existing `STEP_ACTIONS` array (lines 42-117 of `schemas.js`) with an import from the registry:

```javascript
import { getAllActions } from "./action_registry"

export const STEP_ACTIONS = getAllActions()
```

Remove the old hardcoded `STEP_ACTIONS` array entirely. Keep all other exports (`BRANCH_OPERATORS`, `BRANCH_CONDITIONS`, `ELEMENT_SCHEMAS`, etc.) unchanged.

- [ ] **Step 2: Precompile assets to verify no import errors**

```bash
RAILS_ENV=development bundle exec rails assets:precompile 2>&1
```

Expected: No errors. The existing StepManager, FormBuilder, and other consumers of `STEP_ACTIONS` continue to work because `getAllActions()` returns entries with the same `value`, `label`, `icon`, `color`, `description`, and `subOptions` fields.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/flowchart/constants/schemas.js
git commit -m "feat: wire STEP_ACTIONS to action registry for backward compatibility"
```

---

## Task 3: BaseStepHelpers Extraction + ActivityGenerator Slim-Down (Ruby TDD)

**Files:**
- Create: `app/services/activity_generator/base_step_helpers.rb`
- Modify: `app/services/activity_generator.rb`
- Test: `spec/services/activity_generator_spec.rb` (existing — must still pass)

**Reference:** Spec section "Base Step Helpers" — extract wrap_with_retry, wrap_with_timeout, wrap_with_guard, condition_operand_to_ruby, build_headers_code.

- [ ] **Step 1: Run existing tests to establish baseline**

```bash
bundle exec rspec spec/services/activity_generator_spec.rb spec/services/activity_generator_compound_conditions_spec.rb --format documentation
```

Expected: All tests PASS. Note the count.

- [ ] **Step 2: Create the activity_generator directory**

```bash
mkdir -p app/services/activity_generator
```

- [ ] **Step 3: Create base_step_helpers.rb**

Extract from `activity_generator.rb` these private methods into a module:

```ruby
# frozen_string_literal: true

module ActivityGenerator::BaseStepHelpers
  private

  def wrap_with_timeout(code, step)
    # ... exact code from activity_generator.rb lines 759-767
  end

  def wrap_with_retry(code, step)
    # ... exact code from activity_generator.rb lines 771-799
  end

  def wrap_with_guard(code, step)
    # ... exact code from activity_generator.rb lines 803-814
  end

  def condition_operand_to_ruby(operand)
    # ... exact code from activity_generator.rb lines 717-733
  end

  def build_headers_code(headers, auth_type, config)
    # New shared helper for API_call and send_webhook
    header_lines = (headers || []).map do |h|
      "request[\"#{h['key']}\"] = \"#{h['value']}\""
    end

    case auth_type
    when "bearer"
      token = config["authToken"] || "ctx[:api_token]"
      header_lines << "request[\"Authorization\"] = \"Bearer \#{#{token}}\""
    when "basic"
      username = config["authUsername"] || "ctx[:username]"
      password = config["authPassword"] || "ctx[:password]"
      header_lines << "request.basic_auth(#{username}, #{password})"
    when "apiKey"
      key_header = config["apiKeyHeader"] || "X-API-Key"
      key_value = config["apiKeyValue"] || "ctx[:api_key]"
      header_lines << "request[\"#{key_header}\"] = #{key_value}"
    end

    header_lines.empty? ? "" : header_lines.join("\n")
  end
end
```

- [ ] **Step 4: Update activity_generator.rb**

Add `include ActivityGenerator::BaseStepHelpers` at the top of the class. Remove the extracted methods (`wrap_with_timeout`, `wrap_with_retry`, `wrap_with_guard`, `condition_operand_to_ruby`) from the file — they now come from the module. Keep `build_loop_condition`, `build_structured_condition`, etc. (these stay in the orchestrator since they're specific to element-level generation, not step-level).

Note: `condition_operand_to_ruby` is used by both step helpers (guard conditions) and element-level code (decision conditions, loop conditions). It belongs in BaseStepHelpers and is available to the orchestrator via `include`.

- [ ] **Step 5: Run existing tests to verify no regressions**

```bash
bundle exec rspec spec/services/activity_generator_spec.rb spec/services/activity_generator_compound_conditions_spec.rb --format documentation
```

Expected: Same number of tests, all PASS. No behavior change.

- [ ] **Step 6: Commit**

```bash
git add app/services/activity_generator/base_step_helpers.rb app/services/activity_generator.rb
git commit -m "refactor: extract BaseStepHelpers module from ActivityGenerator"
```

---

## Task 4: Model + Validation Step Modules (Ruby TDD)

**Files:**
- Create: `app/services/activity_generator/model_steps.rb`
- Create: `app/services/activity_generator/validation_steps.rb`
- Create: `spec/services/activity_generator/model_steps_spec.rb`
- Create: `spec/services/activity_generator/validation_steps_spec.rb`
- Modify: `app/services/activity_generator.rb`

**Reference:** Spec section "Model Operations" and "Validation" for all config variations and generated code.

- [ ] **Step 1: Write model_steps_spec.rb**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityGenerator::ModelSteps do
  # Include the module in a test class that mimics ActivityGenerator
  let(:generator_class) do
    Class.new do
      include ActivityGenerator::BaseStepHelpers
      include ActivityGenerator::ModelSteps
    end
  end
  let(:generator) { generator_class.new }
  let(:ctx) { {} }

  describe '#generate_new_model' do
    it 'generates new model code' do
      step = { "action" => "new_model" }
      code = generator.generate_new_model(step, ctx)
      expect(code).to include("EntityEntry.build_for")
      expect(code).to include(".new(customer_id:")
    end
  end

  describe '#generate_find_model' do
    context 'with default config (find strategy)' do
      it 'generates find by id' do
        step = { "action" => "find_model" }
        code = generator.generate_find_model(step, ctx)
        expect(code).to include(".find(ctx[:id])")
      end
    end

    context 'with findBy strategy' do
      it 'generates find_by with configured field' do
        step = { "action" => "find_model", "config" => { "findStrategy" => "findBy", "findField" => "email", "findValue" => "ctx[:email]" } }
        code = generator.generate_find_model(step, ctx)
        expect(code).to include("find_by!(email: ctx[:email])")
      end
    end

    context 'with where strategy' do
      it 'generates where query' do
        step = { "action" => "find_model", "config" => { "findStrategy" => "where", "findField" => "status", "findValue" => "ctx[:status]" } }
        code = generator.generate_find_model(step, ctx)
        expect(code).to include("where(status: ctx[:status])")
      end
    end

    context 'with custom resultVar' do
      it 'uses the configured result variable' do
        step = { "action" => "find_model", "config" => { "resultVar" => "user" } }
        code = generator.generate_find_model(step, ctx)
        expect(code).to include("ctx[:user]")
      end
    end

    context 'with no config (backward compat)' do
      it 'defaults to find by id with model var' do
        step = { "action" => "find_model" }
        code = generator.generate_find_model(step, ctx)
        expect(code).to include("ctx[:model]")
        expect(code).to include(".find(ctx[:id])")
      end
    end
  end

  describe '#generate_save_model' do
    context 'with default config' do
      it 'generates SaveAll call' do
        step = { "action" => "save_model" }
        code = generator.generate_save_model(step, ctx)
        expect(code).to include("ActivitySteps::SaveAll.call(ctx)")
      end
    end

    context 'with saveOnly strategy' do
      it 'generates direct save' do
        step = { "action" => "save_model", "config" => { "saveStrategy" => "saveOnly" } }
        code = generator.generate_save_model(step, ctx)
        expect(code).to include("ctx[:model].save!")
      end
    end
  end

  describe '#generate_destroy_model' do
    context 'with default config' do
      it 'generates destroy' do
        step = { "action" => "destroy_model" }
        code = generator.generate_destroy_model(step, ctx)
        expect(code).to include("ctx[:model].destroy")
      end
    end

    context 'with softDelete strategy' do
      it 'generates soft delete' do
        step = { "action" => "destroy_model", "config" => { "destroyStrategy" => "softDelete" } }
        code = generator.generate_destroy_model(step, ctx)
        expect(code).to include("update!(status: :deleted")
      end
    end
  end

  describe '#generate_update_model' do
    it 'generates update with field mappings' do
      step = { "action" => "update_model", "config" => { "fieldMappings" => [{ "key" => "name", "value" => "ctx[:new_name]" }] } }
      code = generator.generate_update_model(step, ctx)
      expect(code).to include("update!")
      expect(code).to include("name: ctx[:new_name]")
    end

    it 'generates comment when no mappings' do
      step = { "action" => "update_model" }
      code = generator.generate_update_model(step, ctx)
      expect(code).to include("update!")
    end
  end

  describe '#generate_query_models' do
    context 'with where query type' do
      it 'generates where clause' do
        step = { "action" => "query_models", "config" => { "queryType" => "where", "conditions" => [{ "key" => "status", "value" => "\"active\"" }], "orderBy" => "created_at desc", "limit" => 10 } }
        code = generator.generate_query_models(step, ctx)
        expect(code).to include("where(")
        expect(code).to include("order(")
        expect(code).to include("limit(10)")
      end
    end

    context 'with scope query type' do
      it 'generates scope call' do
        step = { "action" => "query_models", "config" => { "queryType" => "scope", "scopeName" => "active_users", "scopeArgs" => "ctx[:role]" } }
        code = generator.generate_query_models(step, ctx)
        expect(code).to include("send(:active_users")
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/activity_generator/model_steps_spec.rb --format documentation
```

Expected: FAIL — `ActivityGenerator::ModelSteps` not defined.

- [ ] **Step 3: Create model_steps.rb**

Move `generate_new_model`, `generate_find_model`, `generate_save_model`, `generate_destroy_model` from `activity_generator.rb` into the module. Add config-aware logic per spec. Add new methods `generate_update_model` and `generate_query_models`.

```ruby
# frozen_string_literal: true

module ActivityGenerator::ModelSteps
  def generate_new_model(_step, _ctx)
    <<~RUBY.chomp
      ctx[:model] = EntityEntry.build_for(ctx[:bound_entity]).new(customer_id: ctx[:customer_id])
      true
    RUBY
  end

  def generate_find_model(step, _ctx)
    config = step["config"] || {}
    strategy = config["findStrategy"] || "find"
    result_var = config["resultVar"] || "model"

    case strategy
    when "findBy"
      field = config["findField"] || "id"
      value = config["findValue"] || "ctx[:id]"
      <<~RUBY.chomp
        ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).find_by!(#{field}: #{value})
        true
      RUBY
    when "where"
      field = config["findField"] || "id"
      value = config["findValue"] || "ctx[:id]"
      <<~RUBY.chomp
        ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).where(#{field}: #{value})
        true
      RUBY
    else # "find" or default
      <<~RUBY.chomp
        ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).find(ctx[:id])
        true
      RUBY
    end
  end

  def generate_save_model(step, _ctx)
    config = step["config"] || {}
    strategy = config["saveStrategy"] || "saveAll"

    if strategy == "saveOnly"
      <<~RUBY.chomp
        ctx[:model].save!
        true
      RUBY
    else
      "ActivitySteps::SaveAll.call(ctx)"
    end
  end

  def generate_destroy_model(step, _ctx)
    config = step["config"] || {}
    strategy = config["destroyStrategy"] || "destroy"

    if strategy == "softDelete"
      <<~RUBY.chomp
        ctx[:model].update!(status: :deleted, deleted_at: Time.current)
        true
      RUBY
    else
      <<~RUBY.chomp
        ctx[:model].destroy
        true
      RUBY
    end
  end

  def generate_update_model(step, _ctx)
    config = step["config"] || {}
    mappings = config["fieldMappings"] || []

    if mappings.any?
      assignments = mappings.map { |m| "#{m['key']}: #{m['value']}" }.join(", ")
      <<~RUBY.chomp
        ctx[:model].update!(#{assignments})
        true
      RUBY
    else
      <<~RUBY.chomp
        ctx[:model].update!
        true
      RUBY
    end
  end

  def generate_query_models(step, _ctx)
    config = step["config"] || {}
    query_type = config["queryType"] || "where"
    result_var = config["resultVar"] || "models"

    case query_type
    when "scope"
      scope_name = config["scopeName"] || "all"
      scope_args = config["scopeArgs"]
      args_part = scope_args.present? ? ", #{scope_args}" : ""
      <<~RUBY.chomp
        ctx[:#{result_var}] = EntityEntry.build_for(ctx[:bound_entity]).send(:#{scope_name}#{args_part})
        true
      RUBY
    when "sql"
      sql = config["sqlExpression"] || "SELECT * FROM entries"
      <<~RUBY.chomp
        ctx[:#{result_var}] = ActiveRecord::Base.connection.execute(#{sql.inspect})
        true
      RUBY
    else # "where"
      conditions = config["conditions"] || []
      order_by = config["orderBy"]
      limit = config["limit"]

      query = "EntityEntry.build_for(ctx[:bound_entity])"
      if conditions.any?
        where_clause = conditions.map { |c| "#{c['key']}: #{c['value']}" }.join(", ")
        query += ".where(#{where_clause})"
      end
      query += ".order(\"#{order_by}\")" if order_by.present?
      query += ".limit(#{limit})" if limit.present?

      <<~RUBY.chomp
        ctx[:#{result_var}] = #{query}
        true
      RUBY
    end
  end
end
```

- [ ] **Step 4: Update activity_generator.rb — include ModelSteps, remove moved methods**

Add `include ActivityGenerator::ModelSteps` to the class. Remove `generate_new_model`, `generate_find_model`, `generate_save_model`, `generate_destroy_model` methods from the file. Add `"update_model" => :generate_update_model` and `"query_models" => :generate_query_models` to `STEP_ACTIONS`.

- [ ] **Step 5: Run model steps tests**

```bash
bundle exec rspec spec/services/activity_generator/model_steps_spec.rb --format documentation
```

Expected: All PASS.

- [ ] **Step 6: Run existing tests to verify no regressions**

```bash
bundle exec rspec spec/services/activity_generator_spec.rb spec/services/activity_generator_compound_conditions_spec.rb --format documentation
```

Expected: All PASS (same count as baseline).

- [ ] **Step 7: Write validation_steps_spec.rb**

Test `generate_build_contract` (no config) and `generate_validate_contract` (contract sub-option default, permission/role_check config, permission/policy_check config, backward compat with no config).

- [ ] **Step 8: Create validation_steps.rb and update activity_generator.rb**

Move `generate_build_contract` and `generate_validate_contract` into the module. Add config-aware permission handling per spec. The `generate_validate_contract` must read `subOption` with a backward-compat fallback:

```ruby
sub_option = step.dig("subOption") || step.dig("suboption") || step.dig("selectionLabels", 0)
```

For permission/role_check config, generate: `raise "Unauthorized" unless #{role_expression} == "#{required_role}"`.
For permission/policy_check config, generate: `Pundit.authorize(#{user_expression}, #{record_expression}, :#{policy_action})`.

- [ ] **Step 9: Run all tests**

```bash
bundle exec rspec spec/services/activity_generator/ spec/services/activity_generator_spec.rb spec/services/activity_generator_compound_conditions_spec.rb --format documentation
```

Expected: All PASS.

- [ ] **Step 10: Commit**

```bash
git add app/services/activity_generator/model_steps.rb app/services/activity_generator/validation_steps.rb spec/services/activity_generator/ app/services/activity_generator.rb
git commit -m "feat: add ModelSteps and ValidationSteps generator modules with tests"
```

---

## Task 5: Data + Communication Step Modules (Ruby TDD)

**Files:**
- Create: `app/services/activity_generator/data_steps.rb`
- Create: `app/services/activity_generator/communication_steps.rb`
- Create: `spec/services/activity_generator/data_steps_spec.rb`
- Create: `spec/services/activity_generator/communication_steps_spec.rb`
- Modify: `app/services/activity_generator.rb`

**Reference:** Spec sections "Data Operations" and "Communication" for all config variations.

- [ ] **Step 1: Write data_steps_spec.rb**

Test all 4 actions: `generate_assign_value` (expression, string, integer, boolean value types), `generate_transform` (mapFields, formatDate, convertType, custom), `generate_calculate` (sum, count, avg, custom), `generate_log` (rails_logger, audit_trail). Each with config variations and backward compat (no config).

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/activity_generator/data_steps_spec.rb --format documentation
```

- [ ] **Step 3: Create data_steps.rb**

Implement 4 generators: `generate_assign_value`, `generate_transform`, `generate_calculate`, `generate_log`. Move existing `generate_transform` from `activity_generator.rb` and add config awareness.

- [ ] **Step 4: Write communication_steps_spec.rb**

Test all 4 actions: `generate_api_call` (GET, POST with body, bearer auth, basic auth, apiKey auth, headers), `generate_send_email` (default inline, custom mailer), `generate_send_webhook` (with/without HMAC), `generate_notify` (each channel). Move existing `generate_api_call` and `generate_notify` from `activity_generator.rb`.

- [ ] **Step 5: Create communication_steps.rb**

Implement 4 generators. Use `build_headers_code` from BaseStepHelpers for API_call and send_webhook.

- [ ] **Step 6: Update activity_generator.rb**

Include both modules. Remove moved methods. Add new action entries to STEP_ACTIONS hash: `"assign_value"`, `"calculate"`, `"log"`, `"send_email"`, `"send_webhook"`.

- [ ] **Step 7: Run all tests**

```bash
bundle exec rspec spec/services/activity_generator/ spec/services/activity_generator_spec.rb spec/services/activity_generator_compound_conditions_spec.rb --format documentation
```

Expected: All PASS.

- [ ] **Step 8: Commit**

```bash
git add app/services/activity_generator/data_steps.rb app/services/activity_generator/communication_steps.rb spec/services/activity_generator/data_steps_spec.rb spec/services/activity_generator/communication_steps_spec.rb app/services/activity_generator.rb
git commit -m "feat: add DataSteps and CommunicationSteps generator modules with tests"
```

---

## Task 6: Remaining Step Modules (Ruby TDD)

**Files:**
- Create: `app/services/activity_generator/security_steps.rb`
- Create: `app/services/activity_generator/background_steps.rb`
- Create: `app/services/activity_generator/file_steps.rb`
- Create: `app/services/activity_generator/realtime_steps.rb`
- Create: `app/services/activity_generator/response_steps.rb`
- Create: `spec/services/activity_generator/security_steps_spec.rb`
- Create: `spec/services/activity_generator/background_steps_spec.rb`
- Create: `spec/services/activity_generator/file_steps_spec.rb`
- Create: `spec/services/activity_generator/realtime_steps_spec.rb`
- Create: `spec/services/activity_generator/response_steps_spec.rb`
- Modify: `app/services/activity_generator.rb`

**Reference:** Spec sections "Security", "Background & Scheduling", "File Operations", "Real-time & Events", "Response" for all config variations.

- [ ] **Step 1: Write specs for all 5 modules**

Write test files for: `generate_authorize` (role_check, policy_check, custom), `generate_enqueue_job` and `generate_schedule_job` (duration, atTime), `generate_file_action` (csv, pdf) and `generate_upload_file`, `generate_publish_event` and `generate_broadcast` (turbo_stream, action_cable), `generate_render_response` (json, html, redirect with flash). Each with backward compat test (no config).

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/services/activity_generator/security_steps_spec.rb spec/services/activity_generator/background_steps_spec.rb spec/services/activity_generator/file_steps_spec.rb spec/services/activity_generator/realtime_steps_spec.rb spec/services/activity_generator/response_steps_spec.rb --format documentation
```

- [ ] **Step 3: Implement all 5 modules**

Create each module with config-aware generators. Move existing `generate_render_response` from `activity_generator.rb` into `response_steps.rb` and add config.

- [ ] **Step 4: Update activity_generator.rb**

Include all 5 modules. Remove moved `generate_render_response` method. Add remaining entries to STEP_ACTIONS: `"authorize"`, `"enqueue_job"`, `"schedule_job"`, `"generate_file"`, `"upload_file"`, `"publish_event"`, `"broadcast"`. Verify the complete STEP_ACTIONS hash has all 24 actions + the `validate_contract` alias = 25 entries.

- [ ] **Step 5: Run ALL tests**

```bash
bundle exec rspec spec/services/activity_generator/ spec/services/activity_generator_spec.rb spec/services/activity_generator_compound_conditions_spec.rb --format documentation
```

Expected: All PASS. Every generator module tested.

- [ ] **Step 6: Commit**

```bash
git add app/services/activity_generator/ spec/services/activity_generator/ app/services/activity_generator.rb
git commit -m "feat: add Security, Background, File, Realtime, Response step generator modules with tests"
```

---

## Task 7: Extend Searchable Select Controller

**Files:**
- Modify: `app/javascript/controllers/searchable_select_controller.js`

**Reference:** Spec section "Searchable Category Dropdown UI". The existing controller at `app/javascript/controllers/searchable_select_controller.js` already supports grouped options with collapsible headers, search filtering, and keyboard navigation. We extend it with: SVG icon rendering per option, disabled item support, and description data attribute for tooltips.

- [ ] **Step 1: Add disabled item support**

In the `renderOptions()` method, the existing `group.items.forEach(([displayName, value]) => {` destructuring at line 91 must be changed to support the new 3-element tuple format. Replace the destructuring with explicit indexing to handle both old (2-element) and new (3-element) formats:

Also check for other usages of `searchable_select_controller` in the codebase (run `grep -r "searchable-select" app/views/`) — existing usages pass 2-element arrays and must continue to work.

When creating option elements, check for a `disabled` flag in the item data. If present, add disabled styling and skip click handler:

```javascript
// In renderOptions(), inside group.items.forEach:
const [displayName, value, meta] = Array.isArray(item) && item.length > 2
  ? item
  : [item[0], item[1], {}]

const isDisabled = meta?.disabled === true

// ... existing opt creation ...
if (isDisabled) {
  opt.classList.add("opacity-40", "cursor-not-allowed")
  opt.classList.remove("cursor-pointer", "hover:bg-indigo-50", "hover:text-indigo-700")
  opt.setAttribute("data-disabled", "true")
  // Add "(already used)" text
  const suffix = document.createElement("span")
  suffix.className = "text-xs text-gray-400 ml-1"
  suffix.textContent = "(already used)"
  opt.appendChild(suffix)
} else {
  opt.addEventListener("click", () => this.select(value, displayName, group.group))
}
```

Update `visibleOptions()` to exclude disabled items from keyboard navigation:

```javascript
visibleOptions() {
  return this.optionTargets.filter(o => {
    if (o.classList.contains("hidden")) return false
    if (o.dataset.disabled === "true") return false
    // ... existing checks
  })
}
```

- [ ] **Step 2: Add SVG icon rendering per option**

In `renderOptions()`, when the item metadata includes an `icon` and `color`, render an inline SVG before the label:

```javascript
if (meta?.icon) {
  // IMPORTANT: Use getColorClasses() from templates.js for Tailwind-safe color mapping.
  // NEVER construct dynamic class names like `text-${color}-500` — Tailwind purges them.
  const colorClasses = getColorClasses(meta.color) // returns { icon: "text-amber-600", ... }
  const iconWrap = document.createElement("span")
  iconWrap.className = "inline-flex items-center justify-center w-4 h-4 mr-1.5 flex-shrink-0"
  iconWrap.innerHTML = `<svg class="w-3.5 h-3.5 ${colorClasses.icon}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="${meta.icon}" /></svg>`
  opt.prepend(iconWrap)
  opt.classList.add("flex", "items-center")
}
```

- [ ] **Step 3: Add description tooltip**

If the item metadata includes a `description`, set it as `title` on the option element:

```javascript
if (meta?.description) {
  opt.title = meta.description
}
```

- [ ] **Step 4: Update the data format**

The existing format is `[{ group: "Name", items: [["Display", "value"], ...] }]`. The extended format adds an optional 3rd element to each item tuple: `["Display", "value", { icon, color, description, disabled }]`. This is backward compatible — existing usages with 2-element tuples continue to work.

- [ ] **Step 5: Precompile assets to verify**

```bash
RAILS_ENV=development bundle exec rails assets:precompile 2>&1
```

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/searchable_select_controller.js
git commit -m "feat: extend searchable select with icon rendering, disabled items, and description tooltips"
```

---

## Task 8: Step Config Field Renderers + key_value_list Widget

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_manager.js`
- Modify: `app/javascript/controllers/property_editor/templates.js`

**Reference:** Spec sections "Expanded Step Item Configuration", "Config Field Types", "key_value_list Widget", "Conditional Visibility".

- [ ] **Step 1: Add config field rendering to templates.js**

Add a new exported function `buildStepConfigFieldsHTML(configSchema, currentConfig)` that generates HTML for an array of config field schemas:

```javascript
export function buildStepConfigFieldsHTML(configSchema, currentConfig = {}) {
  if (!configSchema || configSchema.length === 0) return ""

  return configSchema.map(field => {
    const value = currentConfig[field.key] ?? field.default ?? ""
    const visibleClass = shouldFieldBeVisible(field, currentConfig) ? "" : "hidden"
    const requiredMark = field.required ? ' <span class="text-red-500">*</span>' : ""

    let inputHTML = ""
    switch (field.type) {
      case "text":
        inputHTML = buildTextFieldHTML(field, value)
        break
      case "textarea":
        inputHTML = buildTextareaFieldHTML(field, value)
        break
      case "number":
        inputHTML = buildNumberFieldHTML(field, value)
        break
      case "select":
        inputHTML = buildSelectFieldHTML(field, value)
        break
      case "key_value_list":
        inputHTML = buildKeyValueListHTML(field, value)
        break
    }

    return `
      <div class="step-config-field ${visibleClass}" data-config-field="${escapeHtml(field.key)}"
           ${field.visibleWhen ? `data-visible-when='${JSON.stringify(field.visibleWhen)}'` : ""}>
        <label class="block text-[10px] font-medium text-gray-600 mb-0.5">
          ${escapeHtml(field.label)}${requiredMark}
        </label>
        ${inputHTML}
      </div>
    `
  }).join("")
}
```

Implement each field builder (`buildTextFieldHTML`, `buildTextareaFieldHTML`, `buildNumberFieldHTML`, `buildSelectFieldHTML`, `buildKeyValueListHTML`) following existing form patterns in `templates.js`. The `key_value_list` uses `data-kv-row`, `data-kv-key`, `data-kv-value` attributes per spec.

The `key_value_list` +/- buttons use `data-action="click->property-editor#addConfigKvRow"` and `data-action="click->property-editor#removeConfigKvRow"`. These delegate to new methods in StepManager (added in Task 9) that follow the same pattern as existing `addKeywordParam` / `removeKeywordParam` methods. The `data-config-field` attribute on the wrapper identifies which config key the rows belong to.

Add `shouldFieldBeVisible(field, currentConfig)` helper that evaluates `visibleWhen` conditions against current config values (same logic as FormBuilder).

Note: `escapeHtml` is already imported in `templates.js` from `"utils"` and is available for all new functions added to this file.

- [ ] **Step 2: Update buildStepItemTemplate to include config fields section**

In `buildStepItemTemplate`, add a `configFieldsHTML` parameter and inject it into the `[data-step-details]` section, before the existing description display:

```javascript
// In buildStepItemTemplate params:
const { ..., configFieldsHTML = "" } = params

// In the detailsHTML section:
const detailsHTML = `
  <div data-step-details class="hidden mt-2 pt-2 border-t border-gray-200 space-y-2">
    ${configFieldsHTML}
    ${description ? `<div class="mb-1">...</div>` : ""}
    ${keywordParamsHTML}
  </div>
`
```

- [ ] **Step 3: Precompile assets to verify**

```bash
RAILS_ENV=development bundle exec rails assets:precompile 2>&1
```

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/templates.js
git commit -m "feat: add config field renderers with key_value_list widget for step items"
```

---

## Task 9: StepManager Config Integration

**Files:**
- Modify: `app/javascript/controllers/property_editor/step_manager.js`

**Reference:** Spec sections "Expanded Step Item Configuration > Implementation", "subOption Casing", "SINGLE_USE_ACTIONS Migration", "Step Presets".

- [ ] **Step 1: Import registry functions**

At the top of `step_manager.js`, add:

```javascript
import { getActionConfig, getSingleUseActions, getActionsByCategory } from "flowchart/constants/action_registry"
```

- [ ] **Step 2: Replace SINGLE_USE_ACTIONS constant**

Remove the hardcoded `const SINGLE_USE_ACTIONS = [...]` (line 17). Replace all references to `SINGLE_USE_ACTIONS` with calls to `getSingleUseActions()`:

- `getUsedSingleUseActions()`: change `SINGLE_USE_ACTIONS.includes(action)` to `getSingleUseActions().includes(action)`
- `_renderDropdownLevel()`: change `SINGLE_USE_ACTIONS.includes(opt.value)` to `getSingleUseActions().includes(opt.value)`

- [ ] **Step 3: Add buildStepConfigHTML method**

```javascript
buildStepConfigHTML(actionValue, currentConfig = {}, subOption = "") {
  const actionEntry = getActionConfig(actionValue)
  if (!actionEntry) return ""

  let configSchema
  if (actionEntry.configSchemaBySubOption && subOption) {
    configSchema = actionEntry.configSchemaBySubOption[subOption] || []
  } else {
    configSchema = actionEntry.configSchema || []
  }

  if (configSchema.length === 0) return ""

  return buildStepConfigFieldsHTML(configSchema, currentConfig)
}
```

Import `buildStepConfigFieldsHTML` from templates.js.

- [ ] **Step 4: Add collectStepConfig method**

```javascript
collectStepConfig(stepItem) {
  const config = {}
  const configFields = stepItem.querySelectorAll("[data-config-field]")

  configFields.forEach(fieldEl => {
    const key = fieldEl.dataset.configField
    const input = fieldEl.querySelector("input, select, textarea")

    if (fieldEl.querySelector("[data-key-value-list]")) {
      // key_value_list: collect all rows
      const rows = fieldEl.querySelectorAll("[data-kv-row]")
      const pairs = []
      rows.forEach(row => {
        const k = row.querySelector("[data-kv-key]")?.value?.trim()
        const v = row.querySelector("[data-kv-value]")?.value?.trim()
        if (k) pairs.push({ key: k, value: v || "" })
      })
      if (pairs.length > 0) config[key] = pairs
    } else if (input) {
      const value = input.value?.trim()
      if (value !== "" && value !== undefined) {
        config[key] = input.type === "number" ? Number(value) : value
      }
    }
  })

  return config
}
```

- [ ] **Step 5: Update collectSteps to include config**

In the `collectSteps()` method, after building `stepData`, add:

```javascript
const config = this.collectStepConfig(item)
if (Object.keys(config).length > 0) {
  stepData.config = config
}
```

- [ ] **Step 6: Update addStepFromModal to include default config**

In `addStepFromModal()`, after building the step data, compute default config from configSchema:

```javascript
const actionEntry = getActionConfig(action)
const defaultConfig = {}
const schema = actionEntry?.configSchemaBySubOption?.[suboption] || actionEntry?.configSchema || []
schema.forEach(field => {
  if (field.default !== undefined) defaultConfig[field.key] = field.default
})
```

Pass `defaultConfig` to `buildStepItemHTML` and store in hidden input.

- [ ] **Step 7: Update buildStepItemHTML to generate config fields**

In `buildStepItemHTML`, call `buildStepConfigHTML(action, config, suboption)` and pass the result as `configFieldsHTML` to `buildStepItemTemplate`.

- [ ] **Step 8: Fix subOption casing**

Replace all occurrences of `suboption` (lowercase) with `subOption` (camelCase) in:
- Hidden input names: `steps[${index}][suboption]` → `steps[${index}][subOption]`
- Data collection in `collectSteps()`
- `addStepFromModal()`

- [ ] **Step 9: Update STEP_PRESETS with config defaults**

```javascript
const STEP_PRESETS = {
  crud_create: {
    label: "CRUD Create",
    steps: [
      { action: "new_model", selectionLabels: ["New Model"], config: {} },
      { action: "build_contract", selectionLabels: ["Build Contract"], config: {} },
      { action: "validate", selectionLabels: ["Validate"], config: {} },
      { action: "save_model", selectionLabels: ["Save Model"], config: { saveStrategy: "saveAll" } }
    ]
  },
  crud_read: {
    label: "CRUD Read",
    steps: [
      { action: "find_model", selectionLabels: ["Find Model"], config: { findStrategy: "find" } }
    ]
  },
  crud_update: {
    label: "CRUD Update",
    steps: [
      { action: "find_model", selectionLabels: ["Find Model"], config: { findStrategy: "find" } },
      { action: "build_contract", selectionLabels: ["Build Contract"], config: {} },
      { action: "validate", selectionLabels: ["Validate"], config: {} },
      { action: "save_model", selectionLabels: ["Save Model"], config: { saveStrategy: "saveAll" } }
    ]
  },
  crud_delete: {
    label: "CRUD Delete",
    steps: [
      { action: "find_model", selectionLabels: ["Find Model"], config: { findStrategy: "find" } },
      { action: "destroy_model", selectionLabels: ["Destroy Model"], config: { destroyStrategy: "destroy" } }
    ]
  }
}
```

- [ ] **Step 10: Add config field visibility toggling**

Add an event listener method for config field changes that evaluates `visibleWhen` conditions on dependent fields:

```javascript
handleConfigFieldChange(event) {
  const stepItem = event.target.closest("[data-step-item]")
  if (!stepItem) return

  const configFields = stepItem.querySelectorAll("[data-config-field]")
  const currentConfig = this.collectStepConfig(stepItem)

  configFields.forEach(fieldEl => {
    const visibleWhenStr = fieldEl.dataset.visibleWhen
    if (!visibleWhenStr) return

    const vw = JSON.parse(visibleWhenStr)
    const fieldValue = currentConfig[vw.field]
    const matchValues = vw.values || [vw.value]
    const isVisible = matchValues.includes(fieldValue)
    fieldEl.classList.toggle("hidden", !isVisible)
  })

  this._dispatchEvent("stepChanged")
}
```

Wire this to config inputs via data-action attributes in the config field templates.

- [ ] **Step 11: Wire searchable dropdown for level 0**

Update `_renderDropdownLevel()` to use `getActionsByCategory()` data with the searchable select controller for level 0. Transform registry data into the searchable select format:

```javascript
if (level === 0) {
  const grouped = getActionsByCategory()
  const usedSingleUse = this.getUsedSingleUseActions()

  const optionsData = grouped.map(g => ({
    group: g.category.label,
    items: g.actions.map(a => [
      a.label,
      a.value,
      {
        icon: a.icon,
        color: a.color,
        description: a.description,
        disabled: getSingleUseActions().includes(a.value) && usedSingleUse.includes(a.value)
      }
    ])
  }))

  // Render searchable select HTML instead of plain <select>
  // Use searchable-select controller with optionsData
}
```

- [ ] **Step 12: Precompile assets and manually test**

```bash
RAILS_ENV=development bundle exec rails assets:precompile 2>&1
```

Restart the server and test on the flowchart edit page:
1. Click a process element → "Add Step" → verify searchable dropdown with categories
2. Select an action with config (e.g., API Call) → verify step is added
3. Expand the step → verify config fields appear
4. Configure fields → verify visibility toggling
5. Save → verify config persisted in flowchart configuration JSON

- [ ] **Step 13: Commit**

```bash
git add app/javascript/controllers/property_editor/step_manager.js
git commit -m "feat: integrate action registry, config rendering, searchable dropdown into StepManager"
```

---

## Task 10: End-to-End Verification

**Files:**
- Test: `spec/services/activity_generator_spec.rb` (existing, verify still passes)
- Modify: none (verification only)

- [ ] **Step 1: Add integration test for config-aware generation**

Add a test to `spec/services/activity_generator_spec.rb` that creates a flowchart with a process element containing a step with a `config` hash, generates the activity code, and verifies the output includes config-parameterized values:

```ruby
context 'with configured step actions' do
  let(:configured_flowchart) do
    create(:flowchart, entity: entity, configuration: {
      'elements' => [
        { 'id' => 'start', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
        { 'id' => 'proc', 'type' => 'process', 'label' => 'Make API Call', 'properties' => {
          'steps' => [{ 'action' => 'API_call', 'config' => {
            'httpMethod' => 'POST', 'url' => '"https://api.example.com"',
            'authType' => 'bearer', 'authToken' => 'ctx[:token]',
            'responseVar' => 'result'
          }}]
        }},
        { 'id' => 'end', 'type' => 'end', 'label' => 'End', 'properties' => {} }
      ],
      'connections' => [
        { 'id' => 'c1', 'from' => 'start', 'to' => 'proc' },
        { 'id' => 'c2', 'from' => 'proc', 'to' => 'end' }
      ]
    }.to_json)
  end

  it 'generates config-parameterized code' do
    code = described_class.new(configured_flowchart).generate
    expect(code).to include('Net::HTTP')
    expect(code).to include('ctx[:result]')
    expect(code).to include('Bearer')
  end
end
```

- [ ] **Step 2: Run the full Ruby test suite**

```bash
bundle exec rspec spec/services/activity_generator/ spec/services/activity_generator_spec.rb spec/services/activity_generator_compound_conditions_spec.rb --format documentation
```

Expected: All PASS. All new module tests + all existing tests.

- [ ] **Step 2: Precompile assets**

```bash
RAILS_ENV=development bundle exec rails assets:precompile 2>&1
```

Expected: No errors.

- [ ] **Step 3: Restart server and end-to-end manual test**

```bash
# Kill existing server and restart
kill $(lsof -ti:3000) 2>/dev/null; bundle exec rails server -b 0.0.0.0 -p 3000 &
```

Test the complete flow on `/96546124/flowcharts/48/edit`:
1. Click process element → open property editor
2. Click "Add Step" → searchable dropdown opens with 9 categories and 24 actions
3. Search for "email" → filters to "Send Email" in Communication category
4. Select "API Call" → step added to process
5. Expand step → config fields appear (HTTP Method, URL, Headers, Auth, etc.)
6. Change HTTP Method to POST → Body Template field appears
7. Change Auth to Bearer → Token field appears
8. Fill in fields → save flowchart
9. Check generated activity code contains parameterized `Net::HTTP` code
10. Open an existing flowchart with old steps → verify backward compatibility

- [ ] **Step 4: Run full application test suite**

```bash
bundle exec rspec --format documentation
```

Expected: All PASS.

- [ ] **Step 6: Final commit**

```bash
git add spec/services/activity_generator_spec.rb
git commit -m "feat: complete enriched process step actions — 24 actions, per-action config, searchable dropdown, modular generator"
```
