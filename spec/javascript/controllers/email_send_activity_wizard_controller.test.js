import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/email_send_activity_wizard_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

function listSelect(element) {
  return element.querySelector("[data-email-send-activity-wizard-target='listSelect']")
}

function selectListIds(element, ids, ctrl = null) {
  // Clear existing chips then add each id via the chip picker.
  const container = element.querySelector("[data-email-send-activity-wizard-target='listsContainer']")
  container.innerHTML = ""
  Array.from(listSelect(element).options).forEach((option) => { option.disabled = false })
  const controller = ctrl || null
  ids.forEach((id) => {
    const select = listSelect(element)
    select.value = String(id)
    if (controller) {
      controller.addList({ preventDefault: () => {} })
    } else {
      // Direct chip injection for tests that run before controller wiring is needed
      const option = select.querySelector(`option[value="${id}"]`)
      const label = option?.textContent?.trim() || String(id)
      container.insertAdjacentHTML("beforeend", `
        <div data-list-item data-list-id="${id}" class="inline-flex items-center gap-1">
          <input type="hidden" name="email_send_activity[email_list_ids][]" value="${id}">
          <span>${label}</span>
          <button type="button" data-action="click->email-send-activity-wizard#removeList">x</button>
        </div>
      `)
      if (option) option.disabled = true
      select.value = ""
    }
  })
  return container
}


