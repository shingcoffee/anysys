import { describe, it, expect } from "vitest"
import JourneyBuilderController from "../../../app/javascript/controllers/journey_builder_controller"
import { mountController, tick } from "../support/stimulus.js"

const plainEffects = { lines: ["Saves the record"], creating: [], next: [], nextCreating: [], skips: [] }

const pages = {
  1: {
    entity: "s",
    updates: true,
    hint: "Student hint",
    inputs: [],
    effects: {
      title: "Processing: Intake",
      path: "/p/1",
      lines: ["Saves the record"],
      creating: ["A new Student starts Submitted"],
      next: ["Next: Review"],
      nextCreating: ["Next: Welcome"],
      skips: ["notes"]
    }
  },
  2: { entity: "b", hint: "Course hint", inputs: [{ field: "student", entity: "s", label: "Student from" }], effects: plainEffects },
  3: {
    entity: "b",
    updates: false,
    hint: "Enrol hint",
    inputs: [
      { field: "student", entity: "s", label: "Student from" },
      { field: "course", entity: "c", label: "Course from" }
    ],
    effects: plainEffects
  },
  4: { entity: null, hint: "Loose hint", effects: plainEffects }
}

const choices = {
  s: [
    {
      field: "status",
      label: "Status",
      options: [{ value: "Submitted", label: "Submitted", sources: "" }, { value: "Approved", label: "Approved", sources: "Reached in Review" }]
    },
    { field: "level", label: "Level", options: [{ value: "1", label: "One", sources: "" }] }
  ]
}

const inputSelect = ({ entity = "s", field = "student", value = "" } = {}) => `
  <label><span class="form-label">Student from</span>
    <select data-step-input data-step-input-entity="${entity}" name="journey[steps][][inputs][${field}]">
      <option value="">Choose a step</option>
      ${value ? `<option value="${value}" selected>${value}</option>` : ""}
    </select>
  </label>`

const stepRow = ({
  key = "", label = "", page = "", optional = false, optionalBox = true, inputs = "", extra = "",
  kind = "add", record = "", recordEntity = "", conditional = false
} = {}) => `
  <li data-journey-builder-target="row">
    <input type="hidden" data-step-key value="${key}">
    <select data-step-kind data-action="change->journey-builder#kindChanged">
      <option value="add"${kind === "add" ? " selected" : ""}>Add records</option>
      <option value="update"${kind === "update" ? " selected" : ""}>Edit a record</option>
    </select>
    <select data-step-page data-action="change->journey-builder#pageChanged">
      <option value="">Choose a page</option>
      <option value="1"${page === "1" ? " selected" : ""}> Student form </option>
      <option value="2"${page === "2" ? " selected" : ""}>Course form</option>
      <option value="3"${page === "3" ? " selected" : ""}>Enrol form</option>
      <option value="4"${page === "4" ? " selected" : ""}>Notes</option>
      <option value="9">Gone</option>
    </select>
    <p data-step-hint></p>
    <input type="text" data-step-label data-action="input->journey-builder#refresh" value="${label}">
    <div data-step-inputs>${inputs}</div>
    <select data-step-record data-step-input-entity="${recordEntity}" name="journey[steps][][record]">
      <option value="">Choose a step</option>
      ${record ? `<option value="${record}" selected>${record}</option>` : ""}
    </select>
    <p data-step-record-hint></p>
    ${optionalBox ? `<input type="checkbox" data-step-optional data-action="change->journey-builder#refresh"${optional ? " checked" : ""}>` : ""}
    <input type="checkbox" data-step-conditional data-action="change->journey-builder#refresh"${conditional ? " checked" : ""}>
    <span data-step-skipped-by></span>
    <div data-step-effects hidden>
      <a data-step-effects-link href="#" hidden></a>
      <ul data-step-effects-lines></ul>
      <ul data-step-effects-next hidden></ul>
    </div>
    ${extra}
    <button type="button" data-action="journey-builder#moveUp" class="up">u</button>
    <button type="button" data-action="journey-builder#moveDown" class="down">d</button>
    <button type="button" data-action="journey-builder#remove" class="rm">x</button>
  </li>`

