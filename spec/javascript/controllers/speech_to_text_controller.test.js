import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/speech_to_text_controller"
import { mountController, controllerFor, click, tick } from "../support/stimulus.js"

const flush = () => new Promise((resolve) => setTimeout(resolve, 0))

function widgetHtml(overrides = {}) {
  const attrs = [
    `data-controller="speech-to-text"`,
    `data-action="ai-assistant:conversationChanged@window->speech-to-text#conversationChanged"`,
    `data-speech-to-text-url-value="${overrides.url ?? "/12345678/admin/modules/ai_assistant/transcriptions"}"`,
    `data-speech-to-text-max-duration-value="${overrides.maxDuration ?? 60}"`,
    overrides.destination != null ? `data-speech-to-text-destination-value="${overrides.destination}"` : "",
    overrides.conversationId != null ? `data-speech-to-text-conversation-id-value="${overrides.conversationId}"` : "",
    overrides.csrf != null ? `data-speech-to-text-csrf-value="${overrides.csrf}"` : "",
    overrides.omitField ? "" : `data-speech-to-text-field-id-unused="1"`
  ].filter(Boolean).join(" ")

  const field = overrides.omitField
    ? (overrides.innerInput === false ? "" : `<input id="field_name" value="">`)
    : `<input id="field_name" data-speech-to-text-target="field" value="">`
  const button = overrides.omitButton
    ? ""
    : `<button type="button" data-speech-to-text-target="button" data-action="click->speech-to-text#toggle" aria-label="Dictate" aria-pressed="false" class="btn btn-ghost text-text-muted">
        ${overrides.omitIcons ? "Mic" : `<svg data-speech-to-text-target="micIcon"></svg><svg data-speech-to-text-target="stopIcon" class="hidden"></svg>`}
      </button>`
  const liveDot = (overrides.omitStatus || overrides.omitLiveDot)
    ? ""
    : `<span data-speech-to-text-target="liveDot" class="hidden size-1.5 rounded-full bg-danger"></span>`
  const status = overrides.omitStatus ? "" : `<p data-speech-to-text-target="status" class="text-text-muted"></p>`
  const inbox = overrides.omitInbox ? "" : `<div data-speech-to-text-target="inbox"></div>`

  return `<div ${attrs}>${field}${button}${liveDot}${status}${inbox}</div>`
}

function installRecorder({
  mimeSupported = true,
  hasIsTypeSupported = true,
  throwOnStop = false,
  chunks = "mixed"
} = {}) {
  class FakeMediaRecorder {
    constructor(stream, options = {}) {
      this.stream = stream
      this.options = options
      this.state = "inactive"
      this.listeners = {}
    }

    addEventListener(name, fn) {
      this.listeners[name] = this.listeners[name] || []
      this.listeners[name].push(fn)
    }

    start() {
      this.state = "recording"
    }

    stop() {
      if (throwOnStop) throw new Error("already stopped")
      this.state = "inactive"
      const emit = (data) => (this.listeners.dataavailable || []).forEach((fn) => fn({ data }))
      if (chunks === "mixed") {
        emit(null)
        emit({ size: 0, type: "audio/webm" })
        emit(new Blob(["x"], { type: "audio/webm" }))
      } else if (chunks === "empty") {
        emit(new Blob([]))
      } else if (chunks === "huge") {
        emit({ size: 25 * 1024 * 1024 + 1, type: "audio/webm" })
      } else if (chunks === "untyped") {
        emit(new Blob(["x"]))
      } else {
        emit(new Blob(["x"], { type: "audio/webm" }))
      }
      ;(this.listeners.stop || []).forEach((fn) => fn())
    }
  }

  if (hasIsTypeSupported) {
    FakeMediaRecorder.isTypeSupported = (type) => mimeSupported && type === "audio/webm"
  }

  vi.stubGlobal("MediaRecorder", FakeMediaRecorder)
  return FakeMediaRecorder
}