const html = () => `
  <form data-controller="email-send-activity-wizard"
        data-email-send-activity-wizard-current-step-value="1"
        data-email-send-activity-wizard-total-steps-value="4"
        data-email-send-activity-wizard-field-required-msg-value="Please complete this field to continue."
        data-email-send-activity-wizard-timing-required-msg-value="Choose Send now or Schedule at to continue."
        data-email-send-activity-wizard-send-now-label-value="Send immediately"
        data-email-send-activity-wizard-lists-url-value="/lists.json"
        data-email-send-activity-wizard-templates-url-value="/templates.json"
        data-email-send-activity-wizard-select-list-blank-value="— select list —"
        data-email-send-activity-wizard-select-template-blank-value="— select template —"
        data-email-send-activity-wizard-refresh-lists-error-value="We couldn't refresh the lists. Please try again."
        data-email-send-activity-wizard-refresh-templates-error-value="We couldn't refresh the templates. Please try again."
        data-email-send-activity-wizard-max-lists-value="10"
        data-email-send-activity-wizard-lists-too-many-msg-value="Select at most 10 lists to continue."
        data-email-send-activity-wizard-remove-list-label-value="Remove list">
    <div data-email-send-activity-wizard-target="step" data-step="audience" data-step-index="1">
      <div data-wizard-field-group
           data-wizard-field="lists"
           data-wizard-required-msg="Select an email list to continue."
           data-wizard-max="10"
           data-wizard-max-msg="Select at most 10 lists to continue."
           data-email-send-activity-wizard-target="listsFieldGroup">
        <div data-email-send-activity-wizard-target="listsContainer"
             class="flex flex-wrap gap-1.5 min-h-[2rem] p-1.5 rounded-lg border"></div>
        <select data-email-send-activity-wizard-target="listSelect" class="input-field">
          <option value="">— select list —</option>
          <option value="1">List A</option>
          <option value="2">List B</option>
          <option value="3">List C</option>
          <option value="4">List D</option>
          <option value="5">List E</option>
          <option value="6">List F</option>
          <option value="7">List G</option>
          <option value="8">List H</option>
          <option value="9">List I</option>
          <option value="10">List J</option>
          <option value="11">List K</option>
        </select>
        <button type="button" data-email-send-activity-wizard-target="addListButton"
                data-action="email-send-activity-wizard#addList">Add</button>
        <button type="button" data-email-send-activity-wizard-target="refreshListsButton"
                data-action="email-send-activity-wizard#refreshLists">Refresh</button>
      </div>
    </div>
    <div class="hidden" data-email-send-activity-wizard-target="step" data-step="content" data-step-index="2">
      <div data-wizard-field-group>
        <select name="email_send_activity[email_template_id]" required data-wizard-field
                data-wizard-required-msg="Select an email template to continue."
                data-email-send-activity-wizard-target="templateSelect">
          <option value="">—</option>
          <option value="2">Template B</option>
        </select>
        <button type="button" data-email-send-activity-wizard-target="refreshTemplatesButton"
                data-action="email-send-activity-wizard#refreshTemplates">Refresh</button>
      </div>
    </div>
    <div class="hidden" data-email-send-activity-wizard-target="step" data-step="schedule" data-step-index="3">
      <div data-wizard-field-group>
        <input name="email_send_activity[name]" required data-wizard-field
               data-wizard-required-msg="Enter a name for this send activity." value="">
      </div>
      <fieldset data-wizard-field-group
                data-wizard-required-msg="Choose Send now or Schedule at to continue."
                data-email-send-activity-wizard-target="timingGroup">
        <input type="radio" name="email_send_activity[send_timing]" value="now" checked
               data-email-send-activity-wizard-target="timingRadio"
               data-action="email-send-activity-wizard#timingChanged">
        <input type="radio" name="email_send_activity[send_timing]" value="later"
               data-email-send-activity-wizard-target="timingRadio"
               data-action="email-send-activity-wizard#timingChanged">
      </fieldset>
      <div class="hidden" data-wizard-field-group data-email-send-activity-wizard-target="scheduleFields">
        <input type="datetime-local" name="email_send_activity[scheduled_at]"
               data-wizard-field
               data-wizard-required-msg="Choose a date and time, or select Send now."
               data-email-send-activity-wizard-target="scheduledAt">
      </div>
      <div class="hidden" data-wizard-field-group data-email-send-activity-wizard-target="timezoneFields">
        <select name="email_send_activity[timezone]" data-wizard-field
                data-email-send-activity-wizard-target="timezoneSelect">
          <option value="UTC" selected>UTC</option>
          <option value="America/New_York">Eastern</option>
        </select>
      </div>
      <select name="email_send_activity[recurrence_preset]"
              data-email-send-activity-wizard-target="recurrenceSelect"
              data-action="email-send-activity-wizard#recurrenceChanged">
        <option value="none" selected>None</option>
        <option value="daily">Daily</option>
      </select>
    </div>
    <div class="hidden" data-email-send-activity-wizard-target="step" data-step="review" data-step-index="4">
      <span data-email-send-activity-wizard-target="reviewName"></span>
      <span data-email-send-activity-wizard-target="reviewList"></span>
      <span data-email-send-activity-wizard-target="reviewTemplate"></span>
      <span data-email-send-activity-wizard-target="reviewSchedule"></span>
      <div data-email-send-activity-wizard-target="reviewTimezoneRow">
        <span data-email-send-activity-wizard-target="reviewTimezone"></span>
      </div>
      <span data-email-send-activity-wizard-target="reviewRecurrence"></span>
    </div>
    <a data-email-send-activity-wizard-target="cancelButton">Cancel</a>
    <button type="button" class="hidden" data-email-send-activity-wizard-target="prevButton"
            data-action="email-send-activity-wizard#previous">Back</button>
    <button type="button" data-email-send-activity-wizard-target="nextButton"
            data-action="email-send-activity-wizard#next">Continue</button>
    <button type="submit" class="hidden" data-email-send-activity-wizard-target="submitButton">Create</button>
    <div data-email-send-activity-wizard-target="stepIndicator" data-step-index="1">
      <span data-email-send-activity-wizard-target="stepBadge" data-step-index="1">
        <span data-email-send-activity-wizard-target="stepNumber" data-step-index="1">1</span>
        <svg data-email-send-activity-wizard-target="stepCheck" data-step-index="1" class="hidden"></svg>
      </span>
      <span data-email-send-activity-wizard-target="stepLabel" data-step-index="1">Audience</span>
    </div>
    <div data-email-send-activity-wizard-target="stepConnector" data-step-index="1" class="bg-border"></div>
    <div data-email-send-activity-wizard-target="stepIndicator" data-step-index="2">
      <span data-email-send-activity-wizard-target="stepBadge" data-step-index="2">
        <span data-email-send-activity-wizard-target="stepNumber" data-step-index="2">2</span>
        <svg data-email-send-activity-wizard-target="stepCheck" data-step-index="2" class="hidden"></svg>
      </span>
      <span data-email-send-activity-wizard-target="stepLabel" data-step-index="2">Content</span>
    </div>
    <div data-email-send-activity-wizard-target="stepConnector" data-step-index="2" class="bg-border"></div>
    <div data-email-send-activity-wizard-target="stepIndicator" data-step-index="3">
      <span data-email-send-activity-wizard-target="stepBadge" data-step-index="3">
        <span data-email-send-activity-wizard-target="stepNumber" data-step-index="3">3</span>
        <svg data-email-send-activity-wizard-target="stepCheck" data-step-index="3" class="hidden"></svg>
      </span>
      <span data-email-send-activity-wizard-target="stepLabel" data-step-index="3">Schedule</span>
    </div>
    <div data-email-send-activity-wizard-target="stepConnector" data-step-index="3" class="bg-border"></div>
    <div data-email-send-activity-wizard-target="stepIndicator" data-step-index="4">
      <span data-email-send-activity-wizard-target="stepBadge" data-step-index="4">
        <span data-email-send-activity-wizard-target="stepNumber" data-step-index="4">4</span>
        <svg data-email-send-activity-wizard-target="stepCheck" data-step-index="4" class="hidden"></svg>
      </span>
      <span data-email-send-activity-wizard-target="stepLabel" data-step-index="4">Review</span>
    </div>
  </form>
`

