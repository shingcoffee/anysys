# Website page editor refinement — UX spec

**Date:** 2026-09-22  
**Audience:** frontend developer. Implement with ViewComponent + Tailwind + Stimulus only. No React runtime and no custom CSS.  
**Approved scope:** refine only `GET/PATCH /:cid/admin/modules/website/pages/:id/edit` and the shared `Websites::Admin::ComposerComponent` workspace mode used by that surface. Page `8` under customer `81721200` is the review fixture, not an ID-specific implementation.

This is a visual and interaction refinement, not a product redesign. Preserve explicit Save, live draft preview, the separate Preview link, `Cmd/Ctrl+S`, all section and field behavior, existing I18n, current tenant authorization, and the responsive Edit/Preview panes.

Reference evidence:

- Desktop screenshot: `tmp/playwright-website-composer/edit-page-8.png` at `1440 × 900`
- Mobile screenshot: `tmp/playwright-website-composer/edit-page-8-mobile.png` at `390 × 844`
- Current templates and components named in the approved task
- Existing `website-builder` Stimulus target/action/value contract

The desktop reference proves that the side-by-side editor and live preview are useful, but the inspector is visually dense and the decorative browser frame competes with the page. The mobile reference proves that pane switching works, but the filled-accent Edit tab competes with Save and the stacked header consumes too much visual attention. The refinement therefore changes hierarchy and composition, not capability.

---

## Design direction

Use a professional clean-minimal editor built from the existing Anysys semantic tokens.

- Save is the only persistent filled-accent action.
- Preview, pane switching, viewport switching, reset, and utility actions are neutral or ghost controls.
- Cards are reserved for major regions. Do not render every field group as a shaded card.
- Form content follows shadcn Field anatomy: label, control, optional description, optional error, then a clear gap to the next field.
- Field groups use Separator-style hairlines and whitespace, not repeated rounded backgrounds.
- Mobile pane switching follows shadcn Tabs composition and accessible tab semantics.
- Published, Draft, Home, Unsaved changes, and Live preview remain text-bearing Badge/status treatments; never communicate these states by color alone.
- Use only existing semantic colors such as `bg-canvas`, `bg-surface`, `text-text-primary`, `text-text-secondary`, `text-text-muted`, `border-border`, `border-border-subtle`, `bg-accent`, `text-accent`, `bg-warning-subtle`, and `text-warning`.

### Shadcn-to-Anysys mapping

| Shadcn principle | Anysys delivery |
|---|---|
| Tabs / TabsList / TabsTrigger / TabsContent | Existing pane switcher buttons and editor/preview targets, composed with ARIA tab semantics and Stimulus |
| FieldGroup / Field / FieldLabel / FieldDescription / FieldError | Existing `PropFieldComponent`, Rails form helpers, `.form-label`, `.input-field`, captions, and inline errors |
| Separator | Tailwind hairline boundary such as `border-t border-border-subtle`; no raw decorative `<hr>` |
| Card | Existing `.card` / `CardComponent`, used only when a whole major region needs containment |
| Button | Existing `ButtonComponent` hierarchy |
| Badge | Existing `BadgeComponent` and the current warning/live status pills |

---

## 1. Surface inventory

| Surface | Navigation area | URL / scope | Audience | Change |
|---|---|---|---|---|
| Website page editor | Modules | `GET/PATCH /:cid/admin/modules/website/pages/:id/edit` | Same-tenant `admin`; `owner` according to existing platform rules | Refine page header, editor rail, inspector, live preview, and responsive pane switching |
| Shared page edit-workspace mode | Modules | `Websites::Admin::ComposerComponent#workspace?` when a non-embedded page composer shows sections and preview | Same as the calling admin page | Apply the same composition to all callers of this exact workspace mode; do not affect non-workspace composer modes |

### Explicitly out of scope

