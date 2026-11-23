# Add Attribute Modal — Full UX Redesign Spec

**Date:** 2026-06-04
**Author:** UX Designer (anysys-ux-designer)
**Surface:** `app/views/admin/maintenance/entities/_attribute_modal.html.erb`
**Nav area:** Maintenance / Modules (`/:cid/admin/maintenance/entities/*`)
**Audience:** `admin` and `owner` roles only

---

## 1. Surface Inventory

| Surface | Nav Area | File |
|---------|----------|------|
| Add Attribute modal (new + edit) | Maintenance / Modules — Entity builder page | `_attribute_modal.html.erb` |

The modal is rendered inline inside the entity form (`_form.html.erb`) and toggled by the `entity-form` Stimulus controller. No routing change. No new surfaces.

---

## 2. Overall Layout Decisions

### 2a. Modal panel width

**Current:** `max-w-xl` (36rem)
**Redesigned:** `max-w-2xl` (42rem)

Rationale: the Name/Display Label pair and the Name Slug/HTML Type pair are 4 short fields that currently stack vertically and waste space. Widening to 2xl lets them sit in a responsive 2-column grid on `sm:` breakpoints, cutting the body scroll height significantly and making the modal feel less cramped.

### 2b. Body section grouping and order

The redesign groups the 8 current fields into 5 named sections. **Field order within each group is unchanged.** Only wrapper markup and visual grouping is added.

| Section | Fields Contained |
|---------|-----------------|
| **Basics** | Name, Display Label (2-col grid on sm+), then Name Slug, HTML Type (2-col grid on sm+) |
| **Field Configuration** | optionsSection (selectionConfig + fileConfig) — only shown conditionally |
| **Validation** | validatorsContainer chips, modalValidatorSelect + add button, validatorConfigSection sub-panel |
| **Visibility** | Admin / Member / Public checkboxes |
| **Notes** | Description textarea |

### 2c. Section header treatment

Each section uses a lightweight divider pattern — NOT a heavy card border. The pattern is:

```
<div class="flex items-center gap-2 mb-3">
  <span class="text-label text-text-muted uppercase tracking-wider">Section Name</span>
  <div class="flex-1 h-px bg-border-subtle"></div>
</div>
```

This uses only design-token classes (`text-label`, `text-text-muted`, `bg-border-subtle`) and produces a subtle rule-with-label header that matches the visual style used in the versions modal and the admin table headers.

### 2d. Responsive column grid for Basics

On mobile (`< sm`), all fields stack. On `sm:` and up, fields pair up:

- Row 1: Name (left col) + Display Label (right col)
- Row 2: Name Slug (left col, readonly) + HTML Type (right col, select)

Grid classes: `grid grid-cols-1 sm:grid-cols-2 gap-4`

---

## 3. ASCII Mockup

The mockup shows the `sm:` (2-column) layout. The modal renders at `max-w-2xl`. Conditional sections are collapsed by default.

