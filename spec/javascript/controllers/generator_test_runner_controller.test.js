import { describe, it, expect, afterEach, vi } from "vitest"
import Controller from "controllers/generator_test_runner_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (attrs = "") => `
  <div data-controller="generator-test-runner" data-generator-test-runner-url-value="/42/admin/generators/run" ${attrs}>
    <textarea data-generator-test-runner-target="config">{"x":1}</textarea>
    <button data-generator-test-runner-target="runButton">Run</button>
    <svg data-generator-test-runner-target="spinner" class="hidden"></svg>
    <div data-generator-test-runner-target="result"><p>initial</p></div>
  </div>`

const t = (el, n) => el.querySelector(`[data-generator-test-runner-target='${n}']`)
const respond = (data) => vi.fn(() => Promise.resolve({ json: () => Promise.resolve(data) }))

describe("generator-test-runner controller", () => {
  let application, element, ctrl
  const mount = async (attrs) => {
    ;({ application, element } = await mountController("generator-test-runner", Controller, html(attrs)))
    ctrl = controllerFor(application, element, "generator-test-runner")
  }
  afterEach(() => vi.restoreAllMocks())

  describe("reset", () => {
    it("restores the sample config and focuses the editor", async () => {
      await mount(`data-generator-test-runner-sample-value='{"a": 1}'`)
      t(element, "config").value = "{broken"
      ctrl.reset()
      expect(t(element, "config").value).toBe('{"a": 1}')
      expect(document.activeElement).toBe(t(element, "config"))
    })

    it("falls back to an empty object without a sample", async () => {
      await mount()
      ctrl.reset()
      expect(t(element, "config").value).toBe("{}")
    })
  })

  describe("run", () => {
    it("posts the config and swaps in the server-rendered result", async () => {
      await mount()
      globalThis.fetch = respond({ html: "<pre>def test_step(ctx, **)</pre>" })
      const event = { preventDefault: vi.fn() }
      await ctrl.run(event)

      expect(event.preventDefault).toHaveBeenCalled()
      expect(globalThis.fetch).toHaveBeenCalledWith(
        "/42/admin/generators/run",
        expect.objectContaining({ method: "POST", body: JSON.stringify({ sample_config: '{"x":1}' }) })
      )
      expect(t(element, "result").innerHTML).toBe("<pre>def test_step(ctx, **)</pre>")
      expect(t(element, "runButton").disabled).toBe(false)
      expect(t(element, "spinner").classList.contains("hidden")).toBe(true)
    })

    it("shows a busy state while the request is in flight", async () => {
      await mount()
      let finish
      globalThis.fetch = vi.fn(() => new Promise((resolve) => { finish = resolve }))
      const pending = ctrl.run()

      expect(t(element, "runButton").disabled).toBe(true)
      expect(t(element, "spinner").classList.contains("hidden")).toBe(false)
      finish({ json: () => Promise.resolve({ html: "<p>done</p>" }) })
      await pending
      expect(t(element, "runButton").disabled).toBe(false)
    })

    it("ignores a run while one is already in flight", async () => {
      await mount()
      globalThis.fetch = respond({ html: "<p>x</p>" })
      t(element, "runButton").disabled = true
      await ctrl.run()
      expect(globalThis.fetch).not.toHaveBeenCalled()
    })

    it("renders a server error without HTML as escaped text", async () => {
      await mount()
      globalThis.fetch = respond({ error: "<b>Generator not found</b>" })
      await ctrl.run()
      const alert = t(element, "result").querySelector("[role='alert']")
      expect(alert.textContent).toBe("<b>Generator not found</b>")
      expect(alert.querySelector("b")).toBeNull()
    })

    it("reports a network failure with the translated template", async () => {
      await mount(`data-generator-test-runner-request-failed-format-value="请求失败：{message}"`)
      globalThis.fetch = vi.fn(() => Promise.reject(new Error("offline")))
      await ctrl.run()
      expect(t(element, "result").textContent).toBe("请求失败：offline")
      expect(t(element, "runButton").disabled).toBe(false)
    })

    it("sends the CSRF token from the meta tag when present", async () => {
      await mount()
      const meta = document.createElement("meta")
      meta.setAttribute("name", "csrf-token")
      meta.setAttribute("content", "tok-123")
      document.head.appendChild(meta)
      globalThis.fetch = respond({ html: "<p>ok</p>" })
      await ctrl.run()
      expect(globalThis.fetch).toHaveBeenCalledWith(
        "/42/admin/generators/run",
        expect.objectContaining({ headers: expect.objectContaining({ "X-CSRF-Token": "tok-123" }) })
      )
      meta.remove()
    })

    it("sends an empty CSRF token when the meta tag is missing", async () => {
      await mount()
      globalThis.fetch = respond({ html: "<p>ok</p>" })
      await ctrl.run()
      expect(globalThis.fetch).toHaveBeenCalledWith(
        "/42/admin/generators/run",
        expect.objectContaining({ headers: expect.objectContaining({ "X-CSRF-Token": "" }) })
      )
    })
  })
})
