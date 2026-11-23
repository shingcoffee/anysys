import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import Controller from "controllers/artifact_preview_controller"
import { click, controllerFor, mountController } from "../support/stimulus.js"

const html = `
  <section tabindex="-1" data-assistant-workspace-target="panel">
    <div data-controller="artifact-preview">
      <button data-artifact-preview-target="trigger"
              data-action="click->artifact-preview#open">View larger</button>
      <dialog data-artifact-preview-target="dialog"
              data-action="click->artifact-preview#backdrop cancel->artifact-preview#cancel">
        <div data-artifact-preview-target="loading">Loading</div>
        <div class="hidden" data-artifact-preview-target="failure">Failed</div>
        <iframe class="opacity-0"
                data-artifact-preview-target="frame"
                data-artifact-preview-src="about:blank#preview"
                data-action="load->artifact-preview#loaded error->artifact-preview#failed"></iframe>
      </dialog>
    </div>
  </section>
`

describe("artifact preview controller", () => {
  let application
  let element
  let controller
  let trigger
  let dialog
  let frame
  let loading
  let failure
  let panel

  beforeEach(async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }))
    ;({ application, element } = await mountController("artifact-preview", Controller, html))
    controller = controllerFor(application, element, "artifact-preview")
    trigger = element.querySelector("button")
    dialog = element.querySelector("dialog")
    frame = element.querySelector("iframe")
    loading = element.querySelector("[data-artifact-preview-target='loading']")
    failure = element.querySelector("[data-artifact-preview-target='failure']")
    panel = element.closest("[data-assistant-workspace-target='panel']")
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("opens with showModal, remembers the trigger, and verifies the preview before loading it", async () => {
    dialog.showModal = vi.fn(() => dialog.setAttribute("open", ""))

    await click(trigger)
    await click(trigger)

    expect(dialog.showModal).toHaveBeenCalledTimes(2)
    expect(dialog.hasAttribute("open")).toBe(true)
    expect(frame.getAttribute("src")).toBe("about:blank#preview")
    expect(controller.returnFocus).toBe(trigger)
    expect(fetch).toHaveBeenCalledTimes(1)
    expect(fetch).toHaveBeenCalledWith("about:blank#preview", {
      method: "HEAD",
      credentials: "same-origin"
    })
  })

  it("falls back to the open attribute and the declared trigger", async () => {
    dialog.showModal = undefined

    controller.open({ currentTarget: null })
    await vi.waitFor(() => expect(frame.getAttribute("src")).toBe("about:blank#preview"))

    expect(dialog.hasAttribute("open")).toBe(true)
    expect(controller.returnFocus).toBe(trigger)
  })

  it("closes through dialog.close and restores trigger focus", () => {
    dialog.close = vi.fn(() => dialog.removeAttribute("open"))
    const focus = vi.spyOn(trigger, "focus")
    controller.returnFocus = trigger

    controller.close()

    expect(dialog.close).toHaveBeenCalledOnce()
    expect(focus).toHaveBeenCalledOnce()
  })

  it("falls back to removing open and tolerates a missing focus target", () => {
    dialog.setAttribute("open", "")
    dialog.close = undefined
    controller.returnFocus = null
    controller.fallbackFocus = null

    expect(() => controller.close()).not.toThrow()
    expect(dialog.hasAttribute("open")).toBe(false)
  })

  it("closes only when the backdrop event targets the dialog itself", () => {
    const close = vi.spyOn(controller, "close")

    controller.backdrop({ target: dialog.querySelector("div") })
    controller.backdrop({ target: dialog })

    expect(close).toHaveBeenCalledOnce()
  })

  it("prevents native cancel and closes", () => {
    const close = vi.spyOn(controller, "close")
    const event = new globalThis.Event("cancel", { cancelable: true })

    controller.cancel(event)

    expect(event.defaultPrevented).toBe(true)
    expect(close).toHaveBeenCalledOnce()
  })

  it("reveals a successfully loaded frame", () => {
    controller.loaded()

    expect(loading.classList.contains("hidden")).toBe(true)
    expect(failure.classList.contains("hidden")).toBe(true)
    expect(frame.classList.contains("opacity-0")).toBe(false)
  })

  it("shows failure feedback and retries the frame", async () => {
    controller.failed()

    expect(loading.classList.contains("hidden")).toBe(true)
    expect(failure.classList.contains("hidden")).toBe(false)
    expect(frame.classList.contains("opacity-0")).toBe(true)

    await controller.retry()

    expect(loading.classList.contains("hidden")).toBe(false)
    expect(failure.classList.contains("hidden")).toBe(true)
    expect(frame.getAttribute("src")).toBe("about:blank#preview")
  })

  it("shows failure feedback when the preview readiness check is not successful", async () => {
    fetch.mockResolvedValueOnce({ ok: false })

    await controller.loadFrame()

    expect(frame.hasAttribute("src")).toBe(false)
    expect(loading.classList.contains("hidden")).toBe(true)
    expect(failure.classList.contains("hidden")).toBe(false)
  })

  it("shows failure feedback when the preview readiness check rejects", async () => {
    fetch.mockRejectedValueOnce(new Error("network"))

    await controller.loadFrame()

    expect(frame.hasAttribute("src")).toBe(false)
    expect(failure.classList.contains("hidden")).toBe(false)
  })

  it("restores focus to the stable preview panel when Turbo removes an open dialog", () => {
    const focus = vi.spyOn(panel, "focus")
    controller.returnFocus = document.createElement("button")
    dialog.setAttribute("open", "")

    controller.disconnect()

    expect(focus).toHaveBeenCalledOnce()
  })

  it("does not move focus on disconnect when the dialog is closed", () => {
    const focus = vi.spyOn(panel, "focus")

    controller.disconnect()

    expect(focus).not.toHaveBeenCalled()
  })

  it("leaves the thumbnail alone when the pane has no framed viewport", () => {
    expect(controller.resizeObserver).toBeUndefined()
    expect(() => controller.scaleThumbnail()).not.toThrow()
    expect(() => controller.syncScroll()).not.toThrow()
  })

  it("opens safely when no trigger target is present", async () => {
    const withoutTrigger = html.replace(
      /<button[\s\S]*?<\/button>/,
      ""
    )
    const mounted = await mountController("artifact-preview", Controller, withoutTrigger)
    const triggerlessController = controllerFor(
      mounted.application,
      mounted.element,
      "artifact-preview"
    )
    const triggerlessDialog = mounted.element.querySelector("dialog")
    triggerlessDialog.showModal = undefined

    expect(() => triggerlessController.open({ currentTarget: null })).not.toThrow()
    await vi.waitFor(() => expect(
      mounted.element.querySelector("iframe").getAttribute("src")
    ).toBe("about:blank#preview"))
    expect(triggerlessController.returnFocus).toBeNull()
    expect(triggerlessDialog.hasAttribute("open")).toBe(true)
  })
})

