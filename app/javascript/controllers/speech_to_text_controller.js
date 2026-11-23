import { Controller } from "@hotwired/stimulus"

const MAX_UPLOAD_BYTES = 25 * 1024 * 1024

export default class extends Controller {
  static targets = ["field", "button", "status", "inbox", "micIcon", "stopIcon", "liveDot"]

  static values = {
    url: String,
    destination: { type: String, default: "field" },
    conversationId: { type: String, default: "" },
    maxDuration: { type: Number, default: 60 },
    csrf: { type: String, default: "" },
    micLabel: { type: String, default: "Dictate" },
    stopLabel: { type: String, default: "Stop recording" },
    recording: { type: String, default: "Recording…" },
    transcribing: { type: String, default: "Transcribing…" },
    permissionDenied: { type: String, default: "Microphone permission denied." },
    noMicrophone: { type: String, default: "No microphone was found." },
    insecure: { type: String, default: "Voice input requires HTTPS or localhost." },
    unavailable: { type: String, default: "Voice input is not available in this browser." },
    tooLong: { type: String, default: "Recording is too long (maximum {seconds} seconds)." },
    tooLarge: { type: String, default: "Audio file is too large." },
    genericError: { type: String, default: "Could not transcribe audio. Try again." },
    rateLimited: { type: String, default: "Too many transcriptions. Try again later." }
  }

  connect() {
    this.recording = false
    this.busy = false
    this.abandoned = false
    this.chunks = []
    this.recorder = null
    this.stream = null
    this.limitTimer = null
    this.startedAt = null
    this.recordingConversationId = ""
  }

  disconnect() {
    this.abandoned = true
    this.#clearLimit()
    if (this.recorder && this.recorder.state !== "inactive") {
      try {
        this.recorder.stop()
      } catch {
        // Recorder already closed.
      }
    }
    this.#stopTracks()
    this.recording = false
  }

  toggle(event) {
    if (event) event.preventDefault()
    if (this.busy) return

    if (this.recording) {
      this.#stopRecording()
      return
    }

    void this.#startRecording()
  }

  conversationChanged(event) {
    const panel = this.element.closest("[data-controller~='ai-assistant']")
    if (!panel || event.target !== panel) return

    // Selection updates apply to the next recording, never to a buffered clip.
    this.conversationIdValue = event.detail.conversationId
  }

  async #startRecording() {
    // getUserMedia is only granted in a secure context, so an insecure origin
    // would otherwise fail with an opaque permission error.
    if (!this.#secureContext()) {
      this.#setStatus(this.insecureValue, true)
      return
    }
    if (!this.#supported()) {
      this.#setStatus(this.unavailableValue, true)
      return
    }

    // Snapshot before the permission prompt can yield to another thread. The
    // live panel attribute also covers a switch before Stimulus fires its event.
    const recordingConversationId = this.#selectedConversationId()
    let stream
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch (error) {
      if (this.#permissionDenied(error)) {
        this.#setStatus(this.permissionDeniedValue, true)
      } else if (this.#noMicrophone(error)) {
        this.#setStatus(this.noMicrophoneValue, true)
      } else {
        this.#setStatus(this.unavailableValue, true)
      }
      return
    }

