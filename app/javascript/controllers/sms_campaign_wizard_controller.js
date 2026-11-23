import { Controller } from "@hotwired/stimulus"

const BADGE_BASE = [
  "flex", "h-8", "w-8", "shrink-0", "items-center", "justify-center",
  "rounded-full", "text-sm", "font-semibold", "transition-colors", "duration-200"
]
const BADGE_COMPLETED = ["bg-accent", "text-white"]
const BADGE_CURRENT = ["bg-accent", "text-white", "ring-4", "ring-accent/20"]
const BADGE_UPCOMING = ["bg-surface-active", "text-text-muted"]
const BADGE_ALL = [...BADGE_COMPLETED, ...BADGE_CURRENT, ...BADGE_UPCOMING]

const LABEL_COMPLETED = ["text-text-muted", "font-medium"]
const LABEL_CURRENT = ["text-accent", "font-semibold"]
const LABEL_UPCOMING = ["text-text-muted", "font-medium"]
const LABEL_ALL = [...new Set([...LABEL_COMPLETED, ...LABEL_CURRENT, ...LABEL_UPCOMING])]

// Client-side campaign wizard: Audience → Content → Schedule → Review.
// Save draft and Preview stay real submits; only Continue is gated in the browser.
export default class extends Controller {
  static targets = [
    "step", "stepIndicator", "stepBadge", "stepNumber", "stepCheck", "stepLabel", "stepConnector",
    "cancelButton", "prevButton", "nextButton", "saveButton", "previewButton",
    "scheduleFields", "scheduledAt", "timingRadio",
    "reviewName", "reviewAudience", "reviewTemplate", "reviewSchedule"
  ]

  static values = {
    currentStep: { type: Number, default: 1 },
    totalSteps: { type: Number, default: 4 },
    fieldRequiredMsg: { type: String, default: "Please complete this field to continue." },
    sendNowLabel: { type: String, default: "Send now" },
    emDash: { type: String, default: "—" },
    allContactsLabel: { type: String, default: "All contacts" }
  }

  connect() {
    this.render()
    this.applyTiming()
    if (this.currentStepValue === this.totalStepsValue) this.refreshReview()
  }

  next(event) {
    event?.preventDefault?.()
    if (!this.validateCurrentStep()) return
    if (this.currentStepValue < this.totalStepsValue) {
      this.currentStepValue++
      if (this.currentStepValue === this.totalStepsValue) this.refreshReview()
    }
  }

  previous(event) {
    event?.preventDefault?.()
    if (this.currentStepValue > 1) this.currentStepValue--
  }

  timingChanged() {
    this.applyTiming()
  }

  currentStepValueChanged() {
    this.render()
  }

  render() {
    const current = this.currentStepValue
    const total = this.totalStepsValue
    const isFirst = current === 1
    const isLast = current === total

    this.stepTargets.forEach((step, idx) => {
      const active = idx + 1 === current
      step.classList.toggle("hidden", !active)
      step.setAttribute("aria-hidden", String(!active))
    })

    this.#renderProgress(current)

    if (this.hasCancelButtonTarget) this.cancelButtonTarget.classList.toggle("hidden", !isFirst)
    if (this.hasPrevButtonTarget) this.prevButtonTarget.classList.toggle("hidden", isFirst)
    if (this.hasNextButtonTarget) this.nextButtonTarget.classList.toggle("hidden", isLast)
    if (this.hasSaveButtonTarget) this.saveButtonTarget.classList.toggle("hidden", !isLast)
    if (this.hasPreviewButtonTarget) this.previewButtonTarget.classList.toggle("hidden", !isLast)
  }

  applyTiming() {
    const later = this.selectedTiming() === "scheduled"
    if (this.hasScheduleFieldsTarget) this.scheduleFieldsTarget.classList.toggle("hidden", !later)
    if (!this.hasScheduledAtTarget) return

    this.scheduledAtTarget.required = later
    if (!later) {
      this.scheduledAtTarget.value = ""
      this.#clearFieldError(this.scheduledAtTarget)
    }
  }

  selectedTiming() {
    if (!this.hasTimingRadioTarget) return "immediate"
    const checked = this.timingRadioTargets.find((el) => el.checked)
    return checked?.value || "immediate"
  }

