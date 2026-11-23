# Operations API — agent-callable operations

Date: 2026-10-15
Status: approved for build. Phase 1 = entity create / update invoked by the AI assistant.
Plan: `docs/operations-api-plan.md`

## 1. Problem

Today the assistant builds entities by returning one free-form JSON *document*
(`intent: apply_entities`) validated against `EntityDefinitions::StructureSchema`.
A pipeline dedicated to that document (Extraction → SchemaValidator → UpdatePolicy →
Persist, plus a DocumentRepair round-trip) turns it into writes.

That contract cannot be reused by another feature, cannot delete or reorder anything,
has implicit update semantics (merge by slug; any key omitted from an attribute is reset),
reports errors as flat strings with no location, and leaves no record of what the AI did.

Goal: a reusable framework in which any feature exposes typed, documented, validated
**operations** that the assistant invokes as **tools**, with exactly the effect of doing
the same work by hand on the page.

## 2. The proposed workflow, refined to industry practice

| Proposal | Refinement |
| --- | --- |
| a) Define a detailed API schema per feature | Each feature registers an **operation**: a versioned name, a JSON Schema 2020-12 input contract, an output shape, behaviour annotations (read-only / destructive / idempotent / confirmation, as in MCP tool annotations), and examples. One registry feeds every consumer — assistant tools now, an HTTP API with an OpenAPI 3.1 document later. |
| b) Describe every field and every enum value | Descriptions are mandatory and **checked in CI**. A contract lint fails when a property has no `description` or when any enum value lacks its own explanation (`x-enum-descriptions`). Enum values are resolved from the live application registries at load, so the documentation cannot drift from what the app accepts. |
| c) Validate the payload against the schema | **Layered validation with one error format**: structural (json_schemer) → semantic (references, uniqueness, cross-field rules) → policy (role, tenant, quota) → domain (model validations at commit). Every violation carries a JSON Pointer (RFC 6901) into the payload, a stable machine `code`, a message, and a **resolution**. The failure envelope follows RFC 9457 Problem Details. |
| d) Feed the payload into the schema, then perform | Validation inserts the schema's `default`s, so the schema is the single source of defaults. A **command pipeline** then runs: authorize → validate → plan (dry run) → confirmation gate → execute atomically → record. Execution goes through the same domain writer and model validations as the entity builder, so "API == manual" holds by construction. Idempotency keys and optimistic concurrency are part of the pipeline. |
| e) The assistant generates and sends the payload | Operations are exposed as native **function-calling tools** (`RubyLLM::Tool`), with the existing JSON `{"tool": …}` convention as the fallback for vendors without native tools. A read tool (`get_entity`) lets the model read before it writes. |
| f) On validation failure, ask the customer | **Triage instead of always asking.** `fix_payload` violations go back to the model to correct silently, with a bounded retry budget — the customer never sees "html_type is invalid". Only `ask_user` items (business facts only the customer knows) become one consolidated question. `blocked` (permission, quota) is explained and never retried. `refresh` (the entity changed) re-reads first. Every change to an existing entity stops at a **human-in-the-loop** approval: the admin reviews the plan and applies it. |

## 3. Architecture

```text
            consumers
  AI assistant tools (native + JSON loop)      HTTP API + OpenAPI (phase 2)
                         \                      /
                          v                    v
             Operations::Activities::Execute   (Trailblazer Railway)
   resolve → authorize → idempotent replay → validate schema (+defaults)
   → validate semantics → plan → gate (dry run / confirmation) → perform → record
                                   |
                    Operations registry — Operations.for(key)
               CreateEntity · UpdateEntity · GetEntity · (CreateFlowchart …)
                                   |
        domain layer: EntityDefinitions::Persist, ChangePlan, Normalizer,
        Entity model validations, bridge sync, versioning (unchanged ownership)
```

### 3.1 Operation contract — `Operations::Base`

An operation is one class file under `app/services/operations/` plus one schema file
under `app/services/operations/schemas/`. The class declares:

