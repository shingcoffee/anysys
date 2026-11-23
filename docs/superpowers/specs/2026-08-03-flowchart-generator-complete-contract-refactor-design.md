# Flowchart Generator Complete Contract Refactor

**Date:** 2026-08-03
**Status:** Approved by autonomous technical decision
**Scope:** Every flowchart element type and every process step action
**Delivery:** Phased category slices on the existing uncommitted refactor

## 1. Goal

Make the flowchart builder configuration and generated Ruby one explicit,
testable contract. Every configurable field and option must be validated,
consumed intentionally, and represented correctly in generated activities.
Dead configuration, hidden generator behavior, unsafe source interpolation,
and hand-rolled implementations covered by mature Ruby/Rails libraries must
be removed.

## 2. Baseline

The repository already contains:

- element schemas in `app/javascript/flowchart/constants/schemas.js`;
- 104 process actions in
  `app/javascript/flowchart/constants/action_configs/`;
- approximately 117 generators under
  `app/services/code_generators/element_types/`;
- declarative generator metadata and `CodeGenerators::ConfigSchema`;
- generator/UI audit scripts and a checked-in audit catalog;
- an uncommitted Slice A/B refactor introducing `FlowchartRuntime` facades for
  HTTP, JWT, cipher, archive, media, templates, sanitization, locks, IDs,
  password hashing, TOML, parallel mapping, and related behavior.

That work is the baseline. It must be completed and corrected in place rather
than replaced or reverted.

## 3. Considered Approaches

### A. Big-bang rewrite

Rewrite all generators and schemas together. This gives conceptual uniformity
but creates an unreviewable change set and makes regressions difficult to
localize.

### B. Ad-hoc bug fixes

Fix only failures found by current tests and greps. This is fast but cannot
prove configuration/generator parity and would preserve architectural drift.

### C. Contract-driven category slices

Define one parity contract, strengthen automated audits, then migrate element
types and process categories in bounded slices. Each slice includes UI schema,
generator metadata, body emission, runtime dependencies, I18n, and tests.

**Decision:** Approach C. It provides complete coverage without the risk of a
big-bang rewrite and makes every intermediate state measurable.

## 4. Contract Architecture

Each configurable behavior follows one path:

```text
Builder schema/action config
  -> serialized element properties/config
  -> generator ConfigSchema and metadata
  -> validated normalized values
  -> generated Trailblazer activity source
  -> FlowchartRuntime/app service or Rails framework API
  -> runtime result/error mapped to Railway semantics
```

### 4.1 Single source of truth

Ruby generator schemas are the authoritative executable contract for accepted
keys, types, enum values, defaults, and required fields. JavaScript schemas
remain the builder presentation model, but automated parity checks must fail
when they diverge from Ruby.

The audit must distinguish:

- persisted user fields;
- computed connection/topology fields;
- framework wrapper fields such as retry, timeout, and guard;
- output-only generator metadata.

Computed fields such as connection match values must not be exposed as fake
user-editable controls merely to satisfy a mechanical audit.

### 4.2 Generator responsibilities

Each generator must:

1. declare every consumed configuration field;
2. validate conditional and cross-field rules explicitly;
3. normalize values before source generation;
4. emit concise, deterministic Ruby;
5. avoid interpolating untrusted configuration as executable Ruby unless the
   field is explicitly an expression field;
6. call a stable app-level service for protocol, crypto, serialization, file,
   scheduling, concurrency, or third-party behavior;
7. map known runtime errors to `ctx[:_last_error]` and Railway failure without
   swallowing unexpected exceptions.

### 4.3 Runtime service boundaries

Prefer Rails APIs and mature gems behind thin `FlowchartRuntime::*` or existing
app services. Generated source must not contain multi-step implementations of
protocols or algorithms.

Examples:

| Behavior | Runtime boundary |
|---|---|
| HTTP | `OutboundHttp` over Faraday |
| JWT | `FlowchartRuntime::Jwt` over `jwt` |
| encryption | `FlowchartRuntime::Cipher` over Rails/controlled crypto API |
| archives | `FlowchartRuntime::Archive` over `rubyzip` and stdlib compression |
| templates | `FlowchartRuntime::Template` over Liquid |
| barcode/QR | Barby and RQRCode facades |
| sanitization | Loofah facade |
| password hashing | bcrypt facade |
| locks/cache/jobs | Rails cache and Active Job facades |
| structured formats | maintained parsers/serializers where Rails/stdlib is insufficient |

