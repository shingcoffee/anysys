# Code Generator Infrastructure Refactoring

**Date:** 2026-04-09
**Status:** Approved
**Scope:** All code generator infrastructure, all 125 generators, ViewComponents, controller, Stimulus, specs

## Summary

Re-implement the code generator infrastructure with clean separation of concerns. Extract I/O introspection into a standalone `CodeIntrospector` service, extract test execution into a `TestRunner` service, purge all deprecated stubs (`example_output`, `input_schema`, `output_schema`), add `sample_input` to every generator, implement smart auto-versioning (only bump when `generate_body` output changes), and restyle all pages with a developer-focused dark aesthetic.

## Architecture

### File Map

| File | Responsibility |
|------|---------------|
| `generator_interface.rb` | Thin concern: metadata DSL hookup, `generator_name`, `generator_kind`, `registered_names`, `sample_input` (default `{}`) |
| `base_generator.rb` | Instance behavior: `initialize(element, context)`, `generate_body`, `generate_step_method`, `validate_config`, `dependencies`, wrappers (timeout/retry/guard) |
| `metadata_dsl.rb` | DSL: `description`, `category`, `version`, `bump_patch` — unchanged |
| `code_introspector.rb` | **New.** `self.analyze(code_string)` -> `{ inputs: [], outputs: [] }` |
| `test_runner.rb` | **New.** `self.run(generator_class, config: {})` -> `{ code:, body:, inputs:, outputs:, validation_errors: }` |
| `source_assembler.rb` | Assembles new generator source. Adds `sample_input` stub. |
| `generator_validator.rb` | Validates source syntax, interface, metadata. Remove deprecated method checks. |
| `generator_registry.rb` | Unchanged. |

### What Gets Removed

- `GeneratorInterface`: `input_schema`, `output_schema` class methods; `_input_keys`, `_output_keys` class attributes; `example_output` instance method; `generate` alias method; `derived_io` class method; `dry_run` class method
- All 125 generators: any remaining `example_output`, `input_schema`, `output_schema` method definitions
- `SourceAssembler`: any references to `input_schema`/`output_schema`

## CodeIntrospector

**Location:** `app/services/code_generators/code_introspector.rb`

**Interface:**
```ruby
CodeGenerators::CodeIntrospector.analyze(code_string)
# => { inputs: ["model", "params"], outputs: ["result", "errors"] }
```

**Detection patterns:**

| Pattern | Example | Detected as |
|---------|---------|-------------|
| `ctx[:key] =` | `ctx[:result] = User.find(1)` | output: `result` |
| `ctx[:key]` (read) | `name = ctx[:user_name]` | input: `user_name` |
| `ctx.dig(:key, ...)` | `ctx.dig(:config, :timeout)` | input: `config` (top-level key only) |
| `ctx.fetch(:key)` | `ctx.fetch(:model)` | input: `model` |
| `ctx.fetch(:key, default)` | `ctx.fetch(:retries, 3)` | input: `retries` |

**Exclusion rules:**
- Keys starting with `_` are excluded (private/internal convention)
- Keys inside string literals are excluded — two-pass approach: strip string literals first, then scan
- A key that appears as both read and write is listed in **both** inputs and outputs

## TestRunner

**Location:** `app/services/code_generators/test_runner.rb`

**Interface:**
```ruby
CodeGenerators::TestRunner.run(generator_class, config: {})
# => {
#   body: "ctx[:model] = User.find(ctx[:id])\ntrue",
#   code: "def find_model(ctx, **)\n  ...\nend",
#   inputs: ["id"],
#   outputs: ["model"],
#   validation_errors: []
# }
```

**Internals:**
1. Build element hash: `{ "config" => config, "properties" => config, "label" => "test_step" }`
2. Instantiate: `generator_class.new(element, {})`
3. Call `generate_body` and `generate_step_method`
4. Pass body to `CodeIntrospector.analyze(body)` for I/O
5. Call `validate_config(config)` for validation errors
6. Return combined result hash

**Usage points:**
- Controller `#test_run` action
- ShowComponent default preview
- RSpec shared example integration test

## Auto-Versioning

**Trigger:** Only when `generate_body` output changes between old and new version.

**Mechanism in controller `#update`:**
1. Capture old body: `old_body = @registry_entry.new(test_element, {}).generate_body`
2. Write new source, reload autoloader and registry
3. Capture new body: `new_body = new_class.new(test_element, {}).generate_body`
4. If `old_body != new_body`, bump patch version via `MetadataDSL.bump_patch` and rewrite source
5. If identical, leave version unchanged

**Test element source:** Uses generator's `sample_input` to build element hash.

