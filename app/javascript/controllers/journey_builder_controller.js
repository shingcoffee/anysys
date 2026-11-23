import { Controller } from "@hotwired/stimulus"

// Step list editing for the journey builder: add, remove and reorder the page
// steps above the fixed finish row. Choosing a page sets the row's hint and
// mode and clones a fill picker per locked input; refresh then lists earlier
// matching steps in those pickers and in an editing row's record picker, and
// earlier non-optional steps on finish. A row set to edit a record offers only
// pages that edit records. A journey that starts from an existing record lists
// that record first, its first row no longer leads (creates with nothing to
// fill), and its condition offers the chosen record type's choice fields and,
// for the chosen field, its values with where other journeys leave records in
// them. Each row shows its page's "On submit" block; a row an earlier step's
// processing may skip names those steps, and is never the first row.
export default class extends Controller {
  static targets = ["list", "template", "row", "inputTemplate", "startKind", "startEntity", "startKey",
    "whenField", "whenValues", "whenValueTemplate"]
  static values = {
    pages: { type: Object, default: {} },
    choices: { type: Object, default: {} },
    none: { type: String, default: "Choose a step" },
    stepName: { type: String, default: "Step {number}" },
    recordName: { type: String, default: "The {entity} record" },
    skippedBy: { type: String, default: "Skipped when the processing of {steps} says so." },
    skippedNone: { type: String, default: "No earlier step's processing skips this step yet." },
    separator: { type: String, default: ", " }
  }

  add() {
    const fragment = this.templateTarget.content.cloneNode(true)
    const key = this.nextKey()
    fragment.querySelector("[data-step-key]").value = key
    const hint = fragment.querySelector("[data-step-hint]")
    hint.id = `journey-step-hint-${key}`
    fragment.querySelector("[data-step-page]").setAttribute("aria-describedby", hint.id)
    fragment.querySelector("[data-step-record-hint]").id = `${hint.id}-record`
    fragment.querySelector("[data-step-record]").setAttribute("aria-describedby", `${hint.id}-record`)
    this.listTarget.append(fragment)
    this.refresh()
  }

  remove(event) {
    this.rowFor(event).remove()
    this.refresh()
  }

  moveUp(event) {
    const row = this.rowFor(event)
    row.previousElementSibling?.before(row)
    this.refresh()
  }

  moveDown(event) {
    const row = this.rowFor(event)
    row.nextElementSibling?.after(row)
    this.refresh()
  }

  pageChanged(event) {
    this.applyPage(this.rowFor(event))
    this.refresh()
  }

  // An editing row offers only pages that edit records; a page it can't keep
  // is cleared.
  kindChanged(event) {
    this.applyKind(this.rowFor(event))
    this.refresh()
  }

  recordTypeChanged() {
    this.rebuildWhenFields()
    this.refresh()
  }

  whenFieldChanged() {
    this.rebuildWhenValues()
  }

  // A picker keeps its choice while that step is still listed; input and
  // record pickers fall back to blank, the finish picker to the first
  // remaining step.
  refresh() {
    const start = this.recordStart()
    const earlier = start.source ? [start.source] : []
    this.rowTargets.forEach((row, index) => {
      const finish = "finish" in row.dataset
      if (!finish) this.lead(row, index === 0 && !start.active)
      row.querySelectorAll("[data-step-input], [data-step-record]").forEach((select) => {
        const current = select.dataset.kept ?? select.value
        delete select.dataset.kept
        const choices = [{ key: "", name: this.noneValue }].concat(
          earlier.filter((step) => step.entity === select.dataset.stepInputEntity)
        )
        this.replaceOptions(select, choices)
        const listed = choices.findIndex(({ key }) => key === current)
        select.selectedIndex = listed >= 0 ? listed : 0
      })
      row.querySelectorAll("[data-step-options]").forEach((select) => {
        const current = select.value
        const sources = earlier.filter((step) => !step.optional)
        this.replaceOptions(select, sources)
        select.selectedIndex = Math.max(sources.findIndex(({ key }) => key === current), 0)
      })
      if (finish) return

      const page = this.pagesValue[row.querySelector("[data-step-page]").value]
      const key = row.querySelector("[data-step-key]").value
      const conditional = row.querySelector("[data-step-conditional]")
      if (index === 0) conditional.checked = false
      const by = earlier.filter(({ skips }) => skips.includes(key)).map(({ name }) => name)
      row.querySelector("[data-step-skipped-by]").textContent = by.length
        ? this.skippedByValue.replace("{steps}", by.join(this.separatorValue))
        : this.skippedNoneValue
      earlier.push({
        key,
        name: this.nameOf(row, index),
        entity: page?.entity ?? null,
        optional: !!row.querySelector("[data-step-optional]")?.checked || conditional.checked,
        skips: page ? page.effects.skips : []
      })
    })
  }

  // The lead row always creates, so it never stays set to edit a record.
  lead(row, leading) {
    row.toggleAttribute("data-step-lead", leading)
    const kind = row.querySelector("[data-step-kind]")
    if (!leading || kind.value !== "update") return

    kind.value = "add"
    this.applyKind(row)
  }

