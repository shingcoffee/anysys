import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { CommandPaletteManager } from "controllers/page_builder/command_palette_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

const withPalette = (ctrl) => {
  ctrl.hasCommandPaletteTarget = true
  ctrl.commandPaletteTarget = document.createElement("div")
  ctrl.commandPaletteTarget.classList.add("hidden")
  ctrl.hasCommandPaletteResultsTarget = true
  ctrl.commandPaletteResultsTarget = document.createElement("div")
  ctrl.hasCommandPaletteInputTarget = false
  return ctrl
}

describe("CommandPaletteManager._displayLabel / _categoryLabel", () => {
  const cm = new CommandPaletteManager(makeCtrl())

  it("falls back to the raw label when an action/field/layout type has no i18n entry", () => {
    expect(cm._displayLabel({ type: "action", action: "unmapped_action", label: "Raw Action" })).toBe("Raw Action")
    expect(cm._displayLabel({ type: "unmapped_field_type", label: "Raw Field" })).toBe("Raw Field")
  })

  it("falls back to the raw category when it has no i18n entry", () => {
    expect(cm._categoryLabel("Unmapped Category")).toBe("Unmapped Category")
  })
})

describe("CommandPaletteManager._fuzzyMatch", () => {
  const cm = new CommandPaletteManager(makeCtrl())
  it("matches empty query, substrings, and subsequences", () => {
    expect(cm._fuzzyMatch("text input", "")).toBe(true)
    expect(cm._fuzzyMatch("text input", "text")).toBe(true)
    expect(cm._fuzzyMatch("text input", "txt")).toBe(true) // subsequence
    expect(cm._fuzzyMatch("text input", "tinp")).toBe(true)
  })
  it("rejects a non-subsequence query", () => {
    expect(cm._fuzzyMatch("text", "zzz")).toBe(false)
    expect(cm._fuzzyMatch("abc", "cba")).toBe(false)
  })
})

describe("CommandPaletteManager._renderResults", () => {
  let ctrl, cm
  beforeEach(() => {
    ctrl = withPalette(makeCtrl())
    cm = new CommandPaletteManager(ctrl)
  })

  it("renders all built-in commands grouped by category when the query is empty", () => {
    cm._renderResults("")
    const html = ctrl.commandPaletteResultsTarget.innerHTML
    expect(html).toContain("Fields")
    expect(html).toContain("Layout")
    expect(html).toContain("Actions")
    expect(cm._results.length).toBeGreaterThan(20)
  })

  it("filters commands by fuzzy query", () => {
    cm._renderResults("email")
    expect(cm._results.some((c) => c.label === "Email")).toBe(true)
    expect(cm._results.every((c) => c.type !== "action" || /email/i.test(c.label))).toBe(true)
  })

  it("shows a no-results message when nothing matches", () => {
    cm._renderResults("zzzzzznope")
    expect(ctrl.commandPaletteResultsTarget.innerHTML).toContain("No results found")
    expect(cm._results).toHaveLength(0)
  })

  it("bails out when there is no results target", () => {
    ctrl.hasCommandPaletteResultsTarget = false
    expect(() => cm._renderResults("")).not.toThrow()
  })
})

describe("CommandPaletteManager.open", () => {
  it("bails out when there is no command palette target", () => {
    const ctrl = makeCtrl()
    ctrl.hasCommandPaletteTarget = false
    const cm = new CommandPaletteManager(ctrl)
    expect(() => cm.open()).not.toThrow()
  })

  it("shows the palette, resets state, and renders results (no input target)", () => {
    const ctrl = withPalette(makeCtrl())
    ctrl.customerIdValue = "" // skip the fetch in _loadTemplates
    const cm = new CommandPaletteManager(ctrl)
    cm._selectedIndex = 3
    cm.open()
    expect(ctrl.commandPaletteTarget.classList.contains("hidden")).toBe(false)
    expect(cm._selectedIndex).toBe(0)
    expect(ctrl.commandPaletteResultsTarget.innerHTML).toContain("Fields")
  })

  it("clears and focuses the input target when present", () => {
    vi.useFakeTimers()
    const ctrl = withPalette(makeCtrl())
    ctrl.customerIdValue = ""
    ctrl.hasCommandPaletteInputTarget = true
    ctrl.commandPaletteInputTarget = document.createElement("input")
    ctrl.commandPaletteInputTarget.value = "stale"
    const focusSpy = vi.spyOn(ctrl.commandPaletteInputTarget, "focus")
    const cm = new CommandPaletteManager(ctrl)
    cm.open()
    expect(ctrl.commandPaletteInputTarget.value).toBe("")
    vi.advanceTimersByTime(50)
    expect(focusSpy).toHaveBeenCalled()
    vi.useRealTimers()
  })
})

