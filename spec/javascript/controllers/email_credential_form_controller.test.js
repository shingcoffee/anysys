import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/email_credential_form_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const LABELS = { smtp: "Password", ses: "Secret Access Key" }

// NOTE: mounted on a <div> rather than the real <form> markup — see
// billing_coupon_form_controller.test.js / sms_credential_form_controller.test.js
// for why (happy-dom's HTMLFormElement.contains() always returns false for
// descendants, which blocks Stimulus action binding for any action inside a
// <form data-controller="..."> root in this environment). The controller
// itself is tag-agnostic; production markup renders a real <form>.
//
// The provider <select> intentionally does NOT carry a Stimulus target
// (co-locating a data-*-target and data-action on the same element is also
// unreliable under happy-dom); the initial provider comes from the
// `provider` Value and subsequent changes come from the change event's own
// target.
const html = (selected = "smtp", labels = LABELS, { secretRequired = true, dkimEnabled = false } = {}) => `
  <div data-controller="email-credential-form"
        data-email-credential-form-provider-value="${selected}"
        data-email-credential-form-labels-value='${JSON.stringify(labels)}'
        data-email-credential-form-secret-required-value="${secretRequired}">
    <label data-email-credential-form-target="secretLabel" class="form-label">Password</label>
    <input data-email-credential-form-target="secretInput" type="password">
    <select data-action="change->email-credential-form#toggle" data-role="provider">
      <option value="smtp" ${selected === "smtp" ? "selected" : ""}>SMTP</option>
      <option value="ses" ${selected === "ses" ? "selected" : ""}>AWS SES</option>
    </select>
    <div data-email-credential-form-target="fields" data-provider="smtp">
      <input name="emails_credential[host]" data-email-credential-form-target="requiredWhenVisible">
      <input type="checkbox" data-email-credential-form-target="dkimEnabled"
             data-action="change->email-credential-form#toggleDkim"
             ${dkimEnabled ? "checked" : ""}>
      <label data-email-credential-form-target="dkimLabel" class="form-label">DKIM domain</label>
      <input data-email-credential-form-target="dkimRequired" name="emails_credential[dkim_domain]">
      <label data-email-credential-form-target="dkimKeyLabel" class="form-label">DKIM key</label>
      <textarea data-email-credential-form-target="dkimKeyInput" name="emails_credential[dkim_private_key]"></textarea>
    </div>
    <div data-email-credential-form-target="fields" data-provider="ses">
      <input name="emails_credential[from_email]" data-email-credential-form-target="requiredWhenVisible">
    </div>
  </div>`

const fieldsFor = (element, provider) =>
  element.querySelector(`[data-email-credential-form-target="fields"][data-provider="${provider}"]`)

const change = (select, value) => {
  select.value = value
  select.dispatchEvent(new Event("change", { bubbles: true }))
}

