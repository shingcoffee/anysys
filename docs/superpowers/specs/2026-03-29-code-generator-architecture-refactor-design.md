# Code Generator Architecture Refactor

**Date:** 2026-03-29
**Status:** Approved
**Scope:** Refactor Trailblazer activity code generation into a modular, self-documenting, file-per-generator architecture with admin CRUD UI

---

## 1. Overview

Refactor the current Trailblazer activity code generation system from a monolithic `ActivityGenerator` (780 lines) with 10 category-grouped modules into a modular architecture where each flowchart element type and each process step action has its own self-contained, self-documenting generator class file. Add an admin CRUD UI for managing these generator files from the browser.

### Goals

- One Ruby file per step action (24 generators) and per element type (7 generators)
- Common interface across all generators with declared input/output schemas
- Fully self-documenting generators (description, category, version, example_output, validate_config, dependencies)
- Convention-based auto-discovery from known directories
- Admin-only CRUD UI for viewing, creating, editing, and deleting generator files
- Syntax + interface validation on save
- Thinner `ActivityGenerator` orchestrator that delegates to individual generators
- Big bang migration — replace old architecture completely

### Non-Goals

- Tenant-scoped custom generators (admin-only for now)
- File versioning/history (write with validation only)
- Backward compatibility with old module-based structure

---

## 2. Architecture

### 2.1 Directory Structure

```
app/services/code_generators/
├── generator_interface.rb          # Module enforcing required methods
├── generator_registry.rb           # Auto-discovery & indexing
├── generator_validator.rb          # Syntax + interface validation for CRUD UI
├── base_generator.rb               # Thin base class (config extraction, wrapping)
│
├── shared/                         # Composable helper modules
│   ├── condition_builder.rb        # Structured condition → Ruby code
│   ├── http_request_builder.rb     # Shared Net::HTTP boilerplate
│   └── operand_converter.rb        # "ctx.user.email" → ctx.dig(:user, :email)
│
├── element_types/                  # One file per flowchart element type
│   ├── start_generator.rb          # Metadata only — start elements are skipped in DFS, generate returns nil
│   ├── end_generator.rb
│   ├── decision_generator.rb
│   ├── loop_generator.rb
│   ├── timer_generator.rb
│   ├── error_handler_generator.rb
│   └── subflow_generator.rb
│
└── step_actions/                   # One file per process step action
    ├── new_model_generator.rb
    ├── find_model_generator.rb
    ├── save_model_generator.rb
    ├── destroy_model_generator.rb
    ├── update_model_generator.rb
    ├── query_models_generator.rb
    ├── build_contract_generator.rb
    ├── validate_contract_generator.rb
    ├── assign_value_generator.rb
    ├── transform_generator.rb
    ├── calculate_generator.rb
    ├── log_generator.rb
    ├── api_call_generator.rb
    ├── send_email_generator.rb
    ├── send_webhook_generator.rb
    ├── notify_generator.rb
    ├── authorize_generator.rb
    ├── enqueue_job_generator.rb
    ├── schedule_job_generator.rb
    ├── generate_file_generator.rb
    ├── upload_file_generator.rb
    ├── publish_event_generator.rb
    ├── broadcast_generator.rb
    └── render_response_generator.rb
```

Admin CRUD UI:

```
app/controllers/admin/code_generators_controller.rb
app/components/admin/code_generators/
├── index_component.rb / index_component.html.erb
├── show_component.rb / show_component.html.erb
├── form_component.rb / form_component.html.erb
└── sidebar_component.rb / sidebar_component.html.erb
```

### 2.2 Component Diagram