```
┌─────────────────────────────────────────────────────────────────┐
│  HEADER                                              [X] close  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  [■] icon   Add Attribute                                  │ │
│  │             Define a new field for this entity type        │ │
│  └────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│  BODY (scrollable, px-6 py-5 space-y-6)                        │
│                                                                 │
│  BASICS ─────────────────────────────────────────────────────   │
│                                                                 │
│  ┌──────────────────────────┐  ┌──────────────────────────┐    │
│  │ Name *                   │  │ Display Label *           │    │
│  │ ┌────────────────────┐   │  │ ┌────────────────────┐   │    │
│  │ │                    │   │  │ │                    │   │    │
│  │ └────────────────────┘   │  │ └────────────────────┘   │    │
│  └──────────────────────────┘  └──────────────────────────┘    │
│                                                                 │
│  ┌──────────────────────────┐  ┌──────────────────────────┐    │
│  │ Name Slug                │  │ HTML Type *               │    │
│  │ ┌────────────────────┐   │  │ ┌────────────────────┐   │    │
│  │ │ auto-generated  ░░░│   │  │ │ Text ▾             │   │    │
│  │ └────────────────────┘   │  │ └────────────────────┘   │    │
│  │ Derived automatically    │  │                           │    │
│  └──────────────────────────┘  └──────────────────────────┘    │
│                                                                 │
│  FIELD CONFIGURATION ──────────────────────────────────────   │
│  (hidden by default; shown when HTML Type is select/file)      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  bg-canvas-elevated, rounded-xl, border-border-subtle   │   │
│  │                                                         │   │
│  │  [Manual Entry]  [ Use Constant ]  ← segmented toggle   │   │
│  │                                                         │   │
│  │  -- Manual section --                                   │   │
│  │  Each row is one selectable value.                      │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ options list (JS-rendered rows)                  │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │  [+ Add Option]                                         │   │
│  │                                                         │   │
│  │  -- Constant section (hidden) --                        │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ Select a constant... ▾                           │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │  ┌── Constant Preview (hidden) ─────────────────────┐   │   │
│  │  │  Options Preview          [3 options]            │   │   │
│  │  │  [opt1] [opt2] [opt3]                            │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  │  -- File Config (hidden) --                             │   │
│  │  Accepted File Types: [.pdf,.jpg,.png          ]        │   │
│  │  [ ] Allow multiple files                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  VALIDATION ──────────────────────────────────────────────    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ (chips appear here as validators are added)             │   │
│  │ bg-canvas-elevated rounded-lg border-border-subtle      │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐ ┌─────────────┐  │
│  │ Presence (required)                    ▾ │ │  [+] Add    │  │
│  └──────────────────────────────────────────┘ └─────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Validator config sub-panel (hidden)                     │   │
│  │ bg-canvas-elevated rounded-xl border-border-subtle      │   │
│  │  Single / Range / Pattern / List variants               │   │
│  │  ─────────────────────────────────────────────────────  │   │
│  │  [Cancel]  [Add Validator]            footer actions    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  VISIBILITY ──────────────────────────────────────────────    │
│                                                                 │
│  [✓] Admin    [✓] Member    [✓] Public                    │
│                                                                 │
│  NOTES ───────────────────────────────────────────────────    │
│                                                                 │
│  Description (optional)                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  FOOTER                                                         │
│  bg-canvas-elevated rounded-b-xl border-t border-border-subtle  │
│                               [Cancel]  [Add Attribute]         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Exact Tailwind Classes — Region by Region

### 4a. Modal overlay + panel shell

```
<!-- Overlay (unchanged) -->
class="hidden fixed inset-0 overflow-y-auto z-[60]"

<!-- Backdrop (unchanged) -->
class="fixed inset-0 bg-text-primary/60 transition-opacity"

<!-- Centering wrapper (unchanged) -->
class="flex min-h-full items-center justify-center p-4"

<!-- Panel — CHANGE max-w-xl -> max-w-2xl, add animate-scale-in -->
class="relative bg-surface rounded-xl shadow-float w-full max-w-2xl flex flex-col max-h-[90vh] animate-scale-in"
```

### 4b. Modal header (redesigned)

The header gains an icon badge (matching the versions modal pattern) and a helper subtext line beneath the title. The close button becomes an `icon-button` (design-system class).

```html
<div class="flex-none px-6 py-4 border-b border-border-subtle">
  <div class="flex items-start justify-between gap-3">

    <!-- Icon + title + subtext group -->
    <div class="flex items-start gap-3">
      <!-- Icon badge: accent-subtle bg, accent icon -->
      <span class="hidden sm:flex h-9 w-9 shrink-0 items-center justify-center
                   rounded-lg bg-accent-subtle text-accent">
        <!-- cube / layers SVG — see icon note below -->
      </span>
      <div>
        <h3 class="section-header"
            id="modal-title"
            data-entity-form-target="modalTitle">Add Attribute</h3>
        <p class="text-caption mt-0.5">Define a new field for this entity type</p>
      </div>
    </div>

    <!-- Close button: icon-button class -->
    <button type="button"
            data-action="click->entity-form#closeModal"
            class="icon-button shrink-0"
            aria-label="Close modal">
      <svg class="w-4 h-4" ...> <!-- X path --> </svg>
    </button>

  </div>