describe("CommandPaletteManager.executeFromClick", () => {
  it("executes the command at the clicked result index", () => {
    const ctrl = withPalette(makeCtrl())
    const cm = new CommandPaletteManager(ctrl)
    cm._results = [{ type: "action", action: "save" }, { type: "action", action: "undo" }]
    cm.executeFromClick({ currentTarget: { dataset: { resultIndex: "1" } } })
    expect(ctrl.undoRedoManager.undo).toHaveBeenCalled()
  })

  it("does nothing when the index has no matching result", () => {
    const ctrl = withPalette(makeCtrl())
    const cm = new CommandPaletteManager(ctrl)
    cm._results = [{ type: "action", action: "save" }]
    expect(() => cm.executeFromClick({ currentTarget: { dataset: { resultIndex: "5" } } })).not.toThrow()
    expect(ctrl.saveManager.save).not.toHaveBeenCalled()
  })
})

describe("CommandPaletteManager.close", () => {
  it("bails out when there is no command palette target", () => {
    const ctrl = makeCtrl()
    ctrl.hasCommandPaletteTarget = false
    const cm = new CommandPaletteManager(ctrl)
    expect(() => cm.close()).not.toThrow()
  })

  it("hides the palette and resets state", () => {
    const ctrl = withPalette(makeCtrl())
    ctrl.commandPaletteTarget.classList.remove("hidden")
    const cm = new CommandPaletteManager(ctrl)
    cm._results = [{ type: "action" }]
    cm._selectedIndex = 3
    cm.close()
    expect(ctrl.commandPaletteTarget.classList.contains("hidden")).toBe(true)
    expect(cm._results).toEqual([])
    expect(cm._selectedIndex).toBe(0)
  })
})

describe("CommandPaletteManager.filter", () => {
  it("resets selection and re-renders from the input value", () => {
    const ctrl = withPalette(makeCtrl())
    const cm = new CommandPaletteManager(ctrl)
    cm._selectedIndex = 5
    cm.filter({ target: { value: "  select  " } })
    expect(cm._selectedIndex).toBe(0)
    expect(cm._results.some((c) => c.label === "Select")).toBe(true)
  })
})

describe("CommandPaletteManager.handleKeydown", () => {
  let ctrl, cm, prevent
  beforeEach(() => {
    ctrl = withPalette(makeCtrl())
    ctrl.hasCommandPaletteResultsTarget = false // skip _updateSelection DOM churn
    cm = new CommandPaletteManager(ctrl)
    cm._results = [{ type: "action", action: "save" }, { type: "action", action: "undo" }, { type: "action", action: "redo" }]
    prevent = vi.fn()
  })

  it("ArrowDown/ArrowUp move the selection within bounds", () => {
    cm.handleKeydown({ key: "ArrowDown", preventDefault: prevent })
    expect(cm._selectedIndex).toBe(1)
    cm.handleKeydown({ key: "ArrowDown", preventDefault: prevent })
    cm.handleKeydown({ key: "ArrowDown", preventDefault: prevent }) // clamp at last
    expect(cm._selectedIndex).toBe(2)
    cm.handleKeydown({ key: "ArrowUp", preventDefault: prevent })
    expect(cm._selectedIndex).toBe(1)
  })

  it("Enter executes the highlighted command", () => {
    cm._selectedIndex = 0
    cm.handleKeydown({ key: "Enter", preventDefault: prevent })
    expect(ctrl.saveManager.save).toHaveBeenCalled()
  })

  it("Escape closes the palette", () => {
    const closeSpy = vi.spyOn(cm, "close")
    cm.handleKeydown({ key: "Escape", preventDefault: prevent })
    expect(closeSpy).toHaveBeenCalled()
  })
})

