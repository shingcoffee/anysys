import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/sms_credential_form_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const LABELS = {
  aliyun: { access_key_id: "Access Key ID", access_key_secret: "Access Key Secret" },
  twilio: { access_key_id: "Account SID", access_key_secret: "Auth Token" }
}

// NOTE: mounted on a <div> rather than the real <form> markup — see
// billing_coupon_form_controller.test.js for why (happy-dom's
// HTMLFormElement.contains() always returns false for descendants, which
// blocks Stimulus action binding for any action inside a <form
// data-controller="..."> root in this environment). The controller itself is
// tag-agnostic; production markup renders a real <form>.
//
// The provider <select> intentionally does NOT carry a Stimulus target
// (co-locating a data-*-target and data-action on the same element is also
// unreliable under happy-dom); the initial provider comes from the
// `provider` Value and subsequent changes come from the change event's own
// target.
const html = (selected = "aliyun", labels = LABELS) => `
  <div data-controller="sms-credential-form"
        data-sms-credential-form-provider-value="${selected}"
        data-sms-credential-form-labels-value='${JSON.stringify(labels)}'>
    <label data-sms-credential-form-target="accessKeyIdLabel">Access Key ID</label>
    <label data-sms-credential-form-target="accessKeySecretLabel">Access Key Secret</label>
    <select data-action="change->sms-credential-form#toggle" data-role="provider">
      <option value="aliyun" ${selected === "aliyun" ? "selected" : ""}>Aliyun SMS</option>
      <option value="twilio" ${selected === "twilio" ? "selected" : ""}>Twilio</option>
    </select>
    <div data-sms-credential-form-target="fields" data-provider="aliyun">
      <input name="sms_credential[sign_name]">
    </div>
    <div data-sms-credential-form-target="fields" data-provider="twilio">
      <input name="sms_credential[messaging_service_sid]">
    </div>
  </div>`

const fieldsFor = (element, provider) =>
  element.querySelector(`[data-sms-credential-form-target="fields"][data-provider="${provider}"]`)

const change = (select, value) => {
  select.value = value
  select.dispatchEvent(new Event("change", { bubbles: true }))
}

describe("sms-credential-form controller", () => {
  let application, element, ctrl

  beforeEach(async () => {
    ;({ application, element } = await mountController("sms-credential-form", Controller, html()))
    ctrl = controllerFor(application, element, "sms-credential-form")
  })

  it("shows only the initially-selected provider's field group on connect", () => {
    expect(fieldsFor(element, "aliyun").classList.contains("hidden")).toBe(false)
    expect(fieldsFor(element, "twilio").classList.contains("hidden")).toBe(true)
  })

  it("applies the selected provider's credential labels on connect", () => {
    expect(element.querySelector('[data-sms-credential-form-target="accessKeyIdLabel"]').textContent)
      .toBe("Access Key ID")
    expect(element.querySelector('[data-sms-credential-form-target="accessKeySecretLabel"]').textContent)
      .toBe("Access Key Secret")
  })

  it("toggles field groups and labels when the provider select changes", () => {
    change(element.querySelector("[data-role='provider']"), "twilio")

    expect(fieldsFor(element, "aliyun").classList.contains("hidden")).toBe(true)
    expect(fieldsFor(element, "twilio").classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-sms-credential-form-target="accessKeyIdLabel"]').textContent)
      .toBe("Account SID")
    expect(element.querySelector('[data-sms-credential-form-target="accessKeySecretLabel"]').textContent)
      .toBe("Auth Token")
  })

  it("starting from twilio, switching back to aliyun restores its group and labels", async () => {
    const { element: el2 } = await mountController("sms-credential-form", Controller, html("twilio"))
    expect(fieldsFor(el2, "twilio").classList.contains("hidden")).toBe(false)
    expect(fieldsFor(el2, "aliyun").classList.contains("hidden")).toBe(true)

    change(el2.querySelector("[data-role='provider']"), "aliyun")

    expect(fieldsFor(el2, "twilio").classList.contains("hidden")).toBe(true)
    expect(fieldsFor(el2, "aliyun").classList.contains("hidden")).toBe(false)
    expect(el2.querySelector('[data-sms-credential-form-target="accessKeyIdLabel"]').textContent)
      .toBe("Access Key ID")
  })

  it("apply() is idempotent when called directly (e.g. connect)", () => {
    ctrl.apply("aliyun")
    expect(fieldsFor(element, "aliyun").classList.contains("hidden")).toBe(false)
  })

  describe("guard clauses when optional targets/values are absent", () => {
    it("applyLabels no-ops when there is no label mapping for the selected provider", async () => {
      const { element: el3 } = await mountController(
        "sms-credential-form", Controller,
        html("aliyun", { twilio: LABELS.twilio })
      )
      // Falls back to the server-rendered default text since no "aliyun" entry exists.
      expect(el3.querySelector('[data-sms-credential-form-target="accessKeyIdLabel"]').textContent)
        .toBe("Access Key ID")
    })

    it("connect() degrades gracefully without a provider Value (empty string default)", async () => {
      const { element: el4 } = await mountController(
        "sms-credential-form", Controller,
        `<div data-controller="sms-credential-form" data-sms-credential-form-labels-value='{}'>
           <div data-sms-credential-form-target="fields" data-provider="aliyun"></div>
         </div>`
      )
      expect(fieldsFor(el4, "aliyun").classList.contains("hidden")).toBe(true)
    })

    it("applyLabels no-ops without accessKeyIdLabel/accessKeySecretLabel targets", async () => {
      const { application: app5, element: el5 } = await mountController(
        "sms-credential-form", Controller,
        `<div data-controller="sms-credential-form"
               data-sms-credential-form-provider-value="aliyun"
               data-sms-credential-form-labels-value='${JSON.stringify(LABELS)}'>
         </div>`
      )
      const c5 = controllerFor(app5, el5, "sms-credential-form")
      expect(() => c5.apply("aliyun")).not.toThrow()
    })
  })
})
