#!/usr/bin/env node
// Usage: node spec/javascript/support/coverage_gaps.mjs <substr> [<substr>...]
// After running `npx vitest run --coverage`, prints uncovered LINES and BRANCHES
// (with 1-based line numbers) for every source file whose path contains any of
// the given substrings. No args => lists all files not at 100% (summary only).
import fs from "node:fs"
const cwd = process.cwd()
// LCOV path override so parallel agents can each read their own report:
//   LCOV=coverage/js-myarea/lcov.info node .../coverage_gaps.mjs <substr>
const lcovPath = process.env.LCOV || "coverage/javascript/lcov.info"
const txt = fs.readFileSync(lcovPath, "utf8")
const subs = process.argv.slice(2)
for (const r of txt.split("end_of_record")) {
  const sf = r.match(/SF:(.*)/); if (!sf) continue
  const file = sf[1].replace(cwd + "/", "")
  if (subs.length && !subs.some(s => file.includes(s))) continue
  const num = (k) => { const m = r.match(new RegExp("^" + k + ":(\\d+)", "m")); return m ? +m[1] : 0 }
  const lf = num("LF"), lh = num("LH"), bf = num("BRF"), bh = num("BRH"), fnf = num("FNF"), fnh = num("FNH")
  const full = lh >= lf && bh >= bf && fnh >= fnf
  if (!subs.length) { if (!full) console.log(`${file}  L ${lh}/${lf}  B ${bh}/${bf}  F ${fnh}/${fnf}`); continue }
  console.log(`\n=== ${file}  L ${lh}/${lf}  B ${bh}/${bf}  F ${fnh}/${fnf} ${full ? "✅100%" : ""}`)
  if (full) continue
  const uncLines = []
  for (const m of r.matchAll(/^DA:(\d+),(\d+)/mg)) if (+m[2] === 0) uncLines.push(+m[1])
  if (uncLines.length) console.log("  uncovered lines:", uncLines.join(", "))
  const uncFns = []
  const fnNames = {}
  for (const m of r.matchAll(/^FN:(\d+),(.*)/mg)) fnNames[m[2]] = +m[1]
  for (const m of r.matchAll(/^FNDA:(\d+),(.*)/mg)) if (+m[1] === 0) uncFns.push(`${m[2]}@${fnNames[m[2]] ?? "?"}`)
  if (uncFns.length) console.log("  uncovered funcs:", uncFns.join(", "))
  const uncBr = []
  for (const m of r.matchAll(/^BRDA:(\d+),(\d+),(\d+),(.*)/mg)) if (m[4] === "0" || m[4] === "-") uncBr.push(`line ${m[1]} branch#${m[3]}(blk${m[2]})`)
  if (uncBr.length) console.log("  uncovered branches:", uncBr.join(", "))
}