```
┌─────────────────────────────────────────────────────┐
│                  ActivityGenerator                    │
│              (thin orchestrator ~200 LOC)             │
│  - DFS traversal, graph building                     │
│  - Class definition assembly, header generation      │
│  - Delegates code generation to registry             │
└──────────────┬──────────────────────┬────────────────┘
               │                      │
               ▼                      ▼
┌──────────────────────┐  ┌──────────────────────────┐
│  GeneratorRegistry   │  │  DynamicClassLoader      │
│  - Auto-discovers    │  │  (unchanged)             │
│  - find_step_action  │  └──────────────────────────┘
│  - find_element_type │
│  - reload!           │
└──────────┬───────────┘
           │ discovers
           ▼
┌──────────────────────────────────────────────────────┐
│              Individual Generators                    │
│                                                      │
│  ┌─────────────────┐    ┌──────────────────────────┐ │
│  │ BaseGenerator    │    │ GeneratorInterface       │ │
│  │ - extract_config │    │ - generator_metadata DSL │ │
│  │ - apply_wrappers │    │ - input/output_schema    │ │
│  │ - wrap_with_*    │    │ - enforces #generate     │ │
│  └────────┬────────┘    │ - enforces #validate_cfg │ │
│           │ inherits     └────────────┬─────────────┘ │
│           ▼                  includes │               │
│  ┌─────────────────────────────────────┐              │
│  │ StepActions::NewModelGenerator      │              │
│  │ StepActions::ApiCallGenerator       │              │
│  │ ElementTypes::DecisionGenerator     │              │
│  │ ... (31 total)                      │              │
│  └─────────────┬───────────────────────┘              │
│                │ opt-in includes                      │
│                ▼                                      │
│  ┌───────────────────────────────────┐                │
│  │ Shared::ConditionBuilder          │                │
│  │ Shared::HttpRequestBuilder        │                │
│  │ Shared::OperandConverter          │                │
│  └───────────────────────────────────┘                │
└──────────────────────────────────────────────────────┘
```

---

## 3. Core Interfaces

### 3.1 GeneratorInterface

A module included by all generators that enforces the required contract.

**Required methods (raise InterfaceError if not implemented):**
- `generate` → `String | nil` — the generated Ruby code (uses instance vars `element`, `context`, `config` from constructor)
- `validate_config(config)` → `Array<String>` — list of validation errors (empty = valid)

**Optional methods with defaults:**
- `example_output` → `String | nil` — sample generated code for preview
- `dependencies` → `Array<Symbol>` — other generators this one is typically used with

**Class-level DSL:**
- `generator_metadata { description "..."; category :symbol; version "x.y.z" }` — self-documenting metadata
- `input_schema :key1, :key2` — ctx keys the generated code reads
- `output_schema :key1, :key2` — ctx keys the generated code writes
- `generator_name` — derived from class name (`NewModelGenerator` → `"new_model"`)
- `generator_kind` — `:element_type` or `:step_action` based on namespace
- `dry_run(sample_config = {})` — instantiate with mock element, return code + metadata hash

**Note on method signatures:** The constructor `initialize(element, context)` stores element, context, and extracts config as instance variables. The `generate` method takes no arguments — it uses these instance vars directly. This avoids the redundancy of passing element/context in both constructor and method call. The orchestrator pattern is:
```ruby
generator = generator_class.new(element, ctx)
code = generator.generate
```

### 3.2 MetadataDSL

Lightweight DSL class used inside `generator_metadata` blocks.

**Fields:** `description` (String), `category` (Symbol), `version` (String matching `\d+\.\d+\.\d+`)

### 3.3 BaseGenerator

Thin base class that all generators inherit from.

**Constructor:** `initialize(element, context)` — stores element, context, extracts config
- Element types: config from `element["properties"]`
- Step actions: config from `element["config"]`
- Config wrapped with `with_indifferent_access` for flexible key access

**Protected methods:**
- `apply_wrappers(code)` — wrapping pipeline: guard → retry → timeout → code
- `wrap_with_timeout(code)` — Timeout.timeout block if timeout > 0
- `wrap_with_retry(code)` — begin/rescue with configurable backoff
- `wrap_with_guard(code)` — conditional execution if guardCondition present

---

## 4. Shared Helper Modules

### 4.1 OperandConverter

Converts operand expressions to Ruby code.

| Input | Output |
|-------|--------|
| `"ctx.user.email"` | `ctx.dig(:user, :email)` |
| `"signal"` | `ctx[:signal]` |
| `"42"` | `42` |
| `"hello"` | `"hello"` |
| `nil` / blank | `"nil"` |

**Used by:** most generators, ConditionBuilder

### 4.2 ConditionBuilder

Converts structured condition objects to Ruby boolean expressions. Handles single conditions, grouped conditions (AND/OR), and all operator types (==, !=, >, contains, is_empty, matches_regex, etc.).

**Used by:** DecisionGenerator, LoopGenerator, TimerGenerator

### 4.3 HttpRequestBuilder

Builds Net::HTTP request code blocks. Eliminates duplication between API call and webhook generators.

**Interface:** `build_http_request(method:, url_expr:, response_var:, headers:, auth_type:, auth_config:, body_expr:)`

**Handles:** GET vs mutating requests, SSL, auth (bearer/basic/apiKey), custom headers, JSON response parsing

**Used by:** ApiCallGenerator, SendWebhookGenerator

### 4.4 Composition Matrix

