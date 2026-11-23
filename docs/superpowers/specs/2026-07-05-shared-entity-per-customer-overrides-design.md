# Shared Entity — Per-Customer Definition Overrides

**Date:** 2026-07-05
**Status:** Approved design, pending implementation plan
**Scope:** Shared **entities** only (shared Flowcharts may adopt the same mechanism later; Pages are always customer-specific and out of scope)

## Problem

A **shared** entity (`Entity#type_shared?`, `customer_id = NULL`) exposes one global definition to every tenant. Today only the platform owner may edit it, and every customer sees the same definition. We want a customer to be able to tailor a shared entity's definition for their own tenant **without** affecting other tenants or the global default.

Requirement:

- When a customer edits a shared entity, it creates/updates a **customer-specific override version** of that entity (the global default is untouched).
- When retrieving a shared entity's definition:
  - **(a)** if the current customer has **no** override → use the shared entity's **global default** version.
  - **(b)** if the current customer **has** an override → use **that customer's current override version** (customer override takes precedence over the global default).

## Approved decisions

1. **Write model** — the platform owner (customer `81721200`) editing a shared entity writes the **global default** version (`customer_id NULL`). Any other customer's admin editing that shared entity writes **that customer's override**. This relaxes the current "only the platform owner may edit shared entities" rule; **AGENTS.md is updated to match.**
2. **Override lifecycle** — an override is a **pinned fork**: once a customer overrides, they keep seeing their own current override even when the platform owner ships new global-default versions. A customer can **Reset to default**, which removes their override and makes reads fall back to the global default.
3. **Scope** — shared **entities** only. The mechanism is built into the shared `Versionable` concern generically (via an opt-in reflection) so shared Flowcharts can adopt it later, but Flowchart is **not** wired in this pass (YAGNI).

## Current architecture (baseline)

- `Versionable` concern: a parent is a HEAD via `current_version_id`; the definition body lives only in version rows; payloads live in a content-addressed store. `after_save :autocommit_version_snapshot` commits body changes; `after_find` → `reload_definition_from_head!` repopulates the virtual definition attributes from `current_version.content.payload`.
- `entity_versions`: `entity_id`, `customer_id`, `version_number` (unique `[entity_id, version_number]`), `content_id`, `based_on_version_id`. A version's `customer_id` is copied from the parent, so a shared entity's versions are all `customer_id = NULL`.
- `entity_definition_contents`: content-addressed payloads, unique `[customer_id, content_hash]`.
- Auth: `guard_shared_write!` blocks non-platform-owner writes to shared entities. `Authentication::User::PLATFORM_CUSTOMER_ID == 81721200`. `Current.customer_id` is request-scoped.

## Chosen approach: per-customer head pointer (same entity row)

The entity remains **one row with a stable id**; only *which version's definition is resolved* varies by `Current.customer`. This keeps `entity_entries` and every id/slug-keyed consumer (palette, association graph, code generators) working untouched — the alternative of forking into a separate `customer_specific` Entity row was rejected because entries are keyed by `entity_id` and a fork gets a new id, breaking the entry↔definition link. A per-customer JSON blob was rejected because it abandons versioning (no history/restore/content-addressing).

### 1. Schema

New table `entity_customer_heads`:

