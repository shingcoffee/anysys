# Entity structure schema + assistant fill & persist

Date: 2026-09-01
Status: superseded for assistant apply behavior by `docs/superpowers/specs/2026-09-03-assistant-entity-configuration-design.md` (create-immediately / update-after-NL-confirmation, clarify intent, JSON Schema validation). Persist API, tenant rules, and EntityReference vocabulary below still hold.

Canonical copies also live under `docs/superpowers/specs/` (cursorignored; written via shell).

## Problem

Tenant admins can already define entities (attributes, groups, associations, auto-created bridges, rollups, calculated fields, extensions). Pages already render from those definitions. The dashboard AI Assistant already collects typed wording and speech-to-text, but it only chats — it does not fill an entity definition or write to the entity store.

This work documents the existing entity definition as one JSON Schema the backend LLM can fill, wires the assistant to that fill, and auto-persists a related set of **customer-owned** entities through the current versioned Entity path.

## Decisions (locked)

- Audience: tenant `admin` (and `owner` acting on a tenant URL). Customer-owned entities only.
- Persist: auto-persist on every successful fill. No confirm step.
- Create vs update: exact `name` match on a **live customer-owned** entity in this tenant → update (new version); otherwise create.
- One turn may persist a related set (several entities + associations). Bridges are never proposed by the LLM.
- Approach: canonical schema + `ApplyFromRequirements` activity, invoked from the existing assistant reply job.
- Persist attribute type for bridge participant links: **`EntityReference`** (replaces `NestedEntity`). No data migration; development data may be dropped. No compatibility alias.
- Shared entities, shared overrides, platform-prefix CUD, page/flowchart/constant generation, member assistant, and entity **entry** creation are out of scope.

## Vocabulary

| Term | Meaning |
|------|---------|
| Primary entity | The entity being defined (e.g. Student). |
| Associated entity | The other side of a relationship (e.g. Course). |
| Bridge entity | Auto-created join (`assoc_<primary>_<associated>`, `category: bridge`). |
| Participant references | The two system-owned attributes on the bridge. Stored `type`: `EntityReference`. First = primary, second = associated. |

The LLM emits associations on the primary entity. It never emits bridge rows, `EntityReference` attributes, `bridge_entity_id`, or `category: "bridge"`.

## Architecture

The existing Entity identity + versioned body remains the source of truth. The “entity structure schema” is a documented JSON Schema of that definition, not a second model.

After each assistant user turn, `SpeechToText::ReplyJob` (already sets `Current.customer`) runs `SpeechToText::Activities::Reply`, which:

1. Sends the schema, this tenant’s live customer-owned entity catalog, and recent complete turns to the chat LLM.
2. Requires a JSON envelope (normal chat included).
3. On `intent: apply_entities` with a non-empty `entities` array, calls `EntityDefinitions::ApplyFromRequirements` inside one transaction.
4. Persists an assistant message: human `reply` plus created/updated names on success, or existing entity-form I18n errors on validation failure. Vendor/parse failure writes nothing to entities.

## Envelope (LLM output)