**New generators:** `#create` always uses form version (default `"1.0.0"`). No bumping on create.

## Sample Input

Each generator defines `self.sample_input` returning a config hash:

```ruby
def self.sample_input
  { "findStrategy" => "find_by_id", "modelName" => "User", "targetVar" => "model" }
end
```

**Default:** `GeneratorInterface` provides `def self.sample_input = {}`.

**Where used:**
- Show page: pre-populates test runner JSON textarea
- TestRunner: default preview on show page uses `klass.sample_input`
- RSpec shared example: verifies `sample_input` returns Hash

**SourceAssembler:** New generators include a `self.sample_input` stub returning `{}`.

**All 125 generators** get a `self.sample_input` added with realistic config that exercises main code paths.

## UI Redesign (Developer-Focused)

### Index Page

**Two-panel layout:** dark sidebar tree nav + right content area.

**Tree view (left sidebar):**
- Dark sidebar: `bg-gray-900`, monospace font for generator names
- Collapsible nodes: Element Types top-level, Process with subcategories nested
- Generator names in `font-mono text-sm` using snake_case (`find_model`, not "Find Model")
- Active item: `border-l-2 border-cyan-400`
- Search input: `bg-gray-800` dark styling

**Right panel (card grid):**
- Dark cards: `bg-gray-800 border-gray-700`, monospace generator name
- Version in `text-gray-500`
- I/O counts as `2 in -> 1 out` monospace
- Description in `text-gray-400`
- Hover: `hover:border-cyan-500/50`

### Show Page

**Header:** Compact — mono generator name, category/version/kind as small inline pills, edit/delete right-aligned.

**Three stacked sections:**

1. **I/O Panel** — side-by-side dark cards:
   - Left: Inputs as `ctx[:key]` monospace pills on `bg-amber-900/20`
   - Right: Outputs as `ctx[:key]` monospace pills on `bg-emerald-900/20`
   - Dependencies below if any

2. **Test Runner** — prominent dark panel:
   - JSON textarea `bg-gray-900 font-mono`, pre-filled with `sample_input`
   - "Run" button with cyan accent (`bg-cyan-600`)
   - Results inline: syntax-highlighted code, I/O badges, validation errors in red
   - No page navigation

3. **Source Code** — full source, syntax highlighted, dark background, line numbers via `CodeBlockComponent`

### Form Page (New/Edit)

- Code fields (methods body): dark `bg-gray-900` monospace
- Metadata fields (description, category): standard light form inputs

## Stimulus Controllers

### `generator_test_runner_controller.js`
- Pre-fill textarea from `data-*-sample-value` attribute (set by ShowComponent from `sample_input`)
- Post to `test_run`, display results inline
- Markup generation matches dark theme

### `generator_search_controller.js` / `generator_nav_controller.js`
- Functionally unchanged
- Active item styling updated for dark sidebar

### `generator_form_controller.js`
- Unchanged

## Tests

### Shared Example (`"a code generator"`)

```ruby
RSpec.shared_examples "a code generator" do
  it "#generate_body returns String or nil"
  it "#generate_step_method wraps body with def step(ctx, **)...end"
  it "#validate_config returns Array"
  it "#dependencies returns Array"
  it ".sample_input returns Hash"
  it "metadata declares description (String), category (Symbol), version (semver)"
  it "has generator_name and generator_kind"
  it "TestRunner.run succeeds with sample_input"
end
```

### New Spec Files

| File | Coverage |
|------|----------|
| `spec/services/code_generators/code_introspector_spec.rb` | All detection patterns, exclusions (string literals, `_`-prefixed), edge cases (read+write same key) |
| `spec/services/code_generators/test_runner_spec.rb` | Full pipeline, nil body handling, validation error passthrough |

### Existing Generator Specs (125 files)

No changes needed — shared example update covers `sample_input` and `TestRunner` integration automatically.

### Controller Spec

Updated:
- `#test_run` returns `TestRunner.run` structure
- `#update` with body-changing edit bumps version
- `#update` with metadata-only edit does NOT bump version

## Change Summary

| Area | Files touched | Nature of change |
|------|--------------|-----------------|
| Infrastructure | 6 files | Refactor + 2 new services |
| All 125 generators | 125 files | Add `self.sample_input` only |
| ViewComponents | 3 components (index/show/form) .rb + .html.erb | Full rewrite |
| Controller | 1 file | TestRunner delegation, smart versioning |
| Stimulus | 3 JS files | Minor styling + sample pre-fill |
| Specs | shared example + 2 new + controller spec | Rewrite shared example, new unit specs |
