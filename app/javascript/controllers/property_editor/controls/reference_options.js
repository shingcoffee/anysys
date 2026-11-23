import { getCSRFToken } from "utils"
import { flowchartUrl } from "flowchart/urls"

const cache = new Map()

export function resetReferenceCache() {
  cache.clear()
}

export function referenceOptionsUrl(source) {
  if (!source) return null
  return flowchartUrl(null, "referenceOptions", { __SOURCE__: source })
}

export async function fetchReferenceOptions(source) {
  const url = referenceOptionsUrl(source)
  const key = url || source
  if (cache.has(key)) return cache.get(key)

  if (!url) {
    const miss = { ok: false, options: [] }
    cache.set(key, miss)
    return miss
  }

  try {
    const response = await fetch(url, {
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": getCSRFToken()
      }
    })
    if (!response.ok) {
      const fail = { ok: false, options: [] }
      cache.set(key, fail)
      return fail
    }
    const body = await response.json()
    const options = Array.isArray(body?.options) ? body.options : []
    const hit = { ok: true, options }
    cache.set(key, hit)
    return hit
  } catch (_error) {
    const fail = { ok: false, options: [] }
    cache.set(key, fail)
    return fail
  }
}

export function filterReferenceOptions(options, query) {
  const needle = String(query || "").trim().toLowerCase()
  if (!needle) return options
  return options.filter(opt => {
    const label = String(opt.label ?? "").toLowerCase()
    const value = String(opt.value ?? "").toLowerCase()
    return label.includes(needle) || value.includes(needle)
  })
}