- Pages index, new-page layout selection, Website settings, platform layout galleries, skeleton galleries, or public website sections
- Routes, controllers, models, persistence format, preview endpoints, upload behavior, authorization, or tenant scoping
- `identity_only?`, `layout_kind?`, `embedded?`, `sections_only?`, or any composer rendering where `workspace?` is false
- New autosave behavior, save-on-blur, navigation blocking, undo/redo, draggable pane resizing, or a new editor framework
- Copy changes beyond any new accessibility-only labels that implementation proves necessary
- Production code changes in this UX-design task

---

## 2. Layout specification

## 2.1 Overall editor shell

Keep `AdminPageComponent` with `width: :edge`. The page uses the remaining viewport height below the global admin chrome and its sticky page header. The browser body must not become the editor's scroll container.

```text
+--------------------------------------------------------------------------+
| Existing admin topbar and primary navigation                             |
+--------------------------------------------------------------------------+
| Breadcrumbs                                                              |
| [page identity] Page title [Published] [Home]       Preview   [Save]      |
+--------------------------------------------------------------------------+
| section navigation | focused inspector      | live preview                |
| independent scroll | independent scroll     | fixed toolbar + frame       |
+--------------------------------------------------------------------------+
```

Required shell behavior:

- `AdminPageComponent` remains the single page header; do not add a second title bar inside the composer.
- The composer remains `min-h-0 flex-1 overflow-hidden`.
- At `xl` and wider, show editor and preview side by side.
- Below `xl`, show one pane at a time through the Edit/Preview tabs.
- The editor pane and preview pane each own their internal scrolling.
- No horizontal browser scroll at `320px`, `390px`, `768px`, `1024px`, or desktop widths.

Recommended desktop proportions:

- Editor pane: `xl:w-[42rem] xl:max-w-[50%] xl:flex-none`
- Preview pane: `min-w-0 flex-1`
- Inside the editor pane, section navigation: `xl:w-52`
- Inspector: `min-w-0 flex-1`

Do not add a resizable divider. A stable split is easier to understand and preserves the current behavior.

---

## 2.2 Page header and action hierarchy

Reuse the current breadcrumbs, title, Published/Draft badge, optional Home badge, Preview link, and Save form binding.

### Desktop

- Keep title and badges on the left.
- Keep Preview and Save on the right in one compact action group.
- Preview remains a neutral ghost/secondary link that opens the existing preview URL in a new tab.
- Save remains the primary filled button and submits `Websites::Admin::ComposerComponent::FORM_ID`.
- Do not place Unsaved changes in the page header; it belongs to the workspace because it describes form state, not publication state.

### Mobile

```text
Breadcrumbs
Page title  [Published]
[Preview] [Save]
----------------------
[ Edit ] [ Preview ]                 [Unsaved changes]
```

- Title and badges may occupy the first line.
- Preview and Save must share one action row; do not allow each action to become its own row.
- Keep Preview before Save so the primary action remains the final action in reading order.
- Buttons remain content-width, not full-width.
- Give the mobile action controls a minimum comfortable touch height without enlarging the desktop header.
- The header may wrap, but it must not overlap or push the pane tabs off-screen.

### States

- Save success: Unsaved changes disappears only after the existing successful persistence response.
- Save failure: keep Unsaved changes visible and leave the user's form values in place.
- Do not add an autosaved or saved badge; explicit Save must remain unambiguous.
- Do not add a toast solely for successful Save in this pass.

---

## 2.3 Responsive Edit/Preview tabs

The pane switcher is visible below `xl` and hidden at `xl+`.

Use a shadcn Tabs-style structure:

- Container: `role="tablist"` with the existing I18n group label.
- Edit and Preview controls: `role="tab"`, stable IDs, `aria-selected`, `aria-controls`, and roving `tabindex`.
- Editor and preview panes: matching `role="tabpanel"` and `aria-labelledby`.
- Inactive pane: visually hidden with the existing responsive class behavior; do not remove it from the form or recreate it.
- Active pane state continues to be owned by `website-builder`.