function installMic({ getUserMedia, tracks } = {}) {
  const stop = vi.fn()
  const stream = { getTracks: () => tracks || [{ stop }] }
  const media = {
    getUserMedia: getUserMedia || vi.fn().mockResolvedValue(stream)
  }
  vi.stubGlobal("navigator", { ...navigator, mediaDevices: media })
  return { stream, stop, media }
}

// `isSecureContext` is a read-only accessor on the real window, so it is
// redefined for the duration of the block and put back afterwards.
async function withSecureContext(value, run) {
  const previous = Object.getOwnPropertyDescriptor(window, "isSecureContext")
  if (value === undefined) delete window.isSecureContext
  else Object.defineProperty(window, "isSecureContext", { configurable: true, value })
  try {
    await run()
  } finally {
    if (previous) Object.defineProperty(window, "isSecureContext", previous)
    else delete window.isSecureContext
  }
}

function mockFetch(status, body, { reject = false, badJson = false } = {}) {
  const fetchMock = vi.fn().mockImplementation(() => {
    if (reject) return Promise.reject(new Error("network"))
    return Promise.resolve({
      status,
      json: badJson
        ? async () => { throw new Error("invalid json") }
        : async () => body
    })
  })
  vi.stubGlobal("fetch", fetchMock)
  return fetchMock
}

