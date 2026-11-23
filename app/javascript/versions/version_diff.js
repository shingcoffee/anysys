/**
 * Pure side-by-side line diff for two flowchart configurations.
 * Produces rows { type: "context"|"add"|"del", left, right } from a
 * stable-key pretty-print of each config so semantically-equal configs with
 * different key ordering do not show spurious differences.
 *
 * The line diff itself is delegated to the jsdiff library (vendored ESM);
 * this module only owns the stable pretty-printing and the row shape.
 */

import { diffLines } from "diff"

function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys)
  if (value && typeof value === "object") {
    return Object.keys(value).sort().reduce((acc, k) => {
      acc[k] = sortKeys(value[k])
      return acc
    }, {})
  }
  return value
}

function parse(config) {
  return typeof config === "string" ? JSON.parse(config) : config
}

function pretty(config) {
  return JSON.stringify(sortKeys(parse(config)), null, 2)
}

function partLines(part) {
  const lines = part.value.split("\n")
  if (lines[lines.length - 1] === "") lines.pop() // trailing newline artifact
  return lines
}

/**
 * @param {string|object} leftConfig
 * @param {string|object} rightConfig
 * @returns {Array<{type:string,left:?string,right:?string}>}
 */
export function versionDiff(leftConfig, rightConfig) {
  const rows = []
  for (const part of diffLines(pretty(leftConfig), pretty(rightConfig))) {
    for (const line of partLines(part)) {
      if (part.added) {
        rows.push({ type: "add", left: null, right: line })
      } else if (part.removed) {
        rows.push({ type: "del", left: line, right: null })
      } else {
        rows.push({ type: "context", left: line, right: line })
      }
    }
  }
  return rows
}

export default versionDiff