describe("CommandPaletteManager._executeAction routing", () => {
  let ctrl, cm
  beforeEach(() => {
    ctrl = withPalette(makeCtrl())
    cm = new CommandPaletteManager(ctrl)
  })

  it.each([
    ["duplicate", () => ctrl.clipboardManager.duplicateSelected],
    ["delete", () => ctrl.fieldManager.deleteField],
    ["copy", () => ctrl.clipboardManager.copy],
    ["paste", () => ctrl.clipboardManager.paste],
    ["undo", () => ctrl.undoRedoManager.undo],
    ["redo", () => ctrl.undoRedoManager.redo],
    ["preview", () => ctrl.saveManager.preview],
    ["save", () => ctrl.saveManager.save],
  ])("dispatches %s to the right manager", (action, getSpy) => {
    cm._executeAction(action)
    expect(getSpy()).toHaveBeenCalled()
  })
})

describe("CommandPaletteManager._loadTemplates", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("does nothing without a customer id", () => {
    const ctrl = withPalette(makeCtrl())
    ctrl.customerIdValue = ""
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const cm = new CommandPaletteManager(ctrl)
    cm._loadTemplates()
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it("fetches templates, maps them, and re-renders when the palette is open", async () => {
    const ctrl = withPalette(makeCtrl())
    ctrl.customerIdValue = "123"
    ctrl.commandPaletteTarget.classList.remove("hidden") // palette considered open
    ctrl.hasCommandPaletteInputTarget = true
    ctrl.commandPaletteInputTarget = document.createElement("input")
    ctrl.commandPaletteInputTarget.value = "  widget  "
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => [{ name: "Widget Template" }, {}],
    }))
    const cm = new CommandPaletteManager(ctrl)
    cm._loadTemplates()
    await vi.waitFor(() => expect(cm._templateCommands).toHaveLength(2))
    expect(cm._templateCommands[0]).toMatchObject({ type: "template", label: "Widget Template", category: "Templates" })
    expect(cm._templateCommands[1].label).toBe("Untitled Template")
    expect(ctrl.commandPaletteResultsTarget.innerHTML).toContain("Templates")
  })

  it("defaults to an empty template list when the resolved templates value is nullish", async () => {
    const ctrl = withPalette(makeCtrl())
    ctrl.customerIdValue = "123"
    ctrl.commandPaletteTarget.classList.remove("hidden")
    ctrl.hasCommandPaletteInputTarget = false // exercise the query-fallback branch too
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => null }))
    const cm = new CommandPaletteManager(ctrl)
    cm._loadTemplates()
    await vi.waitFor(() => expect(cm._templateCommands).toEqual([]))
  })

  it("treats a non-ok response as an empty template list and skips re-rendering when the palette is closed", async () => {
    const ctrl = withPalette(makeCtrl())
    ctrl.customerIdValue = "123"
    ctrl.commandPaletteTarget.classList.add("hidden") // palette closed
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false }))
    const cm = new CommandPaletteManager(ctrl)
    const renderSpy = vi.spyOn(cm, "_renderResults")
    cm._loadTemplates()
    await vi.waitFor(() => expect(cm._templateCommands).toEqual([]))
    expect(renderSpy).not.toHaveBeenCalled()
  })

  it("swallows fetch errors and resets templates to an empty list", async () => {
    const ctrl = withPalette(makeCtrl())
    ctrl.customerIdValue = "123"
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")))
    const cm = new CommandPaletteManager(ctrl)
    cm._templateCommands = [{ label: "stale" }]
    cm._loadTemplates()
    await vi.waitFor(() => expect(cm._templateCommands).toEqual([]))
  })
})

