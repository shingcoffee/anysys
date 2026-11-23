# Distribution Card — Visibility Radio Group UX Spec

Date: 2026-06-11
Status: Ready for frontend implementation
Related design: docs/superpowers/specs/2026-06-11-page-visibility-hierarchy-design.md

---

## 1. Surface Inventory

| Surface | Component | Nav area |
|---------|-----------|----------|
| "Audience & Distribution" card on page detail | `Pages::DistributionCardComponent` | Maintenance / Modules (`/:cid/admin/maintenance/pages/:id`) |

This spec covers only the card redesign. The page chrome (breadcrumbs, header, `PageInfoCardComponent`) is unchanged.

---

## 2. Layout Spec

### Overall card structure (unchanged chrome)

The card wrapper, header region, and footer "Save" row are preserved exactly as they exist today. Only the three audience rows change internally — checkboxes become radio buttons, the column header changes, and the hint copy reflects hierarchy.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Audience & Distribution                          [card header]      │
│  Who can open this page once published…           [subhead]          │
├─────────────────────────────────────────────────────────────────────┤
│  [sm+] Audience                  Visibility    Open   [col labels]   │
├─────────────────────────────────────────────────────────────────────┤
│  ● Admin     Admins and owners…  ( radio )     [Open / disabled]    │
├─────────────────────────────────────────────────────────────────────┤
│  ● Member    Members and admins  ( radio )     [Open / disabled]    │
├─────────────────────────────────────────────────────────────────────┤
│  ● Public    Everyone…           ( radio )     [Open / disabled]    │
├─────────────────────────────────────────────────────────────────────┤
│                                         [Save visibility]  [footer] │
└─────────────────────────────────────────────────────────────────────┘
```

### Column header row

Keep the existing `hidden sm:grid sm:grid-cols-[1fr_auto_auto]` row. Change the centre column label from "Visible" to "Level" (or keep "Visible" — both are acceptable; "Level" better matches the radio semantics). Width classes `w-20` are unchanged.

```erb
<%# Column labels — visible sm+ — CHANGE ONLY THE CENTRE LABEL %>
<div class="hidden sm:grid sm:grid-cols-[1fr_auto_auto] gap-x-6 px-6 pt-3 pb-1">
  <span class="text-caption text-text-muted">Audience</span>
  <span class="text-caption text-text-muted text-center w-20">Level</span>
  <span class="text-caption text-text-muted w-20">Open</span>
</div>
```

### Audience row — element breakdown

Each of the three rows uses the same `grid grid-cols-1 sm:grid-cols-[1fr_auto_auto]` layout the current template already employs. The only column that changes is Col 2 (checkbox → radio).

**Col 1 — Audience identity (unchanged structure, updated hint copy)**

```
[dot] Admin
      Admins and owners of this customer      ← HINTS["admin"] unchanged
```

```
[dot] Member
      Members and admins                      ← UPDATED copy (was "Signed-in members...")
      ℹ Requires an active member session…   ← info note REMOVED (see §2.3)
```

```
[dot] Public
      Everyone, including anonymous visitors  ← UPDATED copy
```

Tailwind: `flex items-start gap-3 min-w-0` / dot `w-2 h-2 rounded-full flex-shrink-0 mt-1.5` with existing dot classes (`bg-accent` / `bg-member-accent` / `bg-success`).

**Col 2 — Radio button (replaces checkbox)**

All three radios share the same `name="page[visibility]"`. The `value` for each row is the level key (`"admin"` / `"member"` / `"public"`). One radio is `checked` when `page.visibility == key`.

No hidden-field trick is needed (radios always send the selected value; the controller validates inclusion).

```erb
<div class="sm:text-center sm:w-20">
  <label class="flex sm:justify-center items-center gap-2 cursor-pointer">
    <input type="radio"
           name="page[visibility]"
           value="<%= item[:key] %>"
           <%= "checked" if item[:checked] %>
           class="h-4 w-4 border-border text-accent focus:ring-accent shrink-0">
    <span class="form-label mb-0 sm:hidden">Level</span>
  </label>
