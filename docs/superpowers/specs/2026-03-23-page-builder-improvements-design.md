# Page Builder Improvements — Design Spec

**Date:** 2026-03-23
**Status:** Approved
**Target users:** Technical users (developers, power users)
**Application type:** Hybrid form builder + web page builder

## Context

The page builder is a sophisticated visual editor supporting 39 field types across 5 categories (input, selection, numeric, date/time, media, rich content, layout), with multi-page wizard support, drag-and-drop, conditional logic, theming, and a modular manager architecture (~15 specialized JS managers).

This spec addresses anti-patterns against industry standards and missing features, organized into three phases that each deliver standalone value.

## Architecture Conventions

All new UI elements follow the project's established conventions:
- **ViewComponents** for all reusable UI: each new panel, toolbar, and overlay is a ViewComponent under `app/components/page_builder/`
- **StimulusJS** for all JavaScript: new behavior lives in dedicated manager classes under `app/javascript/controllers/page_builder/` or new Stimulus controllers
- **TailwindCSS** only for styling
- **Trailblazer Activity + Reform Contract** for server-side operations (Phase 3 template CRUD)

### New ViewComponents

| Phase | Component | Purpose |
|-------|-----------|---------|
| 1 | `PageBuilder::PropertyPanel::TabbedPanelComponent` | Tabbed property panel with contextual tabs |
| 1 | `PageBuilder::FloatingActionBarComponent` | Multi-select action bar |
| 1 | `PageBuilder::FieldActionBarComponent` | Hover action bar (duplicate, delete) |
| 1 | `PageBuilder::DependencyBadgeComponent` | Conditional rule indicator badges |
| 2 | `PageBuilder::ResizeHandleComponent` | Drag resize handle overlay |
| 2 | `PageBuilder::FieldGroupComponent` | Field group container |
| 3 | `PageBuilder::CommandPaletteComponent` | Slash command palette |
| 3 | `PageBuilder::ContextMenuComponent` | Right-click context menu |
| 3 | `PageBuilder::BreadcrumbComponent` | Nested field breadcrumb bar |
| 3 | `PageBuilder::ZoomControlsComponent` | Zoom toolbar + mini-map toggle |
| 3 | `PageBuilder::MiniMapComponent` | Canvas mini-map |

### New Stimulus Managers

| Phase | Manager | Purpose |
|-------|---------|---------|
| 1 | `inline_edit_manager.js` | contenteditable lifecycle, cursor management, save/cancel |
| 1 | `clipboard_manager.js` | Copy/cut/paste, in-memory clipboard |
| 2 | `resize_manager.js` | Resize handle drag, snap-to-grid, reflow |
| 3 | `command_palette_manager.js` | Slash command palette, fuzzy search |
| 3 | `context_menu_manager.js` | Right-click menus |
| 3 | `zoom_manager.js` | Canvas zoom, mini-map, field search |

### Field ID Uniqueness

Field IDs are globally unique within a form (across all pages). Move operations preserve IDs. Copy/Paste always generates new IDs.

## Key Files

- `app/javascript/controllers/page_builder_controller.js` — Main Stimulus controller
- `app/javascript/controllers/page_builder/field_manager.js` — Field CRUD, rendering, layout
- `app/javascript/controllers/page_builder/property_manager.js` — Property panel logic
- `app/javascript/controllers/page_builder/drag_drop_manager.js` — Drag-and-drop
- `app/javascript/controllers/page_builder/tab_manager.js` — Sidebar tabs, search
- `app/javascript/controllers/page_builder/save_manager.js` — Save and preview
- `app/javascript/controllers/page_builder/selection_manager.js` — Multi-select
- `app/views/pages/_editor.html.erb` — Main editor template
- `app/views/pages/_property_panel.html.erb` — Property panel template

---

## Phase 1: Foundation — Property Panel Rework + Core UX Fixes

### 1.1 Property Panel Redesign

**Problem:** Flat list of General + Type Settings, same panel structure for layout elements and data fields, no logical grouping.

**Design:** Restructure with tabbed navigation at the top and contextual sections that change based on field category.