Visual treatment:

- Use a quiet neutral TabsList surface: `bg-canvas`, a subtle border/ring, and compact padding.
- Selected tab: `bg-surface text-text-primary shadow-sm`.
- Unselected tab: `text-text-secondary hover:text-text-primary`.
- Do not fill the active Edit or Preview tab with the accent color; Save owns the accent.
- Keep Unsaved changes as a warning Badge/status beside the tab list.
- At very narrow widths, the row may wrap once, but tab labels must remain visible and the badge must not overlap them.

Keyboard behavior:

- `Tab` enters the active tab.
- Left/Right arrows move between Edit and Preview.
- `Home`/`End` select the first/last tab.
- Enter/Space activates the focused tab.
- Switching panes must not automatically move focus into the preview iframe.

The default below `xl` remains Edit on initial connect, matching current behavior.

---

## 2.4 Editor pane

### Desktop composition

```text
+---------------------+-------------------------------------+
| Sections on this    | Page settings                      |
| page                | ---------------------------------- |
|                     | Cinematic hero                     |
| 1 Cinematic hero    | A large opening image...           |
|   Playwright...     |                                     |
| 2 Proof strip       | Text                                |
| 3 Split content     | [Small label field]                |
|                     | [Headline field]                   |
|                     | [Supporting text field]            |
|                     | -------- separator --------------- |
|                     | Photo                               |
|                     | [image field]                      |
|                     | -------- separator --------------- |
|                     | Buttons                             |
|                     | [button fields]                    |
+---------------------+-------------------------------------+
```

### Section navigation

Reuse `Websites::Admin::ComposerSectionsComponent`.

- Desktop: a vertical `nav` at `w-52`, `shrink-0`, `overflow-y-auto`, `border-r border-border-subtle`, `bg-canvas`.
- Below `xl`: a horizontal, independently scrollable strip at the top of the Edit panel.
- Keep the existing nav label and `aria-current` behavior.
- Each item shows:
  - Section number in tabular figures
  - Localized section type name
  - Optional one-line preview text from the existing `section_nav_items`
- Selected item uses a quiet accent cue: accent left/bottom border plus `bg-surface` and primary text.
- Idle items remain flat; no rounded card around every item.
- Preserve truncation. A long page title or section excerpt must not widen the pane.
- Clicking a section keeps the user in Edit, reveals the matching workspace row, synchronizes `aria-current`, and does not change data.

For generic unlocked workspace callers, preserve Add section, kit picker, reorder, and delete behavior. Add section remains a secondary button at the end of the navigation region. The approved page-8 route is structure-locked and therefore does not show these controls.

### Inspector

Reuse `PageIdentityComponent`, `SectionEditorComponent`, and `PropFieldComponent`.

- Inspector shell: `overflow-y-auto bg-surface`.
- Content column: centered, `w-full max-w-2xl`, `px-5 py-6 sm:px-6`, `flex flex-col gap-6`.
- Avoid a card around the entire inspector; the pane itself is the major surface.
- Keep Page settings collapsed by default for persisted workspace records.
- Page settings summary shows the existing title/path summary and chevron.
- When open, Page settings follows the same Field-style rhythm as section fields.
- Only the active section row is visible in workspace mode.
- Section title uses a modest section heading, not a display headline and not a colored badge.
- Section description remains a muted caption directly below the section title.

### Field and group anatomy

Every scalar field follows:

```text
Field label                              optional character count
[control]
optional help or validation text
```

- Field stack: `flex flex-col gap-1.5`.
- Labels use the existing `.form-label`.
- Controls use the existing `.input-field`.
- Descriptions use `text-caption`.
- Errors sit immediately after their control, use `text-danger`, and are associated through `aria-describedby`.
- Invalid controls use `aria-invalid="true"`.
- Character count may remain hidden at zero and appears in the label row when nonzero.
- Do not restore oversized transparent “document editor” inputs for headline fields; controls remain visually consistent.

