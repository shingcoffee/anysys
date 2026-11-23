import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/captcha_throttle_picker_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = `
<form data-controller="captcha-throttle-picker"
      data-captcha-throttle-picker-custom-value="custom"
      data-captcha-throttle-picker-skip-value="skip"
      data-action="submit->captcha-throttle-picker#guard">
  <input type="hidden" name="preset" value="100_per_5min" data-captcha-throttle-picker-target="preset">
  <input type="hidden" name="skipped" value="false" data-captcha-throttle-picker-target="skipped">
  <button type="button" data-captcha-throttle-picker-target="display" aria-expanded="false">100 / 5 min / IP</button>
  <select hidden data-captcha-throttle-picker-target="choice" data-action="change->captcha-throttle-picker#choose keydown.esc->captcha-throttle-picker#escape blur->captcha-throttle-picker#blurChoice">
    <option value="100_per_5min" selected>100 / 5 min / IP</option>
    <option value="custom">Custom…</option>
    <option value="skip">Skip captcha</option>
  </select>
  <div hidden data-captcha-throttle-picker-target="customFields">
    <input data-captcha-throttle-picker-target="limitCount" value="">
    <input data-captcha-throttle-picker-target="periodMinutes" value="">
    <button type="button" data-action="click->captcha-throttle-picker#apply">Apply</button>
  </div>
</form>
`

const customHtml = `
<form data-controller="captcha-throttle-picker"
      data-captcha-throttle-picker-custom-value="custom"
      data-captcha-throttle-picker-skip-value="skip">
  <input type="hidden" name="preset" value="custom" data-captcha-throttle-picker-target="preset">
  <button type="button" data-captcha-throttle-picker-target="display">50 / 2 min / IP</button>
  <select hidden data-captcha-throttle-picker-target="choice">
    <option value="custom" selected>Custom…</option>
    <option value="100_per_5min">100 / 5 min / IP</option>
  </select>
  <div data-captcha-throttle-picker-target="customFields">
    <input data-captcha-throttle-picker-target="limitCount" value="50">
    <input data-captcha-throttle-picker-target="periodMinutes" value="2">
  </div>
</form>
`