| Generator | OperandConverter | ConditionBuilder | HttpRequestBuilder |
|-----------|:---:|:---:|:---:|
| DecisionGenerator | via ConditionBuilder | Y | |
| LoopGenerator | via ConditionBuilder | Y | |
| TimerGenerator | Y | | |
| EndGenerator | Y | | |
| ApiCallGenerator | | | Y |
| SendWebhookGenerator | | | Y |
| FindModelGenerator | Y | | |
| AssignValueGenerator | Y | | |
| CalculateGenerator | Y | | |
| Most others | | | |

---

## 5. Generator Registry

### 5.1 Auto-Discovery

`GeneratorRegistry` scans two directories on initialization:
- `app/services/code_generators/step_actions/*.rb`
- `app/services/code_generators/element_types/*.rb`

For each file:
1. Derive class name from file path convention (e.g., `step_actions/new_model_generator.rb` → `CodeGenerators::StepActions::NewModelGenerator`)
2. Constantize the class
3. Verify it includes `GeneratorInterface`
4. Register under `generator_name` (e.g., `"new_model"`)

### 5.2 Lookup API

- `find_step_action(action_name)` → generator class or nil
- `find_element_type(type_name)` → generator class or nil
- `all_generators` → merged hash of all registered generators
- `step_action_generators` → hash of step action generators only
- `element_type_generators` → hash of element type generators only
- `reload!` → clear caches, re-scan directories (called after CRUD operations)

### 5.3 Singleton Access

`GeneratorRegistry.instance` returns a memoized singleton. Class-level delegates provide convenient access: `GeneratorRegistry.find_step_action("new_model")`.

---

## 6. Refactored ActivityGenerator

The `ActivityGenerator` drops from ~780 lines to ~200 lines. It retains:

- **Initialization:** flowchart, elements, connections, bound_entity, class_loader, registry
- **Validation:** `validate_structure` (start/end element checks, connectivity)
- **Graph building:** `build_graph`, `start_node_id`
- **DFS traversal:** `dfs_collect_steps`, `dfs_visit`, `detect_subprocess`
- **Name derivation:** `derive_method_name`, `extract_base_name`, `normalize_method_name`, `ensure_unique_name`, `derive_activity_class_name`
- **Class assembly:** `class_definition_with_steps`, `step_declarations`, `derive_step_type`, `build_subprocess_declaration`, `step_methods`, `build_method`
- **Header generation:** `header`, `build_trigger_info`, `build_bound_entity_header`, `build_shared_header`

Key changes:
- **`STEP_ACTIONS` hash eliminated** — replaced by `@registry.find_step_action(action)`
- **All 10 `include` statements removed**
- **`method_body` delegates to element type generators** via registry lookup
- **`generate_step_code` delegates to step action generators** via registry lookup, then calls `apply_wrappers`
- **All element-type-specific methods removed** from this file (loop, decision, timer, error_handler, end, condition building)

---

## 7. Admin CRUD UI

### 7.1 Routes

```ruby
namespace :admin do
  resources :code_generators, only: [:index, :show, :new, :create, :edit, :update, :destroy], param: :path do
    member do
      post :validate   # AJAX syntax + interface validation
      get :preview     # Render example_output
    end
  end
end
```

### 7.2 Controller

`Admin::CodeGeneratorsController < AdminController`

- **index:** Lists all generators grouped by kind (element types / step actions), using registry
- **show:** Reads file from filesystem, displays source + metadata from loaded class
- **new:** Renders editor with template skeleton for chosen kind
- **create:** Validates source → writes file → reloads autoloader + registry → redirects
- **edit:** Reads file, renders editor
- **update:** Validates source → overwrites file → reloads autoloader + registry → redirects
- **destroy:** Deletes file → reloads autoloader + registry → redirects
- **validate:** AJAX endpoint — returns `{ valid: bool, errors: [] }` as JSON
- **preview:** Returns `{ example_output: "..." }` from generator's `example_output` method

File identification uses URL-encoded relative path as `param: :path`, e.g., `/admin/code_generators/step_actions%2Fnew_model_generator`.

### 7.3 GeneratorValidator

Validates source code before saving. Three-phase check:

1. **Syntax check:** `RubyVM::InstructionSequence.compile(source)` — catches SyntaxError
2. **Interface check:** Regex-based verification that class inherits from `BaseGenerator` and defines `generate` and `validate_config` methods
3. **Metadata check:** Verifies `generator_metadata` block is present with `description`, `category`, and `version`