const finishRow = `
  <div data-journey-builder-target="row" data-finish>
    <input type="hidden" data-step-key value="finish">
    <select data-step-options></select>
  </div>`

const whenControl = ({ field = "", values = "" } = {}) => `
  <select data-journey-builder-target="whenField" data-action="change->journey-builder#whenFieldChanged">
    <option value="">Any record</option>
    ${field ? `<option value="${field}" selected>${field}</option>` : ""}
  </select>
  <div data-journey-builder-target="whenValues"${field ? "" : " hidden"}>
    <div data-when-options>${values}</div>
  </div>
  <template data-journey-builder-target="whenValueTemplate">
    <label><input type="checkbox" name="journey[start][when][in][]" data-when-value><span data-when-value-label></span><span data-when-value-sources></span></label>
  </template>`

const startControl = ({ kind = "create", entity = "", condition = "" } = {}) => `
  <fieldset>
    <input type="hidden" data-journey-builder-target="startKey" value="record">
    ${["create", "record"].map((value) => `
      <input type="radio" name="journey[start][kind]" value="${value}" class="kind-${value}"${kind === value ? " checked" : ""}
             data-journey-builder-target="startKind" data-action="change->journey-builder#refresh">`).join("")}
    <select data-journey-builder-target="startEntity" data-action="change->journey-builder#recordTypeChanged">
      <option value="">Choose a record type</option>
      <option value="s"${entity === "s" ? " selected" : ""}> Student </option>
      <option value="c"${entity === "c" ? " selected" : ""}>Course</option>
    </select>
    ${condition}
  </fieldset>`

