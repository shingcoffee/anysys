// Pure list math for canvas drag-and-drop. No DOM, no imports — unit-tested
// under test/js/. Functions return NEW arrays; callers assign back and
// re-number `order`.

export function isSection(f) {
  return !!f && f.property_type === "layout" && f.field_type === "section"
}

// Move `movingIds` (kept in their current relative order) so they land at
// `targetIndex`, expressed against the ORIGINAL list. Returns a new array.
export function moveFields(list, movingIds, targetIndex) {
  const ids = new Set(movingIds)
  const moving = list.filter(f => ids.has(f.id))
  const remaining = list.filter(f => !ids.has(f.id))
  const removedBefore = list.slice(0, targetIndex).filter(f => ids.has(f.id)).length
  const insertAt = Math.max(0, Math.min(targetIndex - removedBefore, remaining.length))
  remaining.splice(insertAt, 0, ...moving)
  return remaining
}

// Move the whole section block headed by `sectionId` (header + fields up to the
// next section header) before/after the target's section. Returns
// { list, movedIds }.
export function reorderSectionBlock(list, sectionId, targetId) {
  const headerIdxs = []
  list.forEach((f, i) => { if (isSection(f)) headerIdxs.push(i) })

  const dStart = list.findIndex(f => f.id === sectionId)
  if (dStart < 0) return { list: list.slice(), movedIds: [] }
  const dNext = headerIdxs.find(i => i > dStart)
  const dEnd = dNext === undefined ? list.length : dNext
  const block = list.slice(dStart, dEnd)
  const ids = new Set(block.map(f => f.id))
  const movedIds = block.map(f => f.id)

  if (ids.has(targetId)) return { list: list.slice(), movedIds }
  const tAny = list.findIndex(f => f.id === targetId)
  if (tAny < 0) return { list: list.slice(), movedIds }

  let tStart = -1
  for (let i = tAny; i >= 0; i--) { if (isSection(list[i])) { tStart = i; break } }

  let beforeId = null
  let afterId = null
  if (tStart === -1) {
    beforeId = list[0] ? list[0].id : null
  } else {
    const tNext = headerIdxs.find(i => i > tStart)
    const tEnd = tNext === undefined ? list.length : tNext
    if (dStart < tStart) afterId = list[tEnd - 1].id
    else beforeId = list[tStart].id
  }

  const remaining = list.filter(f => !ids.has(f.id))
  let insertIdx = remaining.length
  if (beforeId != null) {
    const i = remaining.findIndex(f => f.id === beforeId)
    if (i !== -1) insertIdx = i
  } else if (afterId != null) {
    const i = remaining.findIndex(f => f.id === afterId)
    if (i !== -1) insertIdx = i + 1
  }
  remaining.splice(insertIdx, 0, ...block)
  return { list: remaining, movedIds }
}