describe("email-credential-form controller", () => {
  let application, element, ctrl

  beforeEach(async () => {
    ;({ application, element } = await mountController("email-credential-form", Controller, html()))
    ctrl = controllerFor(application, element, "email-credential-form")
  })

  it("shows only the initially-selected provider's field group on connect", () => {
    expect(fieldsFor(element, "smtp").classList.contains("hidden")).toBe(false)
    expect(fieldsFor(element, "ses").classList.contains("hidden")).toBe(true)
  })

  it("applies the selected provider's secret label on connect", () => {
    expect(element.querySelector('[data-email-credential-form-target="secretLabel"]').textContent)
      .toBe("Password")
  })

  it("marks visible provider required fields and clears required on hidden groups", () => {
    const host = element.querySelector("[name='emails_credential[host]']")
    const from = element.querySelector("[name='emails_credential[from_email]']")
    expect(host.required).toBe(true)
    expect(from.required).toBe(false)
    expect(host.disabled).toBe(false)
    expect(from.disabled).toBe(true)

    change(element.querySelector("[data-role='provider']"), "ses")

    expect(host.required).toBe(false)
    expect(from.required).toBe(true)
    expect(host.disabled).toBe(true)
    expect(from.disabled).toBe(false)
  })

  it("requires the secret on new credentials and marks the label", () => {
    const secret = element.querySelector('[data-email-credential-form-target="secretInput"]')
    const label = element.querySelector('[data-email-credential-form-target="secretLabel"]')
    expect(secret.required).toBe(true)
    expect(label.classList.contains("form-label-required")).toBe(true)
  })

  it("toggles field groups and the secret label when the provider select changes", () => {
    change(element.querySelector("[data-role='provider']"), "ses")

    expect(fieldsFor(element, "smtp").classList.contains("hidden")).toBe(true)
    expect(fieldsFor(element, "ses").classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-email-credential-form-target="secretLabel"]').textContent)
      .toBe("Secret Access Key")
  })

  it("starting from ses, switching back to smtp restores its group and label", async () => {
    const { element: el2 } = await mountController("email-credential-form", Controller, html("ses"))
    expect(fieldsFor(el2, "ses").classList.contains("hidden")).toBe(false)
    expect(fieldsFor(el2, "smtp").classList.contains("hidden")).toBe(true)

    change(el2.querySelector("[data-role='provider']"), "smtp")

    expect(fieldsFor(el2, "ses").classList.contains("hidden")).toBe(true)
    expect(fieldsFor(el2, "smtp").classList.contains("hidden")).toBe(false)
    expect(el2.querySelector('[data-email-credential-form-target="secretLabel"]').textContent)
      .toBe("Password")
  })

  it("apply() is idempotent when called directly (e.g. connect)", () => {
    ctrl.apply("smtp")
    expect(fieldsFor(element, "smtp").classList.contains("hidden")).toBe(false)
  })

  describe("DKIM required toggling", () => {
    it("does not require DKIM fields when DKIM is off", () => {
      const domain = element.querySelector("[name='emails_credential[dkim_domain]']")
      expect(domain.required).toBe(false)
      expect(element.querySelector('[data-email-credential-form-target="dkimLabel"]')
        .classList.contains("form-label-required")).toBe(false)
    })

    it("requires DKIM domain/selector and key on new records when DKIM is enabled", async () => {
      const { element: el } = await mountController(
        "email-credential-form", Controller, html("smtp", LABELS, { secretRequired: true, dkimEnabled: true })
      )
      const domain = el.querySelector("[name='emails_credential[dkim_domain]']")
      const key = el.querySelector("[name='emails_credential[dkim_private_key]']")
      expect(domain.required).toBe(true)
      expect(key.required).toBe(true)
      expect(el.querySelector('[data-email-credential-form-target="dkimLabel"]')
        .classList.contains("form-label-required")).toBe(true)
      expect(el.querySelector('[data-email-credential-form-target="dkimKeyLabel"]')
        .classList.contains("form-label-required")).toBe(true)
    })

    it("requires DKIM domain but not key on edit when DKIM is enabled (blank-keep)", async () => {
      const { element: el } = await mountController(
        "email-credential-form", Controller, html("smtp", LABELS, { secretRequired: false, dkimEnabled: true })
      )
      expect(el.querySelector("[name='emails_credential[dkim_domain]']").required).toBe(true)
      expect(el.querySelector("[name='emails_credential[dkim_private_key]']").required).toBe(false)
      expect(el.querySelector('[data-email-credential-form-target="dkimKeyLabel"]')
        .classList.contains("form-label-required")).toBe(false)
    })

    it("toggleDkim updates required state from the checkbox", () => {
      const checkbox = element.querySelector('[data-email-credential-form-target="dkimEnabled"]')
      const domain = element.querySelector("[name='emails_credential[dkim_domain]']")
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      expect(domain.required).toBe(true)

      checkbox.checked = false
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
      expect(domain.required).toBe(false)
    })

    it("clears DKIM required when switching away from SMTP", async () => {
      const { element: el } = await mountController(
        "email-credential-form", Controller, html("smtp", LABELS, { dkimEnabled: true })
      )
      change(el.querySelector("[data-role='provider']"), "ses")
      expect(el.querySelector("[name='emails_credential[dkim_domain]']").required).toBe(false)
    })
  })

  describe("guard clauses when optional targets/values are absent", () => {
    it("applyLabel no-ops when there is no label mapping for the selected provider", async () => {
      const { element: el3 } = await mountController(
        "email-credential-form", Controller,
        html("smtp", { ses: LABELS.ses })
      )
      // Falls back to the server-rendered default text since no "smtp" entry exists.
      expect(el3.querySelector('[data-email-credential-form-target="secretLabel"]').textContent)
        .toBe("Password")
    })

    it("connect() degrades gracefully without a provider Value (empty string default)", async () => {
      const { element: el4 } = await mountController(
        "email-credential-form", Controller,
        `<div data-controller="email-credential-form" data-email-credential-form-labels-value='{}'>
           <div data-email-credential-form-target="fields" data-provider="smtp"></div>
         </div>`
      )
      expect(fieldsFor(el4, "smtp").classList.contains("hidden")).toBe(true)
    })

    it("applyLabel no-ops without a secretLabel target", async () => {
      const { application: app5, element: el5 } = await mountController(
        "email-credential-form", Controller,
        `<div data-controller="email-credential-form"
               data-email-credential-form-provider-value="smtp"
               data-email-credential-form-labels-value='${JSON.stringify(LABELS)}'>
         </div>`
      )
      const c5 = controllerFor(app5, el5, "email-credential-form")
      expect(() => c5.apply("smtp")).not.toThrow()
    })

    it("does not require the secret when secretRequired is false", async () => {
      const { element: el } = await mountController(
        "email-credential-form", Controller, html("smtp", LABELS, { secretRequired: false })
      )
      expect(el.querySelector('[data-email-credential-form-target="secretInput"]').required).toBe(false)
      expect(el.querySelector('[data-email-credential-form-target="secretLabel"]')
        .classList.contains("form-label-required")).toBe(false)
    })
  })
})
