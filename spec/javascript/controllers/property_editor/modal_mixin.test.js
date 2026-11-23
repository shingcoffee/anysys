import { describe, it, expect, beforeEach, vi } from "vitest"
import ModalMixin, { applyModalMixin } from "controllers/property_editor/modal_mixin"

// A tiny host with the mixin methods bound.
const host = () => Object.assign({}, ModalMixin)

const container = (inner) => {
  const el = document.createElement("div")
  el.innerHTML = inner
  return el
}

describe("_openModal", () => {
  it("returns null when container or modal is missing", () => {
    expect(host()._openModal(null, "[data-m]")).toBeNull()
    expect(host()._openModal(container("<div></div>"), "[data-m]")).toBeNull()
  })

  it("un-hides the modal and returns it", () => {
    const c = container('<div data-m class="hidden"></div>')
    const modal = host()._openModal(c, "[data-m]")
    expect(modal).not.toBeNull()
    expect(modal.classList.contains("hidden")).toBe(false)
  })

  it("invokes onOpen with the modal", () => {
    const c = container('<div data-m class="hidden"></div>')
    const onOpen = vi.fn()
    host()._openModal(c, "[data-m]", { onOpen })
    expect(onOpen).toHaveBeenCalledWith(c.querySelector("[data-m]"))
  })

  it("focuses the focusSelector element after a timeout", () => {
    vi.useFakeTimers()
    const c = container('<div data-m class="hidden"><input data-f></div>')
    const focus = vi.spyOn(c.querySelector("[data-f]"), "focus")
    host()._openModal(c, "[data-m]", { focusSelector: "[data-f]" })
    vi.advanceTimersByTime(100)
    expect(focus).toHaveBeenCalled()
    vi.useRealTimers()
  })
})

describe("_closeModal", () => {
  it("no-ops gracefully when container/modal missing", () => {
    expect(() => host()._closeModal(null, "[data-m]")).not.toThrow()
    expect(() => host()._closeModal(container("<div></div>"), "[data-m]")).not.toThrow()
  })

  it("hides the modal and calls onClose", () => {
    const c = container("<div data-m></div>")
    const onClose = vi.fn()
    host()._closeModal(c, "[data-m]", { onClose })
    expect(c.querySelector("[data-m]").classList.contains("hidden")).toBe(true)
    expect(onClose).toHaveBeenCalled()
  })
})

describe("_resetModalFields", () => {
  it("clears textareas and inputs (single or array selectors)", () => {
    const modal = container(`
      <textarea data-ta>hi</textarea>
      <input data-i1 value="x">
      <input data-i2 value="y">
    `)
    host()._resetModalFields(modal, {
      textareas: "[data-ta]",
      inputs: ["[data-i1]", "[data-i2]"],
    })
    expect(modal.querySelector("[data-ta]").value).toBe("")
    expect(modal.querySelector("[data-i1]").value).toBe("")
    expect(modal.querySelector("[data-i2]").value).toBe("")
  })

  it("resets selects to first option (string selector)", () => {
    const modal = container(`
      <select data-s><option>a</option><option>b</option></select>
    `)
    const select = modal.querySelector("[data-s]")
    select.selectedIndex = 1
    host()._resetModalFields(modal, { selects: "[data-s]" })
    expect(select.selectedIndex).toBe(0)
  })

  it("resets a select to a specified defaultValue (object selector)", () => {
    const modal = container(`
      <select data-s><option value="a">a</option><option value="b">b</option></select>
    `)
    host()._resetModalFields(modal, {
      selects: [{ selector: "[data-s]", defaultValue: "b" }],
    })
    expect(modal.querySelector("[data-s]").value).toBe("b")
  })

  it("no-ops on a null modal", () => {
    expect(() => host()._resetModalFields(null, { inputs: "[data-i]" })).not.toThrow()
  })

  it("also accepts textareas as an array and inputs as a single selector", () => {
    const modal = container(`
      <textarea data-ta1>hi</textarea>
      <textarea data-ta2>bye</textarea>
      <input data-i1 value="x">
    `)
    host()._resetModalFields(modal, {
      textareas: ["[data-ta1]", "[data-ta2]"],
      inputs: "[data-i1]",
    })
    expect(modal.querySelector("[data-ta1]").value).toBe("")
    expect(modal.querySelector("[data-ta2]").value).toBe("")
    expect(modal.querySelector("[data-i1]").value).toBe("")
  })
})

describe("_setSubmitButtonState", () => {
  it("toggles the disabled attribute", () => {
    const modal = container("<button data-b></button>")
    const btn = modal.querySelector("[data-b]")
    host()._setSubmitButtonState(modal, "[data-b]", false)
    expect(btn.disabled).toBe(true)
    host()._setSubmitButtonState(modal, "[data-b]", true)
    expect(btn.disabled).toBe(false)
  })

  it("no-ops on null modal", () => {
    expect(() => host()._setSubmitButtonState(null, "[data-b]", true)).not.toThrow()
  })
})

describe("_highlightFieldError", () => {
  it("adds red ring classes + focus, removing them after the duration", () => {
    vi.useFakeTimers()
    const field = document.createElement("input")
    const focus = vi.spyOn(field, "focus")
    host()._highlightFieldError(field, 1000)
    expect(field.classList.contains("ring-red-500")).toBe(true)
    expect(focus).toHaveBeenCalled()
    vi.advanceTimersByTime(1000)
    expect(field.classList.contains("ring-red-500")).toBe(false)
    vi.useRealTimers()
  })

  it("no-ops on null field", () => {
    expect(() => host()._highlightFieldError(null)).not.toThrow()
  })
})

describe("_showSuccessAnimation", () => {
  it("adds green classes then removes them after the duration", () => {
    vi.useFakeTimers()
    const el = document.createElement("div")
    host()._showSuccessAnimation(el, 300)
    expect(el.classList.contains("ring-green-400")).toBe(true)
    vi.advanceTimersByTime(300)
    expect(el.classList.contains("ring-green-400")).toBe(false)
    vi.useRealTimers()
  })

  it("no-ops on a null element", () => {
    expect(() => host()._showSuccessAnimation(null)).not.toThrow()
  })
})

describe("applyModalMixin", () => {
  it("copies every mixin method onto a class prototype", () => {
    class Manager {}
    applyModalMixin(Manager)
    const m = new Manager()
    expect(typeof m._openModal).toBe("function")
    expect(typeof m._closeModal).toBe("function")
    expect(typeof m._resetModalFields).toBe("function")
    expect(typeof m._highlightFieldError).toBe("function")
  })
})