**For Data Fields** (text, select, number, date, etc.) — 4 tabs:

| Tab | Contents |
|-----|----------|
| Content | Label, placeholder, help text, default value, options editor (inline for select/radio/checkbox — not a separate modal) |
| Layout | Width (visual 12-col grid picker), spacing (margin top/bottom), alignment |
| Validation | Required toggle, type-specific constraints (min/max length, min/max value, pattern, etc.), custom error messages |
| Advanced | Property slug, autocomplete, conditional visibility summary (link to Rules tab), dynamic options source |

**For Layout Elements** (heading, section, divider, alert, etc.) — 2 tabs:

| Tab | Contents |
|-----|----------|
| Content | Element-specific content (heading text + level, paragraph text, alert text + variant, image URL + alt, etc.) |
| Style | Width, spacing, alignment, variant/color selections |

**For Column Layouts** — 2 tabs:

| Tab | Contents |
|-----|----------|
| Structure | Column count preset selector, individual column width ratios |
| Style | Gap size, padding, border |

**Panel header:** Field type icon + colored badge, field label (editable inline), field type name. Delete button moves from footer to a dropdown menu (...) in the header alongside "Duplicate" and "Copy".

### 1.2 Inline Editing on Canvas

**Problem:** Every edit requires opening the property panel. Changing a label means click field, find label input in panel, type, look back at canvas.

**Design:** Double-click to edit on canvas field cards.

| Element | Inline Edit Behavior |
|---------|---------------------|
| Data fields | Double-click label text — contenteditable, Enter to save |
| Heading | Double-click — edit text, small floating toolbar for heading level (H2/H3/H4) |
| Paragraph | Double-click — edit text with basic formatting |
| Alert/Callout | Double-click — edit message text |
| Button | Double-click — edit button label |
| Section | Double-click section title — edit inline |

- Single-click still selects the field and opens the property panel.
- Escape cancels inline edit and reverts. Enter confirms (Shift+Enter for newlines in paragraph/alert).
- Hover a field card: subtle pencil icon appears on editable text areas to signal double-click availability.

### 1.3 Copy/Paste & Duplicate

**Problem:** No way to duplicate a field or copy between pages. Every field configured from scratch.

**Duplicate:**
- Hover a field card — small action bar (top-right) with icons: Duplicate, Delete
- Keyboard: Select field, Ctrl+D
- Inserted directly below the original
- Auto-generates new ID, appends "_copy" to property_slug ("_copy_2", etc.)
- All properties, options, and type settings deep-cloned

**Copy/Paste:**
- Ctrl+C copies selected field(s) to in-memory clipboard (serialized field config)
- Ctrl+V pastes at current insertion point (after last selected field, or end of page)
- Works across pages in the same builder session
- Multi-select + Ctrl+C copies all selected fields, Ctrl+V pastes in order

**Cut:**
- Ctrl+X cuts (copies + removes from current position)

**Clipboard format:** JSON field config array stored on the controller instance (not system clipboard — avoids permission issues, data structure is complex).

### 1.4 Drag-and-Drop Improvements

**Problem:** Drop zones are subtle, insertion points unclear, drag feedback minimal, moving fields feels unpredictable.

**Visual drop indicators:**
- During drag, bold blue horizontal line (3px, rounded endpoints) at each valid insertion point between rows
- Line spans full canvas width with small blue circle at left end (Notion-style)
- Only one indicator visible at a time — nearest valid drop point to cursor

**Field card drag state:**
- Dragged card gets slight rotation (2-3 degrees) and elevated shadow (shadow-xl) for "lifted" feel
- Original position shows dashed placeholder of same dimensions so layout doesn't collapse

**Column drop zones:**
- Dragging over columns layout: each column highlights with dashed blue border and light blue background tint
- "Drop here" text centered in empty columns

**Smooth animations:**
- After drop, fields animate into position with 200ms ease-out transition (translate + opacity)
- Other fields shift smoothly to accommodate (not instant reflow)

