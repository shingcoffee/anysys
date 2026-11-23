import { describe, it, expect, afterEach } from "vitest"
import Controller from "controllers/speech_to_text_result_controller"
import { mountController } from "../support/stimulus.js"

const html = ({
  fieldId = "field_bio",
  status = "succeeded",
  transcript = "hello world",
  error = "",
  existing = "",
  includeField = true,
  wrap = false
} = {}) => {
  const field = includeField ? `<input id="field_bio" value="${existing}">` : ""
  const result =
    `<div data-controller="speech-to-text-result"` +
    ` data-speech-to-text-result-field-id-value="${fieldId}"` +
    ` data-speech-to-text-result-status-value="${status}"` +
    ` data-speech-to-text-result-transcript-value="${transcript}"` +
    ` data-speech-to-text-result-error-value="${error}"></div>`
  if (!wrap) return `${field}${result}`
  return `<div data-controller="speech-to-text">${field}` +
    `<p data-speech-to-text-target="status" class="text-text-muted">Transcribing…</p>` +
    `<div data-speech-to-text-target="inbox">${result}</div></div>`
}

describe("speech-to-text-result controller", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("writes the transcript into an empty field on succeeded", async () => {
    await mountController("speech-to-text-result", Controller, html())
    expect(document.getElementById("field_bio").value).toBe("hello world")
  })

  it("appends the transcript with a leading space when the field already has a value", async () => {
    await mountController("speech-to-text-result", Controller, html({ existing: "Notes:" }))
    expect(document.getElementById("field_bio").value).toBe("Notes: hello world")
  })

  it("does not change the field when status is failed", async () => {
    await mountController("speech-to-text-result", Controller, html({
      status: "failed",
      transcript: "should not appear",
      error: "vendor_down",
      existing: "keep me"
    }))
    expect(document.getElementById("field_bio").value).toBe("keep me")
  })

  it("does not change the field when the transcript is blank", async () => {
    await mountController("speech-to-text-result", Controller, html({
      transcript: "",
      existing: "unchanged"
    }))
    expect(document.getElementById("field_bio").value).toBe("unchanged")
  })

  it("does nothing when the field id is blank", async () => {
    await mountController("speech-to-text-result", Controller, html({ fieldId: "", existing: "safe" }))
    expect(document.getElementById("field_bio").value).toBe("safe")
  })

  it("does nothing when the field is missing from the document", async () => {
    await mountController("speech-to-text-result", Controller, html({
      fieldId: "missing_field",
      includeField: false
    }))
    expect(document.getElementById("field_bio")).toBeNull()
  })

  it("clears the parent transcribing caption on succeeded", async () => {
    const { element } = await mountController("speech-to-text-result", Controller, html({ wrap: true }))
    const root = element.closest("[data-controller='speech-to-text']") || element.parentElement
    const status = root.querySelector("[data-speech-to-text-target='status']")
    expect(status.textContent).toBe("")
    expect(status.classList.contains("text-text-muted")).toBe(true)
  })

  it("clears the parent transcribing caption when succeeded with a blank transcript", async () => {
    const { element } = await mountController(
      "speech-to-text-result",
      Controller,
      html({ wrap: true, transcript: "", existing: "unchanged" })
    )
    const root = element.closest("[data-controller='speech-to-text']") || element.parentElement
    const status = root.querySelector("[data-speech-to-text-target='status']")
    expect(document.getElementById("field_bio").value).toBe("unchanged")
    expect(status.textContent).toBe("")
  })

  it("writes the translated error onto the parent status when failed", async () => {
    const { element } = await mountController("speech-to-text-result", Controller, html({
      wrap: true,
      status: "failed",
      transcript: "",
      error: "Transcription service is unavailable. Try again.",
      existing: "keep me"
    }))
    const root = element.closest("[data-controller='speech-to-text']") || element.parentElement
    const status = root.querySelector("[data-speech-to-text-target='status']")
    expect(document.getElementById("field_bio").value).toBe("keep me")
    expect(status.textContent).toBe("Transcription service is unavailable. Try again.")
    expect(status.classList.contains("text-danger")).toBe(true)
  })
})
