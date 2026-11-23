// Pure geometry for canvas drag-and-drop. No DOM, no imports — unit-tested
// under test/js/. Given a "region" (a container's children laid out as rows of
// cells) and a pointer position, return the insertion slot.
//
// Region = {
//   containerKey: string,
//   rows: Array<{ top, bottom, cells: Array<{ left, right, index }> }>
// }
// `index` is the insertion index in the container's field array for the slot
// BEFORE that cell; the slot AFTER the last cell uses cell.index + 1.
//
// NestedEntry (for pickRegion) = {
//   rect: { left, right, top, bottom },   — viewport-relative bounding box
//   mayNest: boolean,
//   region: Region                         — pre-built region for this container
// }
//
// pickRegion(snapshot, pointer) — pure: selects the best nested container region
// or falls back to the top-level region. snapshot = { topLevel: Region,
// nested: Array<NestedEntry> }. Innermost/last matching mayNest container wins.
export function pickRegion(snapshot, pointer) {
  const { x, y } = pointer
  let best = null
  for (const entry of snapshot.nested) {
    if (!entry.mayNest) continue
    const r = entry.rect
    if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) {
      best = entry.region
    }
  }
  return best || snapshot.topLevel
}

// Over a cell's leading 60% → insert before it (dropping onto a field takes its
// place); the trailing 40% inserts after.
const BEFORE_BIAS = 0.6

export function resolveSlot(region, pointer) {
  const rows = region.rows || []
  if (rows.length === 0) {
    return { containerKey: region.containerKey, index: 0, orientation: "horizontal", rect: null }
  }

  // Clear prepend / append zones: above the first row or below the last row.
  const firstRow = rows[0]
  const lastRow  = rows[rows.length - 1]
  if (pointer.y < firstRow.top)   return horizontalSlot(region, firstRow, "before")
  if (pointer.y > lastRow.bottom) return horizontalSlot(region, lastRow,  "after")

  // Otherwise snap to the NEAREST row by vertical distance (0 when inside the
  // band). This is the key to easy cross-row dropping: the gaps between rows no
  // longer behave as dead-zones that force an awkward between-rows insert — each
  // gap splits at its midpoint and resolves to the closer row, so hovering
  // anywhere near a target field reliably inserts beside it.
  let row = firstRow
  let bestDist = Infinity
  for (const r of rows) {
    const d = pointer.y < r.top    ? r.top - pointer.y
            : pointer.y > r.bottom ? pointer.y - r.bottom
            : 0
    if (d < bestDist) { bestDist = d; row = r }
  }

  // A standalone single cell (full-width section, divider, or a lone field) →
  // insert above or below it, chosen by the nearer vertical half. The index
  // still flows correctly: a half-width field dropped "after" a lone half-width
  // field packs beside it.
  if (row.cells.length === 1) {
    const midY = (row.top + row.bottom) / 2
    return horizontalSlot(region, row, pointer.y < midY ? "before" : "after")
  }

  // Multi-cell row (side-by-side fields) → vertical slot beside a cell. A point
  // anywhere over a cell's leading ~60% inserts BEFORE that cell, so dropping a
  // field onto another field puts it in that field's place (the target shifts
  // aside) instead of landing after it. Only the trailing ~40% inserts after.
  for (const cell of row.cells) {
    if (pointer.x < cell.left + (cell.right - cell.left) * BEFORE_BIAS) {
      return verticalSlot(region, row, cell.left, cell.index)
    }
  }
  const lastCell = row.cells[row.cells.length - 1]
  return verticalSlot(region, row, lastCell.right, lastCell.index + 1)
}

function verticalSlot(region, row, x, index) {
  return {
    containerKey: region.containerKey,
    index,
    orientation: "vertical",
    rect: { left: x, top: row.top, width: 2, height: row.bottom - row.top }
  }
}

function horizontalSlot(region, row, edge) {
  const cells = row.cells
  const left = cells.length ? cells[0].left : 0
  const right = cells.length ? cells[cells.length - 1].right : 0
  const index = edge === "before"
    ? (cells.length ? cells[0].index : 0)
    : (cells.length ? cells[cells.length - 1].index + 1 : 0)
  const y = edge === "before" ? row.top : row.bottom
  return {
    containerKey: region.containerKey,
    index,
    orientation: "horizontal",
    rect: { left, top: y, width: right - left, height: 2 }
  }
}