**Auto-scroll:**
- Keep existing 60px trigger zone, add acceleration — scroll speed increases closer to edge
- Smooth scroll (not jumpy)

**Invalid drop feedback:**
- Dragging over non-droppable area: cursor shows `not-allowed`, no drop indicator

### 1.5 Multi-Select Operations

**Problem:** SelectionManager exists but is limited. No bulk operations on selected fields.

**Selection methods:**
- Click selects one field (deselects others)
- Ctrl+Click toggles a field in/out of multi-selection
- Shift+Click selects a range (from last selected to clicked field, in order)
- Ctrl+A selects all fields on current page
- Escape clears selection

**Visual state:**
- Single selected: current blue ring highlight
- Multi-selected: lighter blue ring + blue checkbox icon in top-left corner of each selected card

**Floating action bar** (appears above canvas when 2+ fields selected):
- Field count: "3 fields selected"
- Width buttons: Full | 2/3 | Half | Third (applies to all)
- Duplicate (inserts after last selected)
- Delete (with confirmation: "Delete 3 fields?")
- Group into Section
- **Move to Page** dropdown: lists existing page tabs (current grayed out) + "+ New Page" option. Moves all selected fields to target page end, preserves relative order. Toast: "3 fields moved to Page 2"

**Bulk drag:**
- Multiple fields selected, dragging one drags all as a stack
- Drop inserts in original relative order at drop point

### 1.6 Field Dependency Visualization

**Problem:** Conditional rules exist but no visual indicator on canvas showing which fields have rules or dependencies.

**Canvas indicators:**
- Fields with conditional visibility rules: small eye icon with lightning bolt badge (top-right of card)
- Color-coded: orange for "has conditions", purple for "is referenced by other fields' conditions"
- Hover icon — tooltip: "Shown when: Status = Active" or "Referenced by: Email, Phone"

**Dependency lines (on demand):**
- Click dependency icon on any field — faint curved connector lines draw to all dependent/referenced fields
- Rendered via an SVG overlay layer positioned absolutely over the canvas (programmatic SVG, not custom CSS)
- Lines use same orange/purple color coding
- Click elsewhere or Escape to dismiss

**Property panel integration:**
- Advanced tab shows "Conditional Rules" summary section
- Lists rules in plain English: "Show this field when [Status] equals [Active]"
- "Edit Rules" link opens Rules tab panel with this field pre-selected

---

## Phase 2: Canvas Overhaul — Visual Fidelity + Layout Power

### 2.1 High-Fidelity Field Previews

**Problem:** Canvas shows simplified cards with field type icons and labels. Doesn't resemble actual rendered form.

**Design:** Replace card-style previews with near-actual form element rendering.

| Field Type | Preview Rendering |
|-----------|-------------------|
| Text/Email/URL/Tel/Password | Actual styled `<input>` with placeholder, matching theme input style/radius/size |
| Textarea | Actual `<textarea>` with configured rows and placeholder |
| Select | Styled dropdown showing first option or placeholder |
| Radio/Checkbox | Actual inputs with option labels, in configured layout (inline/vertical) |
| Switch | Toggle switch with on/off labels |
| Number/Currency/Range/Rating | Styled inputs with appropriate controls (arrows, slider, stars) |
| Date/Time | Inputs with date/time picker styling |
| File | File upload zone with accept types shown |
| Rich-text | Mini editor placeholder with toolbar icons |
| Layout elements | Keep as-is, apply theme styles |

**Theme-aware rendering:**
- Canvas previews respect active theme (primary color, font family, input style, border radius, spacing)
- Switching themes updates all field previews immediately

**Interaction boundary:**
- Visual-only: clicking a rendered input doesn't allow typing. Single-click selects. Double-click activates inline label editing (Phase 1).
- Subtle selection overlay (semi-transparent blue border) distinguishes builder card from live form.

### 2.2 Resize Handles

**Problem:** Field width changed via toolbar buttons or property panel dropdown. No direct manipulation.

**Visual handles:**
- When field is selected (single-select only), vertical drag handle on right edge — pill-shaped grabber (6px wide, 32px tall, gray, centered vertically)
- Cursor changes to `col-resize` on hover

