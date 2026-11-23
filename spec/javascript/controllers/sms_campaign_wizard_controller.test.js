import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/sms_campaign_wizard_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

function wizardHtml({
  step = 1,
  total = 4,
  name = "Offer",
  timing = "immediate",
  scheduled = "2026-10-16T10:00",
  segment = "",
  segmentLabel = "VIP",
  template = "42",
  templateLabel = "Approved offer",
  includeSchedule = true,
  includeRadios = true,
  includeButtons = true,
  includeReview = true,
  includeName = true,
  includeSelects = true,
  templateControl = "select",
  values = true,
  hiddenRequired = false,
  nameMessage = "Name is required.",
  nameRequired = true
} = {}) {
  const valueAttrs = values ? `
    data-sms-campaign-wizard-current-step-value="${step}"
    data-sms-campaign-wizard-total-steps-value="${total}"
    data-sms-campaign-wizard-field-required-msg-value="Please complete this field to continue."
    data-sms-campaign-wizard-send-now-label-value="Send now"
    data-sms-campaign-wizard-em-dash-value="—"
    data-sms-campaign-wizard-all-contacts-label-value="All contacts"` : ""

  const schedule = includeSchedule ? `
    <div data-sms-campaign-wizard-target="scheduleFields" class="${timing === "scheduled" ? "" : "hidden"}">
      <input name="sms_campaign[scheduled_local]" value="${scheduled}" data-wizard-field data-wizard-required-msg="Set a scheduled time" data-sms-campaign-wizard-target="scheduledAt">
    </div>` : ""

  const steps = [1, 2, 3, 4].map((index) => {
    const hidden = index === Number(step) ? "" : "hidden"
    let body = ""
    if (index === 1) {
      body = `
        ${includeName ? `<input name="sms_campaign[name]" value="${name}" ${nameRequired ? "required" : ""} data-wizard-field ${nameMessage ? `data-wizard-required-msg="${nameMessage}"` : ""}>` : ""}
        ${hiddenRequired ? `<div class="hidden"><input required data-wizard-field value=""></div>` : ""}
        <div data-wizard-field-group><input data-wizard-field data-group-field value="kept"></div>`
    } else if (index === 3) {
      body = schedule
    }
    return `<div data-sms-campaign-wizard-target="step" data-step-index="${index}" class="${hidden}" aria-hidden="${hidden ? "true" : "false"}">${body}</div>`
  }).join("")

  const progress = [1, 2, 3, 4].map((index) => `
    <div data-sms-campaign-wizard-target="stepIndicator" data-step-index="${index}"></div>
    <span data-sms-campaign-wizard-target="stepBadge" data-step-index="${index}" class="bg-surface-active text-text-muted"></span>
    <span data-sms-campaign-wizard-target="stepNumber" data-step-index="${index}">${index}</span>
    <svg data-sms-campaign-wizard-target="stepCheck" data-step-index="${index}" class="hidden"></svg>
    <span data-sms-campaign-wizard-target="stepLabel" data-step-index="${index}" class="text-text-muted font-medium">Step</span>
    ${index < 4 ? `<div data-sms-campaign-wizard-target="stepConnector" data-step-index="${index}" class="bg-border"></div>` : ""}
  `).join("")

  const radios = includeRadios ? `
    <input type="radio" name="sms_campaign[send_timing]" value="immediate" data-sms-campaign-wizard-target="timingRadio" ${timing === "immediate" ? "checked" : ""}>
    <input type="radio" name="sms_campaign[send_timing]" value="scheduled" data-sms-campaign-wizard-target="timingRadio" ${timing === "scheduled" ? "checked" : ""}>` : ""

  const selects = includeSelects ? `
    <select name="sms_campaign[segment_id]">
      <option value="">All contacts</option>
      <option value="7" ${segment === "7" ? "selected" : ""}>${segmentLabel}</option>
    </select>
    ${templateControl === "select" ? `
      <select name="sms_campaign[template_id]">
        <option value="">Choose</option>
        <option value="42" ${template === "42" ? "selected" : ""}>${templateLabel}</option>
        <option value="9">   </option>
      </select>` : `<input name="sms_campaign[template_id]" value="${template}">`}` : ""

  const review = includeReview ? `
    <dd data-sms-campaign-wizard-target="reviewName"></dd>
    <dd data-sms-campaign-wizard-target="reviewAudience"></dd>
    <dd data-sms-campaign-wizard-target="reviewTemplate"></dd>
    <dd data-sms-campaign-wizard-target="reviewSchedule"></dd>` : ""

  const buttons = includeButtons ? `
    <a data-sms-campaign-wizard-target="cancelButton" class="${step === 1 ? "" : "hidden"}">Cancel</a>
    <button type="button" data-sms-campaign-wizard-target="prevButton" class="${step === 1 ? "hidden" : ""}">Back</button>
    <button type="button" data-sms-campaign-wizard-target="nextButton" class="${step === total ? "hidden" : ""}">Continue</button>
    <button type="submit" data-sms-campaign-wizard-target="saveButton" class="${step === total ? "" : "hidden"}">Save</button>
    <button type="submit" data-sms-campaign-wizard-target="previewButton" class="${step === total ? "" : "hidden"}">Preview</button>` : ""

  return `<form data-controller="sms-campaign-wizard" ${valueAttrs}>
    ${progress}
    ${steps}
    ${radios}
    ${selects}
    ${review}
    ${buttons}
  </form>`
}