</div>
```

**Icon to use in the badge:** a "layers" or "tag" icon (24x24, stroke-width 1.75). Suggested SVG path:
`M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5` (layers icon from heroicons).

### 4c. Modal body

```
class="flex-1 overflow-y-auto px-6 py-5 space-y-6"
```

(spacing increased from `space-y-5` to `space-y-6` to give sections more breathing room.)

### 4d. Section divider headers

Reuse exactly this pattern for each of the 5 sections:

```html
<div class="flex items-center gap-2 mb-3">
  <span class="text-label">BASICS</span>
  <div class="flex-1 h-px bg-border-subtle"></div>
</div>
```

Labels (all uppercase, matching `text-label` which already sets `uppercase` and `tracking-wider`):
- `BASICS`
- `FIELD CONFIGURATION`
- `VALIDATION`
- `VISIBILITY`
- `NOTES`

### 4e. Basics section — responsive 2-col grid

```html
<!-- Section wrapper -->
<div>
  <!-- Section header (divider pattern) -->

  <!-- Two-column grid: Name + Display Label -->
  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
    <div>
      <label class="form-label-required">Name</label>
      <input type="text"
             data-entity-form-target="modalName"
             data-action="input->entity-form#updateAttributeNameSlug"
             class="input-field mt-1">
    </div>
    <div>
      <label class="form-label-required">Display Label</label>
      <input type="text"
             data-entity-form-target="modalDisplayLabel"
             data-action="input->entity-form#markDisplayLabelEdited"
             class="input-field mt-1">
    </div>
  </div>

  <!-- Two-column grid: Name Slug + HTML Type -->
  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-4">
    <div>
      <label class="form-label">Name Slug</label>
      <input type="text"
             data-entity-form-target="modalNameSlug"
             readonly
             tabindex="-1"
             class="input-field mt-1 bg-surface-active text-text-muted cursor-not-allowed"
             placeholder="Auto-generated from name">
      <p class="mt-1 text-caption">Derived automatically — not editable</p>
    </div>
    <div>
      <label class="form-label-required">HTML Type</label>
      <select data-entity-form-target="modalHtmlType"
              data-action="change->entity-form#htmlTypeChanged"
              class="input-field mt-1">
        <!-- optgroups unchanged -->
      </select>
    </div>
  </div>
</div>
```

### 4f. Field Configuration section (optionsSection)

The outer container `optionsSection` remains, with updated wrapper classes for tighter visual containment:

```
data-entity-form-target="optionsSection"
class="hidden rounded-xl border border-border-subtle bg-canvas-elevated overflow-hidden"
```

Remove the `transition-all duration-200 ease-in-out` from this outer div (leave animation to JS toggling `hidden`). The inner sections keep their `p-4 space-y-4` padding.

**Segmented toggle — improved active-state contrast:**

The active button currently uses `text-accent bg-canvas-elevated border border-accent/30 shadow-sm` which can be hard to distinguish at a glance. Change to a stronger active state:

Active button:
```
class="flex-1 px-3 py-1.5 text-sm font-medium rounded-md transition-base
       text-accent-text bg-accent-subtle border border-accent shadow-sm"
```

Inactive button:
```
class="flex-1 px-3 py-1.5 text-sm font-medium rounded-md transition-base
       text-text-muted bg-transparent border border-transparent hover:bg-surface-active"
```

Note: `text-accent-text` is `#4338ca` (stronger than `text-accent` which is `#6366f1`). The `bg-accent-subtle` + `border-accent` combination gives an unmistakable filled-pill active look.