**Snap-to-grid behavior:**
- Dragging snaps to the 12-column grid boundaries
- Tooltip near cursor: "6/12 (Half)" or "4/12 (Third)"
- Valid snap points: named widths only (see width system below)
- Faint vertical grid lines appear across canvas during resize

**Width system expansion:**
The existing `WIDTH_CLASSES` map (full/two_thirds/half/third) is extended with two new named widths. All widths remain named strings — no raw column counts.

| Name | Columns | New? |
|------|---------|------|
| full | 12 | existing |
| three_quarters | 9 | new |
| two_thirds | 8 | existing |
| half | 6 | existing |
| third | 4 | existing |
| quarter | 3 | new |

Update `WIDTH_CLASSES` and `WIDTH_COLS` in `field_manager.js` to include the two new entries. The resize handle snaps to these 6 positions only.

**Adjacent field reflow:**
- Resizing past remaining row space wraps next field to new row (smooth animation)
- Shrinking may pull adjacent fields up to fill gap

**Property panel sync:**
- Resize handle updates width in Layout tab in real-time

**Layout template interaction:**
- Resize handles override template `field_width_rules` for that specific field (user customization takes priority)

### 2.3 Responsive Breakpoint Editing

**Problem:** Viewport switcher shows desktop/tablet/mobile but can't set different field widths per breakpoint.

**Per-breakpoint width storage:**
```json
{
  "width": "half",
  "responsive_widths": {
    "tablet": "two_thirds",
    "mobile": "full"
  }
}
```
- `width` is the desktop default
- `responsive_widths` stores overrides only — unset breakpoints inherit from next larger (mobile inherits tablet, tablet inherits desktop)

**Editing workflow:**
- Switch viewport via toolbar (existing feature)
- Canvas resizes to breakpoint width (existing)
- In tablet/mobile viewport, resize handles and width controls operate on that breakpoint's width
- Small breakpoint indicator badge on fields with responsive overrides ("T" or "M" chip)

**Property panel integration:**
- Layout tab shows width for active viewport
- Row of small breakpoint icons (desktop/tablet/mobile) below width control — click to view that breakpoint's width
- "Reset to inherit" link when override exists

**Rendering pipeline:**
- `PageContentGenerator` reads `responsive_widths` and generates Tailwind responsive classes

**Breakpoint mapping:**

| Builder viewport | Tailwind prefix | Pixel threshold | Notes |
|-----------------|-----------------|-----------------|-------|
| Mobile | (none, default) | < 768px | Base styles, no prefix |
| Tablet | `md:` | >= 768px | Matches existing viewport manager (768px) |
| Desktop | `lg:` | >= 1024px | Desktop-first layout |

Example output: A field with `width: "half"`, `responsive_widths: { tablet: "two_thirds", mobile: "full" }` generates:
`col-span-12 md:col-span-8 lg:col-span-6`

### 2.4 Field Groups

**Problem:** No way to treat multiple related fields as a unit. Common patterns like "Address block" rebuilt every time.

**Creating a group:**
- Multi-select 2+ fields — floating action bar shows "Group Fields" button
- Creates a field group: lightweight container with dashed border and group label header
- Group label editable inline (defaults to "Field Group")

**Group behavior on canvas:**
- Click group border/header selects whole group (all fields highlight)
- Drag group moves all fields as a unit
- Click specific field inside group selects just that field
- Group has its own resize handle for container width
- Fields inside group have widths relative to group's internal 12-column grid

**Group in property panel (when group selected):**

| Tab | Contents |
|-----|----------|
| Content | Group label, description (optional subtitle) |
| Layout | Group width, internal padding, border style (none/dashed/solid/subtle), background tint (none/light gray/light blue) |

**Save as template:**
- Group action bar includes "Save as Template" button — visually present but **disabled with tooltip "Available in a future update"** until Phase 3.1 template library is implemented. This is a Phase 3 hook only.

