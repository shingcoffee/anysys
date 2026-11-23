# Send Activity Detail Links + Templates Index UX

**Date:** 2026-07-25  
**Status:** Draft for review  
**Surfaces:**
- `GET /:cid/admin/modules/emails/send_activities/:id` (detail)
- `GET /:cid/admin/modules/emails/templates` (index)

## Goal

1. Make template and audience-list links on the send activity detail page obviously clickable (pill/chip style).
2. Make the email templates index more professional: visual polish **and** a richer primary column + Editor field + clearer row actions.

## Non-goals

- No schema / model changes (no “last used” column).
- No card-grid layout for templates (stay on `AdminTableComponent` for consistency with Lists / Send Activities).
- No new preview HTTP API beyond what exists (member `POST preview` is workspace AJAX only).
- No Figma redesign if the Figma MCP is unavailable — match existing AdminPage / chip / table patterns (same override used for recent email wizard work).

## Decisions (approved)

| Topic | Choice |
|-------|--------|
| Detail-page links | Pill / chip links (wizard list-chip language) |
| Templates index | Visual polish + richer index (A + B) |
| Primary column | Stack **Name + Subject** |
| New column | **Editor** (`rich_text` / `code`) |
| Keep | Status badge, Updated, Versions, status transitions |

## 1. Send activity detail — chip links

### Current

Template and each list use `class: "text-primary hover:underline"` and open in a new tab.

### Target

- Render each linked resource as a **chip link**:
  - Classes aligned with wizard list chips: e.g. `inline-flex items-center gap-1 px-2 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded border border-blue-200 hover:bg-blue-100 transition-colors`
  - Keep `target: "_blank"` and `rel: "noopener noreferrer"`
- Multiple lists: wrapping flex row of chips (not a plain `<ul>` of text links).
- Missing template / empty lists: unchanged em-dash / empty handling.
- Prefer inline markup in `show.html.erb` (or a tiny partial under send_activities) — two call sites on one page do not require a shared ViewComponent yet.

### Acceptance

- Template name and every list name are visually distinct chips.
- Chips remain keyboard-focusable links and open the correct admin destination in a new tab.
- Request specs that assert link `href` / `target` continue to pass (update selectors if they assume bare text links).

## 2. Templates index — professional table

### Columns (left → right)

| Key | Label | Behavior |
|-----|-------|----------|
| `name` (primary) | Template (I18n) | **Name** as the primary row link text; **Subject** muted on a second line under the name. Keep subject searchable (resolver still knows about subject — either retain searchable metadata for subject without a visible column, or keep subject in `columns` as searchable alongside the stacked display). |
| `editor_type` | Editor | I18n via existing `admin_modules.emails.templates.form.editor_types.*` |
| `status` | Status | Existing badge |
| `updated_at` | Updated | Existing datetime |

Drop the standalone visible **Subject** column (subject moves under the name).

### Primary cell rendering

`AdminTableComponent` currently stringifies cells and wraps column 0 in `link_to`. Do **not** inject HTML from the controller via `html_safe`.

**Preferred approach:** extend `AdminTableComponent` with an optional column option:

```ruby
subtitle: ->(row) { row.subject }
```

When present, render name (existing link styling) with subject underneath as `text-xs text-text-muted truncate`. Mobile card layout gets the same subtitle under the primary value.

### Row actions

Order:

1. **Edit** — `edit_admin_modules_emails_template_path`
2. **Preview** — deep-link to the edit workspace preview tab, e.g. `edit_..._path(..., tab: "preview")`, **only if** the workspace tabs honor a `tab` query param (add minimal wiring if missing). If deep-link is not feasible in this slice, omit Preview from index actions and keep Preview on the edit workspace only (do not fake a GET against `POST preview`).
3. **Versions** — existing `versions#open` (unchanged)
4. Existing **status transition** actions

Row click → Edit (unchanged `row_path`).

### Visual polish

- Clearer primary column hierarchy (name strong / subject muted).
- Editor column uses short I18n labels (already present for the form).
- Page chrome (`AdminPageComponent`, content tabs, empty state, New Template CTA) unchanged aside from any new column/action I18n keys.

### I18n

- New keys only where English UI text would otherwise be hard-coded (e.g. column header “Template”, “Editor”, action “Preview” if not reusable).
- Reuse `common.actions.edit`, existing editor type labels, and versions nav label where possible.
- Both `en` and `zh-CN` required for any new key.

## 3. Testing

- **Request:** send activities show — chip markup / `target="_blank"` for template + lists.
- **Request:** templates index — Editor label, stacked subject presence, Edit (+ Preview if shipped), Versions still present.
- **Component:** `AdminTableComponent` coverage for `subtitle:` on desktop + mobile.
- Vitest only if Stimulus tab deep-link JS is added/changed (100% on touched files).

## 4. Auth / tenancy

- No new routes or authorization changes beyond existing admin module guards.
- Preview deep-link (if any) remains on the existing edit action (already tenant-scoped).

## Out of scope follow-ups

- “Last used in send activity” column (needs data model).
- Shared `ResourceChipLinkComponent` extraction.
- Card directory layout for templates.