**The toggle wrapper** (group container):
```
class="flex gap-1 p-1 bg-surface border border-border-subtle rounded-lg"
```
(unchanged)

**Constant Preview sub-card** — add `mt-1` to the badge to give it micro-spacing:
```
class="rounded-lg border border-border-subtle bg-surface p-3 space-y-2"
```
(unchanged, already well-styled)

### 4g. Validation section

The validator chips container gains an explicit min-height and a placeholder hint when empty:

```
data-entity-form-target="validatorsContainer"
class="flex flex-wrap gap-1.5 min-h-[2.5rem] p-2 rounded-lg border border-border-subtle bg-canvas-elevated"
```

The dropdown + add button row is unchanged:
```html
<div class="flex gap-2 mt-2">
  <select data-entity-form-target="modalValidatorSelect"
          data-action="change->entity-form#validatorSelectChanged"
          class="input-field flex-1">
    <!-- optgroups unchanged -->
  </select>
  <button type="button"
          data-action="click->entity-form#addValidator"
          class="flex-none px-3 py-2 text-accent bg-canvas-elevated border border-accent/40
                 rounded-lg hover:bg-surface-active hover:border-accent/70 transition-base"
          title="Add validator">
    <!-- + SVG unchanged -->
  </button>
</div>
```

**Validator config sub-panel** — remove the `transition-all duration-200 ease-in-out` (let JS handle show/hide without fighting the `hidden` class):

```
data-entity-form-target="validatorConfigSection"
class="hidden rounded-xl border border-border-subtle bg-canvas-elevated overflow-hidden mt-2"
```

Sub-panel footer (Cancel / Add Validator) — unchanged:
```
class="flex justify-end gap-2 px-4 py-3 bg-surface border-t border-border-subtle"
```

### 4h. Visibility section

Add a subtle helper beneath the label:

```html
<div>
  <label class="form-label-required">Visibility</label>
  <p class="text-caption -mt-1 mb-2">Choose who can see this attribute on records.</p>
  <div class="flex flex-wrap items-center gap-5">
    <label class="flex items-center gap-2 text-sm text-text-primary cursor-pointer">
      <input type="checkbox"
             checked
             data-entity-form-target="modalVisibilityAdmin"
             class="w-4 h-4 text-accent border-border-subtle rounded focus:ring-accent">
      <span>Admin</span>
    </label>
    <label class="flex items-center gap-2 text-sm text-text-primary cursor-pointer">
      <input type="checkbox"
             checked
             data-entity-form-target="modalVisibilityMember"
             class="w-4 h-4 text-accent border-border-subtle rounded focus:ring-accent">
      <span>Member</span>
    </label>
    <label class="flex items-center gap-2 text-sm text-text-primary cursor-pointer">
      <input type="checkbox"
             checked
             data-entity-form-target="modalVisibilityPublic"
             class="w-4 h-4 text-accent border-border-subtle rounded focus:ring-accent">
      <span>Public</span>
    </label>
  </div>
</div>
```

### 4i. Notes section (Description)

```html
<div>
  <label class="form-label">
    Description
    <span class="text-text-muted font-normal text-xs">(optional)</span>
  </label>
  <textarea data-entity-form-target="modalDescription"
            rows="2"
            class="input-field mt-1 resize-none"
            placeholder="Describe what this attribute represents..."></textarea>
</div>
```

(unchanged content; new section header wrapper added above it)

### 4j. Modal footer

Add `sm:justify-end` to ensure right-alignment is explicit:

```html
<div class="flex-none px-6 py-4 bg-canvas-elevated rounded-b-xl border-t border-border-subtle
            flex items-center justify-end gap-3">
  <button type="button"
          data-action="click->entity-form#closeModal"
          class="btn btn-secondary">
    Cancel
  </button>
  <button type="button"
          data-action="click->entity-form#addAttributeFromModal"
          data-entity-form-target="modalSubmitBtn"
          class="btn btn-primary">
    Add Attribute
  </button>
</div>
```