Always JSON (optionally wrapped in a ` ```json ` fence). Shape:

```json
{
  "intent": "chat" | "apply_entities",
  "reply": "string — shown in the assistant thread",
  "entities": []
}
```

- `intent: chat` or empty `entities` → no entity write. `reply` is the chat answer.
- `intent: apply_entities` with one or more entities → apply then persist. `reply` is the summary (backend may append created/updated names).

### Entity object (fill)

Identity: `name` (required), `display_label`, optional `name_slug` (`\A\w+\z`, derived from name if omitted), optional `extended_model` (presence ⇒ category `extension`, else `plain`).

Versioned body: `icon`, `color`, `description`, `attribute_groups`, `property_schema`, `associations`, `default_properties`, `referenced_template`.

Forbidden on fill: `id`, `customer_id`, `category: bridge`, `shared`, `status`, `bridge_entity_id`, attributes with `type: EntityReference`.

### Attribute groups

`{ "id", "name", "icon", "color" }` — same constraints as `EntitySchemaValidation` (id format, icon/color allow-lists, unique ids/names). Attributes may set `group_id` to an id in the same entity.

### Attributes (`property_schema`)

Shared fields: `name`, `name_slug`, `display_label`, `html_type` (existing HTML types: text, textarea, search, password, hidden, select, radio, checkbox, number, range, date, time, datetime-local, month, week, email, tel, url, file, image, color), `description`, `validators` (same keys as the entity form: presence, numericality, numericality_integer, length_*, format_*, inclusion, …), `visibility` `{ admin, member, public }`, `validator_apply`, `group_id`, `config`.

Kinds:

- **Data field** — omit `type` (default).
- **Calculated** — `type: "Calculated"`, `formula` using sibling slugs, readonly/computed storage.
- **Rollup** — `type: "Rollup"`. LLM config uses `target_entity_name` (association peer), `function` (`count` / `sum` / `avg` / `min` / `max`), optional `source_slug` (bridge extra attribute), optional `precision`, optional `filter`, optional `bridge_role`. Must **not** send `bridge_entity_id`. Apply resolves the bridge after association sync.
- **EntityReference** — system-owned on bridges only. Rejected if present in the fill.

### Associations

```json
{
  "associated_entity_name": "Course",
  "display_field": "name",
  "display_field_label": "Name",
  "additional_attributes": []
}
```

`associated_entity_name` must name a live customer-owned entity in this tenant or another entity in the same `entities` array. `display_field` / `display_field_label` required. `additional_attributes` are extra **data** fields on the auto-created bridge. No self-association. Duplicate associated name + display field is invalid.

After persist, the stored association uses today’s keys (`target_entity_id`, `target_entity_name`, `bridge_entity_id`, …). The fill key `associated_entity_name` maps to `target_entity_name` / id resolution.

## Components

| Unit | Responsibility |
|------|----------------|
| `EntityDefinitions::StructureSchema` | Loads JSON Schema + prompt fragment with field-level explanations. |
| `EntityDefinitions::Envelope` | Parses LLM text → envelope hash or error. |
| `EntityDefinitions::ApplyFromRequirements` | Validates and persists a related set for `Current.customer`. |
| `SpeechToText::Activities::Reply` | Prompt, chat, parse, optional apply, assistant message. |
| `Entity::ENTITY_REFERENCE_TYPE` (`"EntityReference"`) | Canonical persist type for participant references. Bridge sync, field organizer, SaveAll, specs, entity feature docs. |

No new routes or UI. Assistant panel and entity maintenance form stay as they are.

## Data flow

1. Admin sends text or STT into the existing per-(customer, user) thread.
2. Reply loads complete history (limit 20), structure schema, and live customer-owned non-bridge entity names/slugs/ids for this tenant.
3. Chat LLM returns the envelope.
4. Envelope parse failure → assistant `failed` (no entity write).
5. Chat intent / empty entities → persist `reply` as complete assistant message.
6. Apply intent, one DB transaction:
   - **Pass A:** for each entity, reject forbidden fields; if live customer-owned `name` exists → update; if inactive or bridge has that name → error; else create (`customer_id` = current tenant). Quota check per create (`Billing::Quota::Guard`, item `entity`). Save via existing Entity validations + versioning.
   - **Pass B:** resolve `associated_entity_name` to ids; write associations; `sync_bridge_entities!` (creates/updates bridges and two `EntityReference` fields).
   - **Pass C:** resolve rollup `target_entity_name` to `bridge_entity_id`; write rollup attributes; save again if needed.
7. Commit. Assistant complete message: `reply` plus created vs updated vs auto-created bridge names.
8. Any failure rolls back. Assistant complete message with entity-form I18n errors (en + zh-CN). Vendor down uses existing `reply_failed` / `failed` status.

Name match is exact on `name`. Missing association targets fail the whole turn.

## Error handling

| Situation | Entity write | Assistant |
|-----------|--------------|-----------|
| Empty wording / empty STT | none | existing validation |
| Module disabled / unconfigured / vendor down | none | existing fail-closed |
| Invalid JSON / missing envelope | none | failed turn (new I18n parse key) |
| Validation / resolve / quota / bridge conflict | none (rollback) | complete turn with form errors |
| Inactive name collision | none | do not restore; tell admin to restore in maintenance |
| Name is an existing bridge | none | reject |
| Shared name only (no customer-owned live row) | create customer-owned | allowed |
| Fill tries to mutate a shared entity | none | reject |
| LLM emits EntityReference / bridge category / bridge_entity_id | none | reject |
| Associated name missing | none | target-not-found |
| Anonymous / member / other-tenant admin | none | existing 401/403 |
| Concurrent same-name writes | one wins | loser uniqueness/validation |

`Current.customer` is the conversation’s customer (set by `ReplyJob`). The LLM cannot choose `customer_id`.

## Testing

- `EntityDefinitions::StructureSchema` — file is valid JSON Schema; required keys present; prompt includes vocabulary (primary / associated / bridge / EntityReference).
- `EntityDefinitions::Envelope` — raw JSON, fenced JSON, invalid text, missing `reply`, unknown intent.
- `EntityDefinitions::ApplyFromRequirements`:
  - create one customer-owned entity
  - related set Student + Course + association → bridge with two `EntityReference` attrs + additional attribute
  - update when name matches live customer-owned
  - rollback on missing associated target, self-association, EntityReference in fill, bridge name proposal, inactive collision, quota exceeded
  - never writes `customer_id` of another tenant; never writes shared / `customer_id` NULL
  - rollup in same turn after bridge exists
- `SpeechToText::Activities::Reply`:
  - chat envelope → no Entity change
  - apply envelope → entities persisted, assistant body includes names
  - parse failure → failed assistant, no Entity change
  - vendor failure → existing reply_failed, no Entity change
- Rename: every former `NestedEntity` production/spec/doc check uses `Entity::ENTITY_REFERENCE_TYPE` / `"EntityReference"`. Existing bridge, rollup, page populator, SaveAll, join specs still pass.
- I18n: every new user-facing string in both `en` and `zh-CN`.
- No new JS expected. If JS comments/docs-only, skip Vitest. If JS logic changes, 100% Vitest on touched files.

## Out of scope

- Auto-rendering or generating Pages, Flowcharts, Constants
- Creating entity entries from conversation
- Shared entity create/update/override via assistant
- Member or public assistant
- Desktop GUI
- New attribute/association kinds beyond what the form already supports
- Data migration for old `NestedEntity` JSON
- Replacing the maintenance entity form
- New HTTP routes
