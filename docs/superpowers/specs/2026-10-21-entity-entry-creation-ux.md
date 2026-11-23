# Entity entry creation — UX design

**Date:** 2026-10-21 · **Status:** ready for builders · **Scope:** design only

Add a **Create Entry** action to each entity's admin entries browser, opening a schema-driven form that creates one primary `EntityEntry`. Course at `/81721200/admin/entities/60` is the concrete acceptance case. [Implementation plan](../plans/2026-10-21-entity-entry-creation.md).

## 1. Surface inventory and inspected conventions

| Surface | URL | Navigation area |
|---|---|---|
| Entries browser header | `/:cid/admin/entities/:id` | admin → Entities |
| New entry and validation rerender | `GET /:cid/admin/entities/:entity_id/entries/new`; failed POST to `/entries` | admin → Entities |

Inspected `AGENTS.md`, `.cursor/agents/anysys-ux-designer.md`, entity show/controller, sibling Authentication user and SMS contact new forms, `AdminPageComponent`, `CardComponent`, `ButtonComponent`, `FormErrorsComponent`, and `FormFields` controls. The current checkout has **no `Dashboard::PageHeaderComponent`**: reuse `AdminPageComponent`, the header shell used by entity show. Its action hashes support `label`, `path`, `variant`, `icon`, `class`, and form-bound submits.