**Nesting rules:**
- Field groups can be placed inside columns (a column can contain a group)
- Columns can NOT be placed inside field groups (groups are leaf containers for fields only)
- Field groups can NOT be nested inside other field groups (max one level of grouping)
- Drag-and-drop respects these constraints: dragging a column into a group shows `not-allowed` cursor
- Dragging a field into/out of a group is allowed — the field joins or leaves the group

**Ungrouping:**
- Select group — action bar or right-click — "Ungroup". Dissolves container, fields remain in place.

**Data structure:**
```json
{
  "id": "group_abc",
  "type": "field_group",
  "label": "Address",
  "width": "full",
  "style": { "border": "subtle", "padding": "normal", "background": "none" },
  "fields": [ ]
}
```

---

## Phase 3: Power Features

### 3.1 Field Templates/Presets

**Problem:** Every field configured from scratch. Common patterns rebuilt repeatedly.

**Template library:**
- New "Templates" tab in left sidebar alongside entity fields and layout elements
- Two categories:
  - **Built-in:** "US Phone", "Email (validated)", "Address Block (US)", "Full Name (first + last)", "Currency (USD)", "Date Range (start + end)", "Yes/No Switch", "Rating (5-star)", "File Upload (images only)"
  - **Custom:** User-saved from existing field/group configurations

**Saving a template:**
- Select field or group — action bar — "Save as Template"
- Modal: template name, category (optional tag), description (optional)
- Saves full config as reusable template
- Scoped per customer (multi-tenant)

**Using a template:**
- Drag from Templates sidebar onto canvas (same as any field)
- Or click to insert at end of current page
- Inserted as independent copy — editing doesn't affect template

**Managing templates:**
- Gear icon in Templates sidebar — template management panel
- List custom templates: edit name, delete
- Built-in templates can be hidden but not deleted

**Storage:**
- New `field_templates` table (see Data Model Changes section for full schema + indexes)

**Service layer (Trailblazer):**
- `FieldTemplate::Create` — Activity for creating a template. Validates via Reform Contract (name presence, name uniqueness per customer, configuration is valid JSON with required field keys).
- `FieldTemplate::Update` — Activity for updating template name/category/description. Prevents editing built-in templates.
- `FieldTemplate::Delete` — Activity for deleting. Prevents deleting built-in templates. Soft-validates no downstream dependencies (informational only, not blocking).
- `FieldTemplate::Contract` — Reform contract: validates `name` (presence, max 100 chars, unique per customer_id), `configuration` (presence, valid structure), `category` (optional, max 50 chars).

### 3.2 Slash Commands

**Problem:** Adding fields requires navigating sidebar or toolbar. Power users want keyboard-driven workflows.

**Activation:**
- Press `/` on canvas (when no field in inline-edit mode) — command palette appears as floating popover, centered on canvas
- Also triggered by clicking "+" inserter buttons and typing "/" in search

**Command palette UI:**
- Text input: "Type a command..."
- Filtered results grouped by category:
  - **Fields:** `/text`, `/email`, `/select`, `/number`, `/date`, `/file`, `/textarea`, `/checkbox`, `/radio`, `/switch`, `/currency`, `/rating`, `/password`, `/tel`, `/url`, `/rich-text`, `/signature`
  - **Layout:** `/section`, `/heading`, `/paragraph`, `/divider`, `/spacer`, `/columns`, `/card`, `/alert`, `/button`, `/image`, `/video`, `/list`, `/code`, `/progress`
  - **Templates:** `/template:<name>` — searches saved templates
  - **Actions:** `/duplicate`, `/delete`, `/copy`, `/paste`, `/undo`, `/redo`, `/preview`, `/save`
  - **Navigation:** `/page:<name>` — switches to page tab

**Behavior:**
- Fuzzy matching: `/em` shows "email" and "template: Email (validated)"
- Arrow keys navigate, Enter selects, Escape dismisses
- Inserted after currently selected field, or at end of page
- `/` only captured when focus on canvas container (not in property panel inputs or inline-edit mode)

### 3.3 Canvas Zoom & Navigation

**Problem:** Large forms (30+ fields) require lots of scrolling. No bird's-eye view.