Standard library use remains appropriate for simple primitives such as CSV,
Base64, JSON, URI, and plain digest operations. A gem is not added merely to
replace a clear standard-library call.

## 5. Audit Matrix

Generate a machine-readable row for every element type and step action:

- UI key and category;
- UI fields, control types, defaults, visibility conditions, and options;
- Ruby generator class and generator key;
- declared config fields, types, defaults, required fields, and enum values;
- fields actually read while generating source;
- generated context inputs and outputs;
- runtime constants/services referenced;
- locale keys in English and Simplified Chinese;
- focused spec paths and coverage status.

The audit fails for:

- missing or extra persisted fields;
- action/generator key mismatch;
- enum/default/type mismatch;
- a visible field ignored by the generator;
- a generator-read field unavailable from UI or documented computed input;
- required/visibility rules not represented by generator validation;
- locale key-set or interpolation mismatch;
- forbidden implementation patterns;
- missing generator interface or parity examples.

## 6. Migration Slices

1. **Foundation:** repair audits, classify computed/common fields, and make the
   audit catalog reproducible.
2. **Existing runtime baseline:** finish and validate the current HTTP,
   security, archive, media, template, lock, ID, parsing, and parallel-map
   work without overwriting user changes.
3. **Structural elements:** start, end, decision, loop, join, fork, switch,
   subflow, timer, signal wait, saga, transaction, and parallel-for-each.
4. **Process categories:** model, validation, data, communication, security,
   background, file, realtime, response, caching, concurrency, human workflow,
   resilience, scheduling, service, and utility.
5. **Generated activity verification:** compile/evaluate generated activity
   source in isolated specs and execute representative success/failure paths.
6. **Regeneration and release:** regenerate persisted activity source through
   the provided rake task and document breaking configuration removals.

Within each slice, configuration parity is fixed before runtime behavior so a
test failure identifies whether the defect is contract or execution related.

## 7. Safety and Error Handling

- No `eval`, `class_eval`, unsafe constant lookup, unsafe YAML/Marshal loading,
  or arbitrary source interpolation for ordinary text fields.
- Model/class/service names use allow-listed resolution and expected ancestry
  checks before invocation.
- HTTP keeps TLS verification enabled and has bounded redirects/timeouts.
- Retry backoff and loop/parallel limits are bounded.
- Runtime wrappers expose narrow error classes; generated code rescues only
  expected operational errors.
- Tenant and authorization behavior is not embedded in generated strings when
  an application policy/service can enforce it.
- Required dependencies fail explicitly; no `defined?(Gem)` success-shaped
  fallback.

## 8. Testing

Each contract row requires:

- schema/metadata parity coverage;
- validation examples for required, enum, bounds, and conditional rules;
- generator source examples for every meaningful option branch;
- forbidden-source assertions;
- runtime facade unit specs;
- generated Ruby syntax checks;
- representative generated activity execution specs;
- English/Simplified Chinese locale parity;
- Vitest coverage at 100% lines and branches for changed JavaScript;
- final generator audits with zero unexplained gaps.

Targeted category specs run during each slice. Because the completed refactor is
cross-cutting, the final verification includes the full RSpec suite and full
Vitest coverage.

## 9. Completion Criteria

The work is complete only when:

1. every registered element/action has exactly one generator and audit row;
2. all persisted builder fields are intentionally consumed or explicitly
   removed from UI, both locales, fixtures, and stored defaults;
3. every generator-read field is declared and available from UI, common
   wrapper configuration, or documented computed topology;
4. option branches have source and execution tests;
5. forbidden hand-rolled/unsafe patterns are absent or explicitly justified;
6. generated activities compile and representative workflows execute;
7. audits, targeted specs, full RSpec, and JavaScript coverage pass;
8. the worktree remains uncommitted for human review.