describe("CommandPaletteManager._updateSelection", () => {
  it("bails out without a results target", () => {
    const ctrl = withPalette(makeCtrl())
    ctrl.hasCommandPaletteResultsTarget = false
    const cm = new CommandPaletteManager(ctrl)
    expect(() => cm._updateSelection()).not.toThrow()
  })

  it("highlights the button at the selected index and un-highlights the rest", () => {
    const ctrl = withPalette(makeCtrl())
    const cm = new CommandPaletteManager(ctrl)
    ctrl.commandPaletteResultsTarget.innerHTML = `
      <button data-result-index="0" class="text-gray-700 hover:bg-gray-50"></button>
      <button data-result-index="1" class="text-gray-700 hover:bg-gray-50"></button>
    `
    const buttons = ctrl.commandPaletteResultsTarget.querySelectorAll("[data-result-index]")
    buttons.forEach((b) => (b.scrollIntoView = vi.fn()))
    cm._selectedIndex = 1
    cm._updateSelection()
    expect(buttons[1].classList.contains("bg-indigo-50")).toBe(true)
    expect(buttons[1].scrollIntoView).toHaveBeenCalled()
    expect(buttons[0].classList.contains("bg-indigo-50")).toBe(false)
    expect(buttons[0].classList.contains("text-gray-700")).toBe(true)
  })
})

describe("CommandPaletteManager._execute field/layout insertion", () => {
  it("inserts a new field after the selected field", () => {
    const ctrl = withPalette(makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" }), field({ id: "b" })] } }))
    ctrl.selectedFieldId = "a"
    const cm = new CommandPaletteManager(ctrl)
    cm._execute({ type: "text", label: "Text Input" })
    expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(
      expect.objectContaining({ type: "text", propertyType: undefined }),
      1
    )
  })

  it("tags layout commands with propertyType 'layout' and appends at the end when nothing selected", () => {
    const ctrl = withPalette(makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" })] } }))
    ctrl.selectedFieldId = null
    const cm = new CommandPaletteManager(ctrl)
    cm._execute({ type: "section", label: "Section" })
    expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(
      expect.objectContaining({ type: "section", propertyType: "layout" }),
      1
    )
  })

  it("routes an action command through _executeAction", () => {
    const ctrl = withPalette(makeCtrl())
    const cm = new CommandPaletteManager(ctrl)
    cm._execute({ type: "action", action: "undo" })
    expect(ctrl.undoRedoManager.undo).toHaveBeenCalled()
  })

  it("routes a template command through _insertTemplate", () => {
    const ctrl = withPalette(makeCtrl())
    const cm = new CommandPaletteManager(ctrl)
    const insertSpy = vi.spyOn(cm, "_insertTemplate").mockImplementation(() => {})
    const template = { configuration: { type: "text" } }
    cm._execute({ type: "template", template })
    expect(insertSpy).toHaveBeenCalledWith(template)
  })
})

describe("CommandPaletteManager._insertTemplate", () => {
  it("does nothing for a nullish template or one without a configuration", () => {
    const ctrl = withPalette(makeCtrl())
    const cm = new CommandPaletteManager(ctrl)
    cm._insertTemplate(null)
    cm._insertTemplate({ name: "no config" })
    expect(ctrl.fieldManager.addFieldAtIndex).not.toHaveBeenCalled()
  })

  it("builds field data from the template configuration and inserts after the selected field", () => {
    const ctrl = withPalette(makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" }), field({ id: "b" })] } }))
    ctrl.selectedFieldId = "a"
    const cm = new CommandPaletteManager(ctrl)
    const template = {
      name: "My Template",
      configuration: { field_type: "select", label: "Favorite Color", property_type: "string", html_type: "select", options: ["red"] },
    }
    cm._insertTemplate(template)
    expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(
      expect.objectContaining({ type: "select", label: "Favorite Color", propertyType: "string", htmlType: "select" }),
      1,
      expect.objectContaining({ options: ["red"] })
    )
  })

  it("falls back to type/label defaults and appends at the end when nothing is selected", () => {
    const ctrl = withPalette(makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" })] } }))
    ctrl.selectedFieldId = null
    const cm = new CommandPaletteManager(ctrl)
    const template = { name: "Fallback Template", configuration: { type: "email" } }
    cm._insertTemplate(template)
    expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(
      expect.objectContaining({ type: "email", label: "Fallback Template", propertyType: undefined, htmlType: undefined }),
      1,
      expect.anything()
    )
  })

  it("falls back to a generic label and 'text' type when the template gives neither", () => {
    const ctrl = withPalette(makeCtrl({ currentPage: { id: "p1", fields: [] } }))
    const cm = new CommandPaletteManager(ctrl)
    cm._insertTemplate({ configuration: {} })
    expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(
      expect.objectContaining({ type: "text", label: "Template Field" }),
      0,
      expect.anything()
    )
  })
})