describe("journey_builder_controller", () => {
  const mount = async (list = "", start = "") => {
    const mounted = await mountController("journey-builder", JourneyBuilderController, `
    <div data-controller="journey-builder"
         data-journey-builder-pages-value='${JSON.stringify(pages)}'
         data-journey-builder-choices-value='${JSON.stringify(choices)}'
         data-journey-builder-none-value="Choose a step"
         data-journey-builder-step-name-value="Step {number}"
         data-journey-builder-record-name-value="The {entity} record"
         data-journey-builder-skipped-by-value="Left out by {steps}."
         data-journey-builder-skipped-none-value="Nothing leaves this out."
         data-journey-builder-separator-value="; ">
      ${start}
      <ol data-journey-builder-target="list">${list}</ol>
      <template data-journey-builder-target="template">${stepRow()}</template>
      <template data-journey-builder-target="inputTemplate">
        <label class="block min-w-0"><span class="form-label" data-step-input-label></span>
          <select class="input-field" data-step-input></select>
        </label>
      </template>
      <button type="button" data-action="journey-builder#add" id="add">+</button>
      ${finishRow}
    </div>`)
    return mounted
  }

  const rows = () => Array.from(document.querySelectorAll("[data-journey-builder-target='list'] > [data-journey-builder-target='row']"))
  const keys = () => rows().map((row) => row.querySelector("[data-step-key]").value)
  const labels = () => rows().map((row) => row.querySelector("[data-step-label]").value)
  const finishPicker = () => document.querySelector("[data-finish] [data-step-options]")
  const picker = (index) => rows()[index].querySelector("[data-step-input]")
  const listed = (select) => Array.from(select.options, (option) => [option.value, option.textContent])
  const add = () => { document.getElementById("add").click(); return tick() }
  const click = (index, action) => rows()[index].querySelector(`.${action}`).click()
  const changePage = (index, value) => {
    const page = rows()[index].querySelector("[data-step-page]")
    page.value = value
    page.dispatchEvent(new Event("change"))
  }

  describe("adding rows", () => {
    it("appends a row above the finish with the next unused key", async () => {
      await mount(stepRow({ key: "start" }))
      await add()
      await add()

      expect(keys()).toEqual(["start", "step_3", "step_4"])
      expect(document.querySelector("[data-finish]").previousElementSibling.id).toBe("add")
    })

    it("gives each added row its own hint id and points the page picker at it", async () => {
      await mount(stepRow({ key: "start" }))
      await add()
      await add()

      const hints = rows().slice(1).map((row) => row.querySelector("[data-step-hint]").id)
      expect(hints).toEqual(["journey-step-hint-step_3", "journey-step-hint-step_4"])
      expect(rows()[2].querySelector("[data-step-page]").getAttribute("aria-describedby")).toBe("journey-step-hint-step_4")
      expect(rows()[2].querySelector("[data-step-record-hint]").id).toBe("journey-step-hint-step_4-record")
      expect(rows()[2].querySelector("[data-step-record]").getAttribute("aria-describedby")).toBe("journey-step-hint-step_4-record")
    })

    it("skips a key that is already taken", async () => {
      await mount(stepRow({ key: "step_3" }))
      await add()

      expect(keys()).toEqual(["step_3", "step_4"])
    })

    it("lists the new row in the finish picker straight away", async () => {
      await mount()
      await add()

      expect(listed(finishPicker())).toEqual([["step_2", "Step 1"]])
    })
  })

  describe("reordering and removing", () => {
    const three = () => mount(stepRow({ key: "a", label: "A" }) + stepRow({ key: "b", label: "B" }) + stepRow({ key: "c", label: "C" }))

    it("moves rows up and down, ignoring moves past either end", async () => {
      await three()

      click(0, "up")
      expect(keys()).toEqual(["a", "b", "c"])
      click(0, "down")
      expect(keys()).toEqual(["b", "a", "c"])
      click(2, "down")
      expect(keys()).toEqual(["b", "a", "c"])
      click(2, "up")
      expect(keys()).toEqual(["b", "c", "a"])
      expect(listed(finishPicker())).toEqual([["b", "B"], ["c", "C"], ["a", "A"]])
    })

    it("removes a row and drops it from the pickers below", async () => {
      await three()

      click(1, "rm")
      expect(labels()).toEqual(["A", "C"])
      expect(listed(finishPicker())).toEqual([["a", "A"], ["c", "C"]])
    })
  })

  describe("step pickers", () => {
    it("lists earlier matching steps in each fill picker, named by label, then page, then number", async () => {
      await mount(
        stepRow({ key: "start", label: " Student ", page: "1" }) +
        stepRow({ key: "courses", page: "1", inputs: inputSelect() }) +
        stepRow({ key: "clubs", inputs: inputSelect() })
      )
      await add()

      expect(listed(picker(1))).toEqual([["", "Choose a step"], ["start", "Student"]])
      expect(listed(picker(2))).toEqual([["", "Choose a step"], ["start", "Student"], ["courses", "Student form"]])
      expect(listed(finishPicker())).toEqual([
        ["start", "Student"], ["courses", "Student form"], ["clubs", "Step 3"], ["step_5", "Step 4"]
      ])
    })

    it("skips earlier steps whose record type does not match the fill picker", async () => {
      await mount(
        stepRow({ key: "start", label: "Student", page: "1" }) +
        stepRow({ key: "course", label: "Course", page: "2" }) +
        stepRow({ key: "courses", inputs: inputSelect({ entity: "s" }) })
      )
      rows()[1].querySelector("[data-step-page]").value = "2"
      rows()[2].querySelector("[data-step-label]").dispatchEvent(new Event("input"))

      expect(listed(picker(2))).toEqual([["", "Choose a step"], ["start", "Student"]])
    })

    it("renames a step as its label is typed or its page is chosen", async () => {
      await mount(stepRow({ key: "start" }))
      const row = rows()[0]

      changePage(0, "2")
      expect(listed(finishPicker())).toEqual([["start", "Course form"]])

      const label = row.querySelector("[data-step-label]")
      label.value = "Courses"
      label.dispatchEvent(new Event("input"))
      expect(listed(finishPicker())).toEqual([["start", "Courses"]])
    })

    it("keeps a fill choice while that step stays listed, and blanks it once it does not", async () => {
      await mount(
        stepRow({ key: "start", label: "Student", page: "1" }) +
        stepRow({ key: "courses", label: "Courses", page: "1" }) +
        stepRow({ key: "clubs", inputs: inputSelect({ value: "courses" }) })
      )
      const label = rows()[0].querySelector("[data-step-label]")
      label.dispatchEvent(new Event("input"))
      picker(2).value = "courses"
      finishPicker().value = "courses"

      label.value = "Learner"
      label.dispatchEvent(new Event("input"))
      expect(picker(2).value).toBe("courses")
      expect(finishPicker().value).toBe("courses")

      click(1, "down")
      expect(keys()).toEqual(["start", "clubs", "courses"])
      expect(listed(picker(1))).toEqual([["", "Choose a step"], ["start", "Learner"]])
      expect(picker(1).value).toBe("")
      expect(finishPicker().value).toBe("courses")
    })

    it("drops optional earlier steps from the finish picker and falls back to the first remaining", async () => {
      await mount(
        stepRow({ key: "start", label: "Student", page: "1" }) +
        stepRow({ key: "extra", label: "Extra" })
      )
      rows()[0].querySelector("[data-step-label]").dispatchEvent(new Event("input"))
      finishPicker().value = "extra"
      expect(finishPicker().value).toBe("extra")

      rows()[1].querySelector("[data-step-optional]").checked = true
      rows()[1].querySelector("[data-step-optional]").dispatchEvent(new Event("change"))
      expect(listed(finishPicker())).toEqual([["start", "Student"]])
      expect(finishPicker().value).toBe("start")
    })

    it("treats a row without an optional checkbox as required", async () => {
      await mount(stepRow({ key: "start", label: "Student", page: "1", optionalBox: false }))
      await add()

      expect(listed(finishPicker())).toEqual([["start", "Student"], ["step_3", "Step 2"]])
    })
  })

  describe("pageChanged", () => {
    it("sets the hint and create mode for a page that locks nothing, and clears fill pickers", async () => {
      await mount(stepRow({ key: "start", page: "2", inputs: inputSelect({ value: "x" }) }))
      changePage(0, "1")

      expect(rows()[0].querySelector("[data-step-hint]").textContent).toBe("Student hint")
      expect(rows()[0].dataset.stepMode).toBe("create")
      expect(rows()[0].querySelector("[data-step-inputs]").children).toHaveLength(0)
    })

    it("sets relate mode and clones a fill picker per locked input", async () => {
      await mount(stepRow({ key: "start", page: "1" }) + stepRow({ key: "courses" }))
      changePage(1, "2")

      expect(rows()[1].querySelector("[data-step-hint]").textContent).toBe("Course hint")
      expect(rows()[1].dataset.stepMode).toBe("relate")
      const select = picker(1)
      expect(select.name).toBe("journey[steps][][inputs][student]")
      expect(select.dataset.stepInputEntity).toBe("s")
      expect(select.closest("label").querySelector(".form-label").textContent).toBe("Student from")
      expect(listed(select)).toEqual([["", "Choose a step"], ["start", "Student form"]])
    })

    it("clears hint and mode when the page is blank", async () => {
      await mount(stepRow({ key: "start", page: "1" }))
      changePage(0, "")

      expect(rows()[0].querySelector("[data-step-hint]").textContent).toBe("")
      expect(rows()[0].dataset.stepMode).toBe("none")
    })

    it("sets create mode for a page with a null entity and no inputs list", async () => {
      await mount(stepRow({ key: "start" }))
      changePage(0, "4")

      expect(rows()[0].dataset.stepMode).toBe("create")
      expect(rows()[0].querySelector("[data-step-hint]").textContent).toBe("Loose hint")
      expect(listed(finishPicker())[0][0]).toBe("start")
    })

    it("keeps each field's previous choice when the new page still has that field", async () => {
      await mount(
        stepRow({ key: "start", label: "Student", page: "1" }) +
        stepRow({ key: "courses", inputs: inputSelect({ value: "start" }) + `<select data-step-input name="other"></select><select data-step-input></select>` })
      )
      rows()[0].querySelector("[data-step-label]").dispatchEvent(new Event("input"))
      changePage(1, "3")

      const selects = rows()[1].querySelectorAll("[data-step-input]")
      expect(selects).toHaveLength(2)
      expect(selects[0].name).toBe("journey[steps][][inputs][student]")
      expect(selects[0].value).toBe("start")
      expect(selects[1].name).toBe("journey[steps][][inputs][course]")
      expect(selects[1].dataset.stepInputEntity).toBe("c")
      expect(selects[1].value).toBe("")
      expect(selects[1].closest("label").querySelector(".form-label").textContent).toBe("Course from")
    })
  })

  describe("start", () => {
    const leading = () => rows().map((row) => row.hasAttribute("data-step-lead"))
    const chooseKind = (value) => {
      const radio = document.querySelector(`.kind-${value}`)
      radio.checked = true
      radio.dispatchEvent(new Event("change"))
    }

    it("leads with the first row when the journey starts with a new record", async () => {
      await mount(stepRow({ key: "start", page: "1" }), startControl())
      await add()

      expect(leading()).toEqual([true, false])
      expect(document.querySelector("[data-finish]").hasAttribute("data-step-lead")).toBe(false)
    })

    it("lists the start record before every step and stops the first row leading", async () => {
      await mount(stepRow({ key: "courses", label: "Courses", inputs: inputSelect() }), startControl({ kind: "record", entity: "s" }))
      chooseKind("record")

      expect(leading()).toEqual([false])
      expect(listed(picker(0))).toEqual([["", "Choose a step"], ["record", "The Student record"]])
      expect(listed(finishPicker())).toEqual([["record", "The Student record"], ["courses", "Courses"]])
    })

    it("offers no start record until a record type is chosen", async () => {
      await mount(stepRow({ key: "courses", inputs: inputSelect() }), startControl({ kind: "record" }))
      chooseKind("record")

      expect(leading()).toEqual([false])
      expect(listed(picker(0))).toEqual([["", "Choose a step"]])
    })

    it("drops the start record and leads again when switched back to a new record", async () => {
      await mount(stepRow({ key: "courses", inputs: inputSelect() }), startControl({ kind: "record", entity: "s" }))
      chooseKind("record")
      chooseKind("create")

      expect(leading()).toEqual([true])
      expect(listed(finishPicker())).toEqual([["courses", "Step 1"]])
    })

    it("sets a row that edits a record back to adding once it leads", async () => {
      await mount(stepRow({ key: "review", kind: "update", page: "1" }), startControl({ kind: "record", entity: "s" }))
      chooseKind("record")
      expect(rows()[0].querySelector("[data-step-kind]").value).toBe("update")

      chooseKind("create")

      expect(leading()).toEqual([true])
      expect(rows()[0].querySelector("[data-step-kind]").value).toBe("add")
      expect(rows()[0].dataset.stepMode).toBe("create")
      expect(rows()[0].querySelector("option[value='2']").disabled).toBe(false)
    })
  })

  describe("a row that edits a record", () => {
    const kindOf = (index) => rows()[index].querySelector("[data-step-kind]")
    const pageSelect = (index) => rows()[index].querySelector("[data-step-page]")
    const recordPicker = (index) => rows()[index].querySelector("[data-step-record]")
    const setKind = (index, value) => {
      kindOf(index).value = value
      kindOf(index).dispatchEvent(new Event("change"))
    }
    const offered = (index) => Array.from(pageSelect(index).options).filter((option) => !option.hidden && !option.disabled)
      .map((option) => option.value)

    it("offers only pages that edit records, keeping a page that does, and lists earlier records of its type", async () => {
      await mount(stepRow({ key: "start", label: "Student", page: "1" }) + stepRow({ key: "review", page: "1" }))
      setKind(1, "update")

      expect(offered(1)).toEqual(["", "1"])
      expect(pageSelect(1).value).toBe("1")
      expect(rows()[1].dataset.stepMode).toBe("update")
      expect(recordPicker(1).dataset.stepInputEntity).toBe("s")
      expect(listed(recordPicker(1))).toEqual([["", "Choose a step"], ["start", "Student"]])
    })

    it("clears a page that doesn't edit records and offers no record until one is chosen", async () => {
      await mount(stepRow({ key: "start", label: "Student", page: "1" }) + stepRow({ key: "review", page: "2" }))
      changePage(1, "2")
      setKind(1, "update")

      expect(pageSelect(1).value).toBe("")
      expect(rows()[1].querySelector("[data-step-hint]").textContent).toBe("")
      expect(rows()[1].dataset.stepMode).toBe("update")
      expect(rows()[1].querySelector("[data-step-inputs]").children).toHaveLength(0)
      expect(listed(recordPicker(1))).toEqual([["", "Choose a step"]])

      changePage(1, "1")
      expect(rows()[1].dataset.stepMode).toBe("update")
      expect(listed(recordPicker(1))).toEqual([["", "Choose a step"], ["start", "Student"]])
    })

    it("offers every page again once set back to adding", async () => {
      await mount(stepRow({ key: "start", page: "1" }) + stepRow({ key: "review", kind: "update", page: "1" }))
      setKind(1, "update")
      setKind(1, "add")

      expect(offered(1)).toEqual(["", "1", "2", "3", "4", "9"])
      expect(rows()[1].dataset.stepMode).toBe("create")
    })

    it("keeps the record choice while that step stays listed, and offers the start record", async () => {
      await mount(
        stepRow({ key: "review", kind: "update", page: "1", record: "record", recordEntity: "s" }),
        startControl({ kind: "record", entity: "s" })
      )
      expect(listed(recordPicker(0))).toEqual([["", "Choose a step"], ["record", "record"]])
      document.querySelector(".kind-record").dispatchEvent(new Event("change"))

      expect(listed(recordPicker(0))).toEqual([["", "Choose a step"], ["record", "The Student record"]])
      expect(recordPicker(0).value).toBe("record")

      const type = document.querySelector("[data-journey-builder-target='startEntity']")
      type.value = "c"
      type.dispatchEvent(new Event("change"))
      expect(listed(recordPicker(0))).toEqual([["", "Choose a step"]])
      expect(recordPicker(0).value).toBe("")
    })
  })

  describe("start condition", () => {
    const fieldSelect = () => document.querySelector("[data-journey-builder-target='whenField']")
    const valuesBox = () => document.querySelector("[data-journey-builder-target='whenValues']")
    const values = () => Array.from(valuesBox().querySelectorAll("[data-when-value]"))
      .map((box) => [box.value, box.closest("label").querySelector("[data-when-value-label]").textContent, box.checked])
    const chooseType = (value) => {
      const type = document.querySelector("[data-journey-builder-target='startEntity']")
      type.value = value
      type.dispatchEvent(new Event("change"))
    }
    const chooseField = (value) => {
      fieldSelect().value = value
      fieldSelect().dispatchEvent(new Event("change"))
    }

    it("lists the chosen record type's choice fields after Any record, and hides the values", async () => {
      await mount(stepRow({ key: "next" }), startControl({ kind: "record", condition: whenControl({ field: "old" }) }))
      chooseType("s")

      expect(listed(fieldSelect())).toEqual([["", "Any record"], ["status", "Status"], ["level", "Level"]])
      expect(fieldSelect().value).toBe("")
      expect(valuesBox().hidden).toBe(true)
      expect(values()).toEqual([])
      expect(listed(finishPicker())[0]).toEqual(["record", "The Student record"])
    })

    it("offers only Any record for a type without choice fields", async () => {
      await mount(stepRow({ key: "next" }), startControl({ kind: "record", entity: "s", condition: whenControl() }))
      chooseType("c")

      expect(listed(fieldSelect())).toEqual([["", "Any record"]])
    })

    it("lists the chosen field's values, unchecked, and clears them for Any record", async () => {
      await mount(stepRow({ key: "next" }), startControl({ kind: "record", entity: "s", condition: whenControl() }))
      chooseType("s")
      chooseField("status")

      expect(valuesBox().hidden).toBe(false)
      expect(values()).toEqual([["Submitted", "Submitted", false], ["Approved", "Approved", false]])
      expect(Array.from(valuesBox().querySelectorAll("[data-when-value-sources]"), (note) => note.textContent))
        .toEqual(["", "Reached in Review"])

      chooseField("")
      expect(valuesBox().hidden).toBe(true)
      expect(values()).toEqual([])
    })

    it("finds no values for a field while no record type is chosen", async () => {
      await mount(stepRow({ key: "next" }), startControl({ kind: "record", condition: whenControl({ field: "status" }) }))
      chooseField("status")

      expect(valuesBox().hidden).toBe(true)
    })

    it("only refreshes the pickers when there is no condition to rebuild", async () => {
      await mount(stepRow({ key: "next", inputs: inputSelect() }), startControl({ kind: "record" }))
      chooseType("s")

      expect(listed(picker(0))).toEqual([["", "Choose a step"], ["record", "The Student record"]])
    })
  })

  describe("On submit", () => {
    const block = (index) => rows()[index].querySelector("[data-step-effects]")
    const link = (index) => block(index).querySelector("[data-step-effects-link]")
    const items = (index, list) => Array.from(block(index).querySelectorAll(`[data-step-effects-${list}] li`), (item) => item.textContent)
    const nextList = (index) => block(index).querySelector("[data-step-effects-next]")

    it("shows the chosen page's processing, what its submit does and who picks its record up", async () => {
      await mount(stepRow({ key: "start" }))
      changePage(0, "1")

      expect(block(0).hidden).toBe(false)
      expect([link(0).hidden, link(0).textContent, link(0).getAttribute("href")]).toEqual([false, "Processing: Intake", "/p/1"])
      expect(items(0, "lines")).toEqual(["Saves the record", "A new Student starts Submitted"])
      expect(items(0, "next")).toEqual(["Next: Review", "Next: Welcome"])
      expect(nextList(0).hidden).toBe(false)
    })

    it("hides the link and the next lines when there are none, and the block without a page", async () => {
      await mount(stepRow({ key: "start" }))
      changePage(0, "1")
      changePage(0, "2")

      expect([link(0).hidden, link(0).textContent, link(0).getAttribute("href")]).toEqual([true, "", "#"])
      expect(items(0, "lines")).toEqual(["Saves the record"])
      expect(items(0, "next")).toEqual([])
      expect(nextList(0).hidden).toBe(true)

      changePage(0, "")
      expect(block(0).hidden).toBe(true)
    })

    it("drops what only a new record does while the row edits one", async () => {
      await mount(stepRow({ key: "start", page: "1" }) + stepRow({ key: "review", page: "1" }))
      const kind = rows()[1].querySelector("[data-step-kind]")
      kind.value = "update"
      kind.dispatchEvent(new Event("change"))

      expect(items(1, "lines")).toEqual(["Saves the record"])
      expect(items(1, "next")).toEqual(["Next: Review"])
    })
  })

  describe("steps processing may skip", () => {
    const box = (index) => rows()[index].querySelector("[data-step-conditional]")
    const skippedBy = (index) => rows()[index].querySelector("[data-step-skipped-by]").textContent
    const refresh = () => rows()[0].querySelector("[data-step-label]").dispatchEvent(new Event("input"))

    it("names the earlier steps whose processing may leave a row out", async () => {
      await mount(
        stepRow({ key: "start", label: "Intake", page: "1" }) +
        stepRow({ key: "second", label: "Second intake", page: "1" }) +
        stepRow({ key: "notes", conditional: true }) +
        stepRow({ key: "other", conditional: true })
      )
      refresh()

      expect(skippedBy(2)).toBe("Left out by Intake; Second intake.")
      expect(skippedBy(3)).toBe("Nothing leaves this out.")
    })

    it("never lets the first row be skipped", async () => {
      await mount(stepRow({ key: "start", page: "1", conditional: true }) + stepRow({ key: "notes", conditional: true }))
      refresh()

      expect([box(0).checked, box(1).checked]).toEqual([false, true])
    })

    it("drops a row processing may skip from the finish picker", async () => {
      await mount(stepRow({ key: "start", label: "Student", page: "1" }) + stepRow({ key: "extra", label: "Extra" }))
      refresh()
      expect(listed(finishPicker())).toEqual([["start", "Student"], ["extra", "Extra"]])

      box(1).checked = true
      box(1).dispatchEvent(new Event("change"))
      expect(listed(finishPicker())).toEqual([["start", "Student"]])
    })
  })
})
