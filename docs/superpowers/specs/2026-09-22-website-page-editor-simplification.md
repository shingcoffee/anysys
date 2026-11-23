# Website Page Editor Simplification — UX Spec

**Date:** 2026-09-22
**Audience:** Website module administrators and the frontend implementation team
**Review fixture:** `/81721200/admin/modules/website/pages/8/edit`

## Problem

The current page editor preserves a useful live preview, but the editing side contains too many simultaneous hierarchy levels: page settings, a dedicated section sidebar, an active section heading, group headings, labels, controls, and repeated bordered items. Customers must continually decide where to look before they can change simple page copy.

The redesign must make the page feel like a focused content editor. The preview remains dominant, basic text is immediately editable, and less frequent media, link, and style controls are available through progressive disclosure.

## Product Requirements

- Preserve explicit Save, standalone Preview, `Cmd/Ctrl+S`, live draft preview, section switching, uploads, link validation, repeatable-item controls, reset behavior, and the existing sections JSON format.
- Preserve the current route, authorization, tenant scoping, controller behavior, and responsive Edit/Preview pane switching.
- Scope visual changes to `Websites::Admin::ComposerComponent#workspace?`; non-workspace layout, skeleton, and embedded composers retain their existing composition.
- Use ViewComponent, Tailwind, Stimulus, and existing semantic design tokens only.
- Add no hard-coded user-facing copy. English and Simplified Chinese locale parity remains mandatory.

## Design Direction

Use a clean two-region editor:

```text
+---------------------------------------------------------------+
| Existing admin header: title, status, Preview, Save            |
+----------------------------+----------------------------------+
| Editor                     | Live preview                     |
| -------------------------- |                                  |
| Page settings (compact)    | viewport controls                |
| 1 Hero  2 Cards  3 Quote   |                                  |
|                            | responsive page iframe           |
| Cinematic hero             |                                  |
| description                |                                  |
|                            |                                  |
| primary text fields        |                                  |
| -------------------------- |                                  |
| > Photo                    |                                  |
| > Buttons                  |                                  |
| > Style                    |                                  |
+----------------------------+----------------------------------+
```

The editor and preview are the only desktop columns. The section navigator is a horizontal strip inside the editor, not a nested vertical sidebar.

## Layout Specification

### Desktop

- Keep `AdminPageComponent` with `width: :edge`.
- Use a stable editor/preview split at `xl+`.
- Editor width: approximately `38rem`, capped near `46%` of the workspace.
- Preview uses the remaining width and remains visually dominant.
- Editor and preview keep independent internal scrolling.
- Do not add draggable resizing or another persistent rail.

### Tablet and Mobile

- Preserve the existing accessible Edit/Preview tabs below `xl`.
- Keep the section navigator horizontal and independently scrollable.
- Show only section number and localized section type in the navigator; omit preview excerpts.
- Prevent horizontal page overflow at `320px`, `390px`, `768px`, `1024px`, and desktop widths.

## Editor Composition

### Compact Page Settings

- Keep page settings collapsed by default for persisted records.
- Render the title and current title/path summary on one compact row.
- Keep the chevron at the end of the row.
- Opening the disclosure reveals the existing title, slug, visibility, publish, and home controls unchanged.

### Section Navigator

- Render one horizontal, labeled tab list across the editor pane.
- Use flat tab-like buttons with a quiet selected underline/accent edge.
- Each button contains only a tabular section number and localized section name.
- Remove the nested desktop `xl:w-52` section rail and preview excerpts.
- Keep `aria-current`, add tab/panel relationships and roving focus, and preserve existing `sectionNav` targets and `focusSection` behavior.

### Active Section

- Use the editor pane's full content width with a centered `max-w-3xl` content column.
- Keep the localized section title and one-line description.
- Render the first field group directly without another visible group heading. For common sections this exposes the primary writing fields immediately.
- Render every later field group as a native `<details>` disclosure:
  - summary uses the existing localized group label;
  - media, button, and style disclosures are collapsed initially;
  - repeatable item lists start open because they are primary section content;
  - a chevron communicates state;
  - opening a disclosure reveals the unchanged controls.
- Use whitespace and separator hairlines instead of cards around field groups.
- Keep image preview wells and repeatable array items as the only locally bordered sub-surfaces where containment is functional.

## Shadcn Composition Mapping

The shadcn MCP server is unavailable in this session, so the official shadcn CLI component documentation is the reference.

| Shadcn pattern | Anysys implementation |
|---|---|
| Tabs / ScrollArea | Existing `sectionNav` buttons in a horizontal overflow container |
| Accordion | Native `<details>/<summary>` for secondary field groups |
| Field / FieldGroup | Existing labels, `.input-field`, captions, and errors |
| Separator | `border-t border-border-subtle` between secondary groups |
| Button | Existing `ButtonComponent` variants |

## Interaction and States

- Selecting a section shows only its editor row, updates `aria-current`, and keeps the user in the Edit pane.
- The first field group is immediately visible after section selection.
- Secondary groups retain their local open/closed state while the section remains mounted.
- Editing any field continues to mark the page unsaved and refresh the live draft preview through the existing controller.
- Save success, save failure, upload failure, invalid links, image errors, empty sections, and unknown section types retain existing behavior.

## Accessibility

- Section navigation uses labeled tab-list semantics with matching tab panels.
- Section buttons remain native buttons with `aria-current`, roving `tabindex`, and arrow/Home/End navigation.
- Group disclosures use native keyboard-accessible `<details>/<summary>`.
- Existing pane tab ARIA, preview status, labels, hints, errors, and focus styles remain intact.
- State is never communicated by color alone.

## Out of Scope

- New autosave, undo/redo, drag-resizable panes, content search, inline editing inside the iframe, route/controller/model changes, schema changes, or authorization changes.
- Redesigning Website settings, layouts, skeletons, public sections, or non-workspace composer modes.
- Changing section schemas, field names, submitted data, or locale wording beyond what is already in the current worktree.

## Verification

- Component specs prove the nested desktop rail and workspace nav preview excerpts are gone.
- Component specs prove the first field group is directly visible and later groups use collapsed disclosures.
- Request specs prove the editor route still renders and persists.
- Tailwind rebuild succeeds.
- Playwright checks page 8 at desktop, tablet, and mobile widths, verifies section switching and editing, and captures updated screenshots.
- Visual review confirms the preview is dominant, the editor has only one navigation layer, and no horizontal overflow or clipped controls remain.
