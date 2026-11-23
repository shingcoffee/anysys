import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/click_to_copy_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const html = (text = "{{first_name}}", feedback) => `
  <button id="copy-btn"
          data-controller="click-to-copy"
          data-click-to-copy-text-value="${text}"
          ${feedback ? `data-click-to-copy-copied-feedback-value="${feedback}"` : ""}
          data-action="click->click-to-copy#copy"
          class="bg-gray-50 text-gray-700 border-gray-200">
    first_name
  </button>
`

describe("click-to-copy controller", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    vi.useRealTimers()
  })

  it("copies text using navigator.clipboard and shows feedback", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal("navigator", { clipboard: { writeText } })

    const { element } = await mountController("click-to-copy", Controller, html())
    element.click()
    await Promise.resolve()

    expect(writeText).toHaveBeenCalledWith("{{first_name}}")
    expect(element.textContent.trim()).toBe("Copied!")
    expect(element.classList.contains("bg-green-100")).toBe(true)
  })

  it("restores the original text and classes after 1500ms", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal("navigator", { clipboard: { writeText } })

    const { element } = await mountController("click-to-copy", Controller, html())
    vi.useFakeTimers()
    element.click()
    await Promise.resolve()

    expect(element.textContent.trim()).toBe("Copied!")

    await vi.advanceTimersByTimeAsync(1500)

    expect(element.textContent.trim()).toBe("first_name")
    expect(element.className).toBe("bg-gray-50 text-gray-700 border-gray-200")
  })

  it("uses fallback when navigator.clipboard is unavailable", async () => {
    vi.stubGlobal("navigator", {})
    document.execCommand = vi.fn(() => true)

    const { element } = await mountController("click-to-copy", Controller, html())
    element.click()

    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(element.textContent.trim()).toBe("Copied!")
  })

  it("falls back to execCommand when clipboard writeText rejects", async () => {
    const error = new Error("denied")
    const writeText = vi.fn().mockRejectedValue(error)
    vi.stubGlobal("navigator", { clipboard: { writeText } })
    document.execCommand = vi.fn(() => true)
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {})

    const { element } = await mountController("click-to-copy", Controller, html())
    element.click()
    await tick()

    expect(consoleError).toHaveBeenCalledWith("Failed to copy using clipboard API:", error)
    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(element.textContent.trim()).toBe("Copied!")
  })

  it("does not show feedback when execCommand returns false", async () => {
    vi.stubGlobal("navigator", {})
    document.execCommand = vi.fn(() => false)

    const { element } = await mountController("click-to-copy", Controller, html())
    element.click()

    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(element.textContent.trim()).toBe("first_name")
    expect(element.classList.contains("bg-green-100")).toBe(false)
  })

  it("logs an error when execCommand throws", async () => {
    vi.stubGlobal("navigator", {})
    const error = new Error("execCommand unsupported")
    document.execCommand = vi.fn(() => { throw error })
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {})

    const { element } = await mountController("click-to-copy", Controller, html())
    expect(() => element.click()).not.toThrow()

    expect(consoleError).toHaveBeenCalledWith("Fallback copy failed:", error)
    expect(element.textContent.trim()).toBe("first_name")
  })

  it("supports copy() without an event argument", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal("navigator", { clipboard: { writeText } })

    const { application, element } = await mountController("click-to-copy", Controller, html())
    const ctrl = controllerFor(application, element, "click-to-copy")
    ctrl.copy()
    await Promise.resolve()

    expect(writeText).toHaveBeenCalledWith("{{first_name}}")
    expect(element.textContent.trim()).toBe("Copied!")
  })

  it("uses a custom copied-feedback value", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal("navigator", { clipboard: { writeText } })

    const { element } = await mountController("click-to-copy", Controller, html("{{last_name}}", "已复制"))
    element.click()
    await Promise.resolve()

    expect(writeText).toHaveBeenCalledWith("{{last_name}}")
    expect(element.textContent.trim()).toBe("已复制")
  })

  it("restores the original text after a second click within 1.5s", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal("navigator", { clipboard: { writeText } })

    const { element } = await mountController("click-to-copy", Controller, html())
    vi.useFakeTimers()
    element.click()
    await Promise.resolve()
    expect(element.textContent.trim()).toBe("Copied!")

    await vi.advanceTimersByTimeAsync(400)
    element.click()
    await Promise.resolve()
    expect(element.textContent.trim()).toBe("Copied!")

    await vi.advanceTimersByTimeAsync(1500)
    expect(element.textContent.trim()).toBe("first_name")
    expect(element.className).toBe("bg-gray-50 text-gray-700 border-gray-200")
  })
})