---

## 5. Complete Section Structure (frontend developer builds in this order)

```
[modal overlay wrapper]   data-entity-form-target="modal"
  [backdrop div]           data-action="click->entity-form#closeModal"
  [centering wrapper]
    [panel div]            max-w-2xl, animate-scale-in

      -- HEADER --
        icon badge (hidden on mobile, sm:flex)
        h3[data-entity-form-target="modalTitle"]
        subtext p.text-caption
        button[data-action="click->entity-form#closeModal"] .icon-button

      -- BODY --  flex-1 overflow-y-auto px-6 py-5 space-y-6

        == Section: BASICS ==
          section divider header
          grid 2-col (sm+): Name + Display Label
            input[data-entity-form-target="modalName"
                  data-action="input->entity-form#updateAttributeNameSlug"]
            input[data-entity-form-target="modalDisplayLabel"
                  data-action="input->entity-form#markDisplayLabelEdited"]
          grid 2-col (sm+): Name Slug + HTML Type
            input[data-entity-form-target="modalNameSlug" readonly]
            select[data-entity-form-target="modalHtmlType"
                   data-action="change->entity-form#htmlTypeChanged"]

        == Section: FIELD CONFIGURATION ==
          section divider header
          div[data-entity-form-target="optionsSection" class="hidden ..."]

            div[data-entity-form-target="selectionConfig" class="hidden p-4 space-y-4"]
              segmented toggle:
                button[data-action="click->entity-form#selectManualOptions"
                       data-entity-form-target="manualOptionsBtn"]
                button[data-action="click->entity-form#selectConstantOptions"
                       data-entity-form-target="constantOptionsBtn"]

              div[data-entity-form-target="manualOptionsSection"]
                div[data-entity-form-target="optionsContainer"]
                button[data-action="click->entity-form#addOption"]

              div[data-entity-form-target="constantOptionsSection" class="hidden"]
                select[data-entity-form-target="constantSelect"
                       data-action="change->entity-form#constantChanged"]
                div[data-entity-form-target="constantPreview" class="hidden"]
                  span[data-entity-form-target="constantOptionsCount"]
                  div[data-entity-form-target="constantPreviewList"]

            div[data-entity-form-target="fileConfig" class="hidden p-4 space-y-4"]
              input[data-entity-form-target="configAccept"]
              input[type="checkbox" data-entity-form-target="configMultiple"]

        == Section: VALIDATION ==
          section divider header
          div[data-entity-form-target="validatorsContainer"]
          div.flex.gap-2
            select[data-entity-form-target="modalValidatorSelect"
                   data-action="change->entity-form#validatorSelectChanged"]
            button[data-action="click->entity-form#addValidator"]
          div[data-entity-form-target="validatorConfigSection" class="hidden ..."]
            div[data-entity-form-target="validatorSingleValueConfig" class="hidden"]
              span[data-entity-form-target="validatorConfigLabel"]
              input[data-entity-form-target="validatorConfigValue"
                    data-action="keydown->entity-form#handleValidatorConfigKeydown"]
            div[data-entity-form-target="validatorRangeConfig" class="hidden"]
              input[data-entity-form-target="validatorConfigMinValue"
                    data-action="keydown->entity-form#handleValidatorConfigKeydown"]
              input[data-entity-form-target="validatorConfigMaxValue"
                    data-action="keydown->entity-form#handleValidatorConfigKeydown"]
            div[data-entity-form-target="validatorPatternConfig" class="hidden"]
              input[data-entity-form-target="validatorConfigPattern"
                    data-action="keydown->entity-form#handleValidatorConfigKeydown"]
            div[data-entity-form-target="validatorListConfig" class="hidden"]
              span[data-entity-form-target="validatorListLabel"]
              textarea[data-entity-form-target="validatorConfigList"
                       data-action="keydown->entity-form#handleValidatorConfigKeydown"]
            sub-panel footer:
              button[data-action="click->entity-form#cancelValidatorConfig"] .btn.btn-secondary
              button[data-action="click->entity-form#addValidatorWithConfig"] .btn.btn-primary

        == Section: VISIBILITY ==
          section divider header
          helper subtext p.text-caption
          flex row:
            input[type="checkbox" data-entity-form-target="modalVisibilityAdmin"]
            input[type="checkbox" data-entity-form-target="modalVisibilityMember"]
            input[type="checkbox" data-entity-form-target="modalVisibilityPublic"]

        == Section: NOTES ==
          section divider header
          textarea[data-entity-form-target="modalDescription"]

      -- FOOTER --
        button[data-action="click->entity-form#closeModal"] .btn.btn-secondary
        button[data-action="click->entity-form#addAttributeFromModal"
               data-entity-form-target="modalSubmitBtn"] .btn.btn-primary
```