Groups such as Text, Photo, Buttons, Style, and Items:

- Use a localized sentence-case group heading.
- Use `flex flex-col gap-4`.
- Place `border-t border-border-subtle pt-5` between groups, except before the first group.
- Do not wrap each group in `rounded-xl bg-canvas-elevated p-4`.
- Do not use uppercase tracking as the primary hierarchy.

Related checkbox fields:

- Use native `fieldset` and `legend`.
- In workspace mode, use quiet rows rather than bordered selection cards.
- Checked state remains visible through the native control and text; do not rely on a tinted container.
- Home-page locked state remains disabled and keeps its explanatory text.

Segmented options:

- Follow ToggleGroup-like behavior with native radios.
- Use a neutral container and neutral selected state.
- Keep the localized option text visible.
- Preserve `role="radiogroup"` and the shared label relationship.

Link fields:

- Keep the site-page picker, custom link field, hint, validation, and current sync behavior.
- The picker appears before the custom link input.
- Avoid placing the picker and input in competing mini-cards.

Image fields:

- The image preview well may use `rounded-lg border border-border-subtle bg-canvas`; it is a control preview, not a Card.
- Keep Add/Replace photo as the stronger secondary action and Clear image as ghost.
- Keep URL entry under the existing disclosure.
- Uploading and upload error text stay adjacent to the image control.

Array/list fields:

- Each item is an outlined subgroup, not a Card: `rounded-lg border border-border-subtle`, no shadow, no elevated background.
- Item number and item toolbar share a compact header row.
- Preserve duplicate, move, remove, min/max, and add-item behavior.
- Use separators or `gap-3` between items; do not nest multiple shaded surfaces.

Reset section:

- Keep Restore original copy at the bottom of a locked section as a muted ghost action.
- Keep the existing confirmation dialog and I18n.
- It is secondary/destructive in consequence but must not visually compete with Save.

---

## 2.5 Preview pane

Reuse the current preview iframe and Stimulus targets. The preview pane is a major region but does not need a Card wrapper.

### Toolbar

```text
Preview   ● Live preview   [Unsaved changes]       [Desktop Tablet Mobile]
```

- Height: compact, approximately `h-12`.
- Background: `bg-canvas` or `bg-surface`; use one consistent surface.
- Bottom boundary: `border-b border-border`.
- Preview is the `h2`.
- Live preview remains visible text with its status dot.
- Unsaved changes remains a warning Badge/status.
- Viewport controls align right on desktop and may wrap below the status group at narrower preview widths.

Viewport controls:

- Compose as a quiet ToggleGroup.
- Retain desktop/tablet/mobile icons and localized visible labels when space permits.
- Pressed state: `bg-surface text-text-primary shadow-sm`.
- Idle state: `text-text-muted hover:bg-surface-hover`.
- Keep `aria-pressed` and the localized group/individual labels.
- Minimum touch target is `40px` when the preview pane is used on touch widths.

### Preview stage

- Stage area: `flex-1 min-h-0 overflow-hidden p-3 sm:p-5`.
- Frame: `mx-auto h-full min-h-0 w-full overflow-hidden rounded-xl bg-white ring-1 ring-border`.
- Continue applying the existing maximum widths: desktop `100%`, tablet `768px`, mobile `390px`.
- The frame remains centered as its viewport width changes.
- The iframe retains its localized title.
- Keep the preview content white even when the admin shell uses another canvas color.

Remove decorative fake browser UI:

- No traffic-light dots.
- No fake address bar.
- No duplicate Live preview pill inside the frame.
- Do not make the iframe look like a screenshot inside a browser mockup.

The toolbar already explains that the pane is a live preview. Removing the decoration gives the rendered website more room and reduces visual noise.

### Preview states

