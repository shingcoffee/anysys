# Website content-body refactor — implementation-ready UX

Date: 2026-09-22
Status: READY_FOR_FRONTEND
Primary surface: `/81721200/admin/modules/website/pages/8/edit`
Navigation area: Modules / Website / Pages; admin URL category.

## 1. Decision and evidence

Refactor the entire content-editing body into compact, task-oriented controls. The unit of composition is a piece of content: copy, a button and its destination, a photo, or an identifiable repeated item. Expanded controls must become substantially simpler too.

This is an incremental follow-up to the existing working tree. The earlier redesign files and four existing untracked spec/plan documents are the baseline. This document is a new artifact.

Read `.cursor/agents/anysys-product-owner.md` and `anysys-ux-designer.md`, current composer/section/prop/toolbar components, `website_builder_controller.js`, the section catalog and validation contract, public rich-text/CTA rendering, and the browser test setup. Consulted official shadcn documentation because its skill/MCP are unavailable:

- [Accordion](https://ui.shadcn.com/docs/components/accordion): identifiable triggers, compact separators, explicit single/multiple-open behavior.
- [Field](https://ui.shadcn.com/docs/components/field): semantic fieldsets, adjacent errors, container-responsive grouping.
- [Input Group](https://ui.shadcn.com/docs/components/input-group): combine the input and its associated action into one control boundary.

Implement those patterns with ViewComponent, Tailwind and native HTML/Stimulus.

### Live read-only audit

Playwright opened all four actual page-8 sections, all group disclosures and every photo-URL disclosure at 1440×900 and 390×844. No edits, saves, uploads, or resets were performed. A request guard blocked non-GET/HEAD requests; none were attempted. Opening controls left sections JSON byte-identical.

Artifacts: `/tmp/opencode/website-content-body-audit/`; script: `/tmp/opencode/website-content-body-audit.cjs`. `report.json` records content, labels and geometry; screenshots include initial and expanded top/middle/bottom states plus card details. These are local inspection artifacts, not portable repository fixtures.

| Actual section | Current desktop expanded body | Current mobile expanded body | Evidence |
| --- | ---: | ---: | --- |
| Cinematic hero | 1,635 px | 1,551 px | Empty kicker/headline/subhead; populated primary button and photo; blank secondary button; light tone |
| Card grid, three cards | 3,471 px | 3,219 px | North gallery, Court, Study; each has a one-line description, photo and `about` destination |
| Quote | 511 px | 511 px | One-line quotation, Hanging crew attribution, empty role |
| CTA band | 745 px | 745 px | Visit the rooms; short body; Plan a visit → `contact` |

Inspector viewport height is only 611 px desktop / 517 px mobile. No horizontal inspector overflow was measured at these two sizes. The issue is excessive vertical form structure, repeated metadata and weak item boundaries.

### Source findings

- `SectionEditorComponent#grouped_fields` classifies individual props into generic copy/links/media/options/lists groups. Label/destination pairs are not represented as editing units.
- Workspace ERB discloses every group after the first. Whether a group collapses depends on its position, not its editing purpose.
- Arrays repeat every field fully expanded. `Lists` → `Cards` → `Title` adds hierarchy without identifying the actual card. Existing and template item markup are duplicated.
- `PropFieldComponent#textarea_rows` assigns eight rows to body, quote, answer, bio and address. Actual short card descriptions and quote render at 200 px tall.
- A link exposes raw destination, a second labeled page select, and a persistent hint. This repeats for primary, secondary, CTA and every card.
- Every image renders at full-width 2:1, followed by upload/remove, another disclosure, URL and hint. A card photo consumes roughly 280 px on desktop before its controls.
- Tone uses a full-width segmented track for two short options. `span` remains a separate native select presentation.
- Item actions are four small icon-only buttons below the entire item; duplicate is guarded in JS at max but is not disabled by `#refreshArrayButtons`.
- Reset is below all content and says “Restore original copy,” although it restores all props including photos, links, options and arrays. `resetSection` invokes `window.confirm`.
- Native-invalid revelation exists, but href validation currently sets ARIA/error text without native custom validity. A redesign must not assume invalid hrefs already reveal collapsed ancestors on save.

## 2. Product brief

### Problem statement

Owners and tenant admins need to edit every part of a website page without navigating a stack of repetitive, oversized forms. The first pass improved workspace chrome but left expanded content controls largely intact. Page 8 exposes the gap especially clearly: three small cards require several inspector screens, while populated hero actions and media sit behind generic disclosures. Success means the whole content body is identifiable, compact, consistent, keyboard-operable and faithful to the existing content data.

### User stories and acceptance criteria

1. **As an admin, I want every section's actual content to be easy to locate, so I can edit the right part immediately.**
   - All props in the 13 supported section schemas have an explicit layout below.
   - Page 8's existing hero button/photo are recognizable without opening empty secondary controls.
   - Switching sections preserves draft values and content-disclosure state.
2. **As an admin, I want to work on an identifiable card/list item, so repeated fields cannot be confused.**
   - Each complex item has a numbered, live title summary and one clearly bounded editing body.
   - Add/duplicate opens and focuses the resulting item; move keeps that item's identity and values.
   - Min/max boundaries disable relevant actions and are announced in localized text when reached.
3. **As an admin, I want button text and its destination to read as one action, so link editing is straightforward.**
   - Every link has one authoritative destination input and an optional inline page-picker action.
   - Selecting a page writes its existing slug; pasting an HTTPS link uses the same field.
   - Invalid input receives an adjacent error, reveals its containing section/item before focus on submit, and retains the draft.
4. **As an admin, I want small, clear photo controls, so media does not dominate every item.**
   - All image fields offer a compact thumbnail/source state plus upload/replace, URL editing and removal.
   - Uploading, upload failure and image-load failure have distinct adjacent statuses.
   - A failed replacement preserves the prior stored value; stale upload completion cannot overwrite a later clear/reset/replacement.
5. **As an owner, I want copy, choices and reset to behave consistently, so editing feels like one tool.**
   - Short copy does not reserve eight lines; long-form content still has a useful writing area.
   - Tone, image side and span use localized native-radio semantics and scoped names.
   - Reset restores the active section's existing defaults directly into the draft, updates all derived UI, and opens no confirmation dialog.
6. **As an admin, I want the same editor to work on small screens and with a keyboard, so all content remains usable.**
   - Expanded controls have no horizontal overflow at 320, 390, 768, 1280 and 1440 px viewport widths.
   - Labels, error associations and radio groups remain correct after add, duplicate, move and reset.
   - Draft preview/serialization includes closed fields; disclosure changes alone do not dirty or persist content.

### Edge cases

- Blank hero text is valid and must stay blank; render labels, not example content injected as values.
- Empty and maxed collections; proof-strip minimum of four; long/duplicate/blank item titles; unknown section type uses the existing fallback.
- A saved internal slug absent from `site_pages` stays editable as text. Current options exclude the home page's blank slug; do not invent a new stored home-link representation.
- Non-HTTPS destinations and malformed media URLs need the existing validation boundary. Internal slugs, uploaded media paths and remote HTTPS media retain their current meaning.
- File picker cancellation is a no-op; replacement failure, reset while upload is pending, removing an uploading item, and disconnecting the controller require explicit state handling.
- An item with invalid content may be closed and its section inactive. Reveal section, item and relevant auxiliary control before focusing the error.
- An admin is tenant-scoped; owner access follows existing application rules. Anonymous/member/cross-tenant denial remains controller-enforced and covered by existing request tests. SKIP_AUTH browser inspection does not verify authorization.
- Concurrent editors keep existing explicit-save behavior; no new conflict-resolution workflow is part of this design.

### Out of scope

Workspace-shell redesign, page identity/SEO/publishing, navigation/theme/layout selection, public renderer redesign, schema migrations, section types, media-library/crop/alt-text features, rich-text formatting tools, autosave, collaboration, undo/history and item drag-and-drop.

### Open questions

None. Ready for implementation; no approval checkpoint.

## 3. Surface inventory and layout

All surfaces below belong to **Modules / Website / Pages → content editor**. They render inside the existing workspace inspector.

### Shared visual grammar

- One flat section surface. One section title row with a quiet `Reset section` action; remove permanent catalog-description prose from the editing body.
- Visible labels, ordinary native inputs, 16 px control text, consistent focus/error treatment. Title hierarchy comes from grouping, not a different oversized input theme.
- Start with `gap-4` between related fields, `gap-6` between content units, `gap-1.5` inside fields. Use `text-sm font-medium text-text-secondary` labels and current surface/border/accent tokens.
- A compound destination gets one `rounded-md border border-border-subtle` boundary; its input/action children do not each get a second outline. Focus uses `focus-within:ring-2 focus-within:ring-accent`.
- No enclosing shaded card for every field group. Use `border-t border-border-subtle` between content units and `divide-y` between collection items. Open item bodies use modest indentation, never concentric cards.
- The inspector is a named Tailwind container. Paired fields become two columns only when its **content width** reaches 30rem; otherwise stack. Do not rely on viewport `sm:` while the desktop inspector itself is narrow.
- Inputs/buttons are about 40 px high; item triggers and touch action targets at least 44 px. Long labels wrap; summaries truncate visually with the full text in the accessible name.
- Character counts remain focus-only, with no layout jump. Instructions appear beside the control only when useful (picker, URL edit, upload failure, rich-text paragraph behavior).

### A. Cinematic hero — actual page 8

```
Cinematic hero                                      Reset section
Kicker       [                                                  ]
Headline     [                                                  ]
Subhead      [ two-line initial writing area                     ]

Primary button
  Button label [ See the work ]   Destination [ about | Choose page ]
> Secondary button — Not set

Photo   [thumbnail]  Photo added     Replace photo   Remove
                                   Edit image link
Tone                               [ Light | Dark ]
```

- Text remains visible. `primary_label` + `primary_href` form one semantic fieldset; always expanded as a core task.
- Secondary pair is one disclosure, collapsed initially, with a populated label/destination summary or localized empty summary. Expand it to the same paired layout as the primary button. Closing never clears values.
- `image_url` renders as a directly visible compact media unit, not `Media` → `Photo` → large preview. Its URL editor is one inline auxiliary disclosure.
- `tone` renders as one label + intrinsic-width segmented radio row, directly visible. No `Options` wrapper for one setting.
- Do not seed blank hero fields. The mockup's blank values deliberately match the audited page.

### B. Card grid — actual page 8

```
Card grid                                            Reset section
Heading      [ On view                                         ]
Subhead      [ Three rooms. Walk them in order, or not.           ]

Cards · 3                                              + Add card
v  1  [thumb] North gallery
   [Move up] [Move down]                     Duplicate   Remove
   Title      [ North gallery                                  ]
   Body       [ three-line initial writing area                ]
   Photo      [thumb]   Replace photo  Remove   Edit image link
   Link       [ about                              | Choose page ]
>  2  [thumb] Court
>  3  [thumb] Study
```

- Remove the outer `Lists` accordion. One real collection heading/count/add action replaces `Lists` + `Cards` + bottom full-width generic Add item.
- Complex items use native `<details data-array-item>` with `<summary>` containing ordinal, optional 40 px thumbnail and current title. First item starts open; others start closed. Allow multiple open for comparison; never auto-close a user's other item.
- Do not put buttons inside the summary. The toolbar is the first row of the expanded body, before fields. Move icons have contextual accessible labels; Duplicate/Remove are quiet text actions. This avoids a separate menu system and the old detached footer toolbar.
- Card title, body, media and destination are all visible once the item opens. No additional card-level Copy/Media/Links accordions.
- Summary updates when title or photo changes. Blank title uses localized `Card {number}`; no persisted title substitution. Display number follows current order; stable DOM identity does not.
- All cards can be expanded simultaneously. Reduced height must come from compact bodies too, not only from closing two cards.

### C. Quote — actual page 8

```
Quote                                                Reset section
Quote        [ three-line initial writing area                  ]
Attribution  [ Hanging crew ]             Role [                 ]
```

`quote` starts at three rows, with manual vertical resize. `attribution` and `role` are a paired field row on wide enough containers, stacked otherwise. No disclosure, redundant Copy heading, catalog description or separate boxed footer.

### D. CTA band — actual page 8

```
CTA band                                             Reset section
Headline     [ Visit the rooms                                  ]
Body         [ three-line initial writing area                  ]
Button
  Button label [ Plan a visit ]   Destination [ contact | Choose page ]
```

`button_label`/`button_href` are a directly visible fieldset, not a generic Links accordion. A CTA's action is primary content, so it stays discoverable alongside its copy.

### E. Complete remaining section coverage

| Section | Explicit content composition | Repeater behavior |
| --- | --- | --- |
| `hero_split` | `eyebrow`, `headline`, two-row `subhead`; paired primary/secondary buttons as above; compact `visual_url` | None |
| `proof_strip` | `items`: paired `label`/`value` with small numbered item header and toolbar | Keep simple two-field rows expanded; 4–6 items. Accordion overhead would add no value here |
| `bento_grid` | `heading`; `cells`: title, three-row body, compact image, intrinsic-width `span` radios | Title-summary accordion; 0–8 |
| `alternating_features` | `heading`; `items`: title, three-row body, compact image | Title-summary accordion; 0–8 |
| `team_grid` | `heading`; `people`: name/role paired, three-row bio, compact photo | Name-summary accordion; 0–12 |
| `faq` | `heading`; `items`: question, three-row answer | Question-summary accordion; 0–20 |
| `rich_text` | `heading`, eight-row `body`, existing paragraph-break instruction | None; keep plain-text storage/rendering |
| `split_image_text` | `heading`, three-row `body`, compact `image_url`, direct `image_side` radio row | None |
| `contact_info` | `heading`, three-row `address`, paired `email`/`phone`, `hours` | None; retain email/tel native input types |

For card_grid, keep its 0–12 bound. Every array has the same count/add/boundary/action grammar, including the simple proof-strip variant. New items, duplicated items and reset-generated items must render the same component structure as initial items.

## 4. Primitive interaction specifications

### Text and choices

- Text remains native input/textarea, with stable `data-prop` keys. Short textarea size is driven by editing context, not just prop name: subhead 2 rows; body/quote/bio/answer/address 3; rich-text body 8. Remove unconditional six-rem minimum where it would defeat the two-row setting.
- Keep manual `resize-y` for long copy. No automatic contenteditable or autosizing engine is needed.
- Tone, image side and span share one fieldset/legend + native radio treatment. Two or three options use an intrinsic-width neutral track, checked surface, focus-visible ring, and sensible wrapping at narrow widths.
- Native arrow keys select radios. Duplicates get fresh group names and label/error ID references; changing a copied cell's span must not alter the original cell.

### Link/destination field

1. Show one labeled text input containing the canonical slug/HTTPS value and a compact `Choose page` button inside the same input group.
2. Choose page expands a native select immediately below the group, in flow. Focus the select. Its options come from the existing `site_pages`; include a localized empty prompt. The picker itself has no `data-prop`.
3. Selecting a nonblank option writes the slug into the canonical input, runs validation/dirty/preview synchronization, closes the picker and focuses the destination input. Selecting the prompt makes no content change.
4. Escape closes the picker and returns focus to Choose page. Toggling it or tabbing through it does not clear the input or dirty content.
5. Typing/pasting updates the same canonical input. Remove the always-visible second label/select and repeated explanatory sentence. Keep a concise localized placeholder and adjacent validation error.
6. With no site pages, omit Choose page; raw entry still works. Existing slugs absent from the picker remain untouched.
7. Button pairs use one fieldset legend plus Button label/Destination labels. Contextual accessible names disambiguate primary, secondary and CTA. A standalone card link uses its existing Link label.
8. Use native custom validity for invalid hrefs so Save activates the existing reveal-invalid path. Initialize validity on connect and refresh after reset/duplicate/picker use. Preserve the existing backend accepted format and errors; do not invent mailto/anchor/home-link types.

### Photo/media field

- A small media row replaces every 2:1 preview/drop panel: 80×64 thumbnail, source state and wrapping actions. The public live preview remains the place to see the page-sized image.
- Empty state: compact placeholder and Add photo; do not display Remove for an empty value. An invalid/nonloading existing value still offers Remove and Edit image link.
- Populated state: thumbnail + localized Photo added (or safe hostname where useful), Replace photo, Remove, Edit image link. Do not display raw signed/token-bearing URLs as summary text. Do not invent filenames absent from stored props.
- Edit image link opens a labeled text input below the row; retain exactly one canonical `data-prop` input. It can live in a closed disclosure and still serialize. Opening/closing is a UI action only.
- The compact row is the drop target; native file input remains keyboard reachable through its label. Accepted formats and 8 MB limit reuse existing server behavior and localized text.
- Uploading: status is neutral, `role=status`/polite, and field `aria-busy=true`; disable repeated file replacement until complete. Keep Remove available to cancel application of that result.
- Upload failure: preserve prior URL/thumbnail, show localized error adjacent, re-enable replacement. Photo load failure: show a compact failed-preview state, retain the entered URL and offer replacement/editing. Do not disguise failure as a never-configured empty state.
- Clear resets URL, thumbnail, file selection, error/status and pending-upload application state. It is a draft operation and requires no confirmation.
- Associate each upload with its originating field and operation token/AbortController. Ignore stale results after reset, removal, newer input, or disconnect. A duplicate must not inherit pending-upload state from its source.

### Repeaters and reset

- Add: append from the shared item template; stamp IDs; open the item; focus its first text control; scroll within the inspector only as needed; update count/bounds/JSON/preview.
- Duplicate: insert immediately after source; copy current values including live selects/radios; fresh IDs and radio names; clear transient busy/error/picker state; open/focus copy. Its title may match its source; ordinal distinguishes them.
- Move: move the existing DOM item, retaining values and disclosure state. Keep focus on its action when enabled, otherwise on that item's summary. Renumber summaries and accessible action labels.
- Remove: apply immediately to draft. Focus next item's summary, then previous, then Add if empty. Simple proof rows use their first input as the equivalent focus destination. No confirm.
- Min/max: disable remove at min; disable add AND duplicate at max; disable boundary move buttons. Announce a concise translated bound at the collection header, not under every disabled button.
- Reset: visible quiet action in the active section title row. Restore `data-section-defaults` using current `defaults_for` logic; all fields/arrays/options/media and derived summaries/statuses refresh. First complex item opens again; reset action retains focus. Direct draft change, no confirmation; explicit Save persists it.
- No UI-only ordinal, disclosure state or operation token enters `sections_json`. Structure-locked page 8 retains its four section IDs, types and order while item editing remains available.

### Loading, failure and navigation

All click/edit flows start and stay on the same edit URL. Content changes use the existing debounced draft-preview path; no new navigation or save mechanism is introduced. Initial section content is server-rendered. Picker/accordion toggles need no loading state. Upload status belongs to its field. Submit-time content errors open the current section and relevant native details ancestors before focus. Backend save failures must retain the draft; the existing server error presentation is the integration boundary. Permission failures remain at the existing controller/page response boundary.

## 5. Minimal component touch map

Paths below are under `app/components/websites/admin/` unless otherwise stated. `.rb` and `.html.erb` are paired where both are needed.

| Component/file | Concrete implementation responsibility |
| --- | --- |
| `section_editor_component.{rb,html.erb}` | Own section-specific content composition, button pairing, contextual row sizes, field order, direct options, reset header. Replace index-based workspace disclosure decisions. Keep schemas/prop keys and option translations authoritative; add UI metadata/helpers, not a second persisted schema |
| `prop_field_component.{rb,html.erb}` | Own shared label/control/count/hint/error anatomy, text context and compact radios. Dispatch image and href rendering to dedicated small components. Accept optional contextual label key/row count rather than relying on global `BODY_KEYS` sizing |
| **New** `link_field_component.{rb,html.erb}` | InputGroup destination + in-flow native page picker + adjacent validation. Inputs: field key, value, ID, label/context, site_pages, workspace. Preserve `data-href-field` and canonical `data-prop` |
| **New** `media_field_component.{rb,html.erb}` | Compact thumbnail/upload/source row, inline URL disclosure and distinct status states. Inputs: field key, value, ID, label, uploadable, workspace. Preserve `data-image-field`, preview/status hooks and canonical prop input |
| **New** `array_field_component.{rb,html.erb}` | Collection legend/count/Add/boundary state and template mount. Inputs: field schema, normalized items, section ID, site_pages, uploadable, workspace. Consume existing min/max; use same item renderer for initial/template items |
| **New** `array_item_component.{rb,html.erb}` | Item identity/summary/details/body or simple proof row. Inputs: item schema/values, unique ID prefix, ordinal, expanded, simple-row flag, site_pages, uploadable, workspace. Own contextual summary fallback keys and per-item field ordering |
| `array_item_toolbar_component.{rb,html.erb}` | Top-of-expanded-body toolbar; translated contextual labels, text duplicate/remove, focus-visible treatment, initial boundary states and duplicate-disabled hook |
| `composer_sections_component.html.erb` | Named content-container utility on inspector body and localized empty/status integration only where needed |
| `composer_component.html.erb` | Pass translated dynamic label maps/status/templates as Stimulus values at existing mount; avoid new app-wide state |
| `app/javascript/controllers/website_builder_controller.js` | Extend existing action ownership for picker open/close, item summaries/counts/focus, native href validity, new clone/template structure, max duplicate state, direct workspace reset, per-field upload lifecycle |
| `config/locales/website.en.yml`, `website.zh-CN.yml` | Matching content-context labels, fallback item names, plural counts, add actions, status/error text and contextual accessible action names |
| `app/assets/builds/tailwind.css` | Regenerate using the existing Tailwind build after implementation |

Reuse `ButtonComponent`, current token utilities and native details/fieldset/input/select/radio elements. `SearchableSelectComponent` was inspected: its named hidden-value/grouped-search contract is broader than this small optional page picker; adapting it would add unrelated complexity. Four extracted content components are enough; no generic form framework, separate button-pair component or new menu component is required.

The shared components also serve non-workspace layouts/skeletons. Thread the current `workspace` presentation through extraction and verify those callers. Their prop contract remains common; page-workspace interaction changes such as direct reset are explicitly keyed to the workspace mount.

### Stimulus/DOM contract details

- Keep `row`, `list`, `json`, `data-array`, `data-array-list`, `data-array-item`, `data-item-template`, `data-prop`, `data-href-field`, `data-image-field` contracts.
- Native `<details data-array-item>` works with current closest/query patterns and `#revealInvalid` ancestor traversal. Do not add `name`-based exclusive accordion behavior: comparison and multiple invalid items require multiple-open support.
- Collection/item UI hooks should distinguish summary title, summary ordinal, count, first-control and duplicate action. UI summaries derive from current control values and safe `textContent`, not cached initial HTML.
- `#refreshArrayButtons` becomes the single place for count, boundary action state and ordinal/action-label refresh. Extend field-chrome refresh to update summary media/title after reset and cloning.
- `#stamp` already rewrites `id`, `name` and IDREF attributes; use standard `aria-controls` relationships so it remains sufficient. Add a regression for any new ID-bearing data attribute rather than leaving a cloned reference pointing at the source.
- Live textarea/select/radio values must be deliberately preserved when duplicating; verify actual edited state rather than assuming every browser's `cloneNode` copies all selection state.
- New JS-facing wording is a Stimulus Value with English defaults; mount supplies `t()` translations or a translated JSON map. Dynamic templates use `{number}`, `{title}`, `{count}`, etc. Ruby stores key names, translating at render time.

## 6. Implementation sequence and verification

### Step 1 — field foundation

Extract LinkField/MediaField from PropField without changing data keys. Implement compact text/choices, paired-field composition helpers, link picker/validation and media states. Add focused component and Stimulus tests for the real branches, especially canonical values and error associations.

### Step 2 — identifiable repeaters

Extract ArrayField/ArrayItem to remove the duplicated template markup. Add native item accordions and simple proof rows. Implement titles/counts/bounds/focus and clone/reset refresh. Cover all six array schemas and edited select/radio duplication.

### Step 3 — compose every section body

Apply the exact page-8 layouts and remaining nine type mappings. Move reset to the section header, use direct workspace draft reset, add all English/zh-CN wording, and thread presentation flags through non-workspace callers.

### Step 4 — behavior and expanded-surface QA

Update existing tests that currently require a `details[data-field-group=lists]` wrapper or assume every card's inputs are immediately visible. Test intended tasks rather than retaining obsolete markup expectations.

| Test layer | Required scope |
| --- | --- |
| Component RSpec | Existing `composer_component_spec.rb`, `section_editor_component_spec.rb`, `prop_field_component_spec.rb`, `array_item_toolbar_component_spec.rb`; new link/media/array/array-item component specs; render all 13 schema types and both locales |
| Request RSpec | `spec/requests/websites/admin_pages_spec.rb` for unchanged authorization, serialization and content validation integration |
| Vitest | `spec/javascript/controllers/website_builder_controller.test.js`: picker keyboard/focus, initial/changed/reset validity, title/count updates, add/duplicate/move/remove focus, min/max incl. duplicate, stable IDs/radios, reset without dialog, pending/stale upload states, closed-field serialization |
| Playwright | `spec/e2e/website_page_composer.app.spec.js`, `website_responsive.app.spec.js`: all four actual sections, all cards open, optional secondary/picker/image URL expanded, mobile and keyboard flows; simple proof and other array/option types via isolated fixtures |

Focused commands after implementation:

```bash
bundle exec rspec spec/components/websites/admin/composer_component_spec.rb spec/components/websites/admin/section_editor_component_spec.rb spec/components/websites/admin/prop_field_component_spec.rb spec/components/websites/admin/array_item_toolbar_component_spec.rb spec/components/websites/admin/link_field_component_spec.rb spec/components/websites/admin/media_field_component_spec.rb spec/components/websites/admin/array_field_component_spec.rb spec/components/websites/admin/array_item_component_spec.rb spec/requests/websites/admin_pages_spec.rb
npx vitest run --config config/javascript/vitest.config.js --coverage
bin/rails tailwindcss:build
APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/website_page_composer.app.spec.js spec/e2e/website_responsive.app.spec.js --project=chromium
git diff --check
```

Require real 100% lines/branches/functions for touched JS. Use browser tests for geometry. Protect the actual development page from persistence during future draft-flow tests: intercept save/upload writes, stub upload responses, allow the known non-persisting draft-preview endpoint only for preview tests, and compare the full saved form after reload. Test real persistence/uploads using isolated test records, not page 8. This audit itself did not exercise those mutation paths.

### Visual acceptance: expanded controls are the gate

- Capture 320×568, 390×844, 768×1024, 1280×800 and 1440×900 in en and zh-CN.
- Compare identical page-8 content with secondary button, image URL editors and every card open. Temporary picker panels may be measured separately.
- At 1440 px target hero body ≤1,050 px and three-card body ≤1,900 px; quote ≤400 px; CTA ≤550 px. At 390 px target three-card body ≤1,800 px. These are implementation targets, not results already achieved.
- With picker panels also open, three-card body should remain at least 40% shorter than the audited fully expanded body at both sizes. Meet this by structural simplification, never by clipping content or shrinking touch/text sizes.
- Recognizable card summaries stay available when closed. All fields/actions remain usable with all three cards open; no multi-screen image preview per item, persistent duplicate page-selector form, or remote toolbar.
- Verify keyboard summary Enter/Space, picker Escape, native radio arrows, item-action focus continuity and invalid hidden-field revelation. Confirm UI toggles alone do not change JSON or trigger draft requests.

## 7. Handoff

Ready for frontend implementation with the existing first-pass work as baseline. The key delivery is a complete content-control system across every schema, with shorter expanded bodies and identifiable repeated items. The new UX doc and the read-only browser artifacts are the output of this audit; the refactor and its test runs remain implementation work.
