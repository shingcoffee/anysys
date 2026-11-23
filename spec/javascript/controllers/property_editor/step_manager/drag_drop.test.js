// NOTE: getBoundingClientRect() returns zeroed rects in happy-dom (no real
// layout engine), so the top/bottom-half midpoint decision is stubbed per test
// via `Object.defineProperty(el, "getBoundingClientRect", ...)` — this exercises
// the ACTUAL branch logic (event.clientY < midpoint) rather than faking it.
// NOTE: _reindexSteps' per-item body calls
// `item.querySelectorAll("[name^='steps[']")`, and happy-dom's `^=` selector
// parser THROWS "Invalid regular expression: /^steps[/: Unterminated character
// class" on that unescaped "[" (verified empirically — real browsers accept it
// fine). This is unconditional: it throws even against an empty subtree,
// purely from compiling the selector string. So _reindexSteps can only be
// exercised up to (and including) an EMPTY step list here; the per-item rename
// loop is UNREACHABLE under happy-dom and is covered by Playwright instead.
// handleStepDrop's successful-move branch calls _reindexSteps for real, so it
// is tested with _reindexSteps stubbed out (isolating handleStepDrop's OWN
// DOM-move/cleanup/dispatch logic, which the stub-free _reindexSteps tests
// below cover separately for its own reachable lines).
import { describe, it, expect, beforeEach, vi } from "vitest"
import { makeStepManager } from "../_step_support.js"

const stepItem = (i) =>
  `<div data-step-item data-step-index="${i}" data-step-id="s${i}">` +
  `<input type="hidden" name="steps[${i}][action]" value="a${i}">` +
  `<textarea name="steps[${i}][description]"></textarea>` +
  `<div data-step-details class="hidden"></div>` +
  `<span data-step-expand-icon><svg></svg></span>` +
  `</div>`

const container = (n) =>
  `<div data-steps-container>${Array.from({ length: n }, (_, i) => stepItem(i)).join("")}</div>`

const fakeDT = () => ({ effectAllowed: "", dropEffect: "", setData: vi.fn(), getData: vi.fn() })

