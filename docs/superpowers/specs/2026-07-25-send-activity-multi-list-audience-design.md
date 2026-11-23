# Send Activity Multi-List Audience

**Date:** 2026-07-25  
**Status:** Approved design (pending implementation plan)  
**Module:** Email — Send Activities

## Summary

Allow a send activity (new and edit) to target **multiple** audience lists. The effective audience is the **union** of selected lists (static and dynamic may be mixed), **deduped by normalized email** so each address receives at most one message per send.

## Goals

- Multi-select lists on the send-activity wizard Audience step (create + edit).
- Hard cap: **at most 10 lists** per send activity (client + server enforced).
- Mix static lists and dynamic segments in one send.
- Deduplicate recipients by email (`LOWER(TRIM(email))`).
- Persist associations in a normalized join table (no JSON list-id blob, no hidden combined list).
- Remove the single `email_list_id` column after migrating existing rows (no compatibility shim).
- On the send-activity **detail (show)** page, template name and each list name are links that open in a **new tab**.

## Non-goals

- Contacts tab / contacts index changes.
- Signup forms, CSV import, or new contact sources.
- Per-list analytics breakdown for a multi-list send.
- Keeping `email_list_id` as a public API after migration.

## Current state

- `email_send_activities.email_list_id` — single optional FK, validated present on the model.
- Wizard Audience step: single `collection_select` on `email_list_id`.
- `SendActivityJob` fans out via `campaign.email_list.audience.find_each`.
- Recurring clone in `StartSendActivity` copies `email_list:`.

## Approach

**Join table** (`email_send_activity_lists`) linking send activities to many lists. Audience resolution and the send job use a single `SendActivity#audience` API.

### Rejected alternatives

- **JSON `email_list_ids` column** — weaker integrity, awkward reporting.
- **Auto-create a hidden combined static list** — hides data, freezes dynamic segments incorrectly, ownership noise.

## Data model

### New table: `email_send_activity_lists`

| Column | Type | Notes |
|--------|------|--------|
| `id` | integer PK | |
| `email_send_activity_id` | integer NOT NULL | FK → `email_send_activities` |
| `email_list_id` | integer NOT NULL | FK → `email_lists` |
| `created_at` / `updated_at` | datetime NOT NULL | |

Indexes:

- Unique `(email_send_activity_id, email_list_id)`
- Index on `email_list_id`

### Migration sequence

1. Create `email_send_activity_lists`.
2. Backfill: for each `email_send_activities` row with non-null `email_list_id`, insert a join row.
3. Remove `email_list_id` (index + FK) from `email_send_activities`.

### Model associations & validations

- `Emails::SendActivities::SendActivity`
  - `has_many :send_activity_lists` (join model), `dependent: :destroy`
  - `has_many :email_lists, through: :send_activity_lists`
  - Validate at least one `email_list` on save (replace `validates :email_list_id, presence: true`)
  - Validate at most **10** associated lists (`MAX_EMAIL_LISTS = 10` constant on the model)
  - Validate every list shares `customer_id` with the activity (replace single-list tenant check)
- Join model `Emails::SendActivities::SendActivityList` (table `email_send_activity_lists`)
  - `belongs_to :send_activity` / `belongs_to :email_list`
  - Uniqueness of `[email_send_activity_id, email_list_id]`

No reader/writer shim for `email_list` / `email_list_id` after the column drop. Call sites update in the same change.

## Audience resolution

### API

- `SendActivity#audience` → enumerable/relation of `Authentication::User` suitable for `find_each` (or batched equivalent).
- `SendActivity#audience_count` → integer unique-recipient count using the same rules.

### Algorithm

1. For each linked list:
   - static → `list.users` (via memberships)
   - dynamic → `Emails::Audience::SegmentQuery.call(customer:, rules: list.segment_rules)`
2. Union all matched users.
3. Deduplicate by normalized email: `LOWER(TRIM(email))`.
4. Tie-break when multiple users share an email: keep the row with the **lowest `user_id`**.
5. Evaluate dynamic lists at call time (send / count / review), not at wizard save.

### Send pipeline

- `SendActivityJob` uses `campaign.audience` instead of `campaign.email_list.audience`.
- Existing per-campaign idempotency (`already_sent_user_ids` via message metadata `user_id`) remains; after email dedupe, at most one user id per address is in the audience iterator.
- `StartSendActivity.ready_to_send?` requires template present and **at least one** associated list.
- Recurring next occurrence copies **all** join rows (all list associations), not a single FK.

## Wizard & UI

Applies to **new** and **edit**.

### Audience step

- Replace single-select with a **multi-select** of tenant lists (static + dynamic together).
- Form param: `email_send_activity[email_list_ids][]`.
- Require ≥1 and ≤10 lists (client wizard validation + server model validation).
- Multi-select UI prevents selecting an 11th list (disable further picks / show localized max-lists error).
- Keep refresh-lists control and “create list” link; refresh reloads options and **preserves** current selections.
- Stimulus: update `email_send_activity_wizard_controller.js` to validate multi-select (min 1, max 10) and refresh multi options; no hard-coded UI strings (Values + `data-*` from server). Maintain 100% Vitest coverage.

### Review step

- Show selected list names.
- Show **unique recipient count** from the same `#audience_count` resolver.

### Index / show

- Index: display associated lists (comma-separated names and/or count), not a single list column.
- **Show (detail) page:**
  - Template name is a link to the template show/edit surface; `target="_blank"` + `rel="noopener noreferrer"`.
  - Each list name is a link to that list’s show page; same new-tab attributes.
  - Links only for records the admin can open in-tenant; missing/deleted associations render as plain text (or em dash), not a broken link.

### Design system

- Figma first for multi-select Audience control and review summary, then implement with existing ViewComponent + Tailwind + Stimulus patterns.
- All new copy: I18n `en` + `zh-CN`.

### Persist / build

- `Emails::SendActivities::Build` (and controller strong params) accept `email_list_ids`, replace join rows on save (clear + recreate, or sync set).
- Reject unknown / cross-tenant list ids.

## Error handling

- Empty list selection → validation error on the activity (localized).
- More than 10 lists → validation error on the activity (localized); do not silently truncate.
- Cross-tenant or missing list id → rejected; do not silently skip.
- Malformed dynamic segment rules continue to behave as today’s list audience path (invalid/empty contribution rather than crashing the whole send); document behavior in implementation if SegmentQuery already surfaces errors.

## Testing

- Migration: existing single-list activities become one join row; null `email_list_id` rows get no join rows.
- Model: presence of ≥1 list; rejection of >10 lists; tenant isolation on associations.
- Audience: union of static + dynamic; email dedupe; lowest `user_id` tie-break.
- Job: one queued/sent message per unique email when user appears on multiple selected lists.
- Recurring: clone copies all list associations.
- Request: create/update with multiple `email_list_ids` (incl. 10 ok / 11 rejected); edit re-renders selections.
- Show page: template and each list render as new-tab links to the correct paths.
- Component/wizard + Vitest: multi-select required + max-10 validation; refresh preserves selection.
- Locale parity for new keys (incl. max-lists error).

## Success criteria

1. Admin can select multiple lists (1–10) on `/admin/modules/emails/send_activities/new` and edit.
2. Selecting an 11th list is blocked in the UI and rejected by the server.
3. Static and dynamic lists may be mixed.
4. A contact on two selected lists receives exactly one email for that send.
5. Two different users with the same email yield one recipient (lowest id).
6. Existing single-list activities keep working after migration via the join table.
7. No remaining production reads of `email_send_activities.email_list_id`.
8. On the send-activity detail page, template and list names open their respective pages in a new tab.
