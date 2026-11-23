import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/website_theme_picker_controller"
import { mountController, click, controllerFor, tick } from "../support/stimulus.js"

class FakeObserver {
  constructor(cb) {
    this.cb = cb
    this.observed = []
    this.disconnected = false
  }

  observe(el) {
    this.observed.push(el)
  }

  disconnect() {
    this.disconnected = true
  }
}

const tokens = {
  light: {
    page: "bg-white text-neutral-950",
    muted: "text-neutral-600",
    accents: {
      azure: { kicker: "text-sky-700", button: "bg-sky-600" },
      rose: { kicker: "text-rose-700", button: "bg-rose-600" }
    }
  },
  dark: {
    page: "bg-neutral-950 text-white",
    muted: "text-neutral-300",
    accents: {
      azure: { kicker: "text-sky-300", button: "bg-sky-500" }
    }
  },
  types: {
    sans: { headline: "font-site-heading font-semibold", body: "font-site-body", style: "--font-site-heading: Inter; --font-site-body: Inter;" },
    serif: { headline: "font-site-heading font-normal", body: "font-site-body", style: "--font-site-heading: Newsreader; --font-site-body: Newsreader;" },
    display: { headline: "font-site-heading font-medium", body: "font-site-body", style: "--font-site-heading: Fraunces; --font-site-body: Inter;" }
  },
  densities: {
    spacious: { pad: "p-6" },
    compact: { pad: "p-4" }
  },
  corners: {
    soft: { style: "--radius-lg: 0.5rem;", button: "rounded-lg" },
    round: { style: "--radius-lg: 1rem;", button: "rounded-full" }
  },
  neutrals: {
    neutral: {},
    warm: { style: "--color-neutral-50: #fafaf9;" }
  }
}

const headingFont = {
  sans: "Inter",
  serif: "Newsreader",
  display: "Fraunces"
}
const previewBase = "preview-base"

const radio = (token, value, checked = false) =>
  `<input type="radio" data-website-theme-picker-target="token" data-token="${token}" name="${token}" value="${value}" ${checked ? "checked" : ""}>`

const presetRadio = (value, presetTokens, checked = false) =>
  `<input type="radio" data-website-theme-picker-target="preset" name="preset" value="${value}" ${checked ? "checked" : ""}
    data-tokens="${presetTokens === null ? "" : JSON.stringify(presetTokens).replace(/"/g, "&quot;")}"
    data-action="change->website-theme-picker#applyPreset">
   <span data-website-theme-picker-target="customized" data-preset="${value}" class="hidden">customized</span>`