const visible = (el) =>
  [...el.querySelectorAll("[data-email-send-activity-wizard-target='step']")].map(
    (s) => !s.classList.contains("hidden")
  )

const inlineError = (el) => el.querySelector(".wizard-field-error")?.textContent

describe("email_send_activity_wizard_controller", () => {
  let application, element, ctrl

  beforeEach(async () => {
    ;({ application, element } = await mountController(
      "email-send-activity-wizard",
      Controller,
      html()
    ))
    ctrl = controllerFor(application, element, "email-send-activity-wizard")
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it("shows audience on connect with Cancel + Continue", () => {
    expect(visible(element)).toEqual([true, false, false, false])
    expect(element.querySelector("[data-email-send-activity-wizard-target='cancelButton']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-email-send-activity-wizard-target='prevButton']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-email-send-activity-wizard-target='submitButton']").classList.contains("hidden")).toBe(true)
  })

  it("marks completed steps with a check and fills connectors as progress advances", async () => {
    const badge1 = element.querySelector("[data-email-send-activity-wizard-target='stepBadge'][data-step-index='1']")
    const check1 = element.querySelector("[data-email-send-activity-wizard-target='stepCheck'][data-step-index='1']")
    const number1 = element.querySelector("[data-email-send-activity-wizard-target='stepNumber'][data-step-index='1']")
    const connector1 = element.querySelector("[data-email-send-activity-wizard-target='stepConnector'][data-step-index='1']")

    expect(badge1.classList.contains("bg-accent")).toBe(true)
    expect(check1.classList.contains("hidden")).toBe(true)
    expect(number1.classList.contains("hidden")).toBe(false)
    expect(connector1.classList.contains("bg-border")).toBe(true)

    selectListIds(element, [1])
    ctrl.next()
    await tick()

    expect(check1.classList.contains("hidden")).toBe(false)
    expect(number1.classList.contains("hidden")).toBe(true)
    expect(connector1.classList.contains("bg-accent")).toBe(true)
    expect(element.querySelector("[data-email-send-activity-wizard-target='stepIndicator'][data-step-index='2']").getAttribute("aria-current")).toBe("step")
  })

  it("hides timezone for Send now without recurrence, and shows it for schedule or recurrence", () => {
    const timezoneFields = element.querySelector("[data-email-send-activity-wizard-target='timezoneFields']")
    expect(timezoneFields.classList.contains("hidden")).toBe(true)

    element.querySelector('input[value="later"]').checked = true
    element.querySelector('input[value="now"]').checked = false
    ctrl.timingChanged()
    expect(timezoneFields.classList.contains("hidden")).toBe(false)

    element.querySelector('input[value="now"]').checked = true
    element.querySelector('input[value="later"]').checked = false
    ctrl.timingChanged()
    expect(timezoneFields.classList.contains("hidden")).toBe(true)

    element.querySelector('[name="email_send_activity[recurrence_preset]"]').value = "daily"
    ctrl.recurrenceChanged()
    expect(timezoneFields.classList.contains("hidden")).toBe(false)
  })

  it("blocks next when required audience field is empty and shows an inline error", () => {
    ctrl.next()
    expect(ctrl.currentStepValue).toBe(1)
    expect(inlineError(element)).toBe("Select an email list to continue.")
  })

  it("advances through steps and Back preserves values", async () => {
    selectListIds(element, [1])
    ctrl.next()
    await tick()
    expect(ctrl.currentStepValue).toBe(2)

    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    ctrl.next()
    await tick()
    expect(ctrl.currentStepValue).toBe(3)

    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    ctrl.previous()
    await tick()
    expect(ctrl.currentStepValue).toBe(2)
    expect(element.querySelector('[name="email_send_activity[email_template_id]"]').value).toBe("2")
    expect(element.querySelector('[name="email_send_activity[name]"]').value).toBe("Campaign")
  })

  it("requires schedule datetime when timing is later", async () => {
    selectListIds(element, [1])
    ctrl.next()
    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    ctrl.next()
    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    element.querySelector('input[value="later"]').checked = true
    element.querySelector('input[value="now"]').checked = false
    ctrl.timingChanged()
    ctrl.next()
    expect(ctrl.currentStepValue).toBe(3)
    expect(inlineError(element)).toBe("Choose a date and time, or select Send now.")
  })

  it("reaches review on Send Now and fills summary", async () => {
    selectListIds(element, [1])
    ctrl.next()
    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    ctrl.next()
    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    ctrl.next()
    await tick()
    expect(ctrl.currentStepValue).toBe(4)
    expect(visible(element)).toEqual([false, false, false, true])
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewName']").textContent).toBe("Campaign")
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewSchedule']").textContent).toBe("Send immediately")
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewTimezoneRow']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-email-send-activity-wizard-target='submitButton']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-email-send-activity-wizard-target='nextButton']").classList.contains("hidden")).toBe(true)
  })

  it("hides schedule fields for Send Now", () => {
    expect(element.querySelector("[data-email-send-activity-wizard-target='scheduleFields']").classList.contains("hidden")).toBe(true)
    element.querySelector('input[value="later"]').checked = true
    element.querySelector('input[value="now"]').checked = false
    ctrl.timingChanged()
    expect(element.querySelector("[data-email-send-activity-wizard-target='scheduleFields']").classList.contains("hidden")).toBe(false)
  })

  it("rejects an unknown timing mode on the schedule step", async () => {
    selectListIds(element, [1])
    ctrl.next()
    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    ctrl.next()
    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    vi.spyOn(ctrl, "selectedTiming").mockReturnValue("")
    ctrl.next()
    expect(ctrl.currentStepValue).toBe(3)
    expect(inlineError(element)).toBe("Choose Send now or Schedule at to continue.")
  })

  it("falls back to the default field message when field-specific copy is missing", () => {
    selectListIds(element, [])
    const group = element.querySelector("[data-email-send-activity-wizard-target='listsFieldGroup']")
    delete group.dataset.wizardRequiredMsg
    expect(ctrl.validateCurrentStep()).toBe(false)
    expect(inlineError(element)).toBe("Please complete this field to continue.")
  })

  it("uses panel host and default timing message when timingGroup target is absent", async () => {
    selectListIds(element, [1])
    ctrl.next()
    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    ctrl.next()
    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    element.querySelector("[data-email-send-activity-wizard-target='timingGroup']")
      .removeAttribute("data-email-send-activity-wizard-target")
    element.querySelector("fieldset[data-wizard-field-group]").removeAttribute("data-wizard-required-msg")
    vi.spyOn(ctrl, "selectedTiming").mockReturnValue("")
    ctrl.next()
    expect(ctrl.currentStepValue).toBe(3)
    expect(inlineError(element.querySelector("[data-step='schedule']"))).toBe(
      "Choose Send now or Schedule at to continue."
    )
  })

  it("falls back when schedule datetime lacks a field-specific message", async () => {
    selectListIds(element, [1])
    ctrl.next()
    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    ctrl.next()
    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    element.querySelector('input[value="later"]').checked = true
    element.querySelector('input[value="now"]').checked = false
    ctrl.timingChanged()
    element.querySelector('[name="email_send_activity[scheduled_at]"]').removeAttribute("data-wizard-required-msg")
    ctrl.next()
    expect(ctrl.currentStepValue).toBe(3)
    expect(inlineError(element)).toBe("Choose Send now or Schedule at to continue.")
  })

  it("advances from schedule when later timing has a datetime", async () => {
    selectListIds(element, [1])
    ctrl.next()
    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    ctrl.next()
    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    element.querySelector('input[value="later"]').checked = true
    element.querySelector('input[value="now"]').checked = false
    ctrl.timingChanged()
    element.querySelector('[name="email_send_activity[scheduled_at]"]').value = "2026-09-01T09:00"
    ctrl.next()
    await tick()
    expect(ctrl.currentStepValue).toBe(4)
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewSchedule']").textContent).toBe("2026-09-01T09:00")
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewTimezoneRow']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewTimezone']").textContent).toBe("UTC")
  })

  it("shows an em dash for timezone on review when the value is blank but still required", () => {
    element.querySelector('input[value="later"]').checked = true
    element.querySelector('input[value="now"]').checked = false
    ctrl.timingChanged()
    element.querySelector('[name="email_send_activity[timezone]"]').value = ""
    ctrl.refreshReview()
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewTimezoneRow']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewTimezone']").textContent).toBe("—")
  })

  it("previous does not go below step 1 and next is a no-op past the last step", async () => {
    ctrl.previous()
    expect(ctrl.currentStepValue).toBe(1)

    selectListIds(element, [1])
    ctrl.next()
    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    ctrl.next()
    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    ctrl.next()
    await tick()
    expect(ctrl.currentStepValue).toBe(4)
    ctrl.next()
    expect(ctrl.currentStepValue).toBe(4)
  })

  it("validateCurrentStep returns true when the current panel is missing", () => {
    ctrl.currentStepValue = 99
    expect(ctrl.validateCurrentStep()).toBe(true)
  })

  it("selectedTiming defaults to now when no radio is checked", () => {
    element.querySelectorAll('input[name="email_send_activity[send_timing]"]').forEach((el) => {
      el.checked = false
    })
    expect(ctrl.selectedTiming()).toBe("now")
  })

  it("next and previous call preventDefault when given an event", () => {
    const event = { preventDefault: vi.fn() }
    selectListIds(element, [1])
    ctrl.next(event)
    expect(event.preventDefault).toHaveBeenCalled()
    ctrl.previous(event)
    expect(event.preventDefault).toHaveBeenCalledTimes(2)
  })

  it("refreshReview uses the em dash when values are blank", async () => {
    selectListIds(element, [1])
    ctrl.next()
    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    ctrl.next()
    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    ctrl.next()
    await tick()
    element.querySelector('[name="email_send_activity[name]"]').value = "   "
    ctrl.refreshReview()
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewName']").textContent).toBe("—")
  })

  it("refreshReview falls back when list/template/recurrence/timezone are missing", async () => {
    const sparseHtml = `
      <form data-controller="email-send-activity-wizard"
            data-email-send-activity-wizard-current-step-value="4"
            data-email-send-activity-wizard-total-steps-value="4">
        <div data-email-send-activity-wizard-target="step" data-step="review" data-step-index="4">
          <span data-email-send-activity-wizard-target="reviewName"></span>
          <span data-email-send-activity-wizard-target="reviewList"></span>
          <span data-email-send-activity-wizard-target="reviewTemplate"></span>
          <span data-email-send-activity-wizard-target="reviewSchedule"></span>
          <span data-email-send-activity-wizard-target="reviewTimezone"></span>
          <span data-email-send-activity-wizard-target="reviewRecurrence"></span>
        </div>
        <input type="radio" name="email_send_activity[send_timing]" value="now" checked
               data-email-send-activity-wizard-target="timingRadio">
      </form>
    `
    const mounted = await mountController("email-send-activity-wizard", Controller, sparseHtml)
    const sparseCtrl = controllerFor(mounted.application, mounted.element, "email-send-activity-wizard")
    sparseCtrl.refreshReview()
    expect(mounted.element.querySelector("[data-email-send-activity-wizard-target='reviewName']").textContent).toBe("—")
    expect(mounted.element.querySelector("[data-email-send-activity-wizard-target='reviewList']").textContent).toBe("—")
    expect(mounted.element.querySelector("[data-email-send-activity-wizard-target='reviewTemplate']").textContent).toBe("—")
    expect(mounted.element.querySelector("[data-email-send-activity-wizard-target='reviewTimezone']").textContent).toBe("—")
    expect(mounted.element.querySelector("[data-email-send-activity-wizard-target='reviewRecurrence']").textContent).toBe("—")
  })

  it("refreshReview uses send-now label when later timing has empty datetime", () => {
    element.querySelector('input[value="later"]').checked = true
    element.querySelector('input[value="now"]').checked = false
    ctrl.timingChanged()
    element.querySelector('[data-email-send-activity-wizard-target="scheduledAt"]').value = ""
    ctrl.refreshReview()
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewSchedule']").textContent).toBe("Send immediately")
  })


  it("addList appends a chip and hidden input", () => {
    listSelect(element).value = "1"
    ctrl.addList({ preventDefault: vi.fn() })
    const chip = element.querySelector("[data-list-item][data-list-id='1']")
    expect(chip).toBeTruthy()
    expect(chip.querySelector('input[name="email_send_activity[email_list_ids][]"]').value).toBe("1")
    expect(listSelect(element).querySelector('option[value="1"]').disabled).toBe(true)
    expect(listSelect(element).value).toBe("")
  })

  it("removeList removes the chip and re-enables the option", () => {
    selectListIds(element, [1])
    const chip = element.querySelector("[data-list-item][data-list-id='1']")
    ctrl.removeList({ preventDefault: vi.fn(), currentTarget: chip.querySelector("button") })
    expect(element.querySelector("[data-list-item][data-list-id='1']")).toBeNull()
    expect(listSelect(element).querySelector('option[value="1"]').disabled).toBe(false)
  })

  it("addList is a no-op when no list is selected", () => {
    listSelect(element).value = ""
    ctrl.addList({ preventDefault: vi.fn() })
    expect(element.querySelectorAll("[data-list-item]").length).toBe(0)
  })

  it("addList highlights an already-selected chip instead of duplicating", () => {
    vi.useFakeTimers()
    selectListIds(element, [1])
    listSelect(element).value = "1"
    const option = listSelect(element).querySelector('option[value="1"]')
    option.disabled = false
    ctrl.addList({ preventDefault: vi.fn() })
    expect(element.querySelectorAll("[data-list-item][data-list-id='1']").length).toBe(1)
    const chip = element.querySelector("[data-list-item][data-list-id='1']")
    expect(chip.classList.contains("ring-2")).toBe(true)
    vi.advanceTimersByTime(800)
    expect(chip.classList.contains("ring-2")).toBe(false)
    vi.useRealTimers()
  })

  it("addList shows max error when already at the list limit", () => {
    selectListIds(element, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    listSelect(element).value = "11"
    ctrl.addList({ preventDefault: vi.fn() })
    expect(element.querySelectorAll("[data-list-item]").length).toBe(10)
    expect(inlineError(element)).toBe("Select at most 10 lists to continue.")
  })

  it("addList falls back to the list id when the option label is blank", () => {
    const option = listSelect(element).querySelector('option[value="1"]')
    option.textContent = "   "
    listSelect(element).value = "1"
    ctrl.addList({ preventDefault: vi.fn() })
    const chip = element.querySelector("[data-list-item][data-list-id='1']")
    expect(chip.querySelector("span").textContent).toBe("1")
  })

  it("addList / removeList are no-ops without required targets", async () => {
    const sparse = await mountController("email-send-activity-wizard", Controller, `
      <form data-controller="email-send-activity-wizard"
            data-email-send-activity-wizard-current-step-value="1"
            data-email-send-activity-wizard-total-steps-value="1">
        <div data-email-send-activity-wizard-target="step" data-step="audience" data-step-index="1"></div>
        <button type="button" data-email-send-activity-wizard-target="nextButton">Next</button>
        <button type="submit" class="hidden" data-email-send-activity-wizard-target="submitButton">Save</button>
      </form>
    `)
    const sparseCtrl = controllerFor(sparse.application, sparse.element, "email-send-activity-wizard")
    sparseCtrl.addList({ preventDefault: vi.fn() })
    sparseCtrl.removeList({ preventDefault: vi.fn(), currentTarget: document.createElement("button") })
    expect(sparse.element.querySelectorAll("[data-list-item]").length).toBe(0)
  })

  it("removeList ignores clicks outside a chip", () => {
    selectListIds(element, [1])
    ctrl.removeList({ preventDefault: vi.fn(), currentTarget: document.createElement("button") })
    expect(element.querySelectorAll("[data-list-item]").length).toBe(1)
  })

  it("removeList clears selection when the matching option is gone", () => {
    selectListIds(element, [1])
    listSelect(element).querySelector('option[value="1"]').remove()
    const chip = element.querySelector("[data-list-item][data-list-id='1']")
    ctrl.removeList({ preventDefault: vi.fn(), currentTarget: chip.querySelector("button") })
    expect(element.querySelector("[data-list-item][data-list-id='1']")).toBeNull()
  })

  it("falls back to maxListsValue when dataset max is zero", () => {
    const group = element.querySelector("[data-email-send-activity-wizard-target='listsFieldGroup']")
    group.dataset.wizardMax = "0"
    delete group.dataset.wizardMaxMsg
    ctrl.maxListsValue = 2
    ctrl.listsTooManyMsgValue = "Select at most {max} lists to continue."
    selectListIds(element, [1, 2])
    listSelect(element).value = "3"
    ctrl.addList({ preventDefault: vi.fn() })
    expect(element.querySelectorAll("[data-list-item]").length).toBe(2)
    expect(inlineError(element)).toBe("Select at most 2 lists to continue.")
  })

  it("shows and clears list errors on the select when listsFieldGroup is absent", async () => {
    element.querySelector("[data-email-send-activity-wizard-target='listsFieldGroup']")
      .removeAttribute("data-email-send-activity-wizard-target")
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 500 }))
    await ctrl.refreshLists()
    expect(inlineError(element)).toBe("We couldn't refresh the lists. Please try again.")
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => [{ id: 1, name: "List A" }]
    }))
    await ctrl.refreshLists()
    expect(inlineError(element)).toBeUndefined()
  })

  it("selectedListIds is empty when listsContainer is missing", async () => {
    element.querySelector("[data-email-send-activity-wizard-target='listsContainer']").remove()
    expect(ctrl.validateCurrentStep()).toBe(false)
  })

  it("field errors fall back to the parent element when no field group exists", async () => {
    selectListIds(element, [1])
    ctrl.currentStepValue = 2
    await tick()
    const template = element.querySelector('[name="email_send_activity[email_template_id]"]')
    template.closest("[data-wizard-field-group]").removeAttribute("data-wizard-field-group")
    template.value = ""
    Array.from(template.options).forEach((option) => { option.selected = option.value === "" })
    expect(ctrl.validateCurrentStep()).toBe(false)
    expect(template.parentElement.querySelector(".wizard-field-error")).toBeTruthy()
  })

  it("highlight is a no-op when the matching chip is missing", () => {
    const container = element.querySelector("[data-email-send-activity-wizard-target='listsContainer']")
    const original = container.querySelectorAll.bind(container)
    let listItemCalls = 0
    vi.spyOn(container, "querySelectorAll").mockImplementation((selector) => {
      if (selector === "[data-list-item]") {
        listItemCalls += 1
        // #selectedListIds sees the id; #chipForListId does not.
        if (listItemCalls === 1) return [{ dataset: { listId: "1" } }]
        return []
      }
      return original(selector)
    })
    listSelect(element).value = "1"
    ctrl.addList({ preventDefault: vi.fn() })
    expect(listItemCalls).toBeGreaterThanOrEqual(2)
  })

  describe("refreshLists", () => {
    it("reloads list options and preserves the current selection", async () => {
      selectListIds(element, [1, 2])
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
        ok: true,
        json: async () => [{ id: 1, name: "List A" }, { id: 2, name: "List B" }, { id: 9, name: "List Z" }]
      }))

      await ctrl.refreshLists({ preventDefault: vi.fn() })

      const select = element.querySelector("[data-email-send-activity-wizard-target='listSelect']")
      expect(fetch).toHaveBeenCalledWith("/lists.json", expect.objectContaining({
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      }))
      expect([...select.options].map((o) => o.value)).toEqual(["", "1", "2", "9"])
      expect(select.querySelector('option[value="1"]').disabled).toBe(true)
      expect(select.querySelector('option[value="2"]').disabled).toBe(true)
      expect(element.querySelectorAll("[data-list-item]").length).toBe(2)
      expect(element.querySelector("[data-email-send-activity-wizard-target='refreshListsButton']").disabled).toBe(false)
    })

    it("shows an inline error when the lists request fails", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 500 }))
      await ctrl.refreshLists()
      expect(inlineError(element)).toBe("We couldn't refresh the lists. Please try again.")
    })

    it("is a no-op when listsUrl is blank", async () => {
      ctrl.listsUrlValue = ""
      vi.stubGlobal("fetch", vi.fn())
      await ctrl.refreshLists()
      expect(fetch).not.toHaveBeenCalled()
    })

    it("treats a non-array JSON body as an empty list", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ unexpected: true })
      }))
      await ctrl.refreshLists()
      const select = element.querySelector("[data-email-send-activity-wizard-target='listSelect']")
      expect([...select.options].map((o) => o.value)).toEqual([""])
    })

    it("refreshes without a refresh button target", async () => {
      element.querySelector("[data-email-send-activity-wizard-target='refreshListsButton']").removeAttribute("data-email-send-activity-wizard-target")
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
        ok: true,
        json: async () => [{ id: 3, name: "New" }]
      }))
      await ctrl.refreshLists()
      const select = element.querySelector("[data-email-send-activity-wizard-target='listSelect']")
      expect([...select.options].map((o) => o.value)).toEqual(["", "3"])
    })
  })

  it("blocks continue when more than max lists are selected", () => {
    selectListIds(element, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    ctrl.next()
    expect(ctrl.currentStepValue).toBe(1)
    expect(inlineError(element)).toBe("Select at most 10 lists to continue.")
  })

  it("uses maxLists / listsTooManyMsg values when wizard-max data attrs are absent", () => {
    const group = element.querySelector("[data-email-send-activity-wizard-target='listsFieldGroup']")
    delete group.dataset.wizardMax
    delete group.dataset.wizardMaxMsg
    ctrl.maxListsValue = 2
    ctrl.listsTooManyMsgValue = "Select at most {max} lists to continue."
    selectListIds(element, [1, 2, 3])
    ctrl.next()
    expect(ctrl.currentStepValue).toBe(1)
    expect(inlineError(element)).toBe("Select at most 2 lists to continue.")
  })

  it("blocks next on content when template is empty", async () => {
    selectListIds(element, [1])
    ctrl.currentStepValue = 2
    await tick()
    const content = element.querySelector("[data-step='content']")
    expect(content.classList.contains("hidden")).toBe(false)
    const template = element.querySelector('[name="email_send_activity[email_template_id]"]')
    template.value = ""
    Array.from(template.options).forEach((option) => { option.selected = option.value === "" })
    expect(template.required).toBe(true)
    expect(ctrl.validateCurrentStep()).toBe(false)
    expect(inlineError(content)).toBe("Select an email template to continue.")
  })

  it("falls back to default required message for non-multiple fields", async () => {
    selectListIds(element, [1])
    ctrl.currentStepValue = 2
    await tick()
    const template = element.querySelector('[name="email_send_activity[email_template_id]"]')
    template.value = ""
    Array.from(template.options).forEach((option) => { option.selected = option.value === "" })
    template.removeAttribute("data-wizard-required-msg")
    expect(ctrl.validateCurrentStep()).toBe(false)
    expect(inlineError(element.querySelector("[data-step='content']"))).toBe(
      "Please complete this field to continue."
    )
  })

  it("review lists shows comma-separated selected labels", () => {
    selectListIds(element, [1, 2])
    element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
    element.querySelector('[name="email_send_activity[name]"]').value = "Campaign"
    ctrl.currentStepValue = 4
    ctrl.refreshReview()
    expect(element.querySelector("[data-email-send-activity-wizard-target='reviewList']").textContent).toBe("List A, List B")
  })

  describe("refreshTemplates", () => {
    it("reloads template options and preserves the current selection", async () => {
      element.querySelector('[name="email_send_activity[email_template_id]"]').value = "2"
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
        ok: true,
        json: async () => [{ id: 2, name: "Template B" }, { id: 8, name: "Template Z" }]
      }))

      await ctrl.refreshTemplates({ preventDefault: vi.fn() })

      const select = element.querySelector("[data-email-send-activity-wizard-target='templateSelect']")
      expect(fetch).toHaveBeenCalledWith("/templates.json", expect.objectContaining({
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      }))
      expect([...select.options].map((o) => o.value)).toEqual(["", "2", "8"])
      expect(select.value).toBe("2")
    })

    it("shows an inline error when the templates request fails", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 500 }))
      await ctrl.refreshTemplates()
      expect(inlineError(element.querySelector("[data-step='content']"))).toBe(
        "We couldn't refresh the templates. Please try again."
      )
    })

    it("is a no-op when templatesUrl is blank", async () => {
      ctrl.templatesUrlValue = ""
      vi.stubGlobal("fetch", vi.fn())
      await ctrl.refreshTemplates()
      expect(fetch).not.toHaveBeenCalled()
    })

    it("treats a non-array JSON body as an empty template list", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ unexpected: true })
      }))
      await ctrl.refreshTemplates()
      const select = element.querySelector("[data-email-send-activity-wizard-target='templateSelect']")
      expect([...select.options].map((o) => o.value)).toEqual([""])
    })

    it("refreshes without a refresh button target", async () => {
      element.querySelector("[data-email-send-activity-wizard-target='refreshTemplatesButton']").removeAttribute("data-email-send-activity-wizard-target")
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
        ok: true,
        json: async () => [{ id: 4, name: "Fresh" }]
      }))
      await ctrl.refreshTemplates()
      const select = element.querySelector("[data-email-send-activity-wizard-target='templateSelect']")
      expect([...select.options].map((o) => o.value)).toEqual(["", "4"])
    })
  })
})