Returns early after syntax errors (can't check interface if syntax is broken).

### 7.4 ViewComponents

All components use TailwindCSS only, Stimulus for interactivity.

**IndexComponent:**
- Two-column layout: sidebar tree + generator card grid
- Sidebar groups generators by kind → category with counts
- Cards show name, description, category badge, version
- "New Generator" button with dropdown (step_action / element_type)

**ShowComponent:**
- Header with name, category badge, version, description
- Input/output schema displayed as tag lists
- Dependencies shown as linked tags
- Read-only source code display with line numbers in `<pre>` block
- Example output in separate code block
- Edit / Delete action buttons

**FormComponent:**
- File name input (create only)
- Kind selector (create only: step_action / element_type)
- Monospace `<textarea>` for source code with line numbers via Stimulus controller
- "Validate" button triggers AJAX POST to validate endpoint, shows errors inline
- Save button submits form

**SidebarComponent:**
- Tree navigation grouped by kind → category
- Highlights current generator
- Count badges per category

---

## 8. Migration Strategy

Big bang replacement — all changes in one pass.

### Step 1: Build new infrastructure (no old code touched)

- `CodeGenerators::GeneratorInterface` + `MetadataDSL`
- `CodeGenerators::BaseGenerator`
- `CodeGenerators::Shared::OperandConverter`
- `CodeGenerators::Shared::ConditionBuilder`
- `CodeGenerators::Shared::HttpRequestBuilder`
- `CodeGenerators::GeneratorRegistry`
- `CodeGenerators::GeneratorValidator`

### Step 2: Create all individual generator files

- 7 element type generators: start (metadata-only, `generate` returns nil since start is skipped in DFS), end, decision, loop, timer, error_handler, subflow
- 24 step action generators: direct port of logic from current category modules
- Each file is self-contained with full metadata, input/output schemas, validate_config, example_output

### Step 3: Refactor ActivityGenerator to delegate

- Remove all 10 `include` statements
- Remove `STEP_ACTIONS` hash
- Replace `method_body` to use `@registry.find_element_type(type)`
- Replace `generate_step_code` to use `@registry.find_step_action(action)`
- Remove all element-type-specific methods (loop, decision, timer, error_handler, end, condition building)
- Delete old module files: `app/services/activity_generator/*.rb`

### Step 4: Build admin CRUD UI

- Routes, controller, ViewComponents
- Stimulus controllers for editor interactivity

### Step 5: Verification

- All existing RSpec tests pass unchanged
- Generated code for any flowchart is byte-identical before and after

---

## 9. Testing Strategy

### Layer 1: Interface contract tests

Shared example group `"a code generator"` that every generator spec includes. Verifies:
- Responds to `generate`, `validate_config`, `example_output`, `dependencies`
- Metadata has description, category (Symbol), version (semver format)
- Input/output schemas are Arrays
- `generate` returns String or nil
- `validate_config` returns Array

### Layer 2: Individual generator specs

One spec file per generator in `spec/services/code_generators/` mirroring the source structure. Tests migrated from current `spec/services/activity_generator/*.rb` files (model_steps_spec.rb → individual generator specs). Each includes the shared example group.

### Layer 3: Shared module specs

- `spec/services/code_generators/shared/operand_converter_spec.rb`
- `spec/services/code_generators/shared/condition_builder_spec.rb`
- `spec/services/code_generators/shared/http_request_builder_spec.rb`

### Layer 4: Infrastructure specs

- `spec/services/code_generators/base_generator_spec.rb` — config extraction, wrapping
- `spec/services/code_generators/generator_registry_spec.rb` — discovery, lookup, reload
- `spec/services/code_generators/generator_validator_spec.rb` — syntax, interface, metadata checks

### Layer 5: Integration tests

Existing `activity_generator_spec.rb` and `activity_generator_compound_conditions_spec.rb` remain unchanged — they test the full pipeline and must pass without modification.

### Layer 6: Admin CRUD specs

- Controller specs for all 7 actions + validate + preview
- ViewComponent specs for index, show, form, sidebar components

### Verification script

```ruby
Flowchart.find_each do |fc|
  old_output = fc.activity
  new_output = ActivityGenerator.new(fc).generate
  puts "MISMATCH: Flowchart ##{fc.id}" if old_output != new_output
end
```

---

## 10. Professional Improvements

### 10.1 Indifferent access config

`BaseGenerator#extract_config` wraps config with `with_indifferent_access`, allowing generators to use either string or symbol keys. Eliminates key-type mismatch bugs.

### 10.2 Dry-run / preview per generator

Class-level `dry_run(sample_config)` method on `GeneratorInterface` instantiates a generator with mock data and returns `{ code:, input_keys:, output_keys:, example: }`. Used by CRUD UI preview panel and for debugging.

### 10.3 Ctx key tracking

`ActivityGenerator#ctx_summary(steps)` collects all `input_schema` and `output_schema` keys across steps. Included as comments in generated activity headers. Enables the flowchart UI to show data flow between steps.

### 10.4 Design-time config validation

New API endpoint `POST /flowcharts/:id/validate_step` calls `generator.validate_config(config)` for real-time validation feedback in the flowchart editor. Catches configuration errors at design time rather than code generation time.

### 10.5 Eliminate blank-line filtering

Current `code.lines.reject { |l| l.strip.empty? }.join` pattern in communication generators is eliminated by `HttpRequestBuilder` conditionally including sections rather than post-processing blank lines.

---

## 11. File Inventory

### New files (39 total)

**Infrastructure (7):**
- `app/services/code_generators/generator_interface.rb`
- `app/services/code_generators/base_generator.rb`
- `app/services/code_generators/generator_registry.rb`
- `app/services/code_generators/generator_validator.rb`
- `app/services/code_generators/shared/operand_converter.rb`
- `app/services/code_generators/shared/condition_builder.rb`
- `app/services/code_generators/shared/http_request_builder.rb`

**Element type generators (7):**
- `app/services/code_generators/element_types/start_generator.rb`
- `app/services/code_generators/element_types/end_generator.rb`
- `app/services/code_generators/element_types/decision_generator.rb`
- `app/services/code_generators/element_types/loop_generator.rb`
- `app/services/code_generators/element_types/timer_generator.rb`
- `app/services/code_generators/element_types/error_handler_generator.rb`
- `app/services/code_generators/element_types/subflow_generator.rb`

**Step action generators (24):**
- `app/services/code_generators/step_actions/new_model_generator.rb`
- `app/services/code_generators/step_actions/find_model_generator.rb`
- `app/services/code_generators/step_actions/save_model_generator.rb`
- `app/services/code_generators/step_actions/destroy_model_generator.rb`
- `app/services/code_generators/step_actions/update_model_generator.rb`
- `app/services/code_generators/step_actions/query_models_generator.rb`
- `app/services/code_generators/step_actions/build_contract_generator.rb`
- `app/services/code_generators/step_actions/validate_contract_generator.rb`
- `app/services/code_generators/step_actions/assign_value_generator.rb`
- `app/services/code_generators/step_actions/transform_generator.rb`
- `app/services/code_generators/step_actions/calculate_generator.rb`
- `app/services/code_generators/step_actions/log_generator.rb`
- `app/services/code_generators/step_actions/api_call_generator.rb`
- `app/services/code_generators/step_actions/send_email_generator.rb`
- `app/services/code_generators/step_actions/send_webhook_generator.rb`
- `app/services/code_generators/step_actions/notify_generator.rb`
- `app/services/code_generators/step_actions/authorize_generator.rb`
- `app/services/code_generators/step_actions/enqueue_job_generator.rb`
- `app/services/code_generators/step_actions/schedule_job_generator.rb`
- `app/services/code_generators/step_actions/generate_file_generator.rb`
- `app/services/code_generators/step_actions/upload_file_generator.rb`
- `app/services/code_generators/step_actions/publish_event_generator.rb`
- `app/services/code_generators/step_actions/broadcast_generator.rb`
- `app/services/code_generators/step_actions/render_response_generator.rb`

**Admin CRUD (1 controller + 4 components = 5):**
- `app/controllers/admin/code_generators_controller.rb`
- `app/components/admin/code_generators/index_component.rb` + `.html.erb`
- `app/components/admin/code_generators/show_component.rb` + `.html.erb`
- `app/components/admin/code_generators/form_component.rb` + `.html.erb`
- `app/components/admin/code_generators/sidebar_component.rb` + `.html.erb`

### Modified files

- `app/services/activity_generator.rb` — refactored from ~780 to ~200 lines
- `config/routes.rb` — add admin code_generators routes

### Deleted files (11)

- `app/services/activity_generator/base_step_helpers.rb`
- `app/services/activity_generator/model_steps.rb`
- `app/services/activity_generator/validation_steps.rb`
- `app/services/activity_generator/data_steps.rb`
- `app/services/activity_generator/communication_steps.rb`
- `app/services/activity_generator/security_steps.rb`
- `app/services/activity_generator/background_steps.rb`
- `app/services/activity_generator/file_steps.rb`
- `app/services/activity_generator/realtime_steps.rb`
- `app/services/activity_generator/response_steps.rb`
- `app/services/activity_generator/` directory itself