---

## 6. Preserve Verbatim — Mandatory Checklist

The frontend developer MUST verify each item below remains on the exact same logical element after the rebuild. Dropping or relocating any of these will silently break the Stimulus controller.

### Targets (data-entity-form-target)

- [ ] `modal` — on the outermost `div` (the overlay)
- [ ] `modalTitle` — on the `h3` inside the header
- [ ] `modalName` — on the Name `input`
- [ ] `modalDisplayLabel` — on the Display Label `input`
- [ ] `modalNameSlug` — on the Name Slug `input` (readonly)
- [ ] `modalHtmlType` — on the HTML Type `select`
- [ ] `optionsSection` — on the outer conditional config wrapper `div`
- [ ] `selectionConfig` — on the selection-options inner `div` (keeps `data-config-type="selection"`)
- [ ] `manualOptionsBtn` — on the Manual Entry toggle `button`
- [ ] `constantOptionsBtn` — on the Use Constant toggle `button`
- [ ] `manualOptionsSection` — on the manual options container `div`
- [ ] `optionsContainer` — on the JS-rendered options list `div`
- [ ] `constantOptionsSection` — on the constant reference `div`
- [ ] `constantSelect` — on the constant reference `select`
- [ ] `constantPreview` — on the preview card `div`
- [ ] `constantOptionsCount` — on the badge `span`
- [ ] `constantPreviewList` — on the preview chips wrapper `div`
- [ ] `fileConfig` — on the file upload inner `div` (keeps `data-config-type="file"`)
- [ ] `configAccept` — on the accepted file types `input`
- [ ] `configMultiple` — on the allow-multiple `input[type="checkbox"]`
- [ ] `validatorsContainer` — on the chips container `div`
- [ ] `modalValidatorSelect` — on the validator `select`
- [ ] `validatorConfigSection` — on the validator config sub-panel outer `div`
- [ ] `validatorSingleValueConfig` — on the single-value config `div`
- [ ] `validatorConfigLabel` — on the label `span` inside single-value config
- [ ] `validatorConfigValue` — on the single-value number `input`
- [ ] `validatorRangeConfig` — on the range config `div`
- [ ] `validatorConfigMinValue` — on the min `input`
- [ ] `validatorConfigMaxValue` — on the max `input`
- [ ] `validatorPatternConfig` — on the custom regex config `div`
- [ ] `validatorConfigPattern` — on the regex `input`
- [ ] `validatorListConfig` — on the list config `div`
- [ ] `validatorListLabel` — on the label `span` inside list config
- [ ] `validatorConfigList` — on the list `textarea`
- [ ] `modalVisibilityAdmin` — on the Admin `input[type="checkbox"]`
- [ ] `modalVisibilityMember` — on the Member `input[type="checkbox"]`
- [ ] `modalVisibilityPublic` — on the Public `input[type="checkbox"]`
- [ ] `modalDescription` — on the Description `textarea`
- [ ] `modalSubmitBtn` — on the Add Attribute `button` in the footer