| Column | Type | Notes |
|---|---|---|
| `id` | pk | |
| `entity_id` | integer, NN | FK → entities |
| `customer_id` | integer, NN | the overriding customer |
| `current_version_id` | integer, NN | FK → entity_versions (that customer's head) |
| `created_at` / `updated_at` | datetime | |

Indexes: unique `[entity_id, customer_id]`; index `[current_version_id]`.

`entity_versions` unique index change (NULL-safe, per-line numbering) — replace the single `unique [entity_id, version_number]` with two **partial** unique indexes:

- `unique [entity_id, version_number] WHERE customer_id IS NULL` — global default line
- `unique [entity_id, customer_id, version_number] WHERE customer_id IS NOT NULL` — per-customer override lines

The global default head stays in `entities.current_version_id`. Override versions are `entity_versions` rows with `customer_id = C`.

### 2. Read resolution

Add to `Versionable` (generic, opt-in per resource):

```
resolved_current_version(customer_id = Current.customer_id)
  → if this resource supports customer heads AND type_shared?
       AND customer_id present AND customer_id != PLATFORM_CUSTOMER_ID:
         head = customer_head_for(customer_id)   # entity_customer_heads row
         return head.current_version if head
    return current_version                       # global default
```

`reload_definition_from_head!` reads from `resolved_current_version.content.payload` instead of `current_version.content.payload`. Because it runs on `after_find` (request-scoped), `Current.customer` is set: a shared entity loaded in customer C's context resolves C's override; the platform customer and null/background contexts resolve the global default.

Resolution is a pure function of `(row, Current.customer)`; no cross-request memoization (`Current` is per-request; rows reload per request).

### 3. Write (commit)

`commit_version!` / `autocommit_version_snapshot` become customer-aware **for shared resources that support customer heads**:

- **Editing customer is global** (`Current.customer_id` nil or `== PLATFORM_CUSTOMER_ID`, or resource not shared): unchanged — create a version with the parent's `customer_id`, advance `entities.current_version_id`.
- **Editing customer is a regular customer C** on a shared entity: create a version with `customer_id = C`, `version_number` sequential within C's line, and advance C's `entity_customer_heads` row (create it if absent). The global default is untouched.

No-op guard compares against the **resolved** head for that customer (re-saving an identical override is a no-op). `prune_versions!` scopes per `(entity, customer)` line so one customer's history can't evict another's or the global's. `content_class.sweep_orphans!` continues to GC unreferenced content.

### 4. Reset-to-default

`reset_customer_override!(customer_id)`:

1. delete the `entity_customer_heads` row for `(entity, C)`
2. destroy this entity's `entity_versions` where `customer_id = C`
3. `sweep_orphans!` for content no longer referenced

Reads for C then fall back to the global default. Exposed via a controller action + a "Reset to default" button, visible only when the current customer has an override on a shared entity.

### 5. Authorization

- `guard_shared_write!`: allow a **non-owner admin** to write a shared entity (routed to the override path). Platform owner still writes the global default. Members remain blocked (admin-only controller).
- Ownership/tenant isolation: override versions carry `customer_id = C`; read resolution filters by `Current.customer_id`; `reset` only touches C's own rows. No cross-tenant leakage.
- Shared entities keep the **no-associations** rule (`shared_entity_has_no_associations`) — overrides are schema-only (property_schema, attribute_groups, default_properties, icon/color/description, referenced_template). This avoids bridge-materialization complexity on a per-customer fork.
- The unversioned columns `category` and `extended_model` remain single-valued on the shared row and are **not** per-customer overridable (they are not part of the versioned definition body).

### 6. Edge cases

- **Customer with no override reads** → global default (rule a).
- **Platform owner reads/writes** → always the global default.
- **Customer overrides, then platform owner ships new global default** → customer stays pinned to their override (rule b + pinned-fork lifecycle).
- **Customer resets** → override removed, falls back to global default.
- **Shared entity deleted / soft-deleted** → its override heads/versions cascade (`dependent: :destroy`).
- **Background/no-`Current.customer` context** (jobs, code generation) → global default.

## Testing

- **Model/concern:** `resolved_current_version` for (no override → global) and (override → customer head); commit branching (owner→global vs customer→override) leaves the other untouched; `reset_customer_override!` removes only C's rows and content; `prune_versions!` isolation across customer lines; NULL-safe version numbering.
- **Request:** platform owner PATCH → global default advances; customer admin PATCH → only their override advances; a second customer reading sees the global default; reset falls back. Cross-tenant isolation (customer B cannot see/reset customer A's override).
- Keep multi-tenant isolation and existing versioning specs green.

## Out of scope

- Shared Flowchart overrides (mechanism built generic; wiring deferred).
- Per-customer overrides of `category` / `extended_model` (unversioned identity columns).
- Field-level merge / live-follow of the global default (rejected in favor of pinned fork).
- Associations on shared entities (still disallowed).
