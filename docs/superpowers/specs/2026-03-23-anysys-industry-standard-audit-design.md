# Anysys — Industry Standard Audit & Missing Features Design

**Date:** 2026-03-23
**Status:** Draft
**Scope:** Comprehensive UX and feature audit comparing the Anysys against industry-standard diagramming tools (Lucidchart, draw.io, Miro) and workflow automation builders (n8n, Zapier, Node-RED, Retool Workflows)

---

## Context

The Anysys serves a dual purpose: it is both a **visual diagramming tool** and an **executable workflow builder** that generates Trailblazer Activity code. This audit evaluates the current implementation against both categories of industry-standard tools.

### Current State Summary

- **Canvas:** Custom SVG-based, fixed 2000x1500px, no zoom/pan. Snap-to-grid exists (GRID_SIZE=15px). Multi-select via Ctrl+drag selection rectangle exists.
- **Element types:** Start, End, Process, Decision, Loop, Subflow
- **Properties:** Schema-driven with delegated managers (StepManager, BranchManager, IOManager, FormBuilder)
- **Connections:** Bezier curves, from/to with position, no editable properties
- **Persistence:** JSON configuration blob, autosave, undo/redo in memory only
- **Code generation:** ActivityGenerator converts flowchart to Trailblazer Activity Ruby code
- **Related specs:** This audit builds upon the March 22 enrichment spec (`2026-03-22-flowchart-element-enrichment-design.md`) which added errorHandling to Process, structured conditions to Decision/Loop, and context-aware operands. Items in this audit extend (not replace) that work.

---

## Audit Findings

### Priority Tiers

- **Tier 1 (Critical):** Every standard flowchart/workflow tool has these — absence makes the tool feel unfinished
- **Tier 2 (Expected):** Serious tools have these — absence feels incomplete to experienced users
- **Tier 3 (Premium):** Differentiators for advanced tools — nice-to-have

---

## Section 1: Canvas Interaction Gaps

### Tier 1 — Critical

#### 1. Zoom and Pan

**Industry standard:** Scroll-to-zoom, drag-to-pan (middle mouse or Space+drag), zoom controls (+/-/fit-to-screen), pinch-to-zoom on trackpad.

**Current state:** Fixed 2000x1500px canvas with browser-native scrolling only. No zoom level control.

**Impact:** Working with any non-trivial flowchart (10+ elements) becomes painful. Users cannot get an overview or focus on details.

**Design:**
- Add SVG viewBox-based zoom (not CSS transform — preserves SVG coordinate fidelity)
- Zoom controls in toolbar: +, -, fit-to-screen, zoom percentage indicator
- Scroll wheel = zoom (with Ctrl modifier to differentiate from scroll)
- Space + drag = pan (standard diagramming convention)
- Pinch-to-zoom for trackpad users
- Zoom range: 25% to 200%, default 100%
- Fit-to-screen: calculate bounding box of all elements, set viewBox to fit with padding

#### 2. Snap-to-Grid Enhancements

**Industry standard:** Elements snap to grid intersections during drag. Toggle on/off. Visual grid dots. Configurable grid size.

**Current state:** Snap-to-grid already exists (`GRID_SIZE = 15px` in `constants/canvas.js`, `snapToGrid()` utility used throughout `drag_handler.js`). Visual grid pattern rendered in SVG. Alignment guides also present.

**What's missing vs industry standard:**
- No toggle to disable snap-to-grid (Alt key escape hatch)
- No configurable grid size
- Grid dots don't adapt to zoom level

**Design:**
- Hold Alt to temporarily disable snap during drag
- Grid size configurable via canvas metadata (default remains 15px)
- Visual grid dots fade at low zoom levels, increase density at high zoom

#### 3. Copy/Paste

**Industry standard:** Ctrl+C/V to duplicate selected elements. Paste offsets slightly from original. Connections between copied elements preserved.

**Current state:** No copy/paste. Must drag new elements from palette every time.

**Impact:** Rebuilding similar process chains from scratch is tedious.

