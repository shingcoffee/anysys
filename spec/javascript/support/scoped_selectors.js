import { beforeAll, afterAll } from "vitest"

// happy-dom 15.11.7 has no :scope > support. Shared browser-API compatibility
// shim extracted from the existing condition-builder suite. Production
// selectors/DOM/collectors stay intact; Chromium tests need no shim.
let nativeQS, nativeQSA

function resolveScopedPart(el, part) {
  const stripped = part.trim().replace(/^:scope\s*>\s*/, "")
  const spaceIdx = stripped.search(/\s/)
  const directSel = spaceIdx === -1 ? stripped : stripped.slice(0, spaceIdx)
  const descendantSel = spaceIdx === -1 ? null : stripped.slice(spaceIdx + 1).trim()
  const directChildren = Array.from(el.children).filter(c => c.matches(directSel))
  if (!descendantSel) return directChildren
  return directChildren.flatMap(c => Array.from(nativeQSA.call(c, descendantSel)))
}

function resolveScoped(el, selector) {
  const parts = selector.split(",").map(s => s.trim())
  const directOnly = []
  const compound = []
  parts.forEach(part => {
    const stripped = part.replace(/^:scope\s*>\s*/, "")
    if (stripped.search(/\s/) === -1) directOnly.push(stripped)
    else compound.push(part)
  })
  let results = []
  if (directOnly.length > 0) {
    results = results.concat(Array.from(el.children).filter(c => directOnly.some(sel => c.matches(sel))))
  }
  compound.forEach(part => { results = results.concat(resolveScopedPart(el, part)) })
  return results
}

beforeAll(() => {
  nativeQS = Element.prototype.querySelector
  nativeQSA = Element.prototype.querySelectorAll
  Element.prototype.querySelector = function (selector) {
    if (typeof selector === "string" && selector.includes(":scope")) return resolveScoped(this, selector)[0] || null
    return nativeQS.call(this, selector)
  }
  Element.prototype.querySelectorAll = function (selector) {
    if (typeof selector === "string" && selector.includes(":scope")) return resolveScoped(this, selector)
    return nativeQSA.call(this, selector)
  }
})
afterAll(() => {
  Element.prototype.querySelector = nativeQS
  Element.prototype.querySelectorAll = nativeQSA
})