**Zoom controls:**
- Bottom-right corner: floating toolbar with -, percentage, + buttons
- Levels: 50%, 75%, 100%, 125%, 150%
- Keyboard: Ctrl+Plus/Minus, Ctrl+0 reset
- CSS `transform: scale()` on canvas inner container

**Mini-map (15+ fields):**
- Bottom-left corner, small (120px x 80px)
- Simplified rectangle representation of fields as tiny colored blocks
- Viewport rectangle shows visible area
- Click/drag viewport rectangle to pan
- Hover to expand slightly
- Toggle via map icon button next to zoom controls

**Field search on canvas:**
- Ctrl+F opens search bar at top of canvas
- Non-matching fields dim to 30% opacity, matches stay bright
- Arrow keys/Enter jump between matches (canvas scrolls to center each)
- "3 of 12 matches" counter
- Escape dismisses, restores full opacity

### 3.4 Breadcrumb Navigation

**Problem:** Editing nested fields (inside columns or groups) lacks hierarchy context.

**Breadcrumb bar:**
- Top of property panel, below header, above tabs
- Only shown when selected field is nested
- Format: `Page 1 > Contact Section > Left Column > Email`
- Each segment clickable — selects that container
- Top-level fields: no breadcrumb (unnecessary)

**Hierarchy levels:**
- Page name
- Section (if inside section element)
- Field Group (if inside group)
- Column (if inside columns layout: "Column 1", "Column 2")
- Field name (current selection, not clickable)

**Canvas echo:**
- Hover breadcrumb segment — corresponding container on canvas gets subtle highlight pulse (brief blue border flash)

### 3.5 Context Menu

**Problem:** Field actions scattered across property panel, toolbar, and keyboard shortcuts. No unified right-click menu.

**Right-click on field card:**
- Edit Label (triggers inline edit)
- Duplicate (Ctrl+D)
- Copy (Ctrl+C)
- Cut (Ctrl+X)
- Paste After (Ctrl+V) — grayed out if clipboard empty
- ---
- Width submenu: Full, 3/4, 2/3, Half, Third, Quarter
- Move to Page submenu: list of pages + "New Page"
- ---
- Group with... (enters pick-fields mode)
- Save as Template
- ---
- Delete (Delete key)

**Right-click on empty canvas:**
- Paste (if clipboard has fields)
- Add Field (opens slash command palette)
- Select All (Ctrl+A)

**Right-click on field group:**
- Same as field menu, plus: Ungroup, Save Group as Template

**Right-click on column container:**
- Add Column
- Remove Column (moves fields to parent)
- Change Layout submenu (column presets)

**Styling:** Tailwind dropdown — shadow-lg, rounded-lg, white bg, text-sm. Keyboard navigable (arrow keys, Enter, Escape).

---

## Keyboard Shortcuts Summary

| Shortcut | Action |
|----------|--------|
| Ctrl+C | Copy selected field(s) |
| Ctrl+V | Paste at insertion point |
| Ctrl+X | Cut selected field(s) |
| Ctrl+D | Duplicate selected field |
| Ctrl+A | Select all fields on page |
| Ctrl+Z | Undo |
| Ctrl+Shift+Z | Redo |
| Ctrl+S | Save |
| Ctrl+F | Field search on canvas |
| Ctrl+Plus | Zoom in |
| Ctrl+Minus | Zoom out |
| Ctrl+0 | Reset zoom to 100% |
| Delete | Delete selected field(s) |
| Escape | Clear selection / cancel inline edit / dismiss palette |
| / | Open slash command palette |
| Double-click | Inline edit (label, heading, paragraph, etc.) |

## Data Model Changes

### New table: `field_templates` (Phase 3)

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | Primary key |
| customer_id | bigint | FK, multi-tenant scope |
| name | string | Template display name |
| category | string | Optional grouping tag |
| description | text | Optional description |
| configuration | jsonb | Full field/group config |
| built_in | boolean | Default false, protects from deletion |
| created_at | datetime | |
| updated_at | datetime | |