**Design:**
- Ctrl+C: serialize selected elements + internal connections to clipboard (in-app clipboard, not system)
- Ctrl+V: deserialize and place at mouse position (or offset +20,+20 from original)
- Ctrl+D: duplicate in place (shortcut for copy+paste)
- New element IDs generated on paste
- Connections between pasted elements preserved; connections to non-pasted elements dropped
- Multi-element copy supported

#### 4. Element Resize

**Industry standard:** Drag handles on element corners/edges to resize. Minimum size enforced. Connections reattach to resized element.

**Current state:** All elements fixed at 100x45px.

**Impact:** Long labels get truncated. Process elements with many steps need more visual space. Elements with long names look cramped.

**Design:**
- Resize handles on 4 corners and 4 edge midpoints (8 handles total)
- Minimum size: 60x30px
- Maximum size: 400x200px
- Connection handles reposition proportionally on resize
- Label text wraps within element bounds
- Double-click element edge to auto-fit to label content

#### 5. Alignment Tools

**Industry standard:** Toolbar or right-click menu: align left/center/right/top/middle/bottom, distribute horizontally/vertically evenly.

**Current state:** No alignment tools. Alignment guides appear during drag but no explicit commands.

**Impact:** Manually aligning a row of elements is error-prone and slow.

**Design:**
- Alignment toolbar appears when 2+ elements selected
- Options: Align Left, Align Center, Align Right, Align Top, Align Middle, Align Bottom
- When 3+ elements selected, add: Distribute Horizontally, Distribute Vertically
- Each operation is a single undoable action

### Tier 2 — Expected

#### 6. Minimap

**Industry standard:** Small overview panel (bottom-right corner) showing the full diagram with a viewport rectangle. Click/drag on minimap to navigate.

**Design:**
- Rendered as a scaled-down SVG clone in a fixed 200x150px panel
- Shows element positions as colored dots/rectangles
- Blue rectangle indicates current viewport
- Drag viewport rectangle to pan
- Click anywhere on minimap to jump
- Toggle visibility with toolbar button
- Only show when canvas has content outside current viewport

#### 7. Auto-Layout

**Industry standard:** Button to automatically arrange elements in a clean hierarchy (top-to-bottom or left-to-right).

**Design:**
- Dagre or similar hierarchical layout algorithm
- Top-to-bottom layout (matches flowchart convention)
- Preserve connection topology
- Single undoable action
- Toolbar button: "Auto Arrange"
- Layout respects element sizes and maintains minimum spacing

#### 8. Connection Labels

**Industry standard:** Click a connection to select it, type to add/edit label. Labels rendered at connection midpoint.

**Note:** This item shares the `label` field with Item #17 (Connection Properties). They should be implemented together — Item #17 adds the full `label` + `properties` structure, and this item covers the inline editing UX.

