import { describe, it, expect, vi } from "vitest"
import { PropertyManager } from "controllers/page_builder/property_manager"
import { makeCtrl } from "../../../support/page_builder.js"

function themeCtrl(theme = {}) {
  const ctrl = makeCtrl({ configuration: { theme, rules: [], calculations: [], pages: [] } })
  ctrl.element = document.createElement("div")
  return ctrl
}
const newPM = (theme) => {
  const ctrl = themeCtrl(theme)
  return { pm: new PropertyManager(ctrl), ctrl }
}

describe("ThemeMixin.updateTheme", () => {
  it("writes the property, toggles selector active rings, and re-renders", () => {
    const { pm, ctrl } = newPM()
    const group = document.createElement("div")
    group.setAttribute("data-theme-group", "primary_color")
    const other = document.createElement("div"); other.dataset.themeValue = "blue"; other.classList.add("ring-2", "ring-indigo-500")
    const chosen = document.createElement("div")
    chosen.dataset.themeValue = "rose"
    chosen.dataset.themeProperty = "primary_color"
    group.append(other, chosen)
    ctrl.element.appendChild(group)

    pm.updateTheme({ currentTarget: chosen })
    expect(ctrl.configuration.theme.primary_color).toBe("rose")
    expect(chosen.classList.contains("ring-indigo-500")).toBe(true)
    expect(other.classList.contains("ring-indigo-500")).toBe(false)
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("ignores an event missing property or value", () => {
    const { pm, ctrl } = newPM()
    pm.updateTheme({ currentTarget: { dataset: { themeProperty: "primary_color" } } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("initializes configuration.theme when it starts undefined", () => {
    const { pm, ctrl } = newPM()
    ctrl.configuration.theme = undefined
    const el = document.createElement("div")
    el.dataset.themeProperty = "primary_color"
    el.dataset.themeValue = "rose"
    pm.updateTheme({ currentTarget: el })
    expect(ctrl.configuration.theme.primary_color).toBe("rose")
  })
})

describe("ThemeMixin.applyThemePreset", () => {
  it("replaces the whole theme with the named preset and marks the preset button active", () => {
    const { pm, ctrl } = newPM({ primary_color: "indigo" })
    const presetBtn = document.createElement("button")
    presetBtn.dataset.preset = "bold"
    ctrl.element.appendChild(presetBtn)

    pm.applyThemePreset({ currentTarget: presetBtn })
    expect(ctrl.configuration.theme.primary_color).toBe("rose")
    expect(ctrl.configuration.theme.button_style).toBe("filled")
    expect(presetBtn.classList.contains("ring-indigo-500")).toBe(true)
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalled()
  })

  it("ignores an unknown preset name", () => {
    const { pm, ctrl } = newPM({ primary_color: "indigo" })
    pm.applyThemePreset({ currentTarget: { dataset: { preset: "nope" } } })
    expect(ctrl.configuration.theme.primary_color).toBe("indigo")
  })

  it("ignores an event with no preset name at all", () => {
    const { pm, ctrl } = newPM({ primary_color: "indigo" })
    pm.applyThemePreset({ currentTarget: { dataset: {} } })
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("highlights the matching value within each theme-group selector", () => {
    const { pm, ctrl } = newPM({ primary_color: "indigo" })
    const presetBtn = document.createElement("button")
    presetBtn.dataset.preset = "elegant"
    ctrl.element.appendChild(presetBtn)

    const group = document.createElement("div")
    group.setAttribute("data-theme-group", "primary_color")
    const match = document.createElement("div"); match.dataset.themeValue = "violet"
    const other = document.createElement("div"); other.dataset.themeValue = "rose"; other.classList.add("ring-2", "ring-indigo-500")
    group.append(match, other)
    ctrl.element.appendChild(group)

    pm.applyThemePreset({ currentTarget: presetBtn })
    expect(match.classList.contains("ring-2")).toBe(true)
    expect(other.classList.contains("ring-2")).toBe(false)
  })
})

describe("ThemeMixin.applyThemeToCanvas", () => {
  function canvasDom(ctrl) {
    const frame = document.createElement("div")
    frame.className = "canvas-frame"
    const header = document.createElement("div"); header.className = "bg-gradient-to-r"
    const submit = document.createElement("button"); submit.type = "submit"
    const container = document.createElement("div"); container.setAttribute("data-form-container", "")
    const form = document.createElement("form")
    frame.append(header, submit, container, form)
    ctrl.element.appendChild(frame)
    ctrl.hasCanvasFrameTarget = true
    ctrl.canvasFrameTarget = frame
    return { header, submit, container, form }
  }

  it("applies gradient header, gradient submit button, font, width/padding for a theme", () => {
    const { pm, ctrl } = newPM({
      primary_color: "emerald", button_style: "gradient", button_width: "full",
      button_size: "lg", font_family: "serif", form_shadow: "lg", form_padding: "spacious",
      form_border: "visible", form_width: "lg", field_spacing: "relaxed",
    })
    const { header, submit, container, form } = canvasDom(ctrl)
    pm.applyThemeToCanvas()

    expect(header.classList.contains("from-emerald-500")).toBe(true)
    expect(submit.classList.contains("bg-gradient-to-r")).toBe(true)
    expect(submit.classList.contains("w-full")).toBe(true)
    expect(submit.classList.contains("text-base")).toBe(true) // lg size
    expect(ctrl.canvasFrameTarget.classList.contains("font-serif")).toBe(true)
    expect(container.classList.contains("shadow-lg")).toBe(true)
    expect(container.classList.contains("p-8")).toBe(true)
    expect(container.classList.contains("max-w-2xl")).toBe(true)
    expect(form.classList.contains("space-y-8")).toBe(true)
  })

  it("applies outline button styling (transparent, bordered, no white text)", () => {
    const { pm, ctrl } = newPM({ primary_color: "rose", button_style: "outline", button_width: "auto", button_size: "sm" })
    const { submit } = canvasDom(ctrl)
    pm.applyThemeToCanvas()
    expect(submit.classList.contains("bg-transparent")).toBe(true)
    expect(submit.classList.contains("border-rose-600")).toBe(true)
    expect(submit.classList.contains("w-auto")).toBe(true)
    expect(submit.classList.contains("px-8")).toBe(true)
    expect(submit.classList.contains("text-white")).toBe(false)
  })

  it("defaults gracefully when the theme is empty", () => {
    const { pm, ctrl } = newPM({})
    const { header, submit, container } = canvasDom(ctrl)
    pm.applyThemeToCanvas()
    expect(header.classList.contains("from-indigo-500")).toBe(true) // default gradient
    expect(submit.classList.contains("bg-indigo-600")).toBe(true)   // default filled
    expect(container.classList.contains("p-6")).toBe(true)          // default padding
    expect(container.classList.contains("max-w-4xl")).toBe(true)    // default width
  })

  it("is a no-op when the canvas frame elements are absent", () => {
    const { pm } = newPM({ primary_color: "rose" })
    expect(() => pm.applyThemeToCanvas()).not.toThrow()
  })

  it("defaults to an empty theme object when configuration.theme is undefined", () => {
    const { pm, ctrl } = newPM()
    ctrl.configuration.theme = undefined
    const { header } = canvasDom(ctrl)
    pm.applyThemeToCanvas()
    expect(header.classList.contains("from-indigo-500")).toBe(true)
  })

  it("applies soft button styling", () => {
    const { pm, ctrl } = newPM({ primary_color: "emerald", button_style: "soft" })
    const { submit } = canvasDom(ctrl)
    pm.applyThemeToCanvas()
    expect(submit.classList.contains("bg-emerald-50")).toBe(true)
    expect(submit.classList.contains("text-white")).toBe(false)
  })

  it("falls back to the default gradient/fill color for an unmapped primary_color", () => {
    const { pm, ctrl } = newPM({ primary_color: "custom", button_style: "gradient" })
    const { submit } = canvasDom(ctrl)
    pm.applyThemeToCanvas()
    expect(submit.classList.contains("from-indigo-500")).toBe(true) // gradient fallback

    ctrl.configuration.theme = { primary_color: "custom", button_style: "filled" }
    pm.applyThemeToCanvas()
    expect(submit.classList.contains("bg-indigo-600")).toBe(true) // colorBg fallback
  })
})