- Initial/server preview: load the existing embedded preview URL.
- Draft edits: after the existing debounce, update `srcdoc` through the current live-preview request without persisting.
- Loading: keep the overlay target and localized Loading preview text. Treat it as a status with polite announcement behavior.
- Draft preview request failure: retain the last successful preview, remove the loading overlay, and keep Unsaved changes visible.
- Save success: reload from the persisted preview URL and clear Unsaved changes.
- Save failure: do not reload the iframe and do not clear Unsaved changes.
- Missing preview URL in another caller: keep the existing neutral preview placeholder; do not add new empty-state copy in this pass.

---

## 2.6 Mobile flow

At `390 × 844`, the screen should read as one focused task rather than a compressed desktop editor.

```text
+--------------------------------------+
| admin mobile chrome                  |
| breadcrumbs                          |
| page title [Published]               |
| [Preview] [Save]                     |
+--------------------------------------+
| [ Edit ] [ Preview ]   [Unsaved]     |
+--------------------------------------+
| horizontal section navigation        |
+--------------------------------------+
| Page settings                        |
|                                      |
| Cinematic hero                       |
| description                          |
|                                      |
| Text                                 |
| label                                |
| [control]                            |
| ...                                  |
+--------------------------------------+
```

Mobile requirements:

- Edit/Preview tabs stay at the top of the workspace while its selected pane scrolls.
- Section navigation scrolls horizontally; the page must not scroll horizontally.
- Inspector fields are one column.
- Inputs, textareas, selects, and image previews use the full available width.
- Preview stage uses the available pane width; selecting the Mobile viewport still caps the inner frame at `390px`.
- Switching back to Edit preserves the inspector scroll position and entered values.
- Switching to Preview never submits the form.
- Header Preview continues opening the standalone preview in a new tab; the Preview tab only changes the embedded pane.

---

## 3. Data mapping

| Region | Data / existing source |
|---|---|
| Page title | `page.title` |
| Path summary | `page.slug`, with home-page behavior preserved |
| Status badges | `page.published?`, `page.home?` |
| Visibility fields | `nav_visible`, `published`, `home` |
| Layout context | `selected_layout_key`, `page.layout`, localized layout name |
| Section navigation | normalized section `id`, `type`, and first available preview prop |
| Section editor | section `props`, field schema, localized field/group/option keys |
| Site-page link picker | current website pages from `site_pages` |
| Image upload | existing same-tenant `upload_url` |
| Embedded preview | existing `preview_url` with `embed=1` |
| Persistence | current form action, method, scope, hidden `sections_json`, and `layout_key` behavior |

Do not change the normalized sections JSON shape:

```text
[{ id, type, props }]
```

---

## 4. Interaction flows

### 4.1 Edit copy and explicitly save

1. Start at `GET /81721200/admin/modules/website/pages/8/edit`.
2. The Edit tab is active below `xl`; both panes are visible at `xl+`.
3. Choose a section from Sections on this page.
4. Change a field.
5. Unsaved changes appears.
6. After the existing debounce, the embedded preview updates with draft content.
7. Select Save or press `Cmd/Ctrl+S`.
8. On success, persist through the existing endpoint, clear Unsaved changes, and reload the persisted preview.
9. Remain on the editor URL.

Failure:

- Invalid/server-rejected save keeps the current field values and Unsaved changes.
- Existing error presentation remains above the workspace through `AlertComponent`.
- Do not redirect to another tenant or clear draft UI state.

### 4.2 Inspect the responsive preview

1. From the editor, select Preview below `xl`; at `xl+`, use the already-visible preview pane.
2. Select Desktop, Tablet, or Mobile in the preview toolbar.
3. The preview stage changes maximum width without changing the underlying content.
4. Return to Edit; field values and editor scroll position remain.

Failure:

- If the preview cannot refresh, show the last successful frame and remove the loading overlay.
- Unsaved changes remains visible.

### 4.3 Open standalone preview