Design reference: [shadcn/ui Field](https://ui.shadcn.com/docs/components/field), consulted directly because the plugin/skill tools are not exposed. Translate its Field → label/control/description/error and FieldSet → legend/group composition into ViewComponent and semantic HTML.

### Course schema, verified in development

Entity 60 is active, customer-owned and plain; its stored display label is `课程`. It has 14 writable fields and one derived field. Render this metadata, rather than embedding Course-specific wording or IDs in application code.

| Group, in stored order | Field slug → control | Required for admin |
|---|---|---|
| `identity` / 课程资料 | `offering_code` → text; `title` → text; `description` → textarea | offering_code, title |
| `teaching` / 教学安排 | `term`, `teacher_name` → text; `delivery_mode` → select; `schedule`, `location` → text; `starts_on`, `ends_on` → date; `status` → select | term, delivery_mode, status |
| `capacity` / 学分与名额 | `credits`, `capacity` → number | both |
| `internal` / 内部管理 | `internal_notes` → textarea | neither |

Defaults: `delivery_mode = "线下"`, `status = "筹备中"`. Choices come from `config.options`. `credits` allows zero; `capacity` must be an integer greater than zero. `internal_notes` is admin-visible despite being hidden from member/public audiences. Omit `enrolled_count` (`Computed`, `storage: computed`, `readonly: true`). The associated bridge (61) contributes no fields or writes.

## 2. Layout

### Entries browser

Keep the existing `AdminPageComponent` header and entries table. Put primary **+ Create Entry** first in the action array, followed by secondary **Export CSV**. Link to `new_admin_entity_entry_path(cid, entity)` with full-page navigation (`data-turbo-frame="_top"`). Both actions wrap below the title on mobile; use `min-h-11 w-full sm:w-auto` for comfortable targets. Creation remains discoverable when the table has no rows or a search has no matches.

The action applies to active, non-bridge entities. A directly visited new form explains unsupported schemas as specified below.

### New entry

One `AdminPageComponent(width: :narrow, wrap_title: true)` inside the existing dashboard layout. Breadcrumbs: **Entities** → entity display label (links back to entries) → **Create Entry**. Title: translated `Create Entry — %{name}`; description: translated `Add a new record to %{name}.`

```text
Entities / 课程 / Create Entry
Create Entry — 课程
Add a new record to 课程.

[Validation summary, only on failure]

┌ Card / fieldset: 课程资料 ──────────────────────────────┐
│ 开课编号 *                 课程名称 *                  │
│ [text                    ] [text                    ] │
│ schema description                                    │
│ 课程简介                                              │
│ [textarea spanning the group                        ] │
└───────────────────────────────────────────────────────┘
┌ Card / fieldset: 教学安排 ──────────────────────────────┐
│ Fields in schema order, short controls paired at md+  │
│ Dates paired; selects retain schema defaults          │
└───────────────────────────────────────────────────────┘
┌ Card / fieldset: 学分与名额 ────────────────────────────┐
│ 学分 * [number          ] 名额上限 * [number         ] │
└───────────────────────────────────────────────────────┘
┌ Card / fieldset: 内部管理 ──────────────────────────────┐
│ 内部备注 [textarea                                  ] │
└───────────────────────────────────────────────────────┘

                                [Create Entry] [Cancel]
```

- Body: `min-w-0 space-y-6`. Each group uses `CardComponent(padding: :none)` with an inner `fieldset` using `min-w-0 p-4 sm:p-6`; legend uses `text-base font-semibold text-text-primary`.
- Field grid: `grid grid-cols-1 gap-5 md:grid-cols-2`. Keep labels above controls at every breakpoint. Textareas, radio groups and multi-selects span `md:col-span-2`. Preserve schema/group order, omit groups with no writable fields, and give ungrouped fields a translated **Other fields** legend.
- Field: associated label, native input, escaped optional schema `description`, then inline error list. IDs are `entry_<slug>`, `entry_<slug>_help`, `entry_<slug>_errors`. Required status comes from admin-applicable presence validators, not merely the presence of a validator on another audience.
- Controls use dashboard `input-field` styling, `w-full min-w-0 min-h-11`, and existing text/border/focus tokens. Invalid state has a visible error border and error text; avoid color-only signaling.
- Footer is in normal document flow, with a top border and `flex flex-col gap-3 sm:flex-row sm:justify-end`; DOM and visual order are Create then Cancel, following the sibling SMS form. Both buttons use `w-full sm:w-auto min-h-11`. Cancel is a normal link to the entity's entries browser; Create is the form's only primary submit.
- No modal, wizard, autosave, extra creation modes, or dedicated Stimulus controller is needed. Ordinary Rails forms work without JavaScript.

## 3. States and interaction

| State/action | Outcome |
|---|---|
| Browser → Create Entry | GET new form; resolve the URL tenant's effective schema and show its allowed defaults. |
| Initial values | Use filtered `default_properties`; otherwise use static options marked default. Explicit defaults, including false/zero/empty, win. |
| Submit | POST `entry[data][<slug>]`; native browser validation may run, and server validation is authoritative. |
| Valid submission | Create one tenant-owned primary entry; 303 to `admin_entity_path(cid, entity)` with translated success flash. Existing table sorting normally shows the newest row first. |
| Invalid submission | 422 full-page `new` render; same values, errors and grouping. Keep explicit blanks, unchecked controls and empty selections; do not replace them with defaults. |
| Error presentation | Linked summary above cards, heading **Please correct the errors below.**; inline messages immediately below controls. Set `aria-invalid`, and link help/error IDs through `aria-describedby`. Summary uses `role="alert"`, `tabindex="-1"`, and autofocus on the 422 render; no initial field autofocus. |
| Invalid value cannot be represented by a native number/date input | Preserve the raw value; on that rerender use a text input for this field (numeric `inputmode` where appropriate), with the same label and inline error. Browser value sanitization must not make the attempt look blank. |
| Pending submit | Use existing Turbo submit behavior when available, with translated `data-turbo-submits-with` text and disabled submit during the request. Keep values visible. No vendor/loading panel. |
| Unsupported admin-visible writable field | Show a translated notice naming those fields, render supported fields for context, disable Create, and retain Cancel. POST also returns 422 with no write. No silent text fallback for unsupported semantics. |
| No writable controls | Show translated **No editable fields are available for this entity.**; disable Create and retain Cancel. |
| Cancel | Return to the entity browser without submitting. |
| Permission denied | Existing authentication/role/tenant responses; anonymous signs in, members and foreign admins are denied. Foreign/missing entities and bridge creation targets return 404. |
| Save failure | Same form, raw values and translated error summary; validation/model errors are mapped to schema labels. Unexpected exceptions follow normal error handling rather than exposing exception text. |

## 4. Supported input contract

The initial surface deliberately has a small explicit control map; omitted `html_type` means `text`.

| Schema `html_type` | Control / request shape |
|---|---|
| `text`, `search`, `tel`, `url` | `FormFields::TextFieldComponent`; scalar |
| `email` | `FormFields::EmailFieldComponent`; scalar |
| `textarea` | `FormFields::TextareaFieldComponent`; scalar |
| `number` | `FormFields::NumberFieldComponent`; scalar, no lossy coercion; `step: 1` for integer validation, otherwise `any` |
| `date` | `FormFields::DateFieldComponent`; blank or valid ISO date string |
| `select` | Native select with static `config.options`; scalar |
| `multi-select` | `FormFields::SelectFieldComponent(multiple: true)`; array of scalar choice values, including an explicit empty-array submission |
| `radio` | `FormFields::RadioFieldComponent`; static choices, one scalar; semantic fieldset/legend |
| `checkbox`, `switch` without an option list | Boolean checkbox/toggle; hidden `"0"` + checked `"1"`, preserving unchecked submissions |

Selection support is the effective schema's static `config.options`, including already-materialized constant choices; no live constant/entity-entry lookup is introduced. Choices are label/value pairs, never labels submitted in place of values. Checkbox option groups, `EntityReference`, dynamic option sources, files/images, password/hidden controls, rich text/signature/rating/range/currency, time/datetime/month/week/color and unknown types are unsupported for this slice. An unsupported visible input blocks creation; hidden and derived fields are simply outside the write set.

Exclude `Calculated`, `Computed`, `storage: computed`, `readonly: true`, internal columns, and fields not visible to `admin`. Neither client input nor schema defaults can write them. The owner uses the admin audience of the URL tenant. No bridge/enrollment or extended-base-model records are created.

## 5. Component reuse and limitations

| Piece | Reuse / extension |
|---|---|
| Dashboard header, breadcrumbs, width | `AdminPageComponent` / `BreadcrumbsComponent`; sibling new forms already use narrow cards. |
| Group surfaces and actions | `CardComponent`, `ButtonComponent`; full-page Rails `form_with`, CSRF included. |
| New form composition | New `Admin::Entities::EntryFormComponent(form:, create_path:, cancel_path:)`; owns summary, fieldsets, form and footer. Shell remains the thin new view. |
| One schema control | New `Admin::Entities::EntryFieldComponent(field:, value:, errors:)`; fixed mapping to the above existing controls, with no DB access. |
| Field label/help/error | Extend `FormFields::BaseFieldComponent` with consumed `id:`, `help_text:`, `errors:` kwargs; label/input share the same ID and description/error ARIA references. Current base has a label and control only; unknown kwargs become HTML attributes, not help/error UI. |
| Radios / booleans | Their separate templates do not forward general HTML/ARIA attributes consistently. Add the same error/help contract, radio IDs/legend, and boolean hidden false input to the new form adapter; never apply HTML `required` to a boolean merely to mean a required value. |
| Numeric/date/time limitations | Number renders only `type=number`; Date hard-codes `type=date` even for datetime use; Time separately ignores general attribute forwarding. Scope reuse to the supported controls above and preserve failed raw literals through the text rerender. |
| Generic wrappers | `FormFields::FormComponent` has public-page theme/page behavior and one submit; use `form_with` for the admin footer. `FormErrorsComponent` expects model errors and has no linked field summary; the new form component owns the schema-aware summary. |

Platform-authored titles, actions, empty/error messages and submit text must use I18n in **both** `admin_misc.en.yml` and `admin_misc.zh-CN.yml`; reuse `common.actions.cancel` and the select's existing blank-option key. Field/group/option labels and descriptions are authored schema data: render escaped stored metadata (`display_label`, then `name`), not new application string literals or automatic translations. Proposed copy and builder interfaces are fixed in the implementation plan.

## 6. Acceptance checks

- Course shows its four groups, 14 input controls, admin-only notes, defaults, required indicators and native choice/date/number controls; no enrolled-count or enrollment inputs.
- Successful create adds exactly one record in the path tenant and returns to the browser; invalid create adds none and retains every allowed attempted value.
- Shared default/override schema, defaults and entry-version provenance all come from the effective tenant head.
- At 375px, 768px and desktop widths, cards, labels and actions fit with no horizontal overflow; keyboard order matches schema order. Verify focus, labels, summary anchors and error descriptions in both locales.
- GET and POST enforce real admin/owner authorization and tenant scoping, independently of header visibility.

## RETURN
ux_doc: docs/superpowers/specs/2026-10-21-entity-entry-creation-ux.md
surfaces:
  - name: Entity entries browser header
    nav_area: admin
    new_components: []
    reused_components: [AdminPageComponent, ButtonComponent]
  - name: New entity entry and validation rerender
    nav_area: admin
    new_components: [Admin::Entities::EntryFormComponent, Admin::Entities::EntryFieldComponent]
    reused_components: [AdminPageComponent, BreadcrumbsComponent, CardComponent, ButtonComponent, FormFields::BaseFieldComponent, FormFields::TextFieldComponent, FormFields::EmailFieldComponent, FormFields::TextareaFieldComponent, FormFields::NumberFieldComponent, FormFields::DateFieldComponent, FormFields::SelectFieldComponent, FormFields::RadioFieldComponent, FormFields::CheckboxFieldComponent, FormFields::ToggleFieldComponent]
overall: READY_FOR_FRONTEND
notes: Use the effective primary schema and existing admin chrome; backend supplies descriptors, filtered values and keyed errors, while security owns routes/controller and frontend owns accessible field composition.