**Design:**
- Double-click connection to enter label edit mode (inline text input at midpoint)
- Label rendered at bezier midpoint with white background pill
- Decision branch labels auto-populated from branch value
- Label stored in connection data structure (see Item #17 for full schema)
- Also editable via property editor when connection selected

#### 9. Connection Routing Options

**Industry standard:** Choose between straight lines, orthogonal (right-angle) paths, or curved (bezier) paths.

**Design:**
- Three routing modes: Bezier (current default), Orthogonal, Straight
- Set per-flowchart in canvas metadata (not per-connection)
- Toolbar toggle or canvas settings
- Orthogonal routing: horizontal/vertical segments with 90-degree turns, auto-routed around elements

#### 10. Dynamic Canvas Size

**Industry standard:** Infinite canvas that grows as elements are placed near edges. No fixed boundary.

**Design:**
- Remove fixed 2000x1500 boundary
- Canvas extends dynamically: when any element is within 200px of edge, extend canvas by 500px
- Fit-to-screen zoom adjusts to actual content bounding box
- Metadata stores content bounds, not canvas size

### Tier 3 — Premium

#### 11. Element Grouping

**Design:** Select multiple elements → right-click → "Group". Grouped elements move/copy/delete together. Visual dashed border around group. Ungroup to restore individual control.

#### 12. Keyboard Shortcuts for Adding Elements

**Design:** With no element selected, press hotkey to create element at canvas center: S=Start, E=End, P=Process, D=Decision, L=Loop, F=subFlow. Show hints in palette.

#### 13. Multi-Page Diagrams

**Design:** Tab bar above canvas for multiple pages within one flowchart. Each page has independent elements/connections. Not recommended for initial implementation — subflows already serve this purpose.

---

## Section 2: Element Properties Gaps

### Tier 1 — Critical

#### 14. Compound Conditions (Decision Element)

**Industry standard:** Combine multiple conditions with AND/OR/NOT operators. Nested condition groups. Visual condition builder tree.

**Current state:** Single structured condition from March 22 enrichment: `{ leftOperand, operator, rightOperand, expression }` with context-aware operands (entity fields, parent outputs, custom values). Works well for simple comparisons.

**Impact:** Real business logic almost always requires compound conditions. Users must chain multiple Decision elements as workaround.

**Design — extends the existing single condition structure:**
- Wrap existing condition format in a group structure:
  ```json
  {
    "type": "group",
    "operator": "AND",
    "conditions": [
      { "type": "comparison", "leftOperand": "ctx.model.status", "operator": "==", "rightOperand": "active" },
      { "type": "comparison", "leftOperand": "ctx.model.role", "operator": "!=", "rightOperand": "guest" }
    ]
  }
  ```
- Each `comparison` item uses the same `{ leftOperand, operator, rightOperand }` structure already implemented in BranchManager, including context-aware operands and custom value toggle
- **Migration from existing format:** Single conditions `{ leftOperand, operator, rightOperand }` (without `type` field) are auto-wrapped as `{ type: "group", operator: "AND", conditions: [{ type: "comparison", ...existingCondition }] }` on load
- UI: Condition rows with AND/OR toggle between them (reuses existing condition row rendering from BranchManager)
- "Add condition" button appends to group
- "Add group" button for nested AND/OR groups (max 2 levels deep)
- Expression preview updates in real-time: `ctx.model.status == "active" AND ctx.model.role != "guest"`
- ActivityGenerator compiles to Ruby: `ctx.dig(:model, :status) == "active" && ctx.dig(:model, :role) != "guest"`
- **Also applies to Loop element** which uses the same structured condition builder

#### 15. Loop Type Selection

**Industry standard:** Distinct loop modes: For-Each (iterate over collection), While (condition-based), Do-While (execute at least once).

**Current state:** Only while-style with structured condition (migrated from free-text per March 22 enrichment) + max iterations.

**Design — extends existing Loop schema:**
- Add `loopType` property to Loop schema: `"for_each"`, `"while"` (default, current behavior), `"do_while"`
- **For-Each mode:**
  - `collection` field: select from context variables (e.g., `ctx.model.items`)
  - `itemVariable` field: variable name for current item (e.g., `item`)
  - `indexVariable` field: optional index variable (e.g., `index`)
  - No condition builder — iterates entire collection
  - Max iterations still applies as safety limit
- **While mode:** Current behavior (condition checked before body)
- **Do-While mode:** Same as while but condition checked after body (guaranteed at least one execution)
- UI: Radio group at top of Loop properties selects mode, form adapts below
- ActivityGenerator handles each mode differently:
  - For-each: `ctx[:items].each_with_index do |item, index|`
  - While: `while condition` (current)
  - Do-while: `loop do ... break unless condition end`

#### 16. Parallel/Fork-Join Element

**Industry standard:** Fork element splits execution into parallel branches. Join element waits for all branches to complete before continuing.

**Current state:** All flow is strictly sequential.

**Impact:** Cannot model concurrent operations (e.g., "send email AND update database simultaneously").

**Design:**
- Two new element types:
  - **Fork** (parallel split): Multiple outgoing connections, all execute concurrently
    - Shape: Horizontal bar (BPMN convention) or diamond with "+" icon
    - Color: Indigo theme
    - Properties: just inputs/outputs/description
  - **Join** (parallel merge): Multiple incoming connections, waits for all
    - Shape: Matching horizontal bar
    - Properties: merge strategy (wait_all, wait_any, wait_first), timeout
- Canvas enforces: Fork must have 2+ outgoing connections, Join must have 2+ incoming
- **ActivityGenerator impact (significant):**
  - Current DFS traversal (`dfs_collect_steps`) produces a linear step sequence — must be modified to detect Fork elements and collect parallel branches separately
  - Fork detection: when DFS encounters a Fork element, collect each outgoing branch as a separate step group until a matching Join is found
  - Code generation: emit sequential execution of branch groups initially (each branch as a nested `step` block)
  - `step_declarations` and `step_methods` need restructuring to handle branch groups
  - True parallelism (threading) deferred to future enhancement
- **Initial implementation executes branches sequentially** (left-to-right order) — this still provides value by modeling the intent of parallel work and enabling future parallelism without flowchart changes
- **Validation:** Fork must have matching Join downstream. Each Fork outgoing path must converge at the same Join element. Nested Fork/Join pairs (Fork inside a Fork branch) are not supported in initial implementation — enforce max 1 level of Fork/Join nesting via validation.

#### 17. Connection Properties

**Industry standard:** Connections carry metadata: labels, conditions, priority/weight, data transformations.

**Current state:** Connections only store `from`, `to`, `fromPosition`, `toPosition` — no editable properties.

**Impact:** Branch labels must be inferred. No way to annotate or configure data flow on connections.

**Design:**
- Extend connection data structure:
  ```json
  {
    "id": "conn_...",
    "from": "el_...",
    "to": "el_...",
    "fromPosition": "bottom",
    "toPosition": "top",
    "label": "yes",
    "properties": {
      "description": "",
      "priority": 0,
      "condition": null
    }
  }
  ```
- Click connection to select → property editor shows connection properties
- Label editable inline (double-click) or via property editor
- Decision outgoing connections auto-labeled from branch values
- Priority field used for ordering when multiple connections leave same element

#### 18. Element Color/Style Customization

**Industry standard:** Right-click or property editor allows custom fill color, border color, and border style per element instance.

**Current state:** Colors hardcoded per element type.

**Design:**
- Add `style` to element data structure:
  ```json
  {
    "style": {
      "fill": "#f0fdf4",
      "stroke": "#10b981",
      "strokeWidth": 2
    }
  }
  ```
- Property editor: color picker for fill and stroke (limited palette of 12 preset colors + custom hex)
- Default: current type-based colors (so existing flowcharts unchanged)
- Canvas renderer reads `element.style` and falls back to type defaults
- **Cross-cutting concern:** This touches both the property editor (schema + form rendering) and the SVG canvas renderer (element rendering must check `element.style` before falling back to type-based colors from `ELEMENT_COLORS`). The canvas renderer changes should be coordinated with Phase 1 canvas work.

### Tier 2 — Expected

#### 19. Retry/Timeout on Process Steps

**Design:**
- Per-step configuration in step modal:
  - `retryCount`: 0-5 (default 0)
  - `retryBackoff`: "none", "linear", "exponential" (default "none")
  - `timeout`: milliseconds (0 = no timeout, default 0)
- ActivityGenerator wraps step in retry loop with backoff logic
- UI: Collapsible "Advanced" section in step modal

#### 20. Conditional Execution Per Step

**Design:**
- Per-step `guard` condition: same structured condition builder as Decision
- Step only executes if guard evaluates to true
- UI: Optional "Run only if..." toggle in step modal, reveals condition builder
- ActivityGenerator wraps step body in `if guard_condition`

#### 21. Start Element Trigger Type

**Design:**
- Add `triggerType` property to Start schema:
  - `"manual"` (default — current behavior)
  - `"http"` — HTTP endpoint trigger (method, path pattern)
  - `"event"` — event listener (event name, source)
  - `"schedule"` — cron-based (cron expression)
- Properties form adapts based on trigger type
- ActivityGenerator generates appropriate entry point code
- **Note:** This is metadata only for initial implementation — actual trigger wiring is a separate infrastructure concern

#### 22. End Element Response Configuration

**Design:**
- Add properties to End schema:
  - `responseType`: "none" (default), "value", "http_response"
  - `returnValue`: context field path in dot-notation to return, e.g. `ctx.model` (for "value" type)
  - `httpStatus`: status code (for "http_response" type)
  - `responseBody`: context field path in dot-notation for response body, e.g. `ctx.response`
- ActivityGenerator generates appropriate return/response code

#### 23. Error/Catch Element Type

**Design:**
- New element type: **Error Handler**
  - Shape: Rounded rectangle with lightning bolt icon
  - Color: Orange theme
  - Properties: error types to catch (array), retry behavior, fallback action
- Can be attached to any Process element (visual dashed connection)
- When attached Process fails, execution routes to Error Handler
- Provides richer error handling than current halt/route_to_error_end modes
- **Simplification:** Could defer this if current errorHandling modes are extended instead

#### 24. Delay/Timer Element

**Design:**
- New element type: **Timer**
  - Shape: Rounded rectangle with clock icon
  - Color: Slate/gray theme
  - Properties: `delayType` ("fixed", "until_condition", "until_event"), `duration` (ms/s/m/h), condition or event name
- ActivityGenerator generates `sleep` or polling logic
- **Note:** True async waiting requires infrastructure support — initial implementation can be synchronous sleep

### Tier 3 — Premium

#### 25. Annotations/Comments on Elements

**Design:** Comment icon on each element. Click to open comment thread. Stored in element properties as `comments` array. Visual indicator (dot) when comments exist.

#### 26. Property Templates/Presets

**Design:** "Apply Template" button in Process property editor. Presets like "CRUD Create" (new_model → build_contract → validate → save_model), "CRUD Read" (find_model → render_response), "CRUD Delete" (find_model → destroy_model). Templates pre-fill steps array.

#### 27. Advanced Branch Condition Types

**Design:** Extend Decision branches with pattern matching (`matches_regex`), range checks (`in_range`), type checking (`is_type`), and null checks (`is_nil`). Add these as additional operator types in BRANCH_OPERATORS.

---

## Section 3: Flow Building Workflow Gaps

### Tier 1 — Critical

#### 28. Flowchart Validation

**Industry standard:** "Validate" button that checks structural integrity and completeness before code generation.

**Current state:** No validation — broken flowcharts are saved and fail at code generation time.

**Impact:** Users discover errors late, error messages from ActivityGenerator are cryptic.

**Design:**
- Validation rules:
  - **Structural:** Exactly one Start element. At least one End element. No orphan elements (every element must have at least one connection). No unreachable elements (all elements reachable from Start via BFS/DFS).
  - **Completeness:** All required properties filled (based on schema `required` flags). Decision elements have at least 2 outgoing connections. Process elements have at least 1 step.
  - **Connections:** No duplicate connections between same elements. No self-connections. Connection endpoints reference existing elements.
  - **Cycles:** Warn on cycles that don't involve Loop elements (potential infinite loops).
- UI:
  - "Validate" button in toolbar (next to Save)
  - **Autosave bypasses validation** — autosave preserves work-in-progress regardless of errors (blocking autosave on incomplete flowcharts would cause data loss during construction)
  - **Manual Save** runs validation: warnings shown but don't block, errors shown with option to "Save Anyway" (escape hatch) or fix first
  - **Code Generation** strictly blocks on validation errors — invalid flowcharts cannot generate Activity code
  - Problems panel at bottom of canvas listing all issues
  - Click issue to highlight and zoom to problem element (with red glow)
  - Element badges: red dot on elements with errors, yellow dot for warnings
- Validation service: pure JavaScript, runs client-side for instant feedback
- Also runs server-side in ActivityGenerator as a guard before code generation

#### 29. Inline Testing/Debugging

**Industry standard:** "Run" button executes the flow with test data. Execution path highlighted on canvas. Step-through mode with data inspection at each node.

**Current state:** Trace endpoint exists (`POST /:customer_id/flowcharts/:id/trace`) but is separate from the visual editor.

**Design:**
- **Test Panel:** Slide-up panel at bottom of canvas for test input/output
  - Input: JSON editor for initial context data (pre-populated from Start inputs)
  - Output: execution result with final context
- **Visual Execution Trace:**
  - After running, highlight executed path in green, skipped elements in gray
  - Show execution order numbers on each visited element
  - Click element to see context snapshot at that point (inputs/outputs values)
- **Step-Through Mode (Tier 2 enhancement):**
  - "Step" button advances one element at a time
  - Current element highlighted with pulsing border
  - Context inspector panel shows live data
- **Integration:** Calls existing `POST /:customer_id/flowcharts/:id/trace` endpoint via `ActivityTracer` service
  - Expected response structure: `{ success: bool, trace: [{ element_id, status ("pass"/"fail"), context_snapshot: {}, duration_ms }], error: { element_id, message } }`
  - Front-end maps `trace[].element_id` to canvas elements for visual overlay
  - If ActivityTracer response format differs, an adapter layer normalizes it
- **Error Display:** If execution fails, highlight failing element in red with error message tooltip

#### 30. Undo/Redo Persistence & Navigation Warning

**Industry standard:** At minimum, warn before navigating away with unsaved changes. Better: persist undo history across page refresh.

**Current state:** Undo/redo in memory only. Lost on refresh. No unsaved changes warning.

**Design:**
- **Phase 1:** `beforeunload` event handler warns when unsaved changes exist
- **Phase 2:** Persist undo stack to `sessionStorage` (survives refresh, cleared on tab close)
- **Phase 3 (optional):** Server-side version snapshots for long-term undo
- Track dirty state: compare current configuration hash with last saved hash
- Visual indicator: "Unsaved changes" badge near Save button

#### 31. Export

**Industry standard:** Export as PNG, SVG, PDF for documentation and presentation.

**Design:**
- **SVG Export:** Serialize current canvas SVG, strip interactive elements (handles, selection), add stylesheet inline. Cleanest output.
- **PNG Export:** Render SVG to Canvas element, then `toDataURL('image/png')`. Configurable resolution (1x, 2x).
- **PDF Export:** Server-side using Grover gem (headless Chrome) for SVG-to-PDF conversion
- Export button in toolbar with dropdown: SVG, PNG, PDF
- Exported image includes all visible elements at current zoom/pan or fit-to-content
- File named: `{flowchart_name}_{date}.{ext}`

### Tier 2 — Expected

#### 32. Flowchart Templates

**Design:**
- Template selection on flowchart creation (instead of bare Start + Process)
- Built-in templates:
  - **Blank** (current behavior)
  - **CRUD Create:** Start → Process(new_model, build_contract, validate, save_model) → End
  - **CRUD Read:** Start → Process(find_model) → Decision(found?) → Process(render_response) / End(not_found)
  - **CRUD Update:** Start → Process(find_model, build_contract, validate, save_model) → End
  - **CRUD Delete:** Start → Process(find_model, destroy_model) → End
  - **API Integration:** Start(http) → Process(validate) → Process(API_call) → Decision(success?) → End
- Templates stored as JSON configuration presets
- Template selection UI: card grid with template name, description, visual preview
- Custom templates: user can save current flowchart as template (Tier 3)

#### 33. Version History

**Design:**
- Store configuration snapshots on each manual save (not autosave)
- `flowchart_versions` table: `id, flowchart_id, configuration, created_at, description`
- UI: "History" button opens version list panel
- Click version to preview (read-only overlay)
- "Restore" button to revert to selected version (creates new version, not destructive)
- Limit: keep last 50 versions per flowchart

#### 34. Search Within Flowchart

**Design:**
- Ctrl+F or search icon in toolbar opens search bar
- Search matches against: element labels, step action names, condition expressions, property values, descriptions
- Results shown as list below search bar with element type icon and label
- Click result to select and center element on canvas
- Highlight matching elements with colored border
- Real-time filtering as user types

#### 35. Bulk Property Viewing / Problems Panel

**Design:**
- "Elements" tab in a bottom panel listing all elements in table form:
  - Columns: Type (icon), Label, Steps/Condition summary, Connections (in/out count), Status (valid/warning/error)
  - Click row to select and center element
  - Sort by type, label, or status
- "Problems" tab showing validation issues (see #28)
- Toggle panel with toolbar button or keyboard shortcut

### Tier 3 — Premium

#### 36. Collaboration

**Design:** Deferred. Multi-user editing requires WebSocket infrastructure (ActionCable). Minimum viable: optimistic locking — warn if another user saved while you were editing. Real-time cursors and co-editing as future enhancement.

#### 37. Documentation Generation

**Design:** "Generate Docs" button produces a Markdown document describing the flow: element list with properties, execution path narrative, input/output specifications, decision logic summary. Useful for technical documentation.

#### 38. Import From Other Formats

**Design:** Support BPMN 2.0 XML import (most universal interchange format). Map BPMN elements to application element types. Lossy conversion with warnings for unsupported BPMN elements. Export to BPMN as companion to import.

---

## Implementation Priority Recommendation

### Phase 1: Foundation (Critical Canvas + Validation)
Items: #1 (zoom/pan), #3 (copy/paste), #5 (alignment), #10 (dynamic canvas), #28 (validation), #30 (undo persistence + nav warning)

**Rationale:** These are the most impactful items that affect every single interaction with the tool. Note: #2 (snap-to-grid) already exists — only minor enhancements needed (Alt-to-disable, zoom-adaptive grid), which can be done alongside #1 zoom/pan.

### Phase 2: Properties Enrichment
Items: #14 (compound conditions), #15 (loop types), #17 (connection properties), #18 (element styles), #8 (connection labels)

**Rationale:** Makes the property system match what users expect from a workflow builder.

### Phase 3: Productivity Features
Items: #4 (element resize — depends on Phase 1 zoom/pan coordinate transforms), #29 (inline testing), #31 (export), #32 (templates), #34 (search)

**Rationale:** These are the features that turn the tool from "functional" to "productive."

### Phase 4: Advanced Elements
Items: #16 (fork/join), #21 (trigger types), #22 (end response), #19 (retry/timeout), #20 (conditional steps)

**Rationale:** Expands the modeling capabilities for complex workflows.

### Phase 5: Power User Features
Items: #6 (minimap), #7 (auto-layout), #9 (connection routing), #33 (version history), #35 (bulk view)

**Rationale:** Polish and advanced features for power users.

### Phase 6: Premium (as needed)
Items: #11, #12, #13, #23, #24, #25, #26, #27, #36, #37, #38

---

## Technical Considerations

### Existing Capabilities (Prerequisites Already Met)
- **Multi-select** already exists via Ctrl+drag selection rectangle (`selection_manager.js`). Items #3 (copy/paste), #5 (alignment), #11 (grouping) can build on this directly.
- **Snap-to-grid** already exists at 15px (`canvas.js`, `drag_handler.js`). Only minor enhancements needed.

### Canvas Architecture Impact
- Zoom/pan (#1) requires SVG viewBox management — affects all coordinate calculations (mouse position, element positioning, connection routing)
- This is the most architecturally impactful change and should be implemented first as other features depend on correct coordinate transforms
- Element resize (#4) must use the same coordinate transform utilities introduced by zoom/pan — explicit dependency

### Schema Extensibility
- Compound conditions (#14) and loop types (#15) extend the structures already established by the March 22 enrichment spec. Migration wraps existing single conditions in group structure.
- **Context field path convention:** All property values referencing context fields use dot-notation (`ctx.model.status`) consistently. ActivityGenerator handles conversion to Ruby (`ctx.dig(:model, :status)` or `ctx[:field]`).

### New Element Types
- Fork/Join (#16), Error Handler (#23), Timer (#24) require:
  - New entries in ELEMENT_SCHEMAS
  - New palette components
  - New SVG rendering shapes
  - New ActivityGenerator handlers
  - Validation rules specific to each type

### External Dependencies
- Auto-layout (#7) references Dagre.js (~30KB). Given the project's StimulusJS-only stance (per AGENTS.md), evaluate whether a layout library is an acceptable exception or if a simpler custom hierarchical layout is preferred. A basic top-down tree layout could be implemented without external dependencies.
- PDF export (#31): Grover gem (headless Chrome wrapper) is recommended over Prawn for SVG-to-PDF, as Prawn's SVG support is limited.

### Performance
- Minimap (#6) requires rendering a second scaled SVG — use requestAnimationFrame throttling
- Search (#34) should index element data on load, not search raw configuration on each keystroke
- Validation (#28) should run incrementally when possible (validate changed element only)

### Data Growth
- Version history (#33): The dedicated `flowchart_versions` table is strongly recommended over the JSON array column alternative. Flowchart configurations can be large, and storing 10+ copies in a single column causes significant row bloat.

---

## Out of Scope

- Real-time collaboration (requires significant infrastructure)
- Mobile/touch support
- Custom element type creation by users
- Plugin/extension system
- AI-assisted flowchart generation