1. From the page header, select Preview.
2. Open the existing admin preview URL in a new tab with `noopener`.
3. Keep the editor tab and unsaved form state untouched.

### 4.4 Edit page settings

1. In Edit, expand Page settings.
2. Change title, slug, navigation visibility, publication, or home state.
3. Preserve the current home-page lock and confirmation behavior.
4. Draft changes update the embedded preview where applicable.
5. Save explicitly.

Failure:

- Slug or server validation is presented through the existing form error path.
- A cancelled Make home confirmation restores the unchecked state and does not mark a false change.

### 4.5 Restore a section

1. In a structure-locked workspace, select Restore original copy.
2. Show the existing localized confirmation.
3. Cancel leaves the section unchanged.
4. Confirm restores the section defaults, marks the form unsaved, and refreshes live preview.
5. Save explicitly to persist.

### 4.6 Authorization and tenant failure

- Existing `/:cid/admin/*` authorization remains controller-enforced through `RouteAuthorization`.
- Same-tenant admins and permitted owner access continue to work according to existing rules.
- Members remain blocked from the route.
- Record lookup, preview, save, and image upload stay scoped to the URL customer.
- Cross-tenant or unauthorized requests follow the existing denial/not-found behavior; do not design an editor-local permission state.

---

## 5. Component reuse map

| Layout piece | Component / owner | Design instruction |
|---|---|---|
| Page shell, breadcrumbs, title, actions | `AdminPageComponent` | Reuse; preserve `width: :edge`; apply only route-specific action sizing/wrapping if needed |
| Save and Preview actions | `ButtonComponent` | Save primary; Preview ghost/secondary |
| Published/Draft/Home | `BadgeComponent` | Reuse existing variants and I18n |
| Form/server error | `AlertComponent` | Keep above workspace |
| Whole composer | `Websites::Admin::ComposerComponent` | Own shared workspace shell, responsive tabs, preview toolbar, and preview stage |
| Section navigation and inspector mount | `Websites::Admin::ComposerSectionsComponent` | Own vertical/horizontal section navigation and focused inspector layout |
| Page settings | `Websites::Admin::PageIdentityComponent` | Keep disclosure and convert body to Field-style grouping |
| Section fields | `Websites::Admin::SectionEditorComponent` | Keep active-row behavior; use group separators instead of group cards |
| Individual controls | `Websites::Admin::PropFieldComponent` | Apply consistent Field anatomy and error/help relationships |
| Repeating item actions | `Websites::Admin::ArrayItemToolbarComponent` | Reuse; keep compact icon/action hierarchy |
| No-sections state | `EmptyStateComponent` | Reuse current localized empty state |
| Kit picker in generic unlocked workspaces | `Websites::Admin::KitPickerComponent` | Preserve current behavior; style as a utility popover/list, not a card grid |

### New components

None required. The pane tabs and preview toolbar are tightly coupled to existing `website-builder` targets and should remain inside `ComposerComponent` unless implementation discovers an already-established shared component with the same Stimulus contract.

---

## 6. Tailwind notes

Use existing utilities and tokens; do not introduce a custom stylesheet.

### Spacing and layout

- Main workspace rhythm: `gap-6`
- Field group rhythm: `gap-4`
- Individual field rhythm: `gap-1.5`
- Compact toolbar rhythm: `gap-2` or `gap-3`
- Inspector padding: `px-5 py-6 sm:px-6`
- Preview stage padding: `p-3 sm:p-5`
- Always use `gap-*`, not `space-x-*` or `space-y-*`

### Typography

- Page title remains owned by `AdminPageComponent`.
- Pane and section headings use existing `section-header` or equivalent body-scale heading.
- Labels use `.form-label`.
- Help, counts, and descriptions use `text-caption`.
- Avoid uppercase tracked group labels in the workspace.
- Do not introduce a new font or display type scale.

### Boundaries and surfaces

