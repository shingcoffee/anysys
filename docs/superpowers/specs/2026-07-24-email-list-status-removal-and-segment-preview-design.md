# Email list: remove Status + Dynamic Segment preview

**Date:** 2026-07-24  
**Status:** Approved for planning  
**Scope:** Audience lists (`Emails::Audience::List`) under Email module

## Problem

Audience lists still expose an `active` / `archived` **Status** field that is noise for the lean ESP: campaigns already filter on `status: "active"`, and archiving is unused product surface. Operators also cannot verify whom a **Dynamic Segment** will match while creating or editing a list — they only see a count after save on the show page.

## Goals

1. Fully remove list **Status** (schema, model, UI, campaign picker filter).
2. On list **create/edit**, when type is Dynamic Segment, let the admin **Preview** the query result as a **full paginated member table** against the **unsaved** segment rules.

## Non-goals

- Soft-archive or any Status replacement.
- Auto/debounced preview as rules change.
- Adding a member browser to the list **show** page in this slice (show keeps type + audience count only).
- Changing segment rule AST, FieldCatalog, or SegmentQuery semantics beyond calling them for preview.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Status removal depth | **Full** — drop DB column; no UI; campaigns list all tenant lists |
| Preview contents | **Full paginated table** (email, first name, last name) |
| Preview trigger | **Explicit Preview button** (not auto-refresh) |
| Architecture | **Dedicated collection POST** `…/lists/preview` returning HTML into a Turbo Frame |

## Section 1 — Remove Status

### Schema

- Migration: remove `email_lists.status` and index `index_email_lists_on_customer_id_and_status`.
- No data backfill required; column is discarded.

### Model

- Remove `STATUSES`, `validates :status`, and `scope :active` from `Emails::Audience::List`.
- Factories/specs stop setting or asserting `status`.

### Controllers / callers

- Lists controller: stop permitting `:status`; stop defaulting `status: "active"` on `new`.
- Campaigns controller (and any other list pickers): replace  
  `Emails::Audience::List.for_current_customer.where(status: "active")`  
  with  
  `Emails::Audience::List.for_current_customer` (ordered as today).

### UI

- Index: drop Status column from `@columns`.
- Form: remove Status select.
- Show: remove Status card; keep Type + Audience count.

### I18n

- Remove unused `admin_modules.emails.lists.form.statuses.*` keys (en + zh-CN) if nothing else references them.

### Retirement semantics

- Lists are available for campaigns until destroyed.
- Destroy remains restricted when campaigns reference the list (`restrict_with_exception`).

## Section 2 — Dynamic Segment preview

### Route

```
POST /:customer_id/admin/modules/emails/lists/preview
```

- Collection action on `Admin::Modules::Emails::ListsController#preview`.
- Same auth stack as other lists actions (admin/owner + email campaigns feature guard).
- No list id required — works for both create and edit before save.

### Request

- `segment_rules_json` (string) **or** already-parsed rules hash.
- Pagination: `page`, `per_page` (via existing ModuleEntriesResolver conventions).
- Optional: `q` / sort only if cheap to wire; **not required** for v1 — default order by email is enough.

### Server behavior

1. Parse `segment_rules_json`; on `JSON::ParserError` render the Turbo Frame with an i18n error (HTTP 422).
2. `relation = Emails::Audience::SegmentQuery.call(customer: current_customer, rules: rules)`.
3. Resolve columns + pagination with `ModuleEntriesResolver` (same pattern as Contacts/Lists index).
4. Render a partial into Turbo Frame `email_list_preview`:
   - Heading + total match count (`relation` / resolver total).
   - `AdminTableComponent` with columns: email, first_name, last_name.
   - Empty state when zero matches.

### Blank rules

- Do **not** special-case empty rules. Current `SegmentQuery` behavior applies (may match all tenant users). Preview shows that result paginated.

### Static lists

- Preview button + frame are **hidden** when list type is Static (existing `email-list-form` panel toggle).
- Endpoint may still be called; it only evaluates posted rules for the current customer (safe). No requirement to 403 on static.

### UI placement

On create/edit form, inside the Dynamic Segment panel (below `SegmentBuilderComponent`):

- **Preview** button (i18n).
- Turbo Frame `email_list_preview` (initially empty or a short hint).

### Client behavior

- Extend `email-list-form` Stimulus (or a small dedicated controller mounted on the same form) to:
  - Read current `email_list[segment_rules_json]` from the segment builder hidden input.
  - `POST` to the preview URL targeting the Turbo Frame (fetch / Turbo stream / `turbo-frame` form — prefer Turbo Frame request so pagination stays in-frame).
  - Not submit the outer create/update form.
- Pagination links inside the frame must re-post (or otherwise carry) the current rules so page 2+ still reflects the unsaved AST. Prefer a mini form inside the frame that includes a hidden `segment_rules_json` copy, or Stimulus that intercepts pagination and re-POSTs with the live builder JSON.

### Security

- Always scope through `current_customer` / `SegmentQuery` tenant root.
- No cross-tenant list id; no user PII beyond what Contacts index already exposes to the same admin role.
- FieldCatalog whitelist remains the only path into SQL (unchanged).

## Section 3 — I18n, errors, tests

### I18n (en + zh-CN)

Required keys (en + zh-CN parity):

| Key | Purpose |
|-----|---------|
| `admin_modules.emails.lists.preview.button` | Preview button label |
| `admin_modules.emails.lists.preview.heading` | Preview panel heading |
| `admin_modules.emails.lists.preview.match_count` | Match count (`%{count}`) |
| `admin_modules.emails.lists.preview.empty_title` | Empty state title |
| `admin_modules.emails.lists.preview.empty_description` | Empty state description |
| `admin_modules.emails.lists.preview.malformed` | Malformed rules error in frame |
| `admin_modules.emails.lists.preview.hint` | Initial empty-frame hint (optional but preferred) |

All Stimulus UI copy via `default:` Values + server `data-*-value` if any JS strings are needed.

### Tests

| Layer | Coverage |
|-------|----------|
| Migration / model | Status gone; list valid without status; factory green |
| Request lists | Create/update without status; index/show/form omit Status |
| Request campaigns | List picker includes lists that would have been archived |
| Request preview | Matching rows for tenant rules; empty matches; malformed JSON → error in frame; other-tenant users never appear |
| JS (Vitest) | Preview posts into frame; static/dynamic panel still toggles; **100%** lines/branches on touched controllers |
| Locales | en / zh-CN key parity for new strings |

### Out of scope (reconfirmed)

- Show-page member table
- Auto-preview
- Status/archive replacement

## Architecture sketch

```
[List form — Dynamic panel]
  SegmentBuilder → hidden segment_rules_json
  [Preview] → Stimulus POST
       ↓
  ListsController#preview
       ↓
  SegmentQuery(customer, rules) → Relation
       ↓
  ModuleEntriesResolver → AdminTableComponent
       ↓
  Turbo Frame email_list_preview (HTML + pagination)
```

## Success criteria

1. No Status field anywhere in list UX or schema; campaigns can target any tenant list.
2. On new/edit Dynamic Segment, Preview shows a paginated table of matching contacts for the current (unsaved) rules.
3. Preview never leaks other tenants' users.
4. Specs and Vitest coverage for touched JS are green at required thresholds.