Total: **39 targets**

### Actions (data-action)

- [ ] `click->entity-form#closeModal` — on the backdrop `div`, the header close `button`, and the footer Cancel `button` (three elements)
- [ ] `input->entity-form#updateAttributeNameSlug` — on the Name `input`
- [ ] `input->entity-form#markDisplayLabelEdited` — on the Display Label `input`
- [ ] `change->entity-form#htmlTypeChanged` — on the HTML Type `select`
- [ ] `click->entity-form#selectManualOptions` — on the Manual Entry toggle `button`
- [ ] `click->entity-form#selectConstantOptions` — on the Use Constant toggle `button`
- [ ] `click->entity-form#addOption` — on the Add Option `button`
- [ ] `change->entity-form#constantChanged` — on the constant `select`
- [ ] `change->entity-form#validatorSelectChanged` — on the validator `select`
- [ ] `click->entity-form#addValidator` — on the add-validator icon `button`
- [ ] `keydown->entity-form#handleValidatorConfigKeydown` — on all four validator config inputs/textarea (`validatorConfigValue`, `validatorConfigMinValue`, `validatorConfigMaxValue`, `validatorConfigPattern`, `validatorConfigList`)
- [ ] `click->entity-form#cancelValidatorConfig` — on the sub-panel Cancel `button`
- [ ] `click->entity-form#addValidatorWithConfig` — on the sub-panel Add Validator `button`
- [ ] `click->entity-form#addAttributeFromModal` — on the footer Add Attribute `button`

Total: **14 distinct action bindings**

### Attribute pass-throughs (non-target, non-action)

- [ ] `class="hidden"` must remain the initial class on: `optionsSection`, `selectionConfig`, `constantOptionsSection`, `constantPreview`, `fileConfig`, `validatorConfigSection`, `validatorSingleValueConfig`, `validatorRangeConfig`, `validatorPatternConfig`, `validatorListConfig`
- [ ] `data-config-type="selection"` on the `selectionConfig` div
- [ ] `data-config-type="file"` on the `fileConfig` div
- [ ] `readonly` and `tabindex="-1"` on `modalNameSlug` input
- [ ] `checked` default on all three visibility checkboxes
- [ ] `rows="3"` on `validatorConfigList` textarea
- [ ] `rows="2"` on `modalDescription` textarea
- [ ] `class="font-mono"` on `validatorConfigPattern` input (monospace rendering)
- [ ] `class="resize-none"` on both textareas
- [ ] `min="0"` on `validatorConfigMinValue` and `validatorConfigMaxValue` inputs

---

## 7. Component Reuse Map

| Element | Reuse / New |
|---------|-------------|
| Modal overlay + centering wrapper | Inline ERB (no component) — unchanged |
| Panel shell | Inline ERB — class tweak only (`max-w-2xl`, `animate-scale-in`) |
| Header | Inline ERB — matches `VersionsModalComponent` header pattern |
| Icon badge in header | Inline SVG — matches `VersionsModalComponent` header icon badge |
| `icon-button` close button | Inline — uses existing `.icon-button` design-system class |
| Section divider headers | Inline ERB — new micro-pattern, reuse `text-label` + `bg-border-subtle` |
| Responsive 2-col grid | Tailwind grid utility — no component needed |
| `input-field`, `form-label`, etc. | Existing design-system component classes |
| `btn`, `btn-primary`, `btn-secondary` | Existing design-system component classes |
| `badge`, `badge-accent` | Existing design-system component classes |
| `text-caption`, `text-label`, `text-text-muted` | Existing typography utilities |
| Validator config sub-panel | Inline ERB — minor class updates only |

No new ViewComponents are required. This is a pure ERB markup + Tailwind-class change to one partial.

---

## 8. Tailwind Utilities Quick Reference

