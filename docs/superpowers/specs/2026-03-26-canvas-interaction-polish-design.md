# Canvas Interaction Polish Design Spec

**Date:** 2026-03-26
**Scope:** Improve connection rendering and selection/drag feedback on the flowchart canvas
**Style Reference:** n8n/Retool — smooth connections, clear selection states, tactile drag feedback

---

## Change 1: Connection Color Update

Update `CONNECTION_STYLE` in `connection_renderer.js`:
- `defaultColor`: `#666666` → `#94a3b8` (slate-400)
- `hoverColor`: `#3b82f6` → `#6366f1` (indigo-500)
- `selectedColor`: `#2563eb` → `#4f46e5` (indigo-600)

**Files:** `app/javascript/flowchart/connection_renderer.js`

---

## Change 2: Rounded Corners on Orthogonal Paths

Replace sharp 90-degree turns with smooth curves. In `ConnectionRenderer.pointsToPath()`, detect corners (where direction changes) and replace the corner point with a quadratic bezier curve (`Q`) using a small radius (8px).

For a path like `M 100 200 L 100 300 L 200 300`:
- The corner at (100, 300) becomes a smooth curve
- Output: `M 100 200 L 100 292 Q 100 300 108 300 L 200 300`

**Files:** `app/javascript/flowchart/connection_renderer.js`

---

## Change 3: Animated Flow on Hover

When hovering a connection, add a flowing dash animation to show direction. Add CSS keyframes in the SVG `<style>` block (in `canvas.js` `_drawGrid`):

```css
.connection-line.flow-animated {
  stroke-dasharray: 6 4;
  animation: connectionFlow 0.6s linear infinite;
}
@keyframes connectionFlow {
  to { stroke-dashoffset: -10; }
}
```

In `connection_manager.js` `_attachConnectionHoverEvents`, add/remove the `flow-animated` class on mouseenter/mouseleave.

**Files:** `app/javascript/flowchart/canvas.js`, `app/javascript/flowchart/connection_manager.js`

---

## Change 4: Visible Selection Outline

Add CSS for the `.selected` class on element groups. In `canvas.js` `_drawGrid` SVG `<style>`:

```css
.selected rect,
.selected ellipse,
.selected polygon,
.selected path.shape-path {
  stroke: #6366f1 !important;
  stroke-width: 2.5;
  stroke-dasharray: 6 3;
}
```

**Files:** `app/javascript/flowchart/canvas.js`

---

## Change 5: Selection Rectangle to Indigo

Update `SELECTION_STYLE` in `selection_manager.js`:
- `fill`: `rgba(59, 130, 246, 0.1)` → `rgba(99, 102, 241, 0.08)` (indigo, subtler)
- `stroke`: `#3b82f6` → `#6366f1` (indigo-500)

**Files:** `app/javascript/flowchart/selection_manager.js`

---

## Change 6: Drag Opacity Feedback

In `drag_handler.js`, when drag starts set `opacity: 0.7` on dragged element groups. On drag end, restore to `opacity: 1`.

**Files:** `app/javascript/flowchart/drag_handler.js`

---

## Files Impact Summary

| File | Changes |
|------|---------|
| `app/javascript/flowchart/connection_renderer.js` | 1, 2 |
| `app/javascript/flowchart/connection_manager.js` | 3 |
| `app/javascript/flowchart/canvas.js` | 3, 4 |
| `app/javascript/flowchart/selection_manager.js` | 5 |
| `app/javascript/flowchart/drag_handler.js` | 6 |
