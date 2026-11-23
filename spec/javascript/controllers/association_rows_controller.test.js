import { describe, it, expect } from "vitest"
import AssociationRows from "controllers/association_rows_controller"
import { mountController, controllerFor, click } from "../support/stimulus.js"

const row = (index, field = `<input type="hidden" name="rows[${index}][flag]" value="0"><input name="rows[${index}][grade]" id="association_row_${index}_grade">`) => `
  <li data-association-rows-target="row">
    <h3 data-association-rows-target="heading"></h3>
    <button type="button" class="remove hidden" data-association-rows-target="remove" data-action="association-rows#remove">x</button>
    ${field}
  </li>`

const form = ({ rows = [row(0)], template = row("__ROW__"), heading = "Enrollment {number}" } = {}) => `
  <div data-controller="association-rows"
        data-association-rows-next-index-value="${rows.length}"
        ${heading ? `data-association-rows-heading-value="${heading}"` : ""}>
    <ol data-association-rows-target="list">${rows.join("")}</ol>
    <template data-association-rows-target="template">${template}</template>
    <button type="button" class="add" data-action="association-rows#add">Add</button>
  </div>`

const headings = (element) => [...element.querySelectorAll("h3")].map((heading) => heading.textContent)
const removeHidden = (element) => [...element.querySelectorAll("ol .remove")].map((button) => button.classList.contains("hidden"))

describe("association-rows controller", () => {
  it("numbers the server rows on connect and shows remove only for several rows", async () => {
    const { element } = await mountController("association-rows", AssociationRows, form({ rows: [row(0), row(1)] }))

    expect(headings(element)).toEqual(["Enrollment 1", "Enrollment 2"])
    expect(removeHidden(element)).toEqual([false, false])
  })

  it("falls back to the English heading template", async () => {
    const { element } = await mountController("association-rows", AssociationRows, form({ heading: null }))

    expect(headings(element)).toEqual(["Entry 1"])
    expect(removeHidden(element)).toEqual([true])
  })

  it("adds a row under the next unused index and focuses its first visible field", async () => {
    const { application, element } = await mountController("association-rows", AssociationRows, form())

    await click(element.querySelector(".add"))
    await click(element.querySelector(".add"))

    const names = [...element.querySelectorAll("ol input:not([type='hidden'])")].map((input) => input.name)
    expect(names).toEqual(["rows[0][grade]", "rows[1][grade]", "rows[2][grade]"])
    expect(document.activeElement.id).toBe("association_row_2_grade")
    expect(headings(element)).toEqual(["Enrollment 1", "Enrollment 2", "Enrollment 3"])
    expect(removeHidden(element)).toEqual([false, false, false])
    expect(controllerFor(application, element, "association-rows").nextIndexValue).toBe(3)
  })

  it("indexes only attributes, leaving labels that contain the row token as written", async () => {
    const select = `<label for="association_row___ROW___course">Course</label>
      <select name="rows[__ROW__][course]" id="association_row___ROW___course"><option value="9">Plan __ROW__ B</option></select>`
    const { element } = await mountController("association-rows", AssociationRows, form({ template: row("__ROW__", select) }))

    await click(element.querySelector(".add"))

    const added = element.querySelectorAll("ol li")[1]
    expect(added.querySelector("select").name).toBe("rows[1][course]")
    expect(added.querySelector("label").htmlFor).toBe("association_row_1_course")
    expect(added.querySelector("option").textContent).toBe("Plan __ROW__ B")
    expect(document.activeElement.id).toBe("association_row_1_course")
  })

  it("adds a row without a focusable field", async () => {
    const { element } = await mountController("association-rows", AssociationRows, form({ template: row("__ROW__", "") }))

    await click(element.querySelector(".add"))

    expect(element.querySelectorAll("ol li")).toHaveLength(2)
  })

  it("removes a row, renumbers the rest and hides remove on the last one", async () => {
    const { element } = await mountController("association-rows", AssociationRows, form({ rows: [row(0), row(1), row(2)] }))

    await click(element.querySelectorAll("ol .remove")[0])
    expect(headings(element)).toEqual(["Enrollment 1", "Enrollment 2"])
    expect([...element.querySelectorAll("ol input:not([type='hidden'])")].map((input) => input.name))
      .toEqual(["rows[1][grade]", "rows[2][grade]"])

    await click(element.querySelectorAll("ol .remove")[0])
    expect(removeHidden(element)).toEqual([true])
  })

  it("keeps the only row", async () => {
    const { element } = await mountController("association-rows", AssociationRows, form())

    await click(element.querySelector("ol .remove"))

    expect(element.querySelectorAll("ol li")).toHaveLength(1)
  })
})