- Major pane boundary: `border-r border-border`
- Group separators: `border-t border-border-subtle`
- Neutral major surface: `bg-surface`
- Navigation/preview canvas: `bg-canvas`
- Use `rounded-lg`/`rounded-xl` only where containment is meaningful.
- No shadows on ordinary field groups or repeating items.
- Preserve focus-visible rings on all interactive controls.

---

## 7. Stimulus notes

Keep the single `website-builder` controller and the current form contract. Do not introduce another JavaScript framework.

Preserve:

- `markDirty`
- debounced live preview
- `persist`
- `saveShortcut`
- `reloadPreview`
- `previewLoaded`
- `focusSection`
- `setWorkspacePane`
- `setPreviewViewport`
- section, array, link, image, and reset actions
- all current values with English defaults and server-provided localized values

Allowed refinement:

- Update pane-tab ARIA state alongside the existing responsive classes.
- Add keyboard handling needed for accessible tab behavior.
- Preserve inactive pane DOM and form controls.
- Add `role="status"` / polite announcement relationships for Unsaved changes and Loading preview without changing visible copy.

If JavaScript changes, update mirrored Vitest coverage and keep the touched source at 100% lines and branches. Browser-only responsive and focus behavior should be exercised by the existing Playwright layer.

---

## 8. I18n requirements

- Every visible and accessibility-facing string must use I18n.
- Keep English and `zh-CN` keys in parity.
- Reuse current keys wherever the wording is unchanged, including:
  - `common.actions.save`
  - `common.labels.preview`
  - `website.admin.pages.edit.workspace_edit`
  - `website.admin.pages.edit.workspace_panes`
  - `website.admin.pages.edit.preview_label`
  - `website.admin.pages.edit.preview_live`
  - `website.admin.pages.edit.unsaved`
  - `website.admin.pages.edit.preview_viewport`
  - `website.admin.pages.edit.preview_desktop`
  - `website.admin.pages.edit.preview_tablet`
  - `website.admin.pages.edit.preview_mobile`
  - `website.admin.pages.edit.preview_loading`
  - existing field, group, reset, and confirmation keys
- Do not hard-code text in ERB, Ruby, or Stimulus.
- Any new Stimulus text value requires an English default and a translated server value.
- Do not translate strings inside Ruby constants.

---

## 9. Accessibility acceptance criteria

- Page maintains one `h1`; pane titles and section hierarchy descend logically.
- Mobile pane controls implement tab semantics and keyboard navigation.
- Every tab has a controlled panel; selected, hidden, and focus states stay synchronized.
- The section navigation has an accessible localized label and a single current item.
- All fields have programmatic labels.
- Help and error text is associated with its control.
- Invalid fields expose `aria-invalid`.
- Preview iframe has a localized title.
- Unsaved and loading states are available to assistive technology without repeated noisy announcements on every keystroke.
- Status is never communicated by color alone.
- Icon-only controls retain localized `aria-label`s.
- Focus indicators remain visible against canvas and surface backgrounds.
- Mobile interactive targets are comfortably operable; no overlapping controls at `320px`.
- At 200% zoom, users can switch panes and reach every field without two-dimensional page scrolling.
- No claim of full WCAG conformance is made from screenshots alone; keyboard, screen-reader, zoom, and contrast checks remain required during implementation QA.

---

## 10. State matrix

| State | Editor | Preview | Primary action |
|---|---|---|---|
| Clean initial load | Current persisted values | Persisted embedded preview | Save available |
| Dirty | Edited values; Unsaved visible | Debounced draft preview | Save remains explicit |
| Preview loading | Editing remains available | Loading overlay/status | Save remains available |
| Draft preview failure | Values retained; Unsaved visible | Last successful preview | Save remains available |
| Save in flight | Values retained; duplicate submit already guarded | Current frame retained | Do not imply success |
| Save success | Values retained; Unsaved hidden | Reload persisted preview | Stay on editor |
| Save failure | Values retained; Unsaved visible; existing alert/error path | Current/last successful preview | Retry Save |
| No sections | Existing `EmptyStateComponent` in inspector | Existing preview/placeholder behavior | Generic unlocked callers may Add section |
| Unknown section | Existing warning treatment | Best available preview | Other sections remain editable |
| Unauthorized/cross-tenant | Editor does not render | Editor does not render | Existing controller response |