const thumbnailHtml = ({ frameWidth = 960, sheet = true, stage = true, thumbnail = true } = {}) => `
  <div data-controller="artifact-preview"
       data-artifact-preview-frame-width-value="${frameWidth}"
       data-artifact-preview-frame-height-value="1400">
    <div data-artifact-preview-target="viewport"
         data-action="scroll->artifact-preview#syncScroll">
      <div ${sheet ? `data-artifact-preview-target="sheet"` : ""}>
        <div ${stage ? `data-artifact-preview-target="stage"` : ""}>
          <div data-artifact-preview-target="canvas">
            ${thumbnail ? `<iframe data-artifact-thumbnail data-artifact-preview-target="thumbnail" data-action="load->artifact-preview#thumbnailLoaded"></iframe>` : ""}
          </div>
        </div>
      </div>
    </div>
  </div>
`

// The thumbnail iframe is a desktop-width window scaled down to the rail and
// exactly as tall as the rail shows. The sheet carries the scaled height of the
// whole framed page so the rail can scroll, and each rail scroll is handed to
// the framed page.
describe("artifact preview thumbnail scaling", () => {
  const sizeViewport = (viewport, width, height = 600) => {
    Object.defineProperty(viewport, "clientWidth", { value: width, configurable: true })
    Object.defineProperty(viewport, "clientHeight", { value: height, configurable: true })
  }

  const framedPage = ({ readyState = "complete", url = "http://test/preview", scrollHeight = 2400, bodyHeight = 0, documentElement = true } = {}) => ({
    readyState,
    URL: url,
    documentElement: documentElement ? { scrollHeight, style: { setProperty: vi.fn() } } : null,
    body: { scrollHeight: bodyHeight }
  })

  const stubFrame = (frame, doc) => {
    Object.defineProperty(frame, "contentDocument", { configurable: true, get: doc })
  }

  const stubWindow = (frame, win) => {
    Object.defineProperty(frame, "contentWindow", { configurable: true, get: () => win })
  }

  const mount = async (options) => {
    const { application, element } = await mountController(
      "artifact-preview",
      Controller,
      thumbnailHtml(options)
    )
    return {
      controller: controllerFor(application, element, "artifact-preview"),
      viewport: element.querySelector("[data-artifact-preview-target='viewport']"),
      stage: element.querySelector("[data-artifact-preview-target='stage']"),
      canvas: element.querySelector("[data-artifact-preview-target='canvas']"),
      sheet: element.querySelector("[data-artifact-preview-target='sheet']"),
      frame: element.querySelector("iframe")
    }
  }

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("fits the window to the rail's visible area when it resizes", async () => {
    let observed = null
    let notify = null
    vi.stubGlobal(
      "ResizeObserver",
      class {
        constructor(callback) {
          notify = callback
        }

        observe(target) {
          observed = target
        }

        disconnect() {
          observed = null
        }
      }
    )

    const { controller, viewport, stage, canvas, sheet } = await mount()
    expect(observed).toBe(viewport)
    expect(canvas.style.transform).toBe("")

    sizeViewport(viewport, 480, 600)
    notify()

    expect(canvas.style.width).toBe("960px")
    expect(canvas.style.height).toBe("1200px")
    expect(canvas.style.transform).toBe("scale(0.5)")
    expect(stage.style.height).toBe("600px")
    // Until the page reports its height, the sheet assumes the declared one.
    expect(sheet.style.height).toBe("700px")

    controller.disconnect()
    expect(observed).toBeNull()
    expect(controller.resizeObserver).toBeNull()
  })

  it("sizes the sheet to the whole framed page and hides its scrollbar once it loads", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { viewport, canvas, sheet, frame } = await mount()
    sizeViewport(viewport, 480, 600)
    const doc = framedPage({ scrollHeight: 2400 })
    stubFrame(frame, () => doc)
    frame.dispatchEvent(new Event("load"))

    expect(canvas.style.height).toBe("1200px")
    expect(sheet.style.height).toBe("1200px")
    expect(doc.documentElement.style.setProperty).toHaveBeenCalledWith("scrollbar-width", "none")
  })

  it("keeps the sheet at least as tall as the stage for a short page", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { controller, viewport, sheet, frame } = await mount()
    sizeViewport(viewport, 480, 600)
    stubFrame(frame, () => framedPage({ scrollHeight: 800 }))
    controller.thumbnailLoaded()

    expect(sheet.style.height).toBe("600px")
  })

  it("falls back to the body height when the document element reports none", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { controller, viewport, sheet, frame } = await mount()
    sizeViewport(viewport, 480, 600)
    stubFrame(frame, () => framedPage({ scrollHeight: 0, bodyHeight: 1800 }))
    controller.thumbnailLoaded()

    expect(sheet.style.height).toBe("900px")
  })

  it("keeps the assumed height when the framed page cannot be measured", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { controller, viewport, sheet, frame } = await mount()
    sizeViewport(viewport, 480, 600)

    const unmeasurable = [
      () => null,
      () => framedPage({ documentElement: false }),
      () => framedPage({ readyState: "loading" }),
      () => framedPage({ url: "about:blank" }),
      () => framedPage({ scrollHeight: 0 }),
      () => {
        throw new Error("cross-origin")
      }
    ]

    unmeasurable.forEach((doc) => {
      stubFrame(frame, doc)
      expect(() => controller.thumbnailLoaded()).not.toThrow()
      expect(sheet.style.height).toBe("700px")
    })
  })

  it("scrolls the framed page by the rail's scroll at full size", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { controller, viewport, frame } = await mount()
    const win = { scrollTo: vi.fn() }
    stubWindow(frame, win)
    sizeViewport(viewport, 480, 600)
    controller.scaleThumbnail()
    expect(win.scrollTo).toHaveBeenLastCalledWith({ top: 0, behavior: "instant" })

    viewport.scrollTop = 300
    viewport.dispatchEvent(new Event("scroll"))

    expect(win.scrollTo).toHaveBeenLastCalledWith({ top: 600, behavior: "instant" })
  })

  it("skips the scroll hand-off before scaling and when the framed page is unreachable", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { controller, viewport, frame } = await mount()
    const win = { scrollTo: vi.fn() }
    stubWindow(frame, win)
    controller.syncScroll()
    expect(win.scrollTo).not.toHaveBeenCalled()

    sizeViewport(viewport, 480, 600)
    stubWindow(frame, null)
    expect(() => controller.scaleThumbnail()).not.toThrow()

    stubWindow(frame, {
      scrollTo: () => {
        throw new Error("cross-origin")
      }
    })
    expect(() => controller.syncScroll()).not.toThrow()
  })

  it("assumes the declared page height for the window when the rail has no height yet", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { controller, viewport, stage, canvas } = await mount()
    sizeViewport(viewport, 480, 0)
    controller.scaleThumbnail()

    expect(stage.style.height).toBe("700px")
    expect(canvas.style.height).toBe("1400px")
  })

  it("scales against the declared frame width", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { controller, viewport, canvas } = await mount({ frameWidth: 600 })
    sizeViewport(viewport, 300)
    controller.scaleThumbnail()

    expect(canvas.style.width).toBe("600px")
    expect(canvas.style.transform).toBe("scale(0.5)")
  })

  it("waits for a measurable width and tolerates a missing sheet, stage, or frame", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { controller, viewport, canvas } = await mount({ sheet: false, stage: false, thumbnail: false })
    sizeViewport(viewport, 0)
    controller.scaleThumbnail()
    expect(canvas.style.transform).toBe("")

    expect(() => controller.thumbnailLoaded()).not.toThrow()

    sizeViewport(viewport, 480)
    controller.scaleThumbnail()
    expect(canvas.style.transform).toBe("scale(0.5)")
    expect(() => controller.syncScroll()).not.toThrow()
  })

  it("falls back to window resize when ResizeObserver is unavailable", async () => {
    vi.stubGlobal("ResizeObserver", undefined)

    const { controller, viewport, canvas } = await mount()
    expect(controller.resizeObserver).toBeUndefined()

    sizeViewport(viewport, 320)
    window.dispatchEvent(new Event("resize"))
    expect(canvas.style.transform).toBe("scale(0.3333333333333333)")

    controller.disconnect()
    sizeViewport(viewport, 960)
    window.dispatchEvent(new Event("resize"))
    expect(canvas.style.transform).toBe("scale(0.3333333333333333)")
  })
})
