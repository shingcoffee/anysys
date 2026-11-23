import { Controller } from "@hotwired/stimulus"

// segment-builder — grouped (nested AND/OR) condition builder for email list
// segment rules, modeled EXACTLY on the flowchart Decision condition builder.
//
// Each group holds members interleaved with INDEPENDENT per-join AND/OR toggles
// (just like the flowchart): clicking a toggle flips only that one join. The
// controller walks the DOM tree and serializes the recursive group JSON into
// the hidden output on every change.
//
// Group JSON: { type:"group", joins:["AND"|"OR",...], conditions:[ leaf|group ] }
//   joins.length === conditions.length - 1 (combined left-associatively)
// Leaf  JSON: { field, operator, value }
//
// DOM contract (rendered by SegmentBuilderComponent):
//   [data-sb-group]      group container
//     > [data-sb-rows]   members container (rows, nested groups, join toggles)
//         [data-sb-row]        condition row
//         [data-sb-group]      nested group
//         [data-sb-join-wrap]  wrapper holding one join toggle
//           [data-sb-join]     toggle button, data-sb-join="AND"|"OR"
//         [data-sb-field] / [data-sb-operator] / [data-sb-value]   row inputs
export default class extends Controller {
  static targets = ["output", "groupRoot", "rowTemplate", "groupTemplate", "joinTemplate"]
  static values  = {
    fields: Object,
    operatorLabels: Object,
    andLabel: { type: String, default: "AND" },
    orLabel: { type: String, default: "OR" }
  }

  connect() {
    // Populate operator selects for every pre-rendered row from the catalog,
    // preserving each row's server-selected operator, then serialize.
    this._allRows().forEach((row) => this._populateOperators(row, this._operatorOf(row)))
    this.serialize()
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  // Add a condition row to the nearest enclosing group. If the group already
  // has a member, prepend an AND join toggle (matching the flowchart).
  addRow(event) {
    const rows = this._rowsContainer(event.target)
    if (!rows || !this.hasRowTemplateTarget) return

    if (this._memberCount(rows) >= 1) rows.appendChild(this._cloneJoin())
    rows.appendChild(this.rowTemplateTarget.content.cloneNode(true))
    const row = this._lastMember(rows)
    if (row && row.matches("[data-sb-row]")) this._populateOperators(row)
    this.serialize()
  }

  // Add a nested group to the nearest enclosing group, with a preceding AND
  // join if the group already has a member.
  addGroup(event) {
    const rows = this._rowsContainer(event.target)
    if (!rows || !this.hasGroupTemplateTarget) return

    if (this._memberCount(rows) >= 1) rows.appendChild(this._cloneJoin())
    rows.appendChild(this.groupTemplateTarget.content.cloneNode(true))
    // Populate operator selects for the new group's seeded row.
    const grp = this._lastMember(rows)
    if (grp) grp.querySelectorAll("[data-sb-row]").forEach((r) => this._populateOperators(r))
    this.serialize()
  }

  removeRow(event) {
    this._removeMember(event.target.closest("[data-sb-row]"))
  }

  removeGroup(event) {
    const group = event.target.closest("[data-sb-group]")
    if (group === this.groupRootTarget) return // never remove the root
    this._removeMember(group)
  }

  // Flip a single join toggle between AND and OR — touches only this button,
  // exactly like the flowchart's toggleConditionJoin.
  toggleJoin(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const next = btn.getAttribute("data-sb-join") === "OR" ? "AND" : "OR"
    btn.setAttribute("data-sb-join", next)
    btn.textContent = next === "OR" ? this.orLabelValue : this.andLabelValue
    btn.className = this._joinClasses(next)
    this.serialize()
  }

  fieldChanged(event) {
    const row = event.target.closest("[data-sb-row]")
    if (row) this._populateOperators(row)
    this.serialize()
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  serialize() {
    if (!this.hasGroupRootTarget || !this.hasOutputTarget) return
    this.outputTarget.value = JSON.stringify(this._readGroup(this.groupRootTarget))
  }

  _readGroup(groupEl) {
    const rows = groupEl.querySelector(":scope > [data-sb-rows]")
    const conditions = []
    const joins = []

    if (rows) {
      Array.from(rows.children).forEach((child) => {
        if (child.matches("[data-sb-join-wrap]")) {
          const btn = child.querySelector("[data-sb-join]")
          // A join only counts once it sits between two kept members.
          if (conditions.length >= 1) joins.push(btn && btn.getAttribute("data-sb-join") === "OR" ? "OR" : "AND")
        } else if (child.matches("[data-sb-group]")) {
          conditions.push(this._readGroup(child))
        } else if (child.matches("[data-sb-row]")) {
          conditions.push(this._readRow(child))
        }
      })
    }

    // Keep joins aligned to (conditions.length - 1) defensively.
    return { type: "group", joins: joins.slice(0, Math.max(conditions.length - 1, 0)), conditions }
  }

  _readRow(row) {
    const f = row.querySelector("[data-sb-field]")
    const o = row.querySelector("[data-sb-operator]")
    const v = row.querySelector("[data-sb-value]")
    return {
      field:    f ? f.value : "",
      operator: o ? o.value : "",
      value:    v ? v.value : "",
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  // Remove a member element plus the join toggle adjacent to it, so joins stay
  // aligned. Prefer removing the PREVIOUS join; if none, remove the NEXT one.
  _removeMember(el) {
    if (!el) return
    const prev = el.previousElementSibling
    const next = el.nextElementSibling
    if (prev && prev.matches("[data-sb-join-wrap]")) prev.remove()
    else if (next && next.matches("[data-sb-join-wrap]")) next.remove()
    el.remove()
    this.serialize()
  }

  _rowsContainer(el) {
    const group = el.closest("[data-sb-group]") || this.groupRootTarget
    return group ? group.querySelector(":scope > [data-sb-rows]") : null
  }

  _memberCount(rows) {
    return rows.querySelectorAll(":scope > [data-sb-row], :scope > [data-sb-group]").length
  }

  _lastMember(rows) {
    const members = rows.querySelectorAll(":scope > [data-sb-row], :scope > [data-sb-group]")
    return members[members.length - 1] || null
  }

  _cloneJoin() {
    return this.joinTemplateTarget.content.cloneNode(true)
  }

  _joinClasses(op) {
    const pill = op === "OR" ? "bg-purple-200 text-purple-800" : "bg-amber-200 text-amber-800"
    return `px-3 py-0.5 text-xs font-bold rounded-full transition-colors ${pill}`
  }

  _operatorOf(row) {
    const o = row.querySelector("[data-sb-operator]")
    return o ? o.value : null
  }

  _populateOperators(row, selectedOperator = null) {
    const fieldEl = row.querySelector("[data-sb-field]")
    const opEl    = row.querySelector("[data-sb-operator]")
    if (!fieldEl || !opEl) return

    const meta = this.fieldsValue[fieldEl.value]
    const operators = meta ? meta.operators : []
    const current = selectedOperator || opEl.value

    opEl.innerHTML = ""
    operators.forEach((op) => {
      const opt = document.createElement("option")
      opt.value = op
      opt.textContent = this.operatorLabelsValue[op] || op.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase())
      if (op === current) opt.selected = true
      opEl.appendChild(opt)
    })
  }

  _allRows() {
    if (!this.hasGroupRootTarget) return []
    return Array.from(this.groupRootTarget.querySelectorAll("[data-sb-row]"))
  }
}