describe("StepManager DragDropMixin", () => {
  let mgr, controller
  beforeEach(() => {
    ;({ mgr, controller } = makeStepManager())
    controller.formTarget.innerHTML = container(3)
  })

  const items = () => [...controller.formTarget.querySelectorAll("[data-step-item]")]

  describe("handleStepDragStart", () => {
    it("records the dragged item, adds lift classes, and seeds dataTransfer", () => {
      const el = items()[1]
      const dt = fakeDT()
      mgr.handleStepDragStart({ target: el, dataTransfer: dt })

      expect(mgr._draggedItem).toBe(el)
      expect(el.classList.contains("opacity-70")).toBe(true)
      expect(el.classList.contains("ring-indigo-300")).toBe(true)
      expect(dt.effectAllowed).toBe("move")
      expect(dt.setData).toHaveBeenCalledWith("text/plain", "1")
      expect(controller.formTarget.querySelector("[data-steps-container]").classList.contains("step-dragging-active")).toBe(true)
    })

    it("no-ops when the drag did not start on a step item", () => {
      const loose = document.createElement("div")
      expect(() => mgr.handleStepDragStart({ target: loose, dataTransfer: fakeDT() })).not.toThrow()
      expect(mgr._draggedItem).toBeNull()
    })
  })

  describe("handleStepDragEnd", () => {
    it("clears the dragged item, lift classes, and container drag state", () => {
      const el = items()[0]
      mgr.handleStepDragStart({ target: el, dataTransfer: fakeDT() })
      mgr.handleStepDragEnd({ target: el })

      expect(mgr._draggedItem).toBeNull()
      expect(el.classList.contains("opacity-70")).toBe(false)
      expect(controller.formTarget.querySelector("[data-steps-container]").classList.contains("step-dragging-active")).toBe(false)
    })
  })

  const stubRect = (el, { top = 0, height = 20 } = {}) => {
    Object.defineProperty(el, "getBoundingClientRect", { value: () => ({ top, height, bottom: top + height, left: 0, right: 0, width: 0, x: 0, y: top }), configurable: true })
  }

  describe("handleStepDragOver", () => {
    const container = () => controller.formTarget.querySelector("[data-steps-container]")

    it("calls preventDefault and sets the move dropEffect", () => {
      const dt = fakeDT()
      const [a, target] = items()
      stubRect(target)
      mgr.handleStepDragOver({ preventDefault: vi.fn(), dataTransfer: dt, currentTarget: container(), target })
      expect(dt.dropEffect).toBe("move")
    })

    it("strips indicator classes from every OTHER item, leaving the dragged item's untouched", () => {
      const [dragged, other, target] = items()
      mgr._draggedItem = dragged
      dragged.classList.add("border-t-2", "bg-indigo-50/50")
      other.classList.add("border-b-2", "scale-[0.98]")
      stubRect(target)
      mgr.handleStepDragOver({ preventDefault() {}, dataTransfer: fakeDT(), currentTarget: container(), target })
      expect(dragged.classList.contains("border-t-2")).toBe(true) // untouched
      expect(other.classList.contains("border-b-2")).toBe(false) // stripped
    })

    it("no-ops (after stripping indicators) when the pointer is not over a step item", () => {
      const loose = document.createElement("div")
      container().appendChild(loose)
      expect(() =>
        mgr.handleStepDragOver({ preventDefault() {}, dataTransfer: fakeDT(), currentTarget: container(), target: loose })
      ).not.toThrow()
    })

    it("no-ops when hovering over the dragged item itself", () => {
      const [dragged] = items()
      mgr._draggedItem = dragged
      mgr.handleStepDragOver({ preventDefault() {}, dataTransfer: fakeDT(), currentTarget: container(), target: dragged })
      expect(dragged.classList.contains("bg-indigo-50/50")).toBe(false)
    })

    it("marks the top half with border-t when clientY is above the midpoint", () => {
      const target = items()[1]
      stubRect(target, { top: 100, height: 20 }) // midpoint = 110
      mgr.handleStepDragOver({ preventDefault() {}, dataTransfer: fakeDT(), currentTarget: container(), target, clientY: 105 })
      expect(target.classList.contains("border-t-2")).toBe(true)
      expect(target.classList.contains("border-b-2")).toBe(false)
      expect(target.classList.contains("bg-indigo-50/50")).toBe(true)
    })

    it("marks the bottom half with border-b when clientY is at/below the midpoint", () => {
      const target = items()[1]
      stubRect(target, { top: 100, height: 20 }) // midpoint = 110
      mgr.handleStepDragOver({ preventDefault() {}, dataTransfer: fakeDT(), currentTarget: container(), target, clientY: 115 })
      expect(target.classList.contains("border-b-2")).toBe(true)
      expect(target.classList.contains("border-t-2")).toBe(false)
    })
  })

  describe("handleStepDrop", () => {
    it("is a no-op with no dragged item", () => {
      const spy = vi.spyOn(mgr, "_dispatchEvent")
      mgr.handleStepDrop({ preventDefault() {}, currentTarget: controller.formTarget.querySelector("[data-steps-container]"), target: items()[0] })
      expect(spy).not.toHaveBeenCalled()
    })

    it("is a no-op when dropping onto the dragged item itself", () => {
      const el = items()[0]
      mgr._draggedItem = el
      const spy = vi.spyOn(mgr, "_dispatchEvent")
      mgr.handleStepDrop({ preventDefault() {}, currentTarget: controller.formTarget.querySelector("[data-steps-container]"), target: el })
      expect(spy).not.toHaveBeenCalled()
    })

    // A successful move calls the real _reindexSteps, whose per-item rename
    // loop throws under happy-dom (see top-of-file NOTE). _reindexSteps itself
    // is unit-tested separately below; here it's stubbed so these tests isolate
    // handleStepDrop's OWN move/cleanup/animation/dispatch logic.
    describe("successful move (with _reindexSteps stubbed)", () => {
      let reindexSpy
      beforeEach(() => {
        reindexSpy = vi.spyOn(mgr, "_reindexSteps").mockImplementation(() => {})
      })

      it("inserts the dragged item BEFORE the target when dropped on its top half", () => {
        const [dragged, , target] = items()
        mgr._draggedItem = dragged
        stubRect(target, { top: 100, height: 20 })
        const spy = vi.spyOn(mgr, "_dispatchEvent")
        mgr.handleStepDrop({
          preventDefault() {}, currentTarget: controller.formTarget.querySelector("[data-steps-container]"),
          target, clientY: 105,
        })
        expect(target.previousElementSibling).toBe(dragged)
        expect(reindexSpy).toHaveBeenCalled()
        expect(spy).toHaveBeenCalledWith("stepReordered")
        expect(dragged.classList.contains("ring-green-400")).toBe(true)
      })

      it("inserts the dragged item AFTER the target when dropped on its bottom half", () => {
        const [dragged, , target] = items()
        mgr._draggedItem = dragged
        stubRect(target, { top: 100, height: 20 })
        mgr.handleStepDrop({
          preventDefault() {}, currentTarget: controller.formTarget.querySelector("[data-steps-container]"),
          target, clientY: 115,
        })
        expect(target.nextElementSibling).toBe(dragged)
      })

      it("clears indicator classes off every item after the move", () => {
        const [dragged, other, target] = items()
        mgr._draggedItem = dragged
        other.classList.add("border-t-2", "bg-indigo-50/50")
        stubRect(target, { top: 100, height: 20 })
        mgr.handleStepDrop({
          preventDefault() {}, currentTarget: controller.formTarget.querySelector("[data-steps-container]"),
          target, clientY: 115,
        })
        expect(other.classList.contains("border-t-2")).toBe(false)
      })
    })
  })

  describe("_setStepExpanded / _collapseAllSteps", () => {
    it("expands and collapses a step item", () => {
      const el = items()[0]
      mgr._setStepExpanded(el, true)
      expect(el.classList.contains("step-expanded")).toBe(true)
      expect(el.querySelector("[data-step-details]").classList.contains("hidden")).toBe(false)
      expect(el.querySelector("[data-step-expand-icon] svg").classList.contains("rotate-90")).toBe(true)

      mgr._setStepExpanded(el, false)
      expect(el.classList.contains("step-expanded")).toBe(false)
      expect(el.querySelector("[data-step-details]").classList.contains("hidden")).toBe(true)
    })

    it("_collapseAllSteps collapses every item", () => {
      const cont = controller.formTarget.querySelector("[data-steps-container]")
      items().forEach((el) => mgr._setStepExpanded(el, true))
      mgr._collapseAllSteps(cont)
      expect(items().every((el) => !el.classList.contains("step-expanded"))).toBe(true)
    })
  })

  describe("_reindexSteps", () => {
    // The per-item rename loop (item.querySelectorAll("[name^='steps[']")) is
    // UNREACHABLE under happy-dom — see top-of-file NOTE. Only the guard and
    // an empty step list can run here without throwing.
    it("no-ops when there is no [data-steps-container]", () => {
      controller.formTarget.innerHTML = `<div>no container</div>`
      expect(() => mgr._reindexSteps()).not.toThrow()
    })

    it("sets stepIndex to 0 for an empty step list without throwing", () => {
      controller.formTarget.innerHTML = `<div data-steps-container></div>`
      mgr.stepIndex = 99
      expect(() => mgr._reindexSteps()).not.toThrow()
      expect(mgr.stepIndex).toBe(0)
    })

    it("reindexes hidden input + textarea names to match each item's DOM position", () => {
      controller.formTarget.innerHTML = `
        <div data-steps-container>
          <div data-step-item>
            <input type="hidden" name="steps[7][action]" value="a">
            <textarea name="steps[7][description]"></textarea>
          </div>
          <div data-step-item>
            <input type="hidden" name="steps[3][action]" value="b">
          </div>
        </div>`
      mgr._reindexSteps()
      const items = controller.formTarget.querySelectorAll("[data-step-item]")
      expect(items[0].dataset.stepIndex).toBe("0")
      expect(items[0].querySelector("input").name).toBe("steps[0][action]")
      expect(items[0].querySelector("textarea").name).toBe("steps[0][description]")
      // second item has no textarea — exercises the `if (textarea)` false side
      expect(items[1].dataset.stepIndex).toBe("1")
      expect(items[1].querySelector("input").name).toBe("steps[1][action]")
      expect(mgr.stepIndex).toBe(2)
    })
  })
})
