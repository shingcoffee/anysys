import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/copy_code_controller"
import { mountController, controllerFor, click } from "../support/stimulus.js"

const html = (code = "puts 1") => `
  <div data-controller="copy-code">
    <pre data-copy-code-target="code">${code}</pre>
    <button data-action="click->copy-code#copy">
      <span data-copy-code-target="copyIcon">c</span>
      <span data-copy-code-target="checkIcon" class="hidden">ok</span>
      <span data-copy-code-target="copyText">Copy</span>
    </button>
  </div>`

const flush = () => new Promise((r) => setTimeout(r, 0))
const text = (el) => el.querySelector("[data-copy-code-target='copyText']").textContent
const checkHidden = (el) => el.querySelector("[data-copy-code-target='checkIcon']").classList.contains("hidden")

describe("copy-code controller", () => {
  let originalClipboard
  beforeEach(() => { originalClipboard = navigator.clipboard })
  afterEach(() => {
    Object.defineProperty(navigator, "clipboard", { value: originalClipboard, configurable: true, writable: true })
    vi.restoreAllMocks()
  })
  const setClipboard = (impl) =>
    Object.defineProperty(navigator, "clipboard", { value: impl, configurable: true, writable: true })

  it("copies the code target text and shows 'Copied!' feedback", async () => {
    const writeText = vi.fn().mockResolvedValue()
    setClipboard({ writeText })
    const { element } = await mountController("copy-code", Controller, html("hello world"))
    click(element.querySelector("button"))
    await flush()
    expect(writeText).toHaveBeenCalledWith("hello world")
    expect(text(element)).toBe("Copied!")
    expect(checkHidden(element)).toBe(false)
    expect(element.classList.contains("copied")).toBe(true)
  })

  it("uses the execCommand fallback when the Clipboard API is unavailable", async () => {
    setClipboard(undefined)
    document.execCommand = vi.fn(() => true)
    const { element } = await mountController("copy-code", Controller, html())
    click(element.querySelector("button"))
    await flush()
    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(text(element)).toBe("Copied!")
  })

  it("falls back to execCommand when the Clipboard API exists but writeText rejects", async () => {
    setClipboard({ writeText: vi.fn().mockRejectedValue(new Error("denied")) })
    document.execCommand = vi.fn(() => true)
    const { element } = await mountController("copy-code", Controller, html())
    click(element.querySelector("button"))
    await flush()
    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(text(element)).toBe("Copied!")
  })

  it("leaves the button unchanged when execCommand reports failure", async () => {
    setClipboard(undefined)
    document.execCommand = vi.fn(() => false)
    const { element } = await mountController("copy-code", Controller, html())
    click(element.querySelector("button"))
    await flush()
    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(text(element)).toBe("Copy")
  })

  it("logs and swallows the error when execCommand throws", async () => {
    setClipboard(undefined)
    const error = new Error("execCommand unsupported")
    document.execCommand = vi.fn(() => { throw error })
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {})
    const { element } = await mountController("copy-code", Controller, html())
    click(element.querySelector("button"))
    await flush()
    expect(consoleError).toHaveBeenCalledWith("Copy failed:", error)
    expect(text(element)).toBe("Copy")
  })

  it("showCopiedFeedback resets after 2000ms", async () => {
    setClipboard({ writeText: vi.fn().mockResolvedValue() })
    const { application, element } = await mountController("copy-code", Controller, html())
    const ctrl = controllerFor(application, element, "copy-code")
    vi.useFakeTimers()
    ctrl.showCopiedFeedback()
    expect(text(element)).toBe("Copied!")
    vi.advanceTimersByTime(2000)
    expect(text(element)).toBe("Copy")
    expect(checkHidden(element)).toBe(true)
    expect(element.classList.contains("copied")).toBe(false)
    vi.useRealTimers()
  })

  it("uses the localized copy/copied labels supplied via values", async () => {
    setClipboard({ writeText: vi.fn().mockResolvedValue() })
    const localized = `
      <div data-controller="copy-code"
           data-copy-code-copy-value="复制"
           data-copy-code-copied-value="已复制!">
        <pre data-copy-code-target="code">puts 1</pre>
        <button data-action="click->copy-code#copy">
          <span data-copy-code-target="copyIcon">c</span>
          <span data-copy-code-target="checkIcon" class="hidden">ok</span>
          <span data-copy-code-target="copyText">复制</span>
        </button>
      </div>`
    const { application, element } = await mountController("copy-code", Controller, localized)
    const ctrl = controllerFor(application, element, "copy-code")
    vi.useFakeTimers()
    ctrl.showCopiedFeedback()
    expect(text(element)).toBe("已复制!")
    vi.advanceTimersByTime(2000)
    expect(text(element)).toBe("复制")
    vi.useRealTimers()
  })
})
