import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/clipboard_controller"
import { mountController, controllerFor, click } from "../support/stimulus.js"

const html = (text = "copy me") => `
  <div data-controller="clipboard">
    <span data-clipboard-target="text">${text}</span>
    <button data-clipboard-target="button" data-action="click->clipboard#copy">
      <span data-clipboard-target="icon">icon</span>
      <span data-clipboard-target="success" class="hidden">done</span>
    </button>
  </div>`

const flush = () => new Promise((r) => setTimeout(r, 0))
const iconHidden = (el) => el.querySelector("[data-clipboard-target='icon']").classList.contains("hidden")
const successHidden = (el) => el.querySelector("[data-clipboard-target='success']").classList.contains("hidden")

describe("clipboard controller", () => {
  let originalClipboard
  beforeEach(() => {
    originalClipboard = navigator.clipboard
  })
  afterEach(() => {
    Object.defineProperty(navigator, "clipboard", { value: originalClipboard, configurable: true, writable: true })
    vi.restoreAllMocks()
  })

  const setClipboard = (impl) => {
    Object.defineProperty(navigator, "clipboard", { value: impl, configurable: true, writable: true })
  }

  it("copies the text-target contents via the async Clipboard API and shows success", async () => {
    const writeText = vi.fn().mockResolvedValue()
    setClipboard({ writeText })
    const { element } = await mountController("clipboard", Controller, html("hello"))
    click(element.querySelector("button"))
    await flush()
    expect(writeText).toHaveBeenCalledWith("hello")
    expect(iconHidden(element)).toBe(true)
    expect(successHidden(element)).toBe(false)
  })

  it("logs an error and does nothing when there is no text to copy", async () => {
    const writeText = vi.fn()
    setClipboard({ writeText })
    const err = vi.spyOn(console, "error").mockImplementation(() => {})
    const { element } = await mountController("clipboard", Controller, html("   "))
    click(element.querySelector("button"))
    await flush()
    expect(writeText).not.toHaveBeenCalled()
    expect(err).toHaveBeenCalledWith("No text to copy")
  })

  it("uses the execCommand fallback when the Clipboard API is unavailable", async () => {
    setClipboard(undefined)
    document.execCommand = vi.fn(() => true)
    const { element } = await mountController("clipboard", Controller, html("fallback"))
    click(element.querySelector("button"))
    await flush()
    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(successHidden(element)).toBe(false)
  })

  it("showSuccess resets the icon/success state after 1500ms", async () => {
    setClipboard({ writeText: vi.fn().mockResolvedValue() })
    const { application, element } = await mountController("clipboard", Controller, html("x"))
    const ctrl = controllerFor(application, element, "clipboard")
    vi.useFakeTimers()
    ctrl.showSuccess()
    expect(iconHidden(element)).toBe(true)
    expect(successHidden(element)).toBe(false)
    vi.advanceTimersByTime(1500)
    expect(iconHidden(element)).toBe(false)
    expect(successHidden(element)).toBe(true)
    vi.useRealTimers()
  })

  it("errors out with no text-target and no dataset value present (ternary false branch)", async () => {
    const writeText = vi.fn()
    setClipboard({ writeText })
    const err = vi.spyOn(console, "error").mockImplementation(() => {})
    const noTextHtml = `
      <div data-controller="clipboard">
        <button data-clipboard-target="button" data-action="click->clipboard#copy">copy</button>
      </div>`
    const { element } = await mountController("clipboard", Controller, noTextHtml)
    click(element.querySelector("button"))
    await flush()
    expect(writeText).not.toHaveBeenCalled()
    expect(err).toHaveBeenCalledWith("No text to copy")
  })

  it("falls back to execCommand when the async Clipboard API rejects", async () => {
    const writeText = vi.fn().mockRejectedValue(new Error("denied"))
    setClipboard({ writeText })
    document.execCommand = vi.fn(() => true)
    const { element } = await mountController("clipboard", Controller, html("hello"))
    click(element.querySelector("button"))
    await flush()
    expect(writeText).toHaveBeenCalledWith("hello")
    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(successHidden(element)).toBe(false)
  })

  it("does not show success when execCommand returns false", async () => {
    setClipboard(undefined)
    document.execCommand = vi.fn(() => false)
    const { element } = await mountController("clipboard", Controller, html("fallback"))
    click(element.querySelector("button"))
    await flush()
    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(successHidden(element)).toBe(true)
  })

  it("silently swallows an execCommand exception", async () => {
    setClipboard(undefined)
    document.execCommand = vi.fn(() => {
      throw new Error("blocked")
    })
    const { element } = await mountController("clipboard", Controller, html("fallback"))
    expect(() => click(element.querySelector("button"))).not.toThrow()
    await flush()
    expect(successHidden(element)).toBe(true)
  })
})