describe("speech-to-text controller", () => {
  beforeEach(() => {
    document.head.innerHTML = ""
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    document.head.innerHTML = ""
  })

  it("shows unavailable when MediaRecorder is missing", async () => {
    vi.stubGlobal("MediaRecorder", undefined)
    installMic()
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Voice input is not available in this browser.")
  })

  it("shows unavailable when mediaDevices is missing", async () => {
    installRecorder()
    vi.stubGlobal("navigator", { ...navigator, mediaDevices: undefined })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Voice input is not available in this browser.")
  })

  it("shows unavailable when getUserMedia is not a function", async () => {
    installRecorder()
    vi.stubGlobal("navigator", { ...navigator, mediaDevices: {} })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Voice input is not available in this browser.")
  })

  it("shows permission denied for NotAllowedError", async () => {
    installRecorder()
    installMic({ getUserMedia: vi.fn().mockRejectedValue(Object.assign(new Error("denied"), { name: "NotAllowedError" })) })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Microphone permission denied.")
  })

  it("shows permission denied for PermissionDeniedError", async () => {
    installRecorder()
    installMic({ getUserMedia: vi.fn().mockRejectedValue(Object.assign(new Error("denied"), { name: "PermissionDeniedError" })) })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Microphone permission denied.")
  })

  it("shows no-microphone copy for NotFoundError", async () => {
    installRecorder()
    installMic({ getUserMedia: vi.fn().mockRejectedValue(Object.assign(new Error("missing"), { name: "NotFoundError" })) })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("No microphone was found.")
  })

  it("shows no-microphone copy for DevicesNotFoundError", async () => {
    installRecorder()
    installMic({ getUserMedia: vi.fn().mockRejectedValue(Object.assign(new Error("missing"), { name: "DevicesNotFoundError" })) })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("No microphone was found.")
  })

  // getUserMedia is only granted in a secure context, so dictation has to say
  // why rather than let the browser raise an opaque permission error.
  it("refuses to record on an insecure origin and asks for HTTPS", async () => {
    installRecorder()
    const { media } = installMic()
    await withSecureContext(false, async () => {
      const { element } = await mountController("speech-to-text", Controller, widgetHtml())
      await click(element.querySelector("button"))
      await flush()
      expect(media.getUserMedia).not.toHaveBeenCalled()
      expect(element.querySelector("[data-speech-to-text-target='status']").textContent)
        .toBe("Voice input requires HTTPS or localhost.")
      expect(element.querySelector("[data-speech-to-text-target='status']").classList.contains("text-danger")).toBe(true)
    })
  })

  it("records on a secure origin", async () => {
    installRecorder()
    const { media } = installMic()
    await withSecureContext(true, async () => {
      const { element } = await mountController("speech-to-text", Controller, widgetHtml())
      await click(element.querySelector("button"))
      await flush()
      expect(media.getUserMedia).toHaveBeenCalledOnce()
      expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Recording…")
    })
  })

  // The flag is absent in some embedders; missing alone must not disable
  // dictation, so it is read as secure and the attempt goes ahead.
  it("treats an absent isSecureContext flag as secure", async () => {
    installRecorder()
    const { media } = installMic()
    await withSecureContext(undefined, async () => {
      const { element } = await mountController("speech-to-text", Controller, widgetHtml())
      await click(element.querySelector("button"))
      await flush()
      expect(media.getUserMedia).toHaveBeenCalledOnce()
      expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Recording…")
    })
  })

  // A windowless embedder (SSR, worker) has no flag to consult at all, so the
  // gate must fall through rather than block on a global it cannot read.
  it("treats a missing window as secure and falls through to the support check", async () => {
    vi.stubGlobal("MediaRecorder", undefined)
    const { media } = installMic()
    const { application, element } = await mountController("speech-to-text", Controller, widgetHtml())
    const ctrl = controllerFor(application, element, "speech-to-text")

    vi.stubGlobal("window", undefined)
    ctrl.toggle()
    await flush()

    expect(media.getUserMedia).not.toHaveBeenCalled()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent)
      .toBe("Voice input is not available in this browser.")
  })

  it("shows unavailable for other getUserMedia errors", async () => {
    installRecorder()
    installMic({ getUserMedia: vi.fn().mockRejectedValue(Object.assign(new Error("abort"), { name: "AbortError" })) })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Voice input is not available in this browser.")
  })

  it("records, posts audio, and inserts a clip placeholder on 202", async () => {
    installRecorder()
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "clip-99" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml({ csrf: "csrf-value" }))
    const button = element.querySelector("button")

    await click(button)
    await flush()
    expect(button.getAttribute("aria-label")).toBe("Stop recording")
    expect(button.getAttribute("aria-pressed")).toBe("true")
    expect(button.classList.contains("btn-danger")).toBe(true)
    expect(button.classList.contains("btn-ghost")).toBe(false)
    expect(button.classList.contains("animate-pulse")).toBe(true)
    expect(element.querySelector("[data-speech-to-text-target='micIcon']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-speech-to-text-target='stopIcon']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-speech-to-text-target='liveDot']").classList.contains("hidden")).toBe(false)
    const status = element.querySelector("[data-speech-to-text-target='status']")
    expect(status.textContent).toBe("Recording…")
    expect(status.classList.contains("text-danger")).toBe(true)
    expect(status.classList.contains("font-medium")).toBe(true)
    expect(status.classList.contains("text-text-muted")).toBe(false)

    await click(button)
    await flush()
    await flush()

    expect(fetchMock).toHaveBeenCalledOnce()
    const [url, options] = fetchMock.mock.calls[0]
    expect(url).toBe("/12345678/admin/modules/ai_assistant/transcriptions")
    expect(options.method).toBe("POST")
    expect(options.headers["X-CSRF-Token"]).toBe("csrf-value")
    expect(options.headers.Accept).toBe("application/json")
    expect(options.body).toBeInstanceOf(FormData)
    expect(options.body.get("field_dom_id")).toBe("field_name")
    expect(options.body.get("destination")).toBe("field")
    expect(options.body.get("audio")).toBeTruthy()
    expect(options.body.get("duration_seconds")).toMatch(/^\d+$/)
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Transcribing…")
    expect(element.querySelector("#speech_to_text_result_clip-99")).toBeTruthy()
    expect(button.disabled).toBe(false)
    expect(button.getAttribute("aria-label")).toBe("Dictate")
    expect(button.getAttribute("aria-pressed")).toBe("false")
    expect(button.classList.contains("btn-ghost")).toBe(true)
    expect(button.classList.contains("btn-danger")).toBe(false)
    expect(element.querySelector("[data-speech-to-text-target='micIcon']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-speech-to-text-target='stopIcon']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-speech-to-text-target='liveDot']").classList.contains("hidden")).toBe(true)
  })

  it("constructs MediaRecorder without a mime type when isTypeSupported is absent", async () => {
    installRecorder({ hasIsTypeSupported: false, chunks: "untyped" })
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "c2" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it("constructs MediaRecorder without options when the mime type is unsupported", async () => {
    installRecorder({ mimeSupported: false })
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "c3" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it("times out at maxDuration and uploads", async () => {
    installRecorder()
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "timed" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml({ maxDuration: 0.001 }))
    await click(element.querySelector("button"))
    await flush()
    await new Promise((resolve) => setTimeout(resolve, 15))
    await flush()
    await flush()
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it("does not stop again when the duration timer fires after recording already ended", async () => {
    installRecorder()
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "nope" })
    const { application, element } = await mountController("speech-to-text", Controller, widgetHtml({ maxDuration: 30 }))
    const ctrl = controllerFor(application, element, "speech-to-text")
    const timers = vi.spyOn(window, "setTimeout")
    await click(element.querySelector("button"))
    await flush()
    const limitCallback = timers.mock.calls.find(([, delay]) => delay === 30_000)[0]
    ctrl.recording = false
    window.clearTimeout(ctrl.limitTimer)
    limitCallback()
    expect(fetchMock).not.toHaveBeenCalled()
    ctrl.disconnect()
  })

  it("sends duration_seconds 0 when startedAt is missing or in the future", async () => {
    installRecorder()
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "dur" })
    const { application, element } = await mountController("speech-to-text", Controller, widgetHtml())
    const ctrl = controllerFor(application, element, "speech-to-text")
    await click(element.querySelector("button"))
    await flush()
    ctrl.startedAt = null
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock.mock.calls[0][1].body.get("duration_seconds")).toBe("0")

    ctrl.startedAt = Date.now() + 10_000
    ctrl.chunks = [new Blob(["x"], { type: "audio/webm" })]
    ctrl.recorder = { state: "inactive" }
    ctrl.recording = true
    ctrl.busy = false
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock.mock.calls.at(-1)[1].body.get("duration_seconds")).toBe("0")
  })

  it("uploads via the inactive-recorder path when chunks are already buffered", async () => {
    installRecorder()
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "inactive" })
    const { application, element } = await mountController("speech-to-text", Controller, widgetHtml())
    const ctrl = controllerFor(application, element, "speech-to-text")
    await click(element.querySelector("button"))
    await flush()
    ctrl.chunks = [new Blob(["x"], { type: "audio/webm" })]
    ctrl.recorder.state = "inactive"
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it("ignores a second toggle while an upload is in flight", async () => {
    installRecorder()
    installMic()
    let resolveFetch
    const fetchMock = vi.fn().mockImplementation(() => new Promise((resolve) => { resolveFetch = resolve }))
    vi.stubGlobal("fetch", fetchMock)
    const { application, element } = await mountController("speech-to-text", Controller, widgetHtml())
    const ctrl = controllerFor(application, element, "speech-to-text")
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    expect(ctrl.busy).toBe(true)
    await click(element.querySelector("button"))
    expect(fetchMock).toHaveBeenCalledOnce()
    resolveFetch({ status: 202, json: async () => ({ clip_id: "late" }) })
    await flush()
    await flush()
  })

  it("toggle() without an event still starts recording", async () => {
    installRecorder()
    installMic()
    const { application, element } = await mountController("speech-to-text", Controller, widgetHtml())
    const ctrl = controllerFor(application, element, "speech-to-text")
    ctrl.toggle()
    await flush()
    expect(ctrl.recording).toBe(true)
  })

  it("reads the CSRF token from the meta tag when the value is blank", async () => {
    installRecorder()
    installMic()
    const meta = document.createElement("meta")
    meta.name = "csrf-token"
    meta.content = "meta-csrf"
    document.head.appendChild(meta)
    const fetchMock = mockFetch(202, { clip_id: "meta" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml({ csrf: "" }))
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("meta-csrf")
  })

  it("sends an empty CSRF token when neither value nor meta is present", async () => {
    installRecorder()
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "none" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml({ csrf: "" }))
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("")
  })

  it("does not insert a placeholder when 202 omits clip_id", async () => {
    installRecorder()
    installMic()
    mockFetch(202, {})
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(element.querySelector("[id^='speech_to_text_result_']")).toBeNull()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Transcribing…")
  })

  it("skips the inbox when the target is missing on 202", async () => {
    installRecorder()
    installMic()
    mockFetch(202, { clip_id: "orphan" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml({ omitInbox: true }))
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(element.querySelector("#speech_to_text_result_orphan")).toBeNull()
  })

  it("shows unavailable on 403", async () => {
    installRecorder()
    installMic()
    mockFetch(403, { error: "forbidden" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Voice input is not available in this browser.")
    expect(element.querySelector("[data-speech-to-text-target='status']").classList.contains("text-danger")).toBe(true)
  })

  it("shows too-long copy on 422 too_long and interpolates seconds", async () => {
    installRecorder()
    installMic()
    mockFetch(422, { error_code: "too_long" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml({ maxDuration: 45 }))
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent)
      .toBe("Recording is too long (maximum 45 seconds).")
  })

  it("shows too-large copy on 422 too_large", async () => {
    installRecorder()
    installMic()
    mockFetch(422, { error: "too_large" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Audio file is too large.")
  })

  it("shows the rate-limited message on 429", async () => {
    installRecorder()
    installMic()
    mockFetch(429, { error: "rate" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Too many transcriptions. Try again later.")
  })

  it("shows the generic error when the error body is not JSON", async () => {
    installRecorder()
    installMic()
    mockFetch(500, null, { badJson: true })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Could not transcribe audio. Try again.")
  })

  it("shows the generic error when fetch rejects", async () => {
    installRecorder()
    installMic()
    mockFetch(0, null, { reject: true })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Could not transcribe audio. Try again.")
  })

  it("rejects an oversized recording without posting", async () => {
    installRecorder({ chunks: "huge" })
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "nope" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    expect(fetchMock).not.toHaveBeenCalled()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Audio file is too large.")
  })

  it("shows a generic error for an empty recording", async () => {
    installRecorder({ chunks: "empty" })
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "nope" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    expect(fetchMock).not.toHaveBeenCalled()
    expect(element.querySelector("[data-speech-to-text-target='status']").textContent).toBe("Could not transcribe audio. Try again.")
  })

  it("finds a nested input when the field target is omitted", async () => {
    installRecorder()
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "nested" })
    const { element } = await mountController("speech-to-text", Controller, widgetHtml({ omitField: true }))
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock.mock.calls[0][1].body.get("field_dom_id")).toBe("field_name")
  })

  it("posts an empty field_dom_id when no input is present", async () => {
    installRecorder()
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "noid" })
    const { element } = await mountController(
      "speech-to-text",
      Controller,
      widgetHtml({ omitField: true, innerInput: false })
    )
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock.mock.calls[0][1].body.get("field_dom_id")).toBe("")
  })

  it("posts the server-declared destination so the transcript is routed explicitly", async () => {
    installRecorder()
    installMic()
    const fetchMock = mockFetch(202, { clip_id: "dest" })
    const { element } = await mountController(
      "speech-to-text",
      Controller,
      widgetHtml({ destination: "assistant" })
    )
    await click(element.querySelector("button"))
    await flush()
    await click(element.querySelector("button"))
    await flush()
    await flush()
    expect(fetchMock.mock.calls[0][1].body.get("destination")).toBe("assistant")
    expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("")
  })

  describe("assistant conversation binding", () => {
    const threadHtml = (conversationId, widget = {}) => `<section data-controller="ai-assistant" data-ai-assistant-conversation-id-value="${conversationId}">
      ${widgetHtml({ destination: "assistant", conversationId, ...widget })}
    </section>`
    const selectThread = (panel, conversationId) => {
      panel.setAttribute("data-ai-assistant-conversation-id-value", conversationId)
      panel.dispatchEvent(new CustomEvent("ai-assistant:conversationChanged", {
        bubbles: true, detail: { conversationId },
      }))
    }
    const recordAndStop = async (element) => {
      await click(element.querySelector("button"))
      await flush()
      await click(element.querySelector("button"))
      await flush()
      await flush()
    }

    it("posts the server-seeded thread for a standalone assistant widget", async () => {
      installRecorder()
      installMic()
      const fetchMock = mockFetch(202, { clip_id: "seeded" })
      const { element } = await mountController("speech-to-text", Controller,
        widgetHtml({ destination: "assistant", conversationId: "42" }))
      await recordAndStop(element)
      expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("42")
    })

    it("reads the live selected thread before its value-change event is delivered", async () => {
      installRecorder()
      installMic()
      const fetchMock = mockFetch(202, { clip_id: "latest" })
      const { element } = await mountController("speech-to-text", Controller, threadHtml("42"))
      element.parentElement.setAttribute("data-ai-assistant-conversation-id-value", "43")
      await recordAndStop(element)
      expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("43")
    })

    it("updates future recordings from its own thread event without retargeting buffered audio", async () => {
      installRecorder()
      installMic()
      const fetchMock = mockFetch(202, { clip_id: "thread" })
      const { application, element } = await mountController("speech-to-text", Controller, threadHtml("42"))
      const controller = controllerFor(application, element, "speech-to-text")
      await click(element.querySelector("button"))
      await flush()
      selectThread(element.parentElement, "43")
      expect(controller.conversationIdValue).toBe("43")
      await click(element.querySelector("button"))
      await flush()
      await flush()
      expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("42")

      await recordAndStop(element)
      expect(fetchMock.mock.calls[1][1].body.get("conversation_id")).toBe("43")
    })

    it("pins the recording before a microphone permission prompt can switch threads", async () => {
      installRecorder()
      let grant
      const { stream } = installMic({ getUserMedia: vi.fn(() => new Promise(resolve => { grant = resolve })) })
      const fetchMock = mockFetch(202, { clip_id: "permission" })
      const { application, element } = await mountController("speech-to-text", Controller, threadHtml("42"))
      const controller = controllerFor(application, element, "speech-to-text")
      controller.toggle()
      selectThread(element.parentElement, "43")
      grant(stream)
      await flush()
      await click(element.querySelector("button"))
      await flush()
      await flush()
      expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("42")
    })

    it("keeps an enqueued upload on its original thread when selection changes before acknowledgement", async () => {
      installRecorder()
      installMic()
      let acknowledge
      const fetchMock = vi.fn(() => new Promise(resolve => { acknowledge = resolve }))
      vi.stubGlobal("fetch", fetchMock)
      const { element } = await mountController("speech-to-text", Controller, threadHtml("42"))
      await recordAndStop(element)
      selectThread(element.parentElement, "43")
      expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("42")
      expect(fetchMock).toHaveBeenCalledOnce()
      acknowledge({ status: 202, json: async () => ({ clip_id: "original-thread" }) })
      await flush()
      await flush()
      expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("42")
    })

    it("ignores selection events from a different assistant panel", async () => {
      installRecorder()
      installMic()
      const fetchMock = mockFetch(202, { clip_id: "scoped" })
      const { application, element } = await mountController("speech-to-text", Controller, threadHtml("42"))
      const controller = controllerFor(application, element, "speech-to-text")
      const otherPanel = document.createElement("section")
      otherPanel.setAttribute("data-controller", "ai-assistant")
      document.body.appendChild(otherPanel)
      selectThread(otherPanel, "99")
      expect(controller.conversationIdValue).toBe("42")
      await recordAndStop(element)
      expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("42")
    })

    it("clears a missing selected thread instead of falling back to a stale id", async () => {
      installRecorder()
      installMic()
      const fetchMock = mockFetch(202, { clip_id: "no-thread" })
      const { application, element } = await mountController("speech-to-text", Controller, threadHtml("42"))
      const controller = controllerFor(application, element, "speech-to-text")
      selectThread(element.parentElement, "")
      expect(controller.conversationIdValue).toBe("")
      await recordAndStop(element)
      expect(fetchMock.mock.calls[0][1].body.get("conversation_id")).toBe("")
    })

    it("leaves ordinary field dictation free of assistant conversation metadata", async () => {
      installRecorder()
      installMic()
      const fetchMock = mockFetch(202, { clip_id: "field-only" })
      const { application, element } = await mountController("speech-to-text", Controller, widgetHtml({ conversationId: "42" }))
      const controller = controllerFor(application, element, "speech-to-text")
      window.dispatchEvent(new CustomEvent("ai-assistant:conversationChanged", { detail: { conversationId: "99" } }))
      expect(controller.conversationIdValue).toBe("42")
      await recordAndStop(element)
      expect(fetchMock.mock.calls[0][1].body.has("conversation_id")).toBe(false)
    })
  })

  it("shows recording chrome without requiring icon or live-dot targets", async () => {
    installRecorder()
    installMic()
    mockFetch(202, { clip_id: "bare" })
    const { element } = await mountController(
      "speech-to-text",
      Controller,
      widgetHtml({ omitIcons: true, omitLiveDot: true })
    )
    const button = element.querySelector("button")
    await click(button)
    await flush()
    expect(button.getAttribute("aria-pressed")).toBe("true")
    expect(button.classList.contains("btn-danger")).toBe(true)
    await click(button)
    await flush()
    await flush()
    expect(button.getAttribute("aria-pressed")).toBe("false")
  })

  it("tolerates missing button and status targets", async () => {
    installRecorder()
    installMic()
    mockFetch(202, { clip_id: "quiet" })
    const { application, element } = await mountController(
      "speech-to-text",
      Controller,
      widgetHtml({ omitButton: true, omitStatus: true })
    )
    const ctrl = controllerFor(application, element, "speech-to-text")
    expect(() => ctrl.toggle()).not.toThrow()
    await flush()
    ctrl.toggle()
    await flush()
    await flush()
  })

  it("stops tracks and swallows recorder.stop errors on disconnect", async () => {
    installRecorder({ throwOnStop: true })
    const { stop } = installMic()
    const { application, element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    expect(() => element.remove()).not.toThrow()
    await tick()
    expect(stop).toHaveBeenCalled()
    application.stop()
  })

  it("disconnects cleanly when recording never started", async () => {
    installRecorder()
    installMic()
    const { application, element } = await mountController("speech-to-text", Controller, widgetHtml())
    expect(() => element.remove()).not.toThrow()
    await tick()
    application.stop()
  })

  it("does not upload after disconnect abandons an in-flight recorder", async () => {
    installRecorder()
    const { stop } = installMic()
    const fetchMock = mockFetch(202, { clip_id: "abandoned" })
    const { application, element } = await mountController("speech-to-text", Controller, widgetHtml())
    await click(element.querySelector("button"))
    await flush()
    element.remove()
    await flush()
    expect(fetchMock).not.toHaveBeenCalled()
    expect(stop).toHaveBeenCalled()
    application.stop()
  })
})