</div>
```

Tailwind for the radio itself: `h-4 w-4 border-border text-accent focus:ring-accent shrink-0`
— these are the identical utility values used by the existing checkbox. The accent ring colour matches the existing design vocabulary.

**Col 3 — Open link / disabled state (unchanged markup, new enablement logic)**

The existing markup for the enabled and disabled states is preserved verbatim. Only the Ruby-side `enabled` boolean and `disabled_reason` string change (handled in `audiences_with_rows`, not in the template). The template's `if item[:enabled]` branch remains.

### Info note on Member row

The current ERB has a `ℹ Requires an active member session to open.` note hardcoded under the Member row. This note was a compensatory hint for the old confusion where an admin couldn't open that link. Now that the controller bypass lets admins open it, the note is no longer needed. Remove it. If a note is desired in future, it can be re-introduced, but for this redesign the row should be clean.

### Save affordance

The existing form uses `form_with … method: :patch` and an explicit `f.submit "Save visibility", class: "btn btn-primary"` in a footer row. This pattern is kept unchanged — no auto-submit, no Stimulus. The user must click "Save visibility" to apply a new radio selection. This is consistent with other card-level forms in the project.

Footer row (unchanged):
```
<div class="px-6 py-4 bg-canvas-elevated rounded-b-xl flex justify-end">
  <%= f.submit "Save visibility", class: "btn btn-primary" %>
</div>
```

---

## 3. Updated Hint Copy

The hint text must make the hierarchy legible without jargon.

| Row | `HINTS[key]` new value |
|-----|------------------------|
| admin | `"Admin only — visible to admins and owners"` |
| member | `"Members — visible to signed-in members and admins"` |
| public | `"Public — visible to everyone, including anonymous visitors"` |

These strings live in the Ruby constant `HINTS` inside `DistributionCardComponent`. The copy makes the "includes the levels above" relationship obvious at a glance.

---

## 4. Component Ruby-Side Changes (`audiences_with_rows`)

The method signature and return shape are preserved. Only the values change:

| Key | Old `checked` | New `checked` |
|-----|--------------|---------------|
| `"admin"` | `page.visible_to?("admin")` | `page.visibility == "admin"` |
| `"member"` | `page.visible_to?("member")` | `page.visibility == "member"` |
| `"public"` | `page.visible_to?("public")` | `page.visibility == "public"` |

`enabled` and `disabled_reason` for each row follow the new enablement matrix (see §5).

No new instance variables, no new helper methods beyond what exists.

---

## 5. Open-Link Enablement Matrix

This matrix determines `item[:enabled]` and `item[:disabled_reason]` for each row.

| Row | Enabled condition | Disabled reason (when not enabled) |
|-----|-------------------|-------------------------------------|
| Admin | `page.published?` | `"Not published"` |
| Member | `page.published? && page.visible_to?("member")` | `"Not published"` if not published; `"Not visible to Member"` if published but level is admin-only |
| Public | `page.published? && page.visible_to?("public") && page.public_token.present?` | `"Not published"` if not published; `"Not visible to Public"` if published but level is below public |

Note: `page.visible_to?("member")` returns true when `page.visibility` is `"member"` or `"public"`. `page.visible_to?("public")` returns true only when `page.visibility == "public"`. This falls naturally out of the new `visible_to?` hierarchy implementation described in the design doc.

The `not_published` / `not_visible` logic in `audiences_with_rows` becomes:

```ruby
# Admin row
disabled_reason = "Not published" unless page.published?

# Member row
disabled_reason = if !page.published?
                    "Not published"
                  elsif !page.visible_to?("member")
                    "Not visible to Member"
                  end

# Public row
disabled_reason = if !page.published?
                    "Not published"
                  elsif !page.visible_to?("public")
                    "Not visible to Public"
                  end
```

---

## 6. Interaction Flow

### Happy path — change from Admin only to Public

```
Starting URL:  /:cid/admin/maintenance/pages/:id

1. Admin views distribution card.
   - Current radio: "Admin only" selected.
   - Member row Open link: disabled ("Not visible to Member").
   - Public row Open link: disabled ("Not visible to Public").

2. Admin clicks the "Public" radio bullet.
   - UI updates selection (native radio behaviour, no JS needed).

3. Admin clicks "Save visibility".
   - PATCH /:cid/admin/maintenance/pages/:id/visibility
   - param: page[visibility]=public

4. Controller processes, page redirects back to show.
   - Flash: "Visibility updated."
   - Distribution card reloads: "Public" radio checked.
   - Member Open link: enabled (btn-ghost with open icon).
   - Public Open link: enabled (btn-ghost with open icon).