  refreshReview() {
    const name = this.element.querySelector('[name="sms_campaign[name]"]')?.value
    if (this.hasReviewNameTarget) this.reviewNameTarget.textContent = name?.trim() || this.emDashValue
    if (this.hasReviewAudienceTarget) {
      this.reviewAudienceTarget.textContent = this.#choiceLabel(
        "sms_campaign[segment_id]",
        this.allContactsLabelValue
      )
    }
    if (this.hasReviewTemplateTarget) {
      this.reviewTemplateTarget.textContent = this.#choiceLabel("sms_campaign[template_id]", this.emDashValue)
    }
    if (this.hasReviewScheduleTarget) {
      const when = this.hasScheduledAtTarget ? this.scheduledAtTarget.value : ""
      this.reviewScheduleTarget.textContent =
        this.selectedTiming() === "scheduled" && when ? when : this.sendNowLabelValue
    }
  }

  validateCurrentStep() {
    const panel = this.stepTargets[this.currentStepValue - 1]
    if (!panel) return true

    this.#clearPanelErrors(panel)
    const fields = panel.querySelectorAll("[data-wizard-field]")
    for (const field of fields) {
      if (field.closest(".hidden")) continue
      if (field.required && !String(field.value || "").trim()) {
        const message = field.dataset.wizardRequiredMsg || this.fieldRequiredMsgValue
        this.#showFieldError(field, message)
        field.focus()
        return false
      }
    }
    return true
  }

  #renderProgress(current) {
    this.stepIndicatorTargets.forEach((el) => {
      const idx = Number(el.dataset.stepIndex)
      if (idx === current) el.setAttribute("aria-current", "step")
      else el.removeAttribute("aria-current")
    })

    this.stepBadgeTargets.forEach((badge) => {
      const idx = Number(badge.dataset.stepIndex)
      badge.classList.remove(...BADGE_ALL)
      BADGE_BASE.forEach((cls) => badge.classList.add(cls))
      if (idx < current) badge.classList.add(...BADGE_COMPLETED)
      else if (idx === current) badge.classList.add(...BADGE_CURRENT)
      else badge.classList.add(...BADGE_UPCOMING)
    })

    this.stepNumberTargets.forEach((el) => {
      el.classList.toggle("hidden", Number(el.dataset.stepIndex) < current)
    })
    this.stepCheckTargets.forEach((el) => {
      el.classList.toggle("hidden", Number(el.dataset.stepIndex) >= current)
    })

    this.stepLabelTargets.forEach((label) => {
      const idx = Number(label.dataset.stepIndex)
      label.classList.remove(...LABEL_ALL)
      if (idx < current) label.classList.add(...LABEL_COMPLETED)
      else if (idx === current) label.classList.add(...LABEL_CURRENT)
      else label.classList.add(...LABEL_UPCOMING)
    })

    this.stepConnectorTargets.forEach((connector) => {
      const filled = Number(connector.dataset.stepIndex) < current
      connector.classList.toggle("bg-accent", filled)
      connector.classList.toggle("bg-border", !filled)
    })
  }

  #choiceLabel(name, blankLabel) {
    const field = this.element.querySelector(`[name="${name}"]`)
    if (!field || !String(field.value || "").trim()) return blankLabel
    const option = Array.from(field.options || []).find((item) => item.value === field.value)
    return option?.text?.trim() || field.value
  }

  #showFieldError(field, message) {
    field.classList.add("border-danger")
    this.#showGroupError(field.closest("[data-wizard-field-group]") || field.parentElement, message)
  }

  #clearFieldError(field) {
    field.classList.remove("border-danger")
    this.#clearGroupError(field.closest("[data-wizard-field-group]") || field.parentElement)
  }

  #showGroupError(group, message) {
    this.#clearGroupError(group)
    const error = document.createElement("p")
    error.className = "wizard-field-error mt-1 text-sm text-danger"
    error.setAttribute("role", "alert")
    error.textContent = message
    group.appendChild(error)
  }

  #clearGroupError(group) {
    group.querySelectorAll(".wizard-field-error").forEach((el) => el.remove())
  }

  #clearPanelErrors(panel) {
    panel.querySelectorAll(".wizard-field-error").forEach((el) => el.remove())
    panel.querySelectorAll(".border-danger").forEach((el) => el.classList.remove("border-danger"))
  }
}