| DSL | Meaning |
| --- | --- |
| `key "create_entity"` | Stable identifier and tool name, verb_noun (Google AIP method naming), `^[a-z][a-z0-9_]{2,63}$`. |
| `version 1` | Contract version; part of the schema `$id` (`urn:anysys:operation:create_entity:v1`) and of every audit row. |
| `title` / `summary` | Tool title and the LLM-facing description: what it does, when to use it, when not to. |
| `schema "create_entity.json"` | Input contract. `shared_defs "entity.defs.json"` merges shared `$defs` in before resolution. |
| `vocabulary EntityDefinitions::Api::Vocabulary` | Supplies the registry-backed slots (§3.2). |
| `annotations read_only:, destructive:, idempotent:, confirmation:` | Behaviour hints. `confirmation: :always` parks every successful plan for human approval; `:never` executes directly. |
| `register!` | Adds the class to the `Operations` registry. |

Instance hooks, all optional except `perform`: `validate(input) → [Violation]`,
`plan(input) → Array<Hash>`, `snapshot(input)` / `stale?(snapshot)` (concurrency),
`perform(input) → Outcome`, and class-level `available?(context)` for feature gating.

### 3.2 Schemas

- JSON Schema 2020-12 files, self-describing: every property has `description`; every
  object sets `additionalProperties: false`; conditionals (`allOf` + `if`/`then`) carry a
  `description` stating the rule in words.
- **Registry-backed slots** replace literal lists wherever the app has a registry:
  - `"x-vocabulary": "<name>"` on a string schema → resolved to `enum` plus
    `x-enum-descriptions` (one English sentence per value). A nullable string gets `null`
    appended to its `enum`.
  - `"x-vocabulary-max": "<name>"` on an integer schema → resolved to `maximum`.
  - Sources may depend on the tenant (e.g. extendable base models), so schemas are resolved
    per `Operations::Context`.
- **One canonical schema, two renderings.** The canonical schema validates and documents.
  `Operations::SchemaProjection` renders the provider-safe tool parameters: `$ref` inlined,
  `x-*` keys removed, `x-enum-descriptions` folded into the property `description`
  ("Allowed values: `a` — …; `b` — …"), conditionals removed with their descriptions folded
  into the parent, `oneOf` → `anyOf`. Anything the projection loosens is still enforced
  server-side.
- **Contract lint** (`Operations::SchemaLint`, run in specs for every registered operation):
  title/description present, every property described, every enum value described, every
  conditional described, every `examples[]` payload valid, projection under the size budget.
- Defaults live only on "create-shaped" containers. Partial ("patch") shapes reuse the same
  leaf definitions without `default` or `required`, so inserting defaults never turns an
  omitted patch key into a change.

### 3.3 Violations

`Operations::Violation` (`pointer`, `code`, `details`, `resolution`):

- `pointer` — RFC 6901 JSON Pointer into the submitted arguments, e.g.
  `/entities/0/attributes/2/html_type`.
- `code` — stable, namespaced: `schema.enum`, `schema.required`, `entity.already_exists`,
  `attribute.unknown_group`, `rule.not_allowed`, `conflict.version_changed`, … The full
  list is in the plan.