    this.abandoned = false
    this.stream = stream
    this.chunks = []
    const mimeType = this.#pickMimeType()
    this.recorder = mimeType ? new MediaRecorder(stream, { mimeType }) : new MediaRecorder(stream)
    this.recorder.addEventListener("dataavailable", (event) => {
      if (event.data && event.data.size > 0) this.chunks.push(event.data)
    })
    this.recorder.addEventListener("stop", () => {
      void this.#handleStop()
    })
    this.recorder.start()
    this.startedAt = Date.now()
    this.recordingConversationId = recordingConversationId
    this.recording = true
    this.#setRecordingUi(true)
    this.#setStatus(this.recordingValue, false)
    const ms = Number(this.maxDurationValue) * 1000
    this.limitTimer = window.setTimeout(() => {
      if (this.recording) this.#stopRecording()
    }, ms)
  }

  #stopRecording() {
    this.recording = false
    this.#clearLimit()
    if (this.recorder && this.recorder.state !== "inactive") {
      this.recorder.stop()
    } else {
      void this.#handleStop()
    }
  }

  async #handleStop() {
    this.#stopTracks()
    this.#setRecordingUi(false)

    if (this.abandoned) return

    const total = this.chunks.reduce((sum, part) => sum + part.size, 0)
    if (total > MAX_UPLOAD_BYTES) {
      this.chunks = []
      this.recorder = null
      this.#setStatus(this.tooLargeValue, true)
      return
    }

    const type = (this.chunks[0] && this.chunks[0].type) || "audio/webm"
    const blob = new Blob(this.chunks, { type })
    this.chunks = []
    this.recorder = null

    if (blob.size === 0) {
      this.#setStatus(this.genericErrorValue, true)
      return
    }

    await this.#upload(blob)
  }

  async #upload(blob) {
    this.busy = true
    this.#setBusyUi(true)
    this.#setStatus(this.transcribingValue, false)

    const body = new FormData()
    body.append("audio", blob, "dictation.webm")
    body.append("field_dom_id", this.#fieldId())
    body.append("destination", this.destinationValue)
    if (this.destinationValue === "assistant") body.append("conversation_id", this.recordingConversationId)
    body.append("duration_seconds", String(this.#elapsedSeconds()))

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.#csrfToken(),
          Accept: "application/json"
        },
        body
      })
      await this.#applyResponse(response)
    } catch {
      this.#setStatus(this.genericErrorValue, true)
    } finally {
      this.busy = false
      this.#setBusyUi(false)
    }
  }

  async #applyResponse(response) {
    if (response.status === 202) {
      const payload = await this.#readJson(response)
      const clipId = payload && payload.clip_id
      this.#setStatus(this.transcribingValue, false)
      if (clipId && this.hasInboxTarget) {
        const placeholder = document.createElement("div")
        placeholder.id = `speech_to_text_result_${clipId}`
        this.inboxTarget.appendChild(placeholder)
      }
      return
    }

    const payload = await this.#readJson(response)
    const code = (payload && (payload.error_code || payload.error)) || ""
    this.#setStatus(this.#messageForResponse(response.status, code), true)
  }

  #elapsedSeconds() {
    const started = this.startedAt || Date.now()
    return Math.max(0, Math.ceil((Date.now() - started) / 1000))
  }

  #messageForResponse(status, code) {
    if (status === 429) return this.rateLimitedValue
    if (status === 403) return this.unavailableValue
    if (code === "too_long") return this.tooLongValue.replace("{seconds}", String(this.maxDurationValue))
    if (code === "too_large") return this.tooLargeValue
    return this.genericErrorValue
  }

  async #readJson(response) {
    try {
      return await response.json()
    } catch {
      return {}
    }
  }

  // `isSecureContext` is absent in some test environments; treat that as
  // secure so the missing flag alone cannot disable dictation.
  #secureContext() {
    if (typeof window === "undefined") return true
    if (typeof window.isSecureContext === "undefined") return true

    return window.isSecureContext === true
  }

  #supported() {
    return typeof MediaRecorder !== "undefined" &&
      navigator.mediaDevices &&
      typeof navigator.mediaDevices.getUserMedia === "function"
  }

  #permissionDenied(error) {
    return Boolean(error && (error.name === "NotAllowedError" || error.name === "PermissionDeniedError"))
  }

  #noMicrophone(error) {
    return Boolean(error && (error.name === "NotFoundError" || error.name === "DevicesNotFoundError"))
  }

  #pickMimeType() {
    if (typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported("audio/webm")) {
      return "audio/webm"
    }
    return ""
  }

  #csrfToken() {
    if (this.csrfValue) return this.csrfValue
    const meta = document.querySelector('meta[name="csrf-token"]')
    return (meta && meta.getAttribute("content")) || ""
  }

  #fieldId() {
    const field = this.#fieldElement()
    return field ? field.id : ""
  }

  #selectedConversationId() {
    const panel = this.element.closest("[data-ai-assistant-conversation-id-value]")
    return panel ? panel.getAttribute("data-ai-assistant-conversation-id-value") : this.conversationIdValue
  }

  #fieldElement() {
    if (this.hasFieldTarget) return this.fieldTarget
    return this.element.querySelector("input:not([type=hidden]), textarea")
  }

  #setRecordingUi(on) {
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-label", on ? this.stopLabelValue : this.micLabelValue)
      this.buttonTarget.setAttribute("aria-pressed", on ? "true" : "false")
      this.buttonTarget.classList.toggle("btn-ghost", !on)
      this.buttonTarget.classList.toggle("btn-danger", on)
      this.buttonTarget.classList.toggle("text-text-muted", !on)
      this.buttonTarget.classList.toggle("animate-pulse", on)
    }
    if (this.hasMicIconTarget) this.micIconTarget.classList.toggle("hidden", on)
    if (this.hasStopIconTarget) this.stopIconTarget.classList.toggle("hidden", !on)
    if (this.hasLiveDotTarget) this.liveDotTarget.classList.toggle("hidden", !on)
  }

  #setBusyUi(on) {
    if (this.hasButtonTarget) this.buttonTarget.disabled = on
  }

  #setStatus(text, isError) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    const recording = Boolean(this.recording) && !isError
    this.statusTarget.classList.toggle("text-danger", Boolean(isError) || recording)
    this.statusTarget.classList.toggle("text-text-muted", !isError && !recording)
    this.statusTarget.classList.toggle("font-medium", recording)
  }

  #clearLimit() {
    if (!this.limitTimer) return
    window.clearTimeout(this.limitTimer)
    this.limitTimer = null
  }

  #stopTracks() {
    if (!this.stream) return
    this.stream.getTracks().forEach((track) => track.stop())
    this.stream = null
  }
}