| Region | Key Utilities |
|--------|---------------|
| Panel | `bg-surface rounded-xl shadow-float w-full max-w-2xl flex flex-col max-h-[90vh] animate-scale-in` |
| Header | `flex-none px-6 py-4 border-b border-border-subtle` |
| Header icon badge | `hidden sm:flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-accent-subtle text-accent` |
| Header title | `section-header` (existing token) |
| Header subtext | `text-caption mt-0.5` |
| Header close btn | `icon-button shrink-0` (existing token) |
| Body | `flex-1 overflow-y-auto px-6 py-5 space-y-6` |
| Section divider | `flex items-center gap-2 mb-3` + `text-label` + `flex-1 h-px bg-border-subtle` |
| Basics grid | `grid grid-cols-1 sm:grid-cols-2 gap-4` |
| Basics second grid row | same + `mt-4` |
| Config sub-card | `rounded-xl border border-border-subtle bg-canvas-elevated overflow-hidden` |
| Config sub-card inner | `p-4 space-y-4` |
| Segmented toggle active | `text-accent-text bg-accent-subtle border border-accent shadow-sm` |
| Segmented toggle inactive | `text-text-muted bg-transparent border border-transparent hover:bg-surface-active` |
| Validators chips container | `flex flex-wrap gap-1.5 min-h-[2.5rem] p-2 rounded-lg border border-border-subtle bg-canvas-elevated` |
| Validator sub-panel | `hidden rounded-xl border border-border-subtle bg-canvas-elevated overflow-hidden mt-2` |
| Validator sub-panel footer | `flex justify-end gap-2 px-4 py-3 bg-surface border-t border-border-subtle` |
| Footer | `flex-none px-6 py-4 bg-canvas-elevated rounded-b-xl border-t border-border-subtle flex items-center justify-end gap-3` |

---

## 9. Stimulus Notes

No new Stimulus controller is needed. No existing controller code changes are needed as part of this redesign (that is a separate concern addressed in the 2026-06-03 bug-fix spec).

The redesign is purely structural ERB + CSS. The JS controller discovers its targets and actions by `data-entity-form-target` / `data-action` scanning; as long as the checklist in section 6 is satisfied, the controller will work without modification.

The only two JS-visible behavior changes caused by the markup changes:
1. Modal panel is wider (`max-w-2xl`). The controller positions nothing relative to the panel, so no JS impact.
2. Segmented toggle active/inactive classes differ. The controller calls `classList.add/remove` on these buttons using hardcoded class strings. The developer must cross-check `entity_form_controller.js` (specifically `selectManualOptions` and `selectConstantOptions` methods) and update the toggled class list to match the new active/inactive class sets defined in section 4f. This is a one-line change per method inside the JS controller — flag it for the frontend developer.

---

## 10. States

| State | Appearance |
|-------|-----------|
| Empty validators container | `min-h-[2.5rem]` ensures the container has visible height; JS can optionally inject a muted placeholder text |
| No constants loaded | `constantSelect` shows "Select a constant..." placeholder option; `constantPreview` stays `hidden` |
| Edit mode | `modalTitle` textContent changes to "Edit Attribute" (controller responsibility); submit button label changes to "Save Changes" (controller responsibility) — no markup change |
| Loading (future) | No loading state defined in current controller; out of scope |
| Validation error | Current behavior (inline JS alerts or native browser validation) unchanged; no new error UI |

---

## 11. Responsive Behavior Summary

| Breakpoint | Modal width | Basics grid | Icon badge |
|------------|-------------|-------------|------------|
| `< sm` (< 640px) | `w-full` (fills viewport with `p-4` margin) | 1 column, all fields stacked | Hidden |
| `sm:` (640px+) | up to `max-w-2xl` (42rem) | 2 columns | Visible |
| `md:` and up | same as sm | same | Visible |

The modal body is always scrollable (`overflow-y-auto`) so even on small phones all fields remain reachable regardless of content height.