---

## 11. Implementation touch map

The frontend implementation is expected to stay focused on:

- `app/views/admin/modules/website/pages/edit.html.erb`
  - Header action hierarchy and route-specific responsive treatment only
- `app/components/websites/admin/composer_component.html.erb`
  - Workspace tabs, shell, preview toolbar, stage, status semantics
- `app/components/websites/admin/composer_component.rb`
  - Workspace-only class helpers if needed
- `app/components/websites/admin/composer_sections_component.html.erb`
  - Section navigation and inspector composition
- `app/components/websites/admin/composer_sections_component.rb`
  - Workspace-only nav classes if needed
- `app/components/websites/admin/page_identity_component.html.erb`
  - Field-style page settings
- `app/components/websites/admin/section_editor_component.html.erb`
  - Section/group hierarchy, separators, list-item boundaries
- `app/components/websites/admin/section_editor_component.rb`
  - Workspace-only grouping/class helpers if needed
- `app/components/websites/admin/prop_field_component.html.erb`
  - Field anatomy and control relationships
- `app/components/websites/admin/prop_field_component.rb`
  - Field class helpers if needed
- `app/javascript/controllers/website_builder_controller.js`
  - Only tab accessibility/state synchronization if markup alone is insufficient
- matching `en` and `zh-CN` Website locale files only if new keys are unavoidable
- focused component, Vitest, and Playwright specs

Do not change public website section rendering or files under `app/services/page_layout_templates/templates/`.

---

## 12. Visual QA checklist

Capture the same route and state at:

- `1440 × 900`
- `1280 × 800`
- `1024 × 768`
- `768 × 1024`
- `390 × 844`
- `320 × 568`

Confirm:

- Save is the strongest action at every width.
- Desktop shows section navigation, inspector, and preview simultaneously.
- Below `xl`, only the selected Edit/Preview pane is visible.
- The mobile tab row does not compete with or obscure the header actions.
- No nested shaded cards surround Text, Photo, Buttons, Style, or Items.
- No fake browser dots/address bar remain.
- Section navigation and inspector scroll independently where intended.
- Preview viewport controls remain usable when the preview pane is narrow.
- No user input is lost when switching panes.
- Live preview updates before Save, but Unsaved remains until Save succeeds.
- Preview link still opens a new tab.
- `Cmd/Ctrl+S` still explicitly persists.
- English and Simplified Chinese layouts both fit without clipping.
- Tenant and role behavior is unchanged.

---

## 13. Definition of ready

This design is ready for frontend implementation when the implementation plan treats the workspace as a shared mode, scopes all visual changes behind `workspace?`, and preserves every existing data and Stimulus contract listed above.

## RETURN
ux_doc: docs/superpowers/specs/2026-09-22-website-page-editor-ux.md
surfaces:
  - name: Website page editor workspace
    nav_area: Modules
    new_components: []
    reused_components: [AdminPageComponent, ButtonComponent, BadgeComponent, AlertComponent, EmptyStateComponent, Websites::Admin::ComposerComponent, Websites::Admin::ComposerSectionsComponent, Websites::Admin::PageIdentityComponent, Websites::Admin::SectionEditorComponent, Websites::Admin::PropFieldComponent, Websites::Admin::ArrayItemToolbarComponent]
overall: READY_FOR_FRONTEND
notes: Refine only the shared page edit-workspace path into a quiet three-region desktop editor and accessible mobile Edit/Preview tabs while preserving explicit Save, live draft preview, all current behavior, I18n, authorization, and tenant scoping.
