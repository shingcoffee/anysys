# Code Generator Architecture Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Trailblazer activity code generation into a modular, file-per-generator architecture with self-documenting interfaces and admin CRUD UI.

**Architecture:** Each generator (31 total: 7 element types + 24 step actions) becomes a standalone class inheriting from `BaseGenerator`, including `GeneratorInterface` for contract enforcement. A `GeneratorRegistry` auto-discovers generators from convention-based directories. The `ActivityGenerator` orchestrator thins from ~780 to ~200 lines by delegating to the registry.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec, TailwindCSS, StimulusJS, ViewComponent

**Spec:** `docs/superpowers/specs/2026-03-29-code-generator-architecture-refactor-design.md`

---

## Plan Parts

This plan is split into parts to keep each file focused. Execute parts in order.

| Part | File | Tasks | Description |
|------|------|-------|-------------|
| 1 | [part-01-infrastructure.md](2026-03-29-code-generator-refactor/part-01-infrastructure.md) | 1–3 | GeneratorInterface, MetadataDSL, BaseGenerator, shared examples |
| 2 | [part-02-shared-modules.md](2026-03-29-code-generator-refactor/part-02-shared-modules.md) | 4–6 | OperandConverter, ConditionBuilder, HttpRequestBuilder |
| 3 | [part-03-registry-validator.md](2026-03-29-code-generator-refactor/part-03-registry-validator.md) | 7–8 | GeneratorRegistry, GeneratorValidator |
| 4 | [part-04-element-type-generators.md](2026-03-29-code-generator-refactor/part-04-element-type-generators.md) | 9–10 | All 7 element type generators |
| 5 | [part-05-step-actions-model-validation.md](2026-03-29-code-generator-refactor/part-05-step-actions-model-validation.md) | 11–12 | Model operations (6) + Validation (2) generators |
| 6 | [part-06-step-actions-data-communication.md](2026-03-29-code-generator-refactor/part-06-step-actions-data-communication.md) | 13–14 | Data (4) + Communication (4) generators |
| 7 | [part-07-step-actions-remaining.md](2026-03-29-code-generator-refactor/part-07-step-actions-remaining.md) | 15–16 | Security + Background + File + Realtime + Response (8) generators |
| 8 | [part-08-orchestrator-refactor.md](2026-03-29-code-generator-refactor/part-08-orchestrator-refactor.md) | 17–18 | Refactor ActivityGenerator, delete old files |
| 9 | [part-09-admin-crud-ui.md](2026-03-29-code-generator-refactor/part-09-admin-crud-ui.md) | 19–21 | Routes, controller, ViewComponents, Stimulus |
| 10 | [part-10-verification.md](2026-03-29-code-generator-refactor/part-10-verification.md) | 22 | Final verification, integration tests |

---

## Key Conventions

### Action Name → Generator Name Mapping

The current `STEP_ACTIONS` hash uses action names like `"API_call"` and has aliases (`"validate"` / `"validate_contract"`). The new registry handles this via:

1. **`registered_names`** class method on generators — defaults to `[generator_name]`, override for aliases
2. **Action name normalization** in orchestrator — `action.downcase` before registry lookup

Generators needing custom registrations:
- `ValidateContractGenerator` → `registered_names: ["validate_contract", "validate"]`
- `ApiCallGenerator` → `registered_names: ["api_call", "API_call"]`
- `GenerateFileGenerator` → `registered_names: ["generate_file"]` (default works)

### File Path Conventions

```
app/services/code_generators/                    # Source
spec/services/code_generators/                   # Tests (mirrors source structure)
app/controllers/admin/code_generators_controller.rb
app/components/admin/code_generators/            # ViewComponents
```

### Test Pattern

Every generator spec includes the shared example group:
```ruby
RSpec.describe CodeGenerators::StepActions::NewModelGenerator do
  it_behaves_like "a code generator"
  # ... specific tests ...
end
```

New generator tests use direct instantiation:
```ruby
# Old pattern (module mixed into anonymous class):
generator_class = Class.new { include ActivityGenerator::ModelSteps; ... }
generator.generate_new_model(step, ctx)

# New pattern (standalone class):
generator = CodeGenerators::StepActions::NewModelGenerator.new(step, {})
generator.generate
```
