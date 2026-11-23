import { describe, it, expect, afterEach, vi } from "vitest"
import Controller from "controllers/source_editor_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (value = "") => `
  <form>
    <div data-controller="source-editor">
      <div data-source-editor-target="gutter"></div>
      <textarea data-source-editor-target="input" data-action="input->source-editor#refresh">${value}</textarea>
    </div>
  </form>`

describe("source-editor controller", () => {
  let application, element, ctrl, input, gutter
  const mount = async (value) => {
    ;({ application, element } = await mountController("source-editor", Controller, html(value)))
    ctrl = controllerFor(application, element, "source-editor")
    input = element.querySelector("textarea")
    gutter = element.querySelector("[data-source-editor-target='gutter']")
  }
  const select = (start, end = start) => input.setSelectionRange(start, end)
  const key = (init) => {
    const event = new KeyboardEvent("keydown", { cancelable: true, ...init })
    ctrl.keydown(event)
    return event
  }

  afterEach(() => {
    vi.restoreAllMocks()
    delete document.execCommand
  })

  describe("line numbers", () => {
    it("numbers every line on connect and after input", async () => {
      await mount("a\nb")
      expect(gutter.textContent).toBe("1\n2")

      input.value = "a\nb\nc"
      input.dispatchEvent(new Event("input", { bubbles: true }))
      expect(gutter.textContent).toBe("1\n2\n3")
    })

    it("keeps the gutter scrolled with the textarea", async () => {
      await mount("a")
      Object.defineProperty(input, "scrollTop", { value: 48, configurable: true })
      ctrl.sync()
      expect(gutter.scrollTop).toBe(48)
    })
  })

  describe("save shortcut", () => {
    it("submits the form on Ctrl+S and Cmd+S", async () => {
      await mount("x")
      const submit = vi.spyOn(input.form, "requestSubmit").mockImplementation(() => {})
      for (const modifier of [{ ctrlKey: true }, { metaKey: true }]) {
        const event = new KeyboardEvent("keydown", { key: "S", cancelable: true, ...modifier })
        ctrl.save(event)
        expect(event.defaultPrevented).toBe(true)
      }
      expect(submit).toHaveBeenCalledTimes(2)
    })

    it("ignores other keys and unmodified S", async () => {
      await mount("x")
      const submit = vi.spyOn(input.form, "requestSubmit").mockImplementation(() => {})
      ctrl.save(new KeyboardEvent("keydown", { key: "s" }))
      ctrl.save(new KeyboardEvent("keydown", { key: "p", ctrlKey: true }))
      expect(submit).not.toHaveBeenCalled()
    })

    it("does nothing outside a form", async () => {
      ;({ application, element } = await mountController("source-editor", Controller, html("x").replace(/<\/?form>/g, "")))
      ctrl = controllerFor(application, element, "source-editor")
      const event = new KeyboardEvent("keydown", { key: "s", ctrlKey: true, cancelable: true })
      expect(() => ctrl.save(event)).not.toThrow()
      expect(event.defaultPrevented).toBe(true)
    })
  })

  describe("Tab", () => {
    it("inserts two spaces at the cursor", async () => {
      await mount("def x")
      select(0)
      expect(key({ key: "Tab" }).defaultPrevented).toBe(true)
      expect(input.value).toBe("  def x")
      expect(input.selectionStart).toBe(2)
    })

    it("indents every selected line and keeps them selected", async () => {
      await mount("a\nb\nc")
      select(0, 3)
      key({ key: "Tab" })
      expect(input.value).toBe("  a\n  b\nc")
      expect([input.selectionStart, input.selectionEnd]).toEqual([2, 7])
    })

    it("does not indent the next line when the selection ends at its start", async () => {
      await mount("a\nb")
      select(0, 2)
      key({ key: "Tab" })
      expect(input.value).toBe("  a\nb")
    })

    it("outdents with Shift+Tab, removing at most two spaces per line", async () => {
      await mount("    a\n b\nc")
      select(4, 9)
      key({ key: "Tab", shiftKey: true })
      expect(input.value).toBe("  a\nb\nc")
      expect([input.selectionStart, input.selectionEnd]).toEqual([2, 6])
    })

    it("outdents the current line from a cursor inside its indentation", async () => {
      await mount("  a")
      select(1)
      key({ key: "Tab", shiftKey: true })
      expect(input.value).toBe("a")
      expect(input.selectionStart).toBe(0)
    })

    it("leaves Tab with a modifier to the browser", async () => {
      await mount("a")
      for (const modifier of [{ ctrlKey: true }, { metaKey: true }, { altKey: true }]) {
        expect(key({ key: "Tab", ...modifier }).defaultPrevented).toBe(false)
      }
      expect(input.value).toBe("a")
    })
  })

  describe("Enter", () => {
    it("keeps the current indentation", async () => {
      await mount("    value = 1")
      select(13)
      expect(key({ key: "Enter" }).defaultPrevented).toBe(true)
      expect(input.value).toBe("    value = 1\n    ")
      expect(input.selectionStart).toBe(18)
    })

    it("indents one level after a line that opens a block", async () => {
      for (const line of ["def generate_body", "items.each do |item|", "body(", "  if ready"]) {
        await mount(line)
        select(line.length)
        key({ key: "Enter" })
        const indent = line.match(/^ */)[0]
        expect(input.value).toBe(`${line}\n${indent}  `)
      }
    })

    it("replaces a selection", async () => {
      await mount("a b")
      select(1, 2)
      key({ key: "Enter" })
      expect(input.value).toBe("a\nb")
    })

    it("leaves Shift+Enter and IME composition alone", async () => {
      await mount("a")
      expect(key({ key: "Enter", shiftKey: true }).defaultPrevented).toBe(false)
      expect(key({ key: "Enter", isComposing: true }).defaultPrevented).toBe(false)
      expect(key({ key: "x" }).defaultPrevented).toBe(false)
    })
  })

  describe("undo-friendly insertion", () => {
    it("uses insertText when the browser supports it", async () => {
      await mount("a")
      document.execCommand = vi.fn(() => {
        input.setRangeText("  ", input.selectionStart, input.selectionEnd, "end")
        return true
      })
      select(0)
      key({ key: "Tab" })
      expect(document.execCommand).toHaveBeenCalledWith("insertText", false, "  ")
      expect(input.value).toBe("  a")
    })

    it("falls back to setRangeText when insertText is refused", async () => {
      await mount("a")
      document.execCommand = vi.fn(() => false)
      select(1)
      key({ key: "Tab" })
      expect(input.value).toBe("a  ")
      expect(gutter.textContent).toBe("1")
    })
  })
})