  applyKind(row) {
    const updating = row.querySelector("[data-step-kind]").value === "update"
    const select = row.querySelector("[data-step-page]")
    Array.from(select.options).forEach((option) => {
      const unfit = updating && option.value !== "" && !this.pagesValue[option.value]?.updates
      option.hidden = unfit
      option.disabled = unfit
    })
    if (select.options[select.selectedIndex].disabled) select.value = ""
    this.applyPage(row)
  }

  applyPage(row) {
    const page = this.pagesValue[row.querySelector("[data-step-page]").value]
    row.querySelector("[data-step-hint]").textContent = page?.hint || ""
    row.dataset.stepMode = this.modeOf(row, page)
    row.querySelector("[data-step-record]").dataset.stepInputEntity = page?.entity ?? ""
    this.rebuildInputs(row, page)
    this.applyEffects(row, page)
  }

  // Lines that hold only when the step creates its record drop out while the
  // row edits one.
  applyEffects(row, page) {
    const block = row.querySelector("[data-step-effects]")
    block.hidden = !page
    if (!page) return

    const { effects } = page
    const creating = row.dataset.stepMode !== "update"
    const link = block.querySelector("[data-step-effects-link]")
    link.hidden = !effects.title
    link.textContent = effects.title ?? ""
    link.href = effects.path ?? "#"
    this.fillList(block.querySelector("[data-step-effects-lines]"), effects.lines.concat(creating ? effects.creating : []))
    const next = effects.next.concat(creating ? effects.nextCreating : [])
    const list = block.querySelector("[data-step-effects-next]")
    this.fillList(list, next)
    list.hidden = next.length === 0
  }

  fillList(list, lines) {
    list.replaceChildren(...lines.map((line) => {
      const item = document.createElement("li")
      item.textContent = line
      return item
    }))
  }

  modeOf(row, page) {
    if (row.querySelector("[data-step-kind]").value === "update") return "update"

    return page ? (page.inputs?.length ? "relate" : "create") : "none"
  }

  recordStart() {
    const active = this.startKindTargets.some((radio) => radio.checked && radio.value === "record")
    if (!active || !this.startEntityTarget.value) return { active, source: null }

    const select = this.startEntityTarget
    return {
      active,
      source: {
        key: this.startKeyTarget.value,
        name: this.recordNameValue.replace("{entity}", select.options[select.selectedIndex].textContent.trim()),
        entity: select.value,
        optional: false,
        skips: []
      }
    }
  }

  // The chosen record type's choice fields, after the "any record" option.
  rebuildWhenFields() {
    if (!this.hasWhenFieldTarget) return

    const select = this.whenFieldTarget
    const fields = this.choicesValue[this.startEntityTarget.value] ?? []
    select.replaceChildren(select.options[0], ...fields.map(({ field, label }) => {
      const option = document.createElement("option")
      option.value = field
      option.textContent = label
      return option
    }))
    select.selectedIndex = 0
    this.rebuildWhenValues()
  }

  rebuildWhenValues() {
    const fields = this.choicesValue[this.startEntityTarget.value] ?? []
    const chosen = fields.find(({ field }) => field === this.whenFieldTarget.value)
    this.whenValuesTarget.hidden = !chosen
    this.whenValuesTarget.querySelector("[data-when-options]").replaceChildren(...(chosen?.options ?? []).map(({ value, label, sources }) => {
      const node = this.whenValueTemplateTarget.content.cloneNode(true)
      node.querySelector("[data-when-value]").value = value
      node.querySelector("[data-when-value-label]").textContent = label
      node.querySelector("[data-when-value-sources]").textContent = sources
      return node
    }))
  }

  rebuildInputs(row, page) {
    const container = row.querySelector("[data-step-inputs]")
    const previous = {}
    container.querySelectorAll("[data-step-input]").forEach((select) => {
      const field = (select.getAttribute("name") || "").match(/\[inputs\]\[([^\]]+)\]$/)
      if (field) previous[field[1]] = select.value
    })
    container.replaceChildren()
    ;(page?.inputs ?? []).forEach((input) => {
      const node = this.inputTemplateTarget.content.cloneNode(true)
      node.querySelector("[data-step-input-label]").textContent = input.label
      const select = node.querySelector("[data-step-input]")
      select.name = `journey[steps][][inputs][${input.field}]`
      select.dataset.stepInputEntity = input.entity
      if (previous[input.field]) select.dataset.kept = previous[input.field]
      container.append(node)
    })
  }

  replaceOptions(select, choices) {
    select.replaceChildren(...choices.map(({ key, name }) => {
      const option = document.createElement("option")
      option.value = key
      option.textContent = name
      return option
    }))
  }

  rowFor(event) {
    return event.target.closest("[data-journey-builder-target='row']")
  }

  nameOf(row, index) {
    const label = row.querySelector("[data-step-label]").value.trim()
    const page = row.querySelector("[data-step-page]")
    const pageName = page.value ? page.options[page.selectedIndex].textContent.trim() : ""
    return label || pageName || this.stepNameValue.replace("{number}", String(index + 1))
  }

  // Step keys only need to be unique; "step_<n>" matches the server's default.
  nextKey() {
    const taken = new Set(this.rowTargets.map((row) => row.querySelector("[data-step-key]").value))
    let number = taken.size + 1
    while (taken.has(`step_${number}`)) number += 1
    return `step_${number}`
  }
}
