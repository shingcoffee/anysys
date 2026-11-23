import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/generator_form_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const html = `
  <div data-controller="generator-form" data-generator-form-preview-url-value="/42/admin/generators/preview">
    <input name="kind" value="step_action">
    <input name="file_name" value="my_gen">
    <input name="category" value="cat">
    <input name="description" value="desc">
    <input name="version" value="2.0.0">
    <input name="registered_names" value="foo,bar">
    <textarea name="methods_body">def x; end</textarea>
    <div data-generator-form-target="previewPanel"></div>
    <span data-generator-form-target="previewLineCount"></span>
  </div>`

const okResponse = (body) => Promise.resolve({ ok: true, json: () => Promise.resolve(body) })

describe("generator-form controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    globalThis.fetch = vi.fn(() => new Promise(() => {})) // connect fires a preview; swallow it
    ;({ application, element } = await mountController("generator-form", Controller, html))
    ctrl = controllerFor(application, element, "generator-form")
  })
  afterEach(() => vi.restoreAllMocks())

  describe("connect", () => {
    it("requests a preview on connect", () => {
      expect(globalThis.fetch).toHaveBeenCalledWith(
        "/42/admin/generators/preview",
        expect.objectContaining({ method: "POST" })
      )
    })
  })

  describe("collectFormData", () => {
    it("reads all named fields off the form", () => {
      expect(ctrl.collectFormData()).toEqual({
        kind: "step_action",
        file_name: "my_gen",
        category: "cat",
        description: "desc",
        version: "2.0.0",
        registered_names: "foo,bar",
        methods_body: "def x; end",
      })
    })

    it("applies defaults for missing fields", async () => {
      const { application: app, element: el } = await mountController(
        "generator-form",
        Controller,
        `<div data-controller="generator-form" data-generator-form-preview-url-value="/x"></div>`
      )
      const c = controllerFor(app, el, "generator-form")
      const data = c.collectFormData()
      expect(data.kind).toBe("step_action")
      expect(data.file_name).toBe("my_generator")
      expect(data.version).toBe("1.0.0")
    })
  })

  describe("updatePreview", () => {
    it("renders line numbers and highlighted code", () => {
      ctrl.updatePreview({ line_count: 3, highlighted: "puts 1" })
      const panel = element.querySelector("[data-generator-form-target='previewPanel']")
      expect(panel.querySelectorAll(".leading-6").length).toBeGreaterThanOrEqual(3)
      expect(panel.textContent).toContain("puts 1")
      expect(element.querySelector("[data-generator-form-target='previewLineCount']").textContent).toBe("3 lines")
    })

    it("handles a zero line count", () => {
      ctrl.updatePreview({ line_count: 0, highlighted: "" })
      expect(element.querySelector("[data-generator-form-target='previewLineCount']").textContent).toBe("0 lines")
    })
  })

  describe("requestPreview", () => {
    it("updates the preview from the fetched JSON", async () => {
      globalThis.fetch = vi.fn(() => okResponse({ line_count: 1, highlighted: "code" }))
      await ctrl.requestPreview()
      expect(element.querySelector("[data-generator-form-target='previewPanel']").textContent).toContain("code")
    })

    it("silently ignores non-ok responses", async () => {
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: false }))
      await expect(ctrl.requestPreview()).resolves.toBeUndefined()
    })

    it("silently ignores a network failure (fetch rejection)", async () => {
      globalThis.fetch = vi.fn(() => Promise.reject(new Error("offline")))
      await expect(ctrl.requestPreview()).resolves.toBeUndefined()
    })

    it("sends the CSRF token from the meta tag when present", async () => {
      const meta = document.createElement("meta")
      meta.setAttribute("name", "csrf-token")
      meta.setAttribute("content", "tok-456")
      document.head.appendChild(meta)
      globalThis.fetch = vi.fn(() => okResponse({ line_count: 0, highlighted: "" }))
      await ctrl.requestPreview()
      expect(globalThis.fetch).toHaveBeenCalledWith(
        "/42/admin/generators/preview",
        expect.objectContaining({ headers: expect.objectContaining({ "X-CSRF-Token": "tok-456" }) })
      )
      meta.remove()
    })
  })

  describe("fieldChanged", () => {
    it("schedules a debounced preview request", () => {
      vi.useFakeTimers()
      globalThis.fetch = vi.fn(() => okResponse({ line_count: 0, highlighted: "" }))
      ctrl.fieldChanged()
      expect(globalThis.fetch).not.toHaveBeenCalled()
      vi.advanceTimersByTime(300)
      expect(globalThis.fetch).toHaveBeenCalledTimes(1)
      vi.useRealTimers()
    })
  })

  describe("debouncedPreview", () => {
    it("coalesces rapid calls into a single delayed request", async () => {
      vi.useFakeTimers()
      globalThis.fetch = vi.fn(() => okResponse({ line_count: 0, highlighted: "" }))
      ctrl.debouncedPreview()
      ctrl.debouncedPreview()
      expect(globalThis.fetch).not.toHaveBeenCalled()
      vi.advanceTimersByTime(300)
      expect(globalThis.fetch).toHaveBeenCalledTimes(1)
      vi.useRealTimers()
    })
  })
})
