import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/ai_assistant_questions_controller"
import { mountController, controllerFor, click, tick } from "../support/stimulus.js"

const NO_PREFERENCE = "No preference"
const LIST_SEPARATOR = ", "
const SKIP_REPLY = "Use your best judgement for these and go ahead."

function fieldset({ type, prompt, options = [], checked = [], other = "", text = "" } = {}) {
  const chips = options
    .map((option) => {
      const isOn = checked.includes(option)
      if (type === "single") {
        return `<label><input type="radio" class="peer" value="${option}" ${isOn ? "checked" : ""} data-action="change->ai-assistant-questions#pickOption"></label>`
      }
      return `<label><input type="checkbox" class="peer" value="${option}" ${isOn ? "checked" : ""} data-action="change->ai-assistant-questions#pickOption"></label>`
    })
    .join("")
  const otherField = type === "text"
    ? ""
    : `<input type="text" data-question-other value="${other}" data-action="input->ai-assistant-questions#typeOther keydown->ai-assistant-questions#preventSubmit">`
  const textField = type === "text"
    ? `<input type="text" data-question-text value="${text}" data-action="keydown->ai-assistant-questions#preventSubmit">`
    : ""
  return `<fieldset data-question-type="${type}" data-question-prompt="${prompt}">${chips}${otherField}${textField}</fieldset>`
}

function cardHtml({ questions, values = {} } = {}) {
  const value = (name, fallback) => {
    if (Object.prototype.hasOwnProperty.call(values, name)) {
      return ` data-ai-assistant-questions-${name}-value="${values[name]}"`
    }
    return fallback == null ? "" : ` data-ai-assistant-questions-${name}-value="${fallback}"`
  }
  return `<section data-controller="ai-assistant-questions"${value("no-preference")}${value("list-separator")}${value("skip-reply")}>
    ${questions}
    <button type="button" data-action="click->ai-assistant-questions#send">Send</button>
    <button type="button" data-action="click->ai-assistant-questions#skip">Skip</button>
  </section>`
}

async function mountCard(questions, values) {
  return mountController("ai-assistant-questions", Controller, cardHtml({ questions, values }))
}

function listen(element) {
  const bodies = []
  element.addEventListener("ai-assistant-questions:answer", (event) => {
    bodies.push(event.detail.body)
  })
  return bodies
}

function pressEnter(input) {
  const event = new Event("keydown", { bubbles: true, cancelable: true })
  event.key = "Enter"
  input.dispatchEvent(event)
  return event
}