```

### Failure — invalid param (direct POST attack / stale form)

```
PATCH with page[visibility]=unknown_value
→ Contract validation fails
→ Redirect back with flash error: "Visibility is not valid"
→ Card shows previously saved level
```

### Failure — unpublished page, any row Open link

```
All three Open links disabled.
Admin row:  XCircle icon + "Not published"
Member row: XCircle icon + "Not published"
Public row: XCircle icon + "Not published"
```

### Failure — published, Admin-only level

```
Admin row:  enabled (btn-ghost "Open")
Member row: EyeSlash icon + "Not visible to Member"
Public row: EyeSlash icon + "Not visible to Public"
```

### Failure — published, Member level

```
Admin row:  enabled (btn-ghost "Open")
Member row: enabled (btn-ghost "Open")  ← admin can now open this thanks to controller bypass
Public row: EyeSlash icon + "Not visible to Public"
```

---

## 7. Responsive Stacking Behaviour

The existing responsive grid (`grid-cols-1 sm:grid-cols-[1fr_auto_auto]`) is preserved unchanged.

**Mobile (< sm, < 640px)**

- Column labels hidden (existing `hidden sm:grid` wrapper).
- Each row stacks vertically: audience identity block → radio label ("Level" text visible inline next to radio) → Open link/disabled state below.
- The inline `sm:hidden` span on the radio label reads "Level" on mobile, matching the existing pattern where checkboxes showed "Visible" inline.

**Tablet / Desktop (≥ sm, ≥ 640px)**

- Three-column grid: audience identity fills remaining width; radio centred in `w-20` column; Open link in `w-20` column.
- Column label "Level" appears above the radio column.
- Radios are centred (`sm:justify-center`) in their column.

No breakpoint changes beyond what the current template already defines.

---

## 8. Component Reuse Map

| Element | Component / pattern |
|---------|---------------------|
| Card chrome (header, divider, footer) | Existing `Pages::DistributionCardComponent` card skeleton — no change |
| Column label row | Inline HTML in the same template — update centre label text only |
| Audience identity col (dot, label, hint) | Same markup; update `HINTS` constant values in `.rb` |
| Visibility col | Replace `<input type="checkbox">` with `<input type="radio">` — identical Tailwind classes |
| Open link (enabled) | Existing `btn btn-ghost` pattern — no change |
| Open link (disabled) | Existing inline-flex muted span — no change |
| Save footer | Existing `f.submit "btn btn-primary"` — no change |

No new ViewComponent is needed. No new Stimulus controller is needed (none exists today, and the radio-group interaction is pure native HTML — a single radio `name` group enforces mutual exclusivity natively).

---

## 9. Tailwind & Stimulus Notes

**Tailwind utilities (no changes from current)**

All utility classes are inherited from the current template:

- Card: `card overflow-hidden`
- Header: `px-6 py-4 border-b border-border-subtle`
- Section heading: `section-header`
- Subhead: `text-body-sm text-text-muted mt-0.5`
- Row: `px-6 py-4` with `grid grid-cols-1 sm:grid-cols-[1fr_auto_auto] gap-x-6 gap-y-3 sm:items-center`
- Dot: `w-2 h-2 rounded-full flex-shrink-0 mt-1.5` + level-specific colour
- Radio input: `h-4 w-4 border-border text-accent focus:ring-accent shrink-0`  (same as existing checkbox)
- Disabled state text: `inline-flex items-center gap-1.5 text-sm text-text-muted py-2`
- Footer: `px-6 py-4 bg-canvas-elevated rounded-b-xl flex justify-end`
- Save button: `btn btn-primary`

**Stimulus**

No Stimulus controller is needed. The radio group is a native HTML form element; mutual exclusivity is enforced by the shared `name` attribute. The form submits via the existing `PATCH` action on button click. No auto-submit on radio change is required.

---

## 10. States Reference Card

| Page state | Visibility level | Admin Open | Member Open | Public Open |
|------------|-----------------|------------|-------------|-------------|
| Unpublished | any | XCircle "Not published" | XCircle "Not published" | XCircle "Not published" |
| Published | admin | btn-ghost "Open" | EyeSlash "Not visible to Member" | EyeSlash "Not visible to Public" |
| Published | member | btn-ghost "Open" | btn-ghost "Open" | EyeSlash "Not visible to Public" |
| Published | public | btn-ghost "Open" | btn-ghost "Open" | btn-ghost "Open" |

XCircle icon = `M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z` (existing)
EyeSlash icon = existing path already in the template
