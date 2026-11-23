# Entity attribute: visibility gates validator apply

**Date:** 2026-08-05  
**Status:** Approved for planning  
**Surface:** Admin Maintenance → Entities → Add / Edit Attribute modal

## Problem

The Add / Edit Attribute modal exposes two independent per-audience toggles:

- **Visible** (`visibility[admin|member|public]`)
- **Apply validators** (`validator_apply[admin|member|public]`)

It is possible today to mark an attribute not Visible for an audience while still leaving Apply validators on. That is incoherent: a hidden field should not run validators for that audience.

## Decisions

| Question | Choice |
|----------|--------|
| UI when Visible is unchecked | Auto-uncheck **and disable** Apply validators (option A) |
| UI when Visible is re-checked | Always turn Apply validators **on** (option B) |
| Enforcement layers | UI + save normalize + runtime contract (option C) |

## Invariant

For each audience `a ∈ {admin, member, public}`:

```text
if visibility[a] == false then validator_apply[a] must be false
```

Equivalently at runtime: validators apply for audience `a` only when the field is Visible for `a` **and** `validator_apply[a]` is not explicitly false.

Missing `validator_apply` continues to mean "apply to all audiences" **only where Visible is true** (visibility still wins).

## UI behavior (Add / Edit Attribute modal)

Matrix per audience row:

| Visible | Apply validators |
|---------|------------------|
| Unchecked | Unchecked + **disabled** (not clickable) |
| Checked (flipped from off → on) | Enabled + **checked** |
| Checked (already on) | Enabled; user may freely uncheck Apply |

Sync runs when:

1. User toggles a Visible checkbox
2. Modal open / reset for a new attribute
3. Prefill for edit — if stored data has `visibility=false` and `validator_apply=true`, UI shows Apply unchecked + disabled; the next save persists the coerced false

No new columns. Optional copy hint is out of scope unless a one-line i18n tip is added later; not required for this change.

## Save normalize (JavaScript)

When collecting the attribute from the modal (and when writing row hidden inputs), coerce:

```text
for each audience:
  if visibility[audience] == false → validator_apply[audience] = false
  else → keep Apply checkbox value
```

Preferred shape: a shared helper (e.g. `SchemaManager.coerceValidatorApply(visibility, apply)`) used by `AttributeManager.collectValidatorApply()` so `data-attr-validator-apply` / hidden inputs never persist `apply=true` with `visible=false`.

View-modal rendering should coerce Apply badges the same way so stale rows do not show "Apply" for a hidden audience until the next save.

## Runtime (Ruby)

Extend `EntityEntryContract.validators_apply_for_audience?`:

1. If attribute `visibility[audience] == false` → return false (skip all validators for that audience), even when `validator_apply` is missing or true (legacy / inconsistent JSON safety net).
2. Else keep today's `validator_apply` gate: missing/blank → apply; explicit `false` → skip.

Audience-nil builds (activities that do not pass `audience:`) stay backward-compatible: no audience gate runs.

## Out of scope

- Changing how entry forms hide non-visible fields
- Restoring per-validator audience toggles
- Redesigning the visibility matrix layout (hiding the Apply cell instead of disabling it)

## Touch points

| Layer | Files |
|-------|--------|
| Modal UI | `attribute_modal_component.html.erb` — `data-action` on Visible inputs |
| Stimulus | `entity_form_controller.js`, `entity_form/modal_manager.js` — sync helper on change / reset / prefill |
| Collect / coerce | `entity_form/attribute_manager.js`, `entity_form/schema_manager.js` |
| View badges | `entity_form/template_builder.js` (coerce when rendering Apply badges) |
| Contract | `app/contracts/entity_entry_contract.rb` |

## Tests

| Layer | Coverage |
|-------|----------|
| Vitest | Visible off → Apply unchecked + disabled; Visible on → Apply enabled + checked; collect / coerce rejects inconsistent state; prefill syncs disabled state |
| RSpec contract | `visibility.public=false` skips validators for `:public` even when `validator_apply.public=true` or `validator_apply` missing |
| Component (optional) | Visible checkboxes wire the change action |

## Success criteria

1. User cannot enable Apply validators while Visible is off in the modal.
2. Turning Visible back on checks Apply validators.
3. Saved attribute JSON never has `validator_apply[a]=true` with `visibility[a]=false`.
4. Entry validation skips validators for hidden audiences regardless of stored `validator_apply`.