describe("ai-assistant-questions controller", () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  describe("compose rules", () => {
    it("uses other-text for a single question when it is present", async () => {
      const { element } = await mountCard(
        fieldset({
          type: "single",
          prompt: "Link style",
          options: [ "Account", "Text" ],
          checked: [ "Account" ],
          other: "  Keep both  "
        })
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ "Link style\nKeep both" ])
    })

    it("uses the checked option when a single question has no other-text", async () => {
      const { element } = await mountCard(
        fieldset({
          type: "single",
          prompt: "Link style",
          options: [ "Account", "Text" ],
          checked: [ "Account" ]
        })
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ "Link style\nAccount" ])
    })

    it("falls back to no preference when a single question is empty", async () => {
      const { element } = await mountCard(
        fieldset({ type: "single", prompt: "Link style", options: [ "Account" ] })
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ `Link style\n${NO_PREFERENCE}` ])
    })

    it("joins checked options and other-text for a multiple question", async () => {
      const { element } = await mountCard(
        fieldset({
          type: "multiple",
          prompt: "Stages",
          options: [ "Qualification", "Proposal", "Negotiation" ],
          checked: [ "Qualification", "Proposal" ],
          other: "Review"
        })
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ `Stages\nQualification${LIST_SEPARATOR}Proposal${LIST_SEPARATOR}Review` ])
    })

    it("joins only the checked options when other-text is blank", async () => {
      const { element } = await mountCard(
        fieldset({
          type: "multiple",
          prompt: "Stages",
          options: [ "Qualification", "Proposal" ],
          checked: [ "Proposal" ]
        })
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ "Stages\nProposal" ])
    })

    it("uses other-text alone when nothing is checked on a multiple question", async () => {
      const { element } = await mountCard(
        fieldset({ type: "multiple", prompt: "Stages", options: [ "Qualification" ], other: "Custom" })
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ "Stages\nCustom" ])
    })

    it("falls back to no preference when a multiple question is empty", async () => {
      const { element } = await mountCard(
        fieldset({ type: "multiple", prompt: "Stages", options: [ "Qualification" ] })
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ `Stages\n${NO_PREFERENCE}` ])
    })

    it("joins checked options when a multiple question has no other input", async () => {
      const { element } = await mountCard(
        `<fieldset data-question-type="multiple" data-question-prompt="Stages"><input type="checkbox" value="Qualification" checked><input type="checkbox" value="Proposal" checked></fieldset>`
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ `Stages\nQualification${LIST_SEPARATOR}Proposal` ])
    })

    it("uses the trimmed text value, else no preference", async () => {
      const { element } = await mountCard(
        fieldset({ type: "text", prompt: "Hours", text: "  Mon–Sat  " }) +
          fieldset({ type: "text", prompt: "Notes", text: "   " })
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ `Hours\nMon–Sat\n\nNotes\n${NO_PREFERENCE}` ])
    })

    it("uses the localized values the server set", async () => {
      const { element } = await mountCard(
        fieldset({ type: "multiple", prompt: "Stages", options: [ "A", "B" ], checked: [ "A", "B" ] }),
        { "no-preference": "无偏好", "list-separator": "、", "skip-reply": "跳过即可。" }
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))
      await click(element.querySelector("[data-action='click->ai-assistant-questions#skip']"))

      expect(bodies).toEqual([ "Stages\nA、B", "跳过即可。" ])
    })

    it("falls back to no preference for a text question with no input", async () => {
      const { element } = await mountCard(`<fieldset data-question-type="text" data-question-prompt="Hours"></fieldset>`)
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ `Hours\n${NO_PREFERENCE}` ])
    })

    it("falls back to no preference for a single question with no other input", async () => {
      const { element } = await mountCard(
        `<fieldset data-question-type="single" data-question-prompt="Link"><input type="radio" value="Account" checked></fieldset>`
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ "Link\nAccount" ])
    })

    it("falls back to no preference for an unknown question type", async () => {
      const { element } = await mountCard(
        `<fieldset data-question-type="essay" data-question-prompt="Why"></fieldset>`
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ `Why\n${NO_PREFERENCE}` ])
    })

    it("treats a missing prompt as an empty heading", async () => {
      const { element } = await mountCard(`<fieldset data-question-type="text"><input data-question-text value="ok"></fieldset>`)
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#send']"))

      expect(bodies).toEqual([ "\nok" ])
    })
  })

  describe("skip", () => {
    it("dispatches the skip phrase and does not compose answers", async () => {
      const { element } = await mountCard(
        fieldset({ type: "text", prompt: "Hours", text: "Mon" })
      )
      const bodies = listen(element)

      await click(element.querySelector("[data-action='click->ai-assistant-questions#skip']"))

      expect(bodies).toEqual([ SKIP_REPLY ])
    })
  })

  describe("other / radio interplay", () => {
    it("clears the other input when a single radio is picked", async () => {
      const { element } = await mountCard(
        fieldset({
          type: "single",
          prompt: "Link",
          options: [ "Account", "Text" ],
          other: "typed"
        })
      )
      const radio = element.querySelector('input[value="Text"]')
      const other = element.querySelector("[data-question-other]")

      radio.checked = true
      radio.dispatchEvent(new Event("change", { bubbles: true }))
      await tick()

      expect(other.value).toBe("")
    })

    it("un-checks radios when typing in a single question's other input", async () => {
      const { element } = await mountCard(
        fieldset({
          type: "single",
          prompt: "Link",
          options: [ "Account" ],
          checked: [ "Account" ]
        })
      )
      const radio = element.querySelector('input[type="radio"]')
      const other = element.querySelector("[data-question-other]")

      other.value = "x"
      other.dispatchEvent(new Event("input", { bubbles: true }))
      await tick()

      expect(radio.checked).toBe(false)
    })

    it("keeps checkboxes when typing in a multiple question's other input", async () => {
      const { element } = await mountCard(
        fieldset({
          type: "multiple",
          prompt: "Stages",
          options: [ "Qualification" ],
          checked: [ "Qualification" ]
        })
      )
      const box = element.querySelector('input[type="checkbox"]')
      const other = element.querySelector("[data-question-other]")

      other.value = "x"
      other.dispatchEvent(new Event("input", { bubbles: true }))
      await tick()

      expect(box.checked).toBe(true)
      expect(other.value).toBe("x")
    })

    it("does not clear other-text when a multiple option is picked", async () => {
      const { element } = await mountCard(
        fieldset({
          type: "multiple",
          prompt: "Stages",
          options: [ "Qualification" ],
          other: "keep"
        })
      )
      const box = element.querySelector('input[type="checkbox"]')

      box.checked = true
      box.dispatchEvent(new Event("change", { bubbles: true }))
      await tick()

      expect(element.querySelector("[data-question-other]").value).toBe("keep")
    })
  })

  describe("Enter in other/text inputs", () => {
    it("prevents Enter in the other and text fields and does not dispatch", async () => {
      const { element } = await mountCard(
        fieldset({ type: "single", prompt: "Link", options: [ "Account" ] }) +
          fieldset({ type: "text", prompt: "Hours", text: "Mon" })
      )
      const bodies = listen(element)
      const other = element.querySelector("[data-question-other]")
      const text = element.querySelector("[data-question-text]")

      expect(pressEnter(other).defaultPrevented).toBe(true)
      expect(pressEnter(text).defaultPrevented).toBe(true)
      expect(bodies).toEqual([])
    })

    it("leaves other keys alone", async () => {
      const { element } = await mountCard(fieldset({ type: "text", prompt: "Hours" }))
      const input = element.querySelector("[data-question-text]")
      const event = new Event("keydown", { bubbles: true, cancelable: true })
      event.key = "a"
      input.dispatchEvent(event)

      expect(event.defaultPrevented).toBe(false)
    })
  })

  describe("defensive edges", () => {
    it("send and skip without an event still dispatch", async () => {
      const { application, element } = await mountCard(fieldset({ type: "text", prompt: "Hours", text: "Mon" }))
      const ctrl = controllerFor(application, element, "ai-assistant-questions")
      const bodies = listen(element)

      expect(() => ctrl.send()).not.toThrow()
      expect(() => ctrl.skip()).not.toThrow()
      expect(bodies).toEqual([ "Hours\nMon", SKIP_REPLY ])
    })

    it("pickOption and typeOther without a fieldset are no-ops", async () => {
      const { application, element } = await mountCard(fieldset({ type: "single", prompt: "Link", options: [ "Account" ] }))
      const ctrl = controllerFor(application, element, "ai-assistant-questions")

      expect(() => ctrl.pickOption()).not.toThrow()
      expect(() => ctrl.pickOption({ currentTarget: document.createTextNode("x") })).not.toThrow()
      expect(() => ctrl.typeOther()).not.toThrow()
      expect(() => ctrl.typeOther({ currentTarget: {} })).not.toThrow()
      expect(() => ctrl.preventSubmit()).not.toThrow()
    })

    it("pickOption on a single question without an other input is a no-op", async () => {
      const { application, element } = await mountCard(
        `<fieldset data-question-type="single" data-question-prompt="Link"><input type="radio" value="Account" data-action="change->ai-assistant-questions#pickOption"></fieldset>`
      )
      const ctrl = controllerFor(application, element, "ai-assistant-questions")
      const radio = element.querySelector("input")

      expect(() => ctrl.pickOption({ currentTarget: radio })).not.toThrow()
    })
  })
})