**Indexes:**
- `index_field_templates_on_customer_id`
- `index_field_templates_on_customer_id_and_category`
- `index_field_templates_on_customer_id_and_built_in`

### Field config additions

```json
{
  "responsive_widths": {
    "tablet": "two_thirds",
    "mobile": "full"
  }
}
```

Added to individual field objects. Absent = inherit from desktop `width`.

### Field group config (new node type)

```json
{
  "id": "group_abc",
  "type": "field_group",
  "label": "Address",
  "width": "full",
  "style": {
    "border": "subtle",
    "padding": "normal",
    "background": "none"
  },
  "fields": []
}
```

Sits alongside regular field objects in the page's `fields` array.

---

## Undo/Redo Integration

All state-mutating operations push to the existing `UndoRedoManager` history stack. One undo entry per logical action:

| Operation | Undo Entry | Granularity |
|-----------|-----------|-------------|
| Inline edit (label, heading, etc.) | On confirm (Enter/blur), not per keystroke | One entry per edit session |
| Duplicate field | One entry | Restores to pre-duplicate state |
| Paste field(s) | One entry | Removes all pasted fields |
| Cut field(s) | One entry | Restores fields to original positions |
| Delete field(s) | One entry | Restores all deleted fields |
| Resize (drag handle) | On drag-end only | One entry per resize, not per snap |
| Bulk width change | One entry | Reverts all fields to prior widths |
| Move to page | One entry | Moves fields back to original page |
| Group fields | One entry | Ungroups and restores original layout |
| Ungroup | One entry | Re-creates the group |
| Reorder (drag-and-drop) | On drop | One entry per reorder |

---

## Testing Strategy

### Phase 1

**Component specs (RSpec + ViewComponent):**
- `PageBuilder::PropertyPanel::TabbedPanelComponent` — renders correct tabs per field category
- `PageBuilder::FloatingActionBarComponent` — shows correct actions for selection count
- `PageBuilder::FieldActionBarComponent` — renders duplicate/delete icons
- `PageBuilder::DependencyBadgeComponent` — renders correct color/tooltip for rule types

**System specs (RSpec + Capybara):**
- Property panel: selecting different field types shows correct tabs and settings
- Inline editing: double-click label, edit, confirm with Enter, verify persistence
- Copy/paste: copy field, paste on same page and different page, verify new IDs
- Duplicate: Ctrl+D creates clone with "_copy" slug
- Multi-select: Ctrl+Click, Shift+Click, bulk delete, bulk width change
- Move to page: select fields, move to existing page and new page
- Drag-and-drop: reorder fields, verify drop indicator appears

### Phase 2

**Component specs:**
- `PageBuilder::ResizeHandleComponent` — renders handle at correct position
- `PageBuilder::FieldGroupComponent` — renders container with label, border, nested fields

**System specs:**
- High-fidelity previews: verify field cards render actual input elements matching theme
- Resize handles: drag to resize, verify snap to grid, verify property panel sync
- Responsive editing: switch viewport, change width, verify responsive_widths stored
- Field groups: create group, drag group, ungroup, verify nesting constraints

### Phase 3

**Model/Request specs:**
- `FieldTemplate` model validations
- Trailblazer Activity specs: Create, Update, Delete operations
- Reform Contract specs: validation rules for name, configuration

**Component specs:**
- `PageBuilder::CommandPaletteComponent` — renders categories, fuzzy search
- `PageBuilder::ContextMenuComponent` — renders correct items per context
- `PageBuilder::BreadcrumbComponent` — renders hierarchy for nested fields
- `PageBuilder::ZoomControlsComponent` — renders zoom levels
- `PageBuilder::MiniMapComponent` — renders field blocks

**System specs:**
- Slash commands: open palette, search, select, verify field inserted
- Context menu: right-click field, group, column, empty canvas — verify correct options
- Zoom: zoom in/out, verify canvas scales
- Field search: Ctrl+F, type query, verify matching fields highlighted
- Breadcrumbs: select nested field, verify breadcrumb renders, click segment to navigate
- Templates: save template, use template, manage templates