describe("captcha-throttle-picker controller", () => {
  let application, element, controller

  beforeEach(async () => {
    ;({ application, element } = await mountController("captcha-throttle-picker", Controller, html))
    controller = controllerFor(application, element, "captcha-throttle-picker")
  })

  it("keeps custom fields hidden on connect for a named preset", () => {
    const fields = element.querySelector("[data-captcha-throttle-picker-target='customFields']")
    expect(fields.hidden).toBe(true)
    expect(element.querySelector("[data-captcha-throttle-picker-target='choice']").hidden).toBe(true)
    expect(element.querySelector("[data-captcha-throttle-picker-target='display']").hidden).toBe(false)
    expect(element.querySelector("[data-captcha-throttle-picker-target='display']").getAttribute("aria-expanded")).toBe("false")
  })

  it("reveals the select and native picker when the rate text is clicked", () => {
    const select = element.querySelector("select")
    const picker = vi.fn()
    select.showPicker = picker
    controller.edit()
    expect(element.querySelector("[data-captcha-throttle-picker-target='display']").hidden).toBe(true)
    expect(select.hidden).toBe(false)
    expect(element.querySelector("[data-captcha-throttle-picker-target='display']").getAttribute("aria-expanded")).toBe("true")
    expect(document.activeElement).toBe(select)
    expect(picker).toHaveBeenCalledOnce()
  })

  it("opens the editor when showPicker is missing", () => {
    const select = element.querySelector("select")
    select.showPicker = undefined
    controller.edit()
    expect(select.hidden).toBe(false)
  })

  it("opens the editor when showPicker throws", () => {
    const select = element.querySelector("select")
    select.showPicker = () => { throw new Error("not shown") }
    controller.edit()
    expect(select.hidden).toBe(false)
  })

  it("collapses back to the rate text on Escape", () => {
    controller.edit()
    const preventDefault = vi.fn()
    controller.escape({ preventDefault })
    expect(preventDefault).toHaveBeenCalledOnce()
    expect(element.querySelector("[data-captcha-throttle-picker-target='display']").hidden).toBe(false)
    expect(element.querySelector("select").hidden).toBe(true)
  })

  it("collapses on Escape without an event object", () => {
    controller.edit()
    controller.escape()
    expect(element.querySelector("select").hidden).toBe(true)
  })

  it("no-ops Escape and blur while collapsed", () => {
    const preventDefault = vi.fn()
    controller.escape({ preventDefault })
    controller.blurChoice()
    expect(preventDefault).not.toHaveBeenCalled()
    expect(element.querySelector("select").hidden).toBe(true)
  })

  it("collapses back to the rate text when the select blurs without a change", () => {
    controller.edit()
    controller.blurChoice()
    expect(element.querySelector("[data-captcha-throttle-picker-target='display']").hidden).toBe(false)
    expect(element.querySelector("select").hidden).toBe(true)
  })

  it("keeps custom fields open when the select blurs after Custom is chosen", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    controller.edit()
    element.querySelector("select").value = "custom"
    controller.choose()
    controller.blurChoice()
    expect(element.querySelector("select").hidden).toBe(false)
    expect(element.querySelector("[data-captcha-throttle-picker-target='customFields']").hidden).toBe(false)
    expect(submit).not.toHaveBeenCalled()
  })

  it("does not collapse on blur when the select value changed", () => {
    controller.edit()
    element.querySelector("select").value = "skip"
    controller.blurChoice()
    expect(element.querySelector("select").hidden).toBe(false)
  })

  it("collapses on blur when the saved choice was never captured", () => {
    controller.savedChoice = null
    controller.edit()
    controller.blurChoice()
    expect(element.querySelector("select").hidden).toBe(true)
  })

  it("shows custom fields when custom is chosen and does not submit", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    element.querySelector("select").value = "custom"
    controller.choose()
    const fields = element.querySelector("[data-captcha-throttle-picker-target='customFields']")
    expect(fields.hidden).toBe(false)
    expect(controller.presetTarget.value).toBe("custom")
    expect(controller.skippedTarget.value).toBe("false")
    expect(submit).not.toHaveBeenCalled()
  })

  it("does not submit Custom when leftover preset numbers are already filled", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    const limit = element.querySelector("[data-captcha-throttle-picker-target='limitCount']")
    const minutes = element.querySelector("[data-captcha-throttle-picker-target='periodMinutes']")
    limit.value = "100"
    minutes.value = "5"
    element.querySelector("select").value = "custom"
    controller.choose()
    expect(controller.presetTarget.value).toBe("custom")
    expect(element.querySelector("[data-captcha-throttle-picker-target='customFields']").hidden).toBe(false)
    expect(submit).not.toHaveBeenCalled()
  })

  it("submits immediately when a named preset is chosen", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    controller.presetTarget.value = "custom"
    element.querySelector("select").value = "100_per_5min"
    controller.choose()
    expect(submit).toHaveBeenCalledOnce()
    expect(controller.skippedTarget.value).toBe("false")
  })

  it("collapses without submitting when the already-selected preset is chosen again", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    controller.edit()
    element.querySelector("select").value = "100_per_5min"
    controller.choose()
    expect(submit).not.toHaveBeenCalled()
    expect(element.querySelector("select").hidden).toBe(true)
    expect(element.querySelector("[data-captcha-throttle-picker-target='display']").hidden).toBe(false)
  })

  it("submits skip without changing the stored preset", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    element.querySelector("select").value = "skip"
    controller.choose()
    expect(controller.skippedTarget.value).toBe("true")
    expect(controller.presetTarget.value).toBe("100_per_5min")
    expect(submit).toHaveBeenCalledOnce()
    const fields = element.querySelector("[data-captcha-throttle-picker-target='customFields']")
    expect(fields.hidden).toBe(true)
  })

  it("submits when leaving skip even if the rate is unchanged", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    controller.skippedTarget.value = "true"
    element.querySelector("select").value = "100_per_5min"
    controller.choose()
    expect(controller.skippedTarget.value).toBe("false")
    expect(submit).toHaveBeenCalledOnce()
  })

  it("no-ops choose when the select has no value", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    element.querySelector("select").value = ""
    controller.choose()
    expect(submit).not.toHaveBeenCalled()
  })

  it("does not submit custom numbers until Apply is used", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    element.querySelector("select").value = "custom"
    controller.choose()
    const limit = element.querySelector("[data-captcha-throttle-picker-target='limitCount']")
    const minutes = element.querySelector("[data-captcha-throttle-picker-target='periodMinutes']")
    limit.value = "50"
    minutes.value = "2"
    expect(submit).not.toHaveBeenCalled()
  })

  it("submits custom values when Apply is used and both fields are filled", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    element.querySelector("select").value = "custom"
    controller.choose()
    const limit = element.querySelector("[data-captcha-throttle-picker-target='limitCount']")
    const minutes = element.querySelector("[data-captcha-throttle-picker-target='periodMinutes']")
    limit.value = "50"
    minutes.value = "2"
    controller.apply()
    expect(submit).toHaveBeenCalledOnce()
  })

  it("does not submit Apply when the preset is not custom", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    const limit = element.querySelector("[data-captcha-throttle-picker-target='limitCount']")
    const minutes = element.querySelector("[data-captcha-throttle-picker-target='periodMinutes']")
    limit.value = "50"
    minutes.value = "2"
    controller.apply()
    expect(submit).not.toHaveBeenCalled()
  })

  it("falls back to submit() when requestSubmit is missing", () => {
    const submit = vi.fn()
    element.requestSubmit = undefined
    element.submit = submit
    controller.presetTarget.value = "custom"
    element.querySelector("select").value = "100_per_5min"
    controller.choose()
    expect(submit).toHaveBeenCalledOnce()
  })

  it("treats non-positive custom numbers as incomplete", () => {
    const submit = vi.fn()
    element.requestSubmit = submit
    element.querySelector("select").value = "custom"
    controller.choose()
    const limit = element.querySelector("[data-captcha-throttle-picker-target='limitCount']")
    const minutes = element.querySelector("[data-captcha-throttle-picker-target='periodMinutes']")
    limit.value = "0"
    minutes.value = "2"
    controller.apply()
    expect(submit).not.toHaveBeenCalled()
  })

  it("prevents native submit while a custom rate is incomplete", () => {
    const preventDefault = vi.fn()
    element.querySelector("select").value = "custom"
    controller.choose()
    controller.guard({ preventDefault })
    expect(preventDefault).toHaveBeenCalledOnce()
  })

  it("allows native submit when a custom rate is complete", () => {
    const preventDefault = vi.fn()
    element.querySelector("select").value = "custom"
    controller.choose()
    element.querySelector("[data-captcha-throttle-picker-target='limitCount']").value = "50"
    element.querySelector("[data-captcha-throttle-picker-target='periodMinutes']").value = "2"
    controller.guard({ preventDefault })
    expect(preventDefault).not.toHaveBeenCalled()
  })

  it("allows native submit for a named preset", () => {
    const preventDefault = vi.fn()
    controller.guard({ preventDefault })
    expect(preventDefault).not.toHaveBeenCalled()
  })
})