- `message` — `I18n.t("operations.violations.<code>", **details)` (en + zh-CN).
- `details` — machine hints the model can act on: `allowed` (enum values), `candidates`
  ("did you mean", via Ruby's `DidYouMean::SpellChecker`), `expected`, `got`.
- `resolution` — what should happen next:

| Resolution | Who acts | Examples |
| --- | --- | --- |
| `fix_payload` | The model corrects the call itself, silently, within the retry budget. | wrong enum, missing choice list, unknown group key, duplicate slug |
| `ask_user` | The model asks the customer one consolidated question. | update target not found and no close candidate; constant list unknown |
| `refresh` | The model re-reads (`get_entity`) and rebuilds the call. | the entity changed since it was read |
| `blocked` | The model explains why; no retry. | permission denied, quota exceeded, entity is a bridge |

Validation stops at the first failing layer and caps the list at 25 violations.

### 3.4 Outcomes

`Operations::Outcome` statuses and the tool payload the model receives (a JSON string):

| Status | `ok` | Meaning |
| --- | --- | --- |
| `succeeded` | true | Performed; `data` holds the operation's output. |
| `confirmation_required` | true | Valid and planned, nothing written; `plan` holds the reviewable diff. |
| `dry_run` | true | Valid and planned, nothing written (non-assistant channels). |
| `invalid` | false | `errors[]` of violations. |
| `conflict` | false | The target moved since it was read or planned. |
| `forbidden` | false | The actor may not perform this operation here. |
| `failed` | false | Unexpected error; logged; generic message. |

Every payload carries `next_step`, an instruction derived from the statuses/resolutions
present (e.g. "Correct the fix_payload items and call create_entity again; do not mention
them to the user. Attempts remaining: 2."). `Outcome#to_problem` renders the RFC 9457 shape
(`type`, `title`, `status`, `detail`, `errors[]`) for the future HTTP channel.

### 3.5 Execution pipeline — `Operations::Activities::Execute`

1. **resolve** the operation (class or key); unknown → `operation.unknown` listing available keys.
2. **authorize**: the actor is active and either the platform owner or an `admin` of the
   context customer, and `available?(context)` holds; otherwise `forbidden`. Members never
   reach an operation.
3. **replay**: an idempotency key already recorded for this customer with the same input
   digest returns the stored outcome (`replayed: true`); a different digest is
   `idempotency.key_reused`.
4. **validate schema** on a deep copy, inserting defaults → normalized input.
5. **validate semantics** (`operation.validate`).
6. **plan** and capture `snapshot`.
7. **gate**: `dry_run` returns the plan; `confirmation: :always` without `confirmed` stores an
   `OperationInvocation` (`awaiting_confirmation`, normalized input, plan, snapshot) and
   returns `confirmation_required`.
8. **perform** inside the context's write wrapper (the assistant passes the generation write
   guard), the customer row lock, and one transaction. Domain errors become `domain.invalid`.
9. **record** an `OperationInvocation` row for every non-read-only call, on both tracks.

`Operations::Activities::Confirm` applies a parked invocation: it re-authorizes, re-validates
the stored input, checks `stale?(snapshot)` under the customer lock (→ `conflict`), performs
with `confirmed: true`, and marks the row. It never accepts a re-authored payload.

### 3.6 Idempotency and concurrency

- `Context#idempotency_key`. The assistant derives `gen-<generation id>-<key>-<input digest>`,
  so a model that repeats a successful call, or a retried job, cannot create twice. The
  HTTP channel will take an `Idempotency-Key` header.
- Optimistic concurrency: `get_entity` returns `version` (the entity's current version
  number); `update_entity` accepts `expected_version` per entity. The confirmation snapshot
  pins each target's current line head version id server-side.

### 3.7 Audit — `OperationInvocation`

One row per write invocation: customer, actor, operation + version, channel
(`assistant`/`api`/`system`), status, idempotency key, input digest, normalized input, plan,
snapshot, result, violations, conversation/generation ids, confirmer and time, duration.
It is also the server-side store for parked proposals.

## 4. Entity operations

### 4.1 Public vocabulary

The API speaks the domain's language rather than the storage format. A mapper
(`EntityDefinitions::Api::Mapper`, an anti-corruption layer) translates to and from the
stored definition. Shared shapes live in `schemas/entity.defs.json`.

| Public field | Stored as | Notes |
| --- | --- | --- |
| `name` | `name` | Identity. Unique per tenant; must not start with `assoc_`. Slug is derived from it and is read-only. |
| `display_label`, `description` | same | `display_label` defaults to `name`. |
| `extends` | `extended_model` | Enum of the tenant's extendable base models. |
| `settings.icon` / `settings.color` | `icon` / `color` | Flowchart palette icon key and hex colour. Defaults `custom` / `#6366f1`. |
| `settings.default_values` | `default_properties` | Initial values for new flowchart elements. Keys are attribute slugs. |
| — | `referenced_template` | Not part of the API: in the editor, picking a template replaces the attribute list. Preserved untouched on update. |
| `attribute_groups[].key` | `attribute_groups[].id` | Plus `name`, `description`, `icon`, `color` (enums). Array order = page order. |
| `attributes[]` | `property_schema[]` | See below. |
| `associations[]` | `associations[]` | `related_entity`, `display_field`, `display_field_label`, `bridge_attributes[]`. The bridge entity is created automatically. |

Attribute (`attributes[]` and `bridge_attributes[]`):

| Public field | Stored as | Notes |
| --- | --- | --- |
| `name`, `slug`, `display_label`, `description` | `name`, `name_slug`, … | Slug derived from name when omitted; immutable after creation. |
| `kind`: `input` / `calculated` / `computed` | `type`: absent / `Calculated` / `Computed` | Bridge attributes are always `input`. |
| `html_type` | `html_type` | Enum of controls, each described. Default `text`. |
| `group` | `group_id` | Must match a group `key`. |
| `rules[]` — *attribute rules* | `validators[]` | `{type, value}`, `{type, min, max}`, `{type, pattern}`, `{type, values}` by rule kind; allowed types depend on `html_type`. |
| `access` — *attribute access* | `visibility`, `validator_apply` | `visible_to` and `rules_apply_to`, each `{admin, member, public}`; rules apply only where visible. |
| `options` | `config` | `source`: `static` (`values`), `constant` (`constant` name), `entity_entries` (`entity`, `label_field`, `value_field`). Required for select / radio / checkbox. |
| `file` | `config.accept`, `config.multiple` | File and image controls only. |
| `formula` | `formula` | Required for `calculated`. |
| `aggregate` | `config` (computed) | `related_entity`, `function`, `source_attribute`, `precision`, `filter{attribute, operator, value}`, `direction` (`source`/`target`). |

### 4.2 `create_entity`

Creates one or more related entities atomically. Associations, entity-entry option sources
and computed aggregates may refer to other entities in the same call by name.

```json
{
  "entities": [
    {
      "name": "Course",
      "attribute_groups": [{ "key": "basics", "name": "Basics", "icon": "folder", "color": "indigo" }],
      "attributes": [
        { "name": "Title", "group": "basics", "rules": [{ "type": "presence" }, { "type": "length_maximum", "value": 120 }] },
        { "name": "Level", "html_type": "select", "group": "basics",
          "options": { "source": "static", "values": ["Beginner", "Intermediate", "Advanced"] } }
      ]
    },
    {
      "name": "Student",
      "attributes": [
        { "name": "Email", "html_type": "email", "rules": [{ "type": "presence" }, { "type": "format_email" }] },
        { "name": "Courses Taken", "kind": "computed", "aggregate": { "related_entity": "Course", "function": "count" } }
      ],
      "associations": [
        { "related_entity": "Course", "display_field": "title",
          "bridge_attributes": [{ "name": "Enrolled On", "html_type": "date" }] }
      ]
    }
  ]
}
```

Applies immediately (`confirmation: :never`). Output: created names, slugs, versions, bridges.

### 4.3 `update_entity` — a typed change set

Each change mirrors one action an admin performs in the entity editor, keyed by stable
identifiers (attribute slug, group key, related entity name), never by array index:

| `op` | Fields | Editor equivalent |
| --- | --- | --- |
| `set_details` | `display_label`, `description`, `extends` | Basic information card |
| `set_settings` | `icon`, `color`, `default_values` | Palette icon, colour, default values (accepted by the save endpoint, not shown in the editor) |
| `add_attribute` | `attribute` (object), `position` | Add attribute |
| `update_attribute` | `slug`, `set` | Edit attribute |
| `remove_attribute` | `slug` | Remove attribute |
| `move_attribute` | `slug`, `to_group`, `position` | Drag a row |
| `add_group` | `group` (object), `position`, `attributes` | New group |
| `update_group` | `key`, `set` | Edit group |
| `remove_group` | `key`, `move_attributes_to` | Delete group |
| `reorder_groups` | `order` | Drag a group |
| `add_association` | `association` (object) | Add association |
| `update_association` | `related_entity`, `set` | Edit association |
| `remove_association` | `related_entity` | Remove association |
| `add_bridge_attribute` | `related_entity`, `attribute` (object), `position` | Association attribute modal |
| `update_bridge_attribute` | `related_entity`, `slug`, `set` | Association attribute modal |
| `remove_bridge_attribute` | `related_entity`, `slug` | Association attribute modal |

Each field name has one meaning across all ops: `attribute`/`group`/`association` are
always full objects; `slug` (attribute) and `key` (group) always identify existing items.
`set` follows JSON Merge Patch (RFC 7396): objects merge, arrays replace, `null` clears an
optional field. `position` is `{ "before": id }` or `{ "after": id }`; omitted means the end.

```json
{
  "updates": [
    {
      "entity": "Student",
      "expected_version": 7,
      "changes": [
        { "op": "add_attribute", "attribute": { "name": "Phone", "html_type": "tel", "rules": [{ "type": "format_phone" }] }, "position": { "after": "email" } },
        { "op": "update_attribute", "slug": "email", "set": { "access": { "visible_to": { "public": false } } } },
        { "op": "remove_attribute", "slug": "fax" }
      ]
    }
  ]
}
```

One call may update several entities; it is one plan, one approval, one transaction.
`confirmation: :always`: every update returns `confirmation_required` with the change plan
(removals and type changes flagged as breaking), and is applied only when the admin approves.

### 4.4 `get_entity`

Read-only. Returns the entity in the public vocabulary plus `slug`, `version`, and each
association's `bridge_entity` name. Not audited.

### 4.5 Scope rules

- Customer-owned, active, non-bridge entities only. Shared entities and their per-tenant
  overrides stay with the Shared Resources editor. Bridge entities change only through
  their association's `bridge_attributes`.
- A name held by an entity in the trash is reported (`entity.name_in_trash`), not reused.
- Renaming an entity stays a manual action in the editor (phase 2).
- Quota is checked at validation (`quota.exceeded`, blocked) and again at write.

### 4.6 Execution

- `create_entity`: mapper → definition documents → `EntityDefinitions::Persist`
  (quota, identity, body, option sources, associations + bridges, computed resolution).
- `update_entity`: `EntityDefinitions::Catalog` document (lossless, name-based) →
  `EntityDefinitions::Api::ChangeSet` applies the changes to the stored shape (untouched
  attributes stay byte-identical) → `ChangePlan` (plan) → `Persist` in **replace mode**,
  which writes the attribute list, groups and associations exactly as given so removals and
  reordering take effect.

## 5. Assistant integration

- Each available operation becomes a native tool (`Tools::OperationTool`, one adapter class
  for every operation) next to `list_catalog`, `generate_page` and `verify_artifact`. Vendors
  without native tools use the JSON `{"tool": …, "arguments": …}` loop; the prompt lists the
  projected schemas for them.
- `Tools::Session` dispatches operation calls to `Execute`, tracks entity effects, enforces
  a per-operation retry budget (3 attempts per turn) and at most one parked proposal per
  turn (`proposal.already_pending` asks the model to combine its updates into one call).
- The final reply stays the JSON envelope `{"intent": "chat"|"clarify", "reply": "…"}`
  (`apply_website` is unchanged). `apply_entities` is removed.
- `TurnProcessor` derives the turn's entity result (created / updated / bridges) from the
  session's effects, so page generation, the flowchart follow-on and the artifact pane keep
  working, and attaches a parked proposal (`kind: "operation"`, `invocation_id`, `plan`) to
  the reply. Approval (Apply button or a bare "yes") runs `Operations::Activities::Confirm`.
- Prompt: `EntityContract` and the repair document are replaced by an operations section;
  authoring guidance and examples are rewritten for tools; the entity catalog is rendered in
  the public vocabulary.

## 6. Adding the next operation (e.g. `create_flowchart`)

1. Add `app/services/operations/create_flowchart.rb` (`Operations::CreateFlowchart < Operations::Base`).
2. Add `app/services/operations/schemas/create_flowchart.json`, fully described.
3. Implement `validate` / `plan` / `perform` by delegating to the domain writer; call `register!`.
4. Add the developer docs section and specs. The contract lint covers it automatically.

No change to the assistant loop, tool session, prompt plumbing or audit is needed.

## 7. Decisions and out of scope

Decided for phase 1:

- The `apply_entities` document protocol is replaced, not kept alongside (no compatibility shims).
- The assistant may remove attributes, groups, associations and bridge attributes, always
  behind the admin's approval with breaking rows flagged — parity with the editor.
- Creates apply immediately; updates always need approval (unchanged policy).
- Assistant channel only. The executor is channel-agnostic; the HTTP endpoint comes next.

Phase 2: HTTP endpoint (`/:cid/admin/api/v1/operations/:key`, Bearer, admin-or-owner,
`Idempotency-Key`, `?dry_run=1`) with a generated OpenAPI 3.1 document; structured elicitation
(a small form in the chat for `ask_user` items); entity rename; starting an entity from a
page-layout template; the entries list view preference (`EntityIndexSetting`); shared-entity overrides;
migrating flowchart and website authoring to operations; routing the manual entity form
through the same operations.