const fullHtml = (opts = {}) => {
  const tokenJson = JSON.stringify(opts.tokens ?? tokens).replace(/"/g, "&quot;")
  const hashRadios = opts.radios ?? (
    radio("appearance", "light", true) +
    radio("appearance", "dark") +
    radio("accent", "azure", true) +
    radio("accent", "rose") +
    radio("type", "sans", (opts.type ?? "sans") === "sans") +
    radio("type", "serif", opts.type === "serif") +
    radio("type", "display", opts.type === "display") +
    radio("density", "spacious", true) +
    radio("density", "compact") +
    radio("corners", "soft", true) +
    radio("corners", "round") +
    radio("neutral", "neutral", true) +
    radio("neutral", "warm")
  )
  const preview = opts.preview === false ? "" : `
    <div data-website-theme-picker-target="preview" data-base-class="${previewBase}" class="${previewBase}">
      ${opts.stage === false ? "" : `<div data-website-theme-picker-target="stage" data-base-class="stage-base" class="stage-base"></div>`}
      <p data-website-theme-picker-target="kicker" data-base-class="kicker-base"></p>
      <h3 data-website-theme-picker-target="headline" data-base-class="headline-base"></h3>
      <p data-website-theme-picker-target="body" data-base-class="body-base"></p>
      <span data-website-theme-picker-target="button" data-base-class="button-base"></span>
    </div>`
  const nav = opts.nav === false ? "" : `
    <a href="#one" data-website-theme-picker-target="nav" data-action="click->website-theme-picker#highlight">one</a>
    <a href="#two" data-website-theme-picker-target="nav" data-action="click->website-theme-picker#highlight">two</a>`
  const sections = opts.sections === false ? "" : `
    <section id="one" data-website-theme-picker-target="section"></section>
    <section id="two" data-website-theme-picker-target="section"></section>`
  return `<div data-controller="website-theme-picker"
    data-action="change->website-theme-picker#apply"
    data-website-theme-picker-tokens-value="${tokenJson}"
    data-website-theme-picker-nav-active-class="nav-on"
    data-website-theme-picker-nav-inactive-class="nav-off">
    ${opts.presets ?? ""}${hashRadios}${preview}${nav}${sections}
  </div>`
}

describe("website-theme-picker controller", () => {
  let application, element, OriginalObserver

  beforeEach(() => {
    OriginalObserver = global.IntersectionObserver
    global.IntersectionObserver = FakeObserver
    window.history.replaceState(null, "", "/")
  })

  afterEach(() => {
    global.IntersectionObserver = OriginalObserver
    window.history.replaceState(null, "", "/")
  })

  async function mount(html) {
    ;({ application, element } = await mountController("website-theme-picker", Controller, html))
    return controllerFor(application, element, "website-theme-picker")
  }

  it("applies the checked light azure tokens on connect and observes sections", async () => {
    const ctrl = await mount(fullHtml())
    const preview = element.querySelector("[data-website-theme-picker-target='preview']")
    expect(preview.className).toContain("preview-base")
    expect(preview.className).toContain("bg-white")
    expect(preview.className).not.toContain("p-6")
    expect(element.querySelector("[data-website-theme-picker-target='stage']").className).toContain("p-6")
    expect(preview.style.getPropertyValue("--font-site-heading")).toBe("Inter")
    expect(preview.style.getPropertyValue("--radius-lg")).toBe("0.5rem")
    expect(preview.style.getPropertyValue("--color-neutral-50")).toBe("")
    expect(preview.dataset.appearance).toBe("light")
    expect(preview.dataset.accent).toBe("azure")
    expect(preview.dataset.corners).toBe("soft")
    expect(preview.dataset.neutral).toBe("neutral")
    expect(element.querySelector("[data-website-theme-picker-target='kicker']").className).toContain("text-sky-700")
    expect(element.querySelector("[data-website-theme-picker-target='button']").className).toBe("button-base rounded-lg bg-sky-600")
    expect(element.querySelector("[data-website-theme-picker-target='headline']").className).toContain("font-site-heading")
    expect(ctrl.observer.observed).toHaveLength(2)
    expect(element.querySelector("a[href='#one']").getAttribute("aria-current")).toBe("location")
  })

  it("updates the preview when a token radio changes", async () => {
    await mount(fullHtml())
    const dark = element.querySelector("input[data-token='appearance'][value='dark']")
    const rose = element.querySelector("input[data-token='accent'][value='rose']")
    const serif = element.querySelector("input[data-token='type'][value='serif']")
    const compact = element.querySelector("input[data-token='density'][value='compact']")
    dark.checked = true
    element.querySelector("input[data-token='appearance'][value='light']").checked = false
    rose.checked = true
    element.querySelector("input[data-token='accent'][value='azure']").checked = false
    serif.checked = true
    element.querySelector("input[data-token='type'][value='sans']").checked = false
    compact.checked = true
    element.querySelector("input[data-token='density'][value='spacious']").checked = false
    element.querySelector("input[data-token='corners'][value='round']").checked = true
    element.querySelector("input[data-token='neutral'][value='warm']").checked = true
    element.dispatchEvent(new Event("change", { bubbles: true }))
    const ctrl = controllerFor(application, element, "website-theme-picker")
    ctrl.apply()
    const preview = element.querySelector("[data-website-theme-picker-target='preview']")
    expect(preview.className).toContain("bg-neutral-950")
    expect(preview.className).not.toContain("p-4")
    expect(element.querySelector("[data-website-theme-picker-target='stage']").className).toContain("p-4")
    expect(preview.style.getPropertyValue("--font-site-heading")).toBe("Newsreader")
    expect(preview.style.getPropertyValue("--radius-lg")).toBe("1rem")
    expect(preview.style.getPropertyValue("--color-neutral-50")).toBe("#fafaf9")
    expect(preview.dataset.appearance).toBe("dark")
    expect(preview.dataset.accent).toBe("rose")
    expect(preview.dataset.type).toBe("serif")
    expect(preview.dataset.density).toBe("compact")
    expect(preview.dataset.corners).toBe("round")
    expect(preview.dataset.neutral).toBe("warm")
    expect(element.querySelector("[data-website-theme-picker-target='button']").className).toBe("button-base rounded-full")
    expect(element.querySelector("[data-website-theme-picker-target='headline']").className).toContain("font-normal")
  })

  it("applies density pad to the preview when the stage target is missing", async () => {
    await mount(fullHtml({ stage: false }))
    const preview = element.querySelector("[data-website-theme-picker-target='preview']")
    expect(preview.className).toContain("p-6")
    expect(element.querySelector("[data-website-theme-picker-target='stage']")).toBeNull()
  })

  it("returns early when the selected appearance is missing from the token map", async () => {
    const ctrl = await mount(fullHtml({ tokens: {} }))
    const preview = element.querySelector("[data-website-theme-picker-target='preview']")
    expect(preview.dataset.appearance).toBeUndefined()
    ctrl.apply()
    expect(preview.className).toBe(previewBase)
  })

  it("falls back when accent/type/density packs are absent", async () => {
    await mount(fullHtml({
      tokens: { light: { page: "bg-white", muted: "text-neutral-600" } }
    }))
    const preview = element.querySelector("[data-website-theme-picker-target='preview']")
    expect(preview.className).toContain("bg-white")
    expect(preview.style.cssText).toBe("")
    expect(element.querySelector("[data-website-theme-picker-target='kicker']").className).toBe("kicker-base")
    expect(element.querySelector("[data-website-theme-picker-target='button']").className).toBe("button-base")
  })

  it.each(["sans", "serif", "display"])("initializes %s typography through scoped font variables", async (type) => {
    await mount(fullHtml({ type }))
    const preview = element.querySelector("[data-website-theme-picker-target='preview']")
    expect(preview.style.getPropertyValue("--font-site-heading")).toBe(headingFont[type])
    expect(preview.classList.contains(tokens.types[type].body)).toBe(true)
    expect(element.querySelector("[data-website-theme-picker-target='headline']").className).toBe(`headline-base ${tokens.types[type].headline}`)
    expect(element.querySelector("[data-website-theme-picker-target='body']").classList.contains(tokens.types[type].body)).toBe(true)
  })

  it("replaces fonts on native radio changes without touching another preview or surrounding app typography", async () => {
    await mount(`<p id="app-label" class="font-sans">Settings</p><form>${fullHtml()}</form><form>${fullHtml({ type: "display" })}</form>`)
    const other = document.querySelectorAll("[data-controller='website-theme-picker']")[1]
    const otherBefore = other.outerHTML
    const labelBefore = document.querySelector("#app-label").outerHTML
    const preview = element.querySelector("[data-website-theme-picker-target='preview']")

    for (const type of ["serif", "display", "sans"]) {
      const radio = element.querySelector(`input[data-token='type'][value='${type}']`)
      radio.checked = true
      radio.dispatchEvent(new Event("change", { bubbles: true }))
      await tick()

      expect(preview.dataset.type).toBe(type)
      expect(preview.className).toBe(`${previewBase} ${tokens.light.page} ${tokens.types[type].body}`)
      expect(preview.style.getPropertyValue("--font-site-heading")).toBe(headingFont[type])
      expect(element.querySelector("[data-website-theme-picker-target='headline']").className).toBe(`headline-base ${tokens.types[type].headline}`)
      expect(element.querySelector("[data-website-theme-picker-target='body']").className).toBe(`body-base ${tokens.light.muted} ${tokens.types[type].body}`)
      expect(other.outerHTML).toBe(otherBefore)
      expect(document.querySelector("#app-label").outerHTML).toBe(labelBefore)
      expect(document.body.hasAttribute("style")).toBe(false)
      expect(document.documentElement.hasAttribute("style")).toBe(false)
    }
  })

  it("applies without preview targets and with no token radios", async () => {
    const ctrl = await mount(fullHtml({ preview: false, radios: "", sections: false }))
    expect(ctrl.selectedValue("appearance")).toBe("")
    expect(ctrl.observer).toBeUndefined()
    ctrl.apply()
  })

  it("selectedValue is empty when no radio for that token is checked", async () => {
    const ctrl = await mount(fullHtml({
      radios: radio("appearance", "light") + radio("appearance", "dark")
    }))
    expect(ctrl.selectedValue("appearance")).toBe("")
    expect(ctrl.selectedValue("accent")).toBe("")
  })

  it("skips IntersectionObserver when the constructor is missing", async () => {
    global.IntersectionObserver = undefined
    const ctrl = await mount(fullHtml())
    expect(ctrl.observer).toBeUndefined()
  })

  it("disconnects the observer when present and no-ops when missing", async () => {
    const ctrl = await mount(fullHtml())
    expect(ctrl.observer.disconnected).toBe(false)
    ctrl.disconnect()
    expect(ctrl.observer).toBeNull()
    ctrl.disconnect()
  })

  it("highlights the clicked nav link and ignores a missing href", async () => {
    const ctrl = await mount(fullHtml())
    const two = element.querySelector("a[href='#two']")
    await click(two)
    expect(two.getAttribute("aria-current")).toBe("location")
    expect(two.classList.contains("nav-on")).toBe(true)
    expect(element.querySelector("a[href='#one']").hasAttribute("aria-current")).toBe(false)
    expect(element.querySelector("a[href='#one']").classList.contains("nav-off")).toBe(true)
    ctrl.highlight({ currentTarget: document.createElement("a") })
    expect(two.getAttribute("aria-current")).toBe("location")
  })

  it("scrolls an overflowing chip strip so the active link stays in view", async () => {
    const ctrl = await mount(fullHtml())
    const two = element.querySelector("a[href='#two']")
    const strip = two.parentElement
    const scrolls = []
    strip.scrollBy = (options) => scrolls.push(options)

    await click(two)
    expect(scrolls).toEqual([])

    Object.defineProperty(strip, "scrollWidth", { configurable: true, value: 600 })
    Object.defineProperty(strip, "clientWidth", { configurable: true, value: 300 })
    Object.defineProperty(two, "offsetWidth", { configurable: true, value: 100 })
    strip.getBoundingClientRect = () => ({ left: 20 })
    two.getBoundingClientRect = () => ({ left: 420 })
    await click(two)
    expect(scrolls).toEqual([{ left: 300, behavior: "smooth" }])

    ctrl.revealNav(document.createElement("a"))
    expect(scrolls).toHaveLength(1)
  })

  it("syncs the active nav from the location hash on connect", async () => {
    window.history.replaceState(null, "", "/#two")
    await mount(fullHtml())
    expect(element.querySelector("a[href='#two']").getAttribute("aria-current")).toBe("location")
  })

  it("setActiveNav no-ops without nav targets or href", async () => {
    const ctrl = await mount(fullHtml({ nav: false }))
    ctrl.setActiveNav("#one")
    ctrl.setActiveNav("")
  })

  it("onIntersect highlights the last visible section and ignores empty or id-less entries", async () => {
    const ctrl = await mount(fullHtml())
    ctrl.onIntersect([])
    ctrl.onIntersect([{ isIntersecting: false, target: { id: "one" } }])
    ctrl.onIntersect([{ isIntersecting: true, target: { id: "" } }])
    ctrl.onIntersect([{ isIntersecting: true, target: { id: "", getAttribute: () => null } }])
    expect(element.querySelector("a[href='#one']").getAttribute("aria-current")).toBe("location")
    ctrl.onIntersect([
      { isIntersecting: true, target: { id: "one" } },
      { isIntersecting: true, target: { id: "two" } }
    ])
    expect(element.querySelector("a[href='#two']").getAttribute("aria-current")).toBe("location")
  })

  it("onIntersect prefers aria-labelledby over the section id", async () => {
    const ctrl = await mount(fullHtml())
    ctrl.onIntersect([{
      isIntersecting: true,
      target: { id: "ignored", getAttribute: (name) => name === "aria-labelledby" ? "two" : null }
    }])
    expect(element.querySelector("a[href='#two']").getAttribute("aria-current")).toBe("location")
  })

  it("applyClass uses an empty base when data-base-class is missing", async () => {
    const ctrl = await mount(fullHtml({ preview: false }))
    const el = document.createElement("div")
    ctrl.applyClass(el, "extra")
    expect(el.className).toBe("extra")
    ctrl.applyClass(el, "")
    expect(el.className).toBe("")
  })

  it("applyPreset checks the preset's token radios and hides the customized badge until a token drifts", async () => {
    const presets =
      presetRadio("lumen", { appearance: "dark", accent: "azure", type: "serif" }) +
      presetRadio("meridian", { appearance: "light", accent: "azure", type: "sans" }, true)
    await mount(fullHtml({ presets }))
    const badge = (key) => element.querySelector(`[data-website-theme-picker-target='customized'][data-preset='${key}']`)
    expect(badge("meridian").classList.contains("hidden")).toBe(true)

    const lumen = element.querySelector("input[data-website-theme-picker-target='preset'][value='lumen']")
    lumen.checked = true
    lumen.dispatchEvent(new Event("change", { bubbles: true }))
    await tick()
    const preview = element.querySelector("[data-website-theme-picker-target='preview']")
    expect(preview.dataset.appearance).toBe("dark")
    expect(preview.dataset.type).toBe("serif")
    expect(preview.dataset.density).toBe("spacious")
    expect(element.querySelector("input[data-token='appearance'][value='light']").checked).toBe(false)
    expect(badge("lumen").classList.contains("hidden")).toBe(true)

    const display = element.querySelector("input[data-token='type'][value='display']")
    display.checked = true
    display.dispatchEvent(new Event("change", { bubbles: true }))
    await tick()
    expect(badge("lumen").classList.contains("hidden")).toBe(false)
    expect(badge("meridian").classList.contains("hidden")).toBe(true)
  })

  it("keeps every customized badge hidden when no preset is checked or no preset radios exist", async () => {
    const ctrl = await mount(fullHtml({ presets: presetRadio("lumen", { appearance: "dark" }) }))
    const lumenBadge = element.querySelector("[data-website-theme-picker-target='customized']")
    ctrl.syncCustomized()
    expect(lumenBadge.classList.contains("hidden")).toBe(true)

    await mount(fullHtml({ presets: `<span data-website-theme-picker-target="customized" data-preset="x"></span>` }))
    expect(element.querySelector("[data-website-theme-picker-target='customized']").classList.contains("hidden")).toBe(true)
  })

  it("presetTokens tolerates missing, invalid and non-object token JSON", async () => {
    const ctrl = await mount(fullHtml())
    const el = document.createElement("input")
    expect(ctrl.presetTokens(el)).toEqual({})
    el.dataset.tokens = "{not json"
    expect(ctrl.presetTokens(el)).toEqual({})
    el.dataset.tokens = "null"
    expect(ctrl.presetTokens(el)).toEqual({})
    el.dataset.tokens = "5"
    expect(ctrl.presetTokens(el)).toEqual({})
    el.dataset.tokens = '{"accent":"rose"}'
    expect(ctrl.presetTokens(el)).toEqual({ accent: "rose" })
  })

  it("observer callback forwards entries to onIntersect", async () => {
    const ctrl = await mount(fullHtml())
    const spy = vi.spyOn(ctrl, "onIntersect")
    ctrl.observer.cb([{ isIntersecting: true, target: { id: "one" } }])
    expect(spy).toHaveBeenCalled()
  })
})