describe("captcha-throttle-picker controller with a saved custom rate", () => {
  it("keeps custom fields closed until the rate text is clicked", async () => {
    const { application, element } = await mountController("captcha-throttle-picker", Controller, customHtml)
    const controller = controllerFor(application, element, "captcha-throttle-picker")
    const fields = element.querySelector("[data-captcha-throttle-picker-target='customFields']")
    expect(fields.hidden).toBe(true)
    controller.edit()
    expect(fields.hidden).toBe(false)
  })
})

describe("captcha-throttle-picker controller without optional targets", () => {
  it("no-ops choose when the preset input is missing", async () => {
    const { application, element } = await mountController(
      "captcha-throttle-picker",
      Controller,
      `<form data-controller="captcha-throttle-picker">
         <select data-captcha-throttle-picker-target="choice"><option value="100_per_5min">100</option></select>
       </form>`
    )
    const controller = controllerFor(application, element, "captcha-throttle-picker")
    const submit = vi.fn()
    element.requestSubmit = submit
    controller.choose()
    expect(submit).not.toHaveBeenCalled()
  })

  it("no-ops when optional targets are missing", async () => {
    const { application, element } = await mountController(
      "captcha-throttle-picker",
      Controller,
      `<form data-controller="captcha-throttle-picker"></form>`
    )
    const controller = controllerFor(application, element, "captcha-throttle-picker")
    const submit = vi.fn()
    element.requestSubmit = submit
    controller.choose()
    controller.apply()
    controller.guard()
    controller.edit()
    controller.collapse()
    controller.blurChoice()
    controller.escape()
    controller.showChoicePicker()
    expect(submit).not.toHaveBeenCalled()
    expect(controller.isCustom()).toBe(false)
    expect(controller.customComplete()).toBe(false)
    expect(controller.shouldShowCustom()).toBe(false)
  })

  it("submits skip when the skipped hidden field is absent", async () => {
    const { application, element } = await mountController(
      "captcha-throttle-picker",
      Controller,
      `<form data-controller="captcha-throttle-picker" data-captcha-throttle-picker-skip-value="skip">
         <input type="hidden" name="preset" value="100_per_5min" data-captcha-throttle-picker-target="preset">
         <select data-captcha-throttle-picker-target="choice"><option value="skip" selected>Skip</option></select>
       </form>`
    )
    const controller = controllerFor(application, element, "captcha-throttle-picker")
    const submit = vi.fn()
    element.requestSubmit = submit
    controller.choose()
    expect(submit).toHaveBeenCalledOnce()
    expect(controller.isCustom()).toBe(false)
  })

  it("shows custom fields without a display target when custom is selected", async () => {
    const { application, element } = await mountController(
      "captcha-throttle-picker",
      Controller,
      `<form data-controller="captcha-throttle-picker" data-captcha-throttle-picker-custom-value="custom">
         <input type="hidden" name="preset" value="custom" data-captcha-throttle-picker-target="preset">
         <select data-captcha-throttle-picker-target="choice"><option value="custom" selected>Custom</option></select>
         <div data-captcha-throttle-picker-target="customFields"></div>
       </form>`
    )
    const controller = controllerFor(application, element, "captcha-throttle-picker")
    expect(controller.shouldShowCustom()).toBe(true)
    expect(element.querySelector("[data-captcha-throttle-picker-target='customFields']").hidden).toBe(false)
    expect(element.querySelector("select").hidden).toBe(false)
  })
})