async function mount(options = {}) {
  const html = wizardHtml(options)
  const mounted = await mountController("sms-campaign-wizard", Controller, html)
  const controller = controllerFor(mounted.application, mounted.element, "sms-campaign-wizard")
  return { ...mounted, controller }
}

describe("sms-campaign-wizard", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("shows the current step and progress states", async () => {
    const { element } = await mount({ step: 2 })
    const steps = element.querySelectorAll("[data-sms-campaign-wizard-target='step']")
    expect(steps[0].classList.contains("hidden")).toBe(true)
    expect(steps[1].classList.contains("hidden")).toBe(false)
    expect(steps[1].getAttribute("aria-hidden")).toBe("false")
    expect(element.querySelector("[data-step-index='2'][data-sms-campaign-wizard-target='stepIndicator']").getAttribute("aria-current")).toBe("step")
    expect(element.querySelector("[data-step-index='1'][data-sms-campaign-wizard-target='stepIndicator']").hasAttribute("aria-current")).toBe(false)
    expect(element.querySelector("[data-step-index='1'][data-sms-campaign-wizard-target='stepBadge']").classList.contains("bg-accent")).toBe(true)
    expect(element.querySelector("[data-step-index='2'][data-sms-campaign-wizard-target='stepBadge']").classList.contains("ring-4")).toBe(true)
    expect(element.querySelector("[data-step-index='3'][data-sms-campaign-wizard-target='stepBadge']").classList.contains("bg-surface-active")).toBe(true)
    expect(element.querySelector("[data-step-index='1'][data-sms-campaign-wizard-target='stepNumber']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-step-index='1'][data-sms-campaign-wizard-target='stepCheck']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-step-index='2'][data-sms-campaign-wizard-target='stepLabel']").classList.contains("text-accent")).toBe(true)
    expect(element.querySelector("[data-step-index='1'][data-sms-campaign-wizard-target='stepConnector']").classList.contains("bg-accent")).toBe(true)
    expect(element.querySelector("[data-step-index='2'][data-sms-campaign-wizard-target='stepConnector']").classList.contains("bg-border")).toBe(true)
    expect(element.querySelector("[data-sms-campaign-wizard-target='cancelButton']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-sms-campaign-wizard-target='prevButton']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-sms-campaign-wizard-target='nextButton']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-sms-campaign-wizard-target='saveButton']").classList.contains("hidden")).toBe(true)
  })

  it("blocks continue until the current step is complete, then advances", async () => {
    const { element, controller } = await mount({ name: "" })
    const prevented = vi.fn()
    controller.next({ preventDefault: prevented })
    expect(prevented).toHaveBeenCalled()
    expect(controller.currentStepValue).toBe(1)
    expect(element.querySelector(".wizard-field-error").textContent).toBe("Name is required.")
    expect(element.querySelector("[name='sms_campaign[name]']").classList.contains("border-danger")).toBe(true)

    element.querySelector("[name='sms_campaign[name]']").value = "Offer"
    const grouped = element.querySelector("[data-group-field]")
    grouped.required = true
    grouped.value = ""
    controller.next({})
    expect(controller.currentStepValue).toBe(1)
    expect(grouped.closest("[data-wizard-field-group]").querySelector(".wizard-field-error")).not.toBeNull()
    grouped.value = "kept"
    controller.next({})
    expect(controller.currentStepValue).toBe(2)
    expect(element.querySelector(".wizard-field-error")).toBeNull()
    expect(element.querySelector("[name='sms_campaign[name]']").classList.contains("border-danger")).toBe(false)
  })

  it("uses the fallback required message and ignores hidden fields", async () => {
    const { element, controller } = await mount({ name: "   ", nameMessage: "", hiddenRequired: true })
    controller.next()
    expect(element.querySelector(".wizard-field-error").textContent).toBe("Please complete this field to continue.")
    expect(controller.currentStepValue).toBe(1)
    element.querySelector("[name='sms_campaign[name]']").value = "Offer"
    controller.next()
    expect(controller.currentStepValue).toBe(2)
  })

  it("requires a time only for scheduled sends and can return to the previous step", async () => {
    const { element, controller } = await mount({ step: 3, timing: "scheduled", scheduled: "" })
    const prevented = vi.fn()
    controller.next({ preventDefault: prevented })
    expect(controller.currentStepValue).toBe(3)
    expect(element.querySelector(".wizard-field-error").textContent).toBe("Set a scheduled time")

    element.querySelector("[name='sms_campaign[scheduled_local]']").value = "2026-10-16T10:00"
    controller.next({ preventDefault: prevented })
    expect(controller.currentStepValue).toBe(4)
    await tick()
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewSchedule']").textContent).toBe("2026-10-16T10:00")
    expect(element.querySelector("[data-sms-campaign-wizard-target='saveButton']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-sms-campaign-wizard-target='previewButton']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-sms-campaign-wizard-target='nextButton']").classList.contains("hidden")).toBe(true)

    controller.previous({ preventDefault: prevented })
    expect(controller.currentStepValue).toBe(3)
    controller.previous()
    expect(prevented).toHaveBeenCalled()
  })

  it("clears a scheduled time when the send is immediate", async () => {
    const { element, controller } = await mount({ step: 3, timing: "scheduled", scheduled: "" })
    controller.next()
    expect(element.querySelector(".wizard-field-error")).not.toBeNull()
    element.querySelector("[value='immediate']").checked = true
    element.querySelector("[value='scheduled']").checked = false
    controller.timingChanged()
    const when = element.querySelector("[name='sms_campaign[scheduled_local]']")
    expect(when.value).toBe("")
    expect(when.required).toBe(false)
    expect(element.querySelector("[data-sms-campaign-wizard-target='scheduleFields']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector(".wizard-field-error")).toBeNull()
    controller.next()
    expect(controller.currentStepValue).toBe(4)
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewSchedule']").textContent).toBe("Send now")
  })

  it("summarizes blank audience, a chosen template, and an input fallback", async () => {
    const { element, controller } = await mount({
      name: "Offer",
      segment: "",
      template: "42",
      templateLabel: "Approved offer"
    })
    controller.currentStepValue = 4
    controller.refreshReview()
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewName']").textContent).toBe("Offer")
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewAudience']").textContent).toBe("All contacts")
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewTemplate']").textContent).toBe("Approved offer")

    const template = element.querySelector("[name='sms_campaign[template_id]']")
    template.value = "9"
    controller.refreshReview()
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewTemplate']").textContent).toBe("9")

    element.querySelector("[name='sms_campaign[name]']").value = ""
    controller.refreshReview()
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewName']").textContent).toBe("—")
  })

  it("refreshes the review when the wizard opens on the last step", async () => {
    const { element } = await mount({ step: 4, segment: "7", segmentLabel: "VIP", template: "42" })
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewAudience']").textContent).toBe("VIP")
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewTemplate']").textContent).toBe("Approved offer")
  })

  it("does not move past the last step and does not leave the first step", async () => {
    const { controller } = await mount({ step: 4, name: "Offer" })
    controller.next({ preventDefault() {} })
    expect(controller.currentStepValue).toBe(4)
    controller.previous({ preventDefault() {} })
    expect(controller.currentStepValue).toBe(3)
    controller.currentStepValue = 1
    controller.previous({ preventDefault() {} })
    expect(controller.currentStepValue).toBe(1)
  })

  it("treats a missing step, missing radios, and missing targets as safe defaults", async () => {
    const { element, controller } = await mount({
      includeSchedule: false,
      includeRadios: false,
      includeButtons: false,
      includeReview: false,
      includeName: false,
      includeSelects: false,
      values: false
    })
    expect(controller.selectedTiming()).toBe("immediate")
    controller.applyTiming()
    controller.refreshReview()
    controller.currentStepValue = 9
    expect(controller.validateCurrentStep()).toBe(true)
    controller.next()
    expect(controller.currentStepValue).toBe(9)
    expect(element.querySelector("[data-sms-campaign-wizard-target='step']")).not.toBeNull()
  })

  it("uses default labels when stimulus values and choice controls are absent", async () => {
    const { element, controller } = await mount({
      step: 4,
      values: false,
      includeName: false,
      includeSelects: false,
      includeSchedule: false,
      timing: "scheduled"
    })
    controller.refreshReview()
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewName']").textContent).toBe("—")
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewAudience']").textContent).toBe("All contacts")
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewTemplate']").textContent).toBe("—")
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewSchedule']").textContent).toBe("Send now")
  })

  it("reads a non-select choice and an unchecked timing group", async () => {
    const { element, controller } = await mount({
      templateControl: "input",
      template: "literal-id",
      includeRadios: true,
      timing: "none"
    })
    element.querySelectorAll("[data-sms-campaign-wizard-target='timingRadio']").forEach((radio) => {
      radio.checked = false
    })
    expect(controller.selectedTiming()).toBe("immediate")
    controller.refreshReview()
    expect(element.querySelector("[data-sms-campaign-wizard-target='reviewTemplate']").textContent).toBe("literal-id")
  })

  it("keeps scheduled fields when a scheduled time is already chosen", async () => {
    const { element, controller } = await mount({ timing: "scheduled", scheduled: "2026-10-16T10:00" })
    controller.applyTiming()
    const when = element.querySelector("[name='sms_campaign[scheduled_local]']")
    expect(when.required).toBe(true)
    expect(when.value).toBe("2026-10-16T10:00")
    expect(element.querySelector("[data-sms-campaign-wizard-target='scheduleFields']").classList.contains("hidden")).toBe(false)
  })

  beforeEach(() => {
    document.body.innerHTML = ""
  })
})
