import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "step", "cancelButton", "prevButton", "nextButton", "submitButton", "stepCounter",
    "stepIndicator", "stepBadge", "stepNumber", "stepCheck", "stepLabel", "stepConnector",
    "form"
  ]
  static values = {
    currentStep: { type: Number, default: 1 },
    totalSteps: Number,
    validateOnNext: { type: Boolean, default: true },
    cancelUrl: { type: String, default: "javascript:history.back()" },
    accentColor: { type: String, default: "bg-indigo-600" },

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the mounting component (wizard_component.rb's
    // wizard_data) supplies translated strings via
    // data-wizard-<name>-value="<%= t(...) %>". ──
    stepOfFormat: { type: String, default: "Step {current} of {total}" },
    fieldRequiredMsg: { type: String, default: "This field is required" }
  }

  connect() {
    this.render()
  }

  next() {
    if (this.validateOnNextValue && !this.validateCurrentStep()) return
    if (this.currentStepValue < this.totalStepsValue) this.currentStepValue++
  }

  previous() {
    if (this.currentStepValue > 1) this.currentStepValue--
  }

  cancel() {
    window.location.href = this.cancelUrlValue
  }

  goToStep(event) {
    const step = parseInt(event.currentTarget.dataset.step, 10)
    // Only allow navigating to completed steps (allow_back) or current step
    if (step >= 1 && step < this.currentStepValue) {
      this.currentStepValue = step
    }
  }

  currentStepValueChanged() {
    this.render()
  }

  render() {
    const current = this.currentStepValue
    const total   = this.totalStepsValue
    const isFirst = current === 1
    const isLast  = current === total

    // Show/hide step panels
    this.stepTargets.forEach((step, idx) => {
      const active = idx + 1 === current
      step.classList.toggle("hidden", !active)
      step.setAttribute("aria-hidden", String(!active))
    })

    // Left navigation: Cancel on step 1, Previous on steps 2+
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.classList.toggle("hidden", !isFirst)
    }
    if (this.hasPrevButtonTarget) {
      this.prevButtonTarget.classList.toggle("hidden", isFirst)
    }

    // Right navigation: Next or Submit
    if (this.hasNextButtonTarget) {
      this.nextButtonTarget.classList.toggle("hidden", isLast)
    }
    this.submitButtonTargets.forEach(button => button.classList.toggle("hidden", !isLast))

    // Step counter label
    if (this.hasStepCounterTarget) {
      this.stepCounterTarget.textContent = this.stepOfFormatValue.replace("{current}", current).replace("{total}", total)
    }

    // Step indicators
    this.updateStepIndicators(current, total)
  }

  updateStepIndicators(current, _total) {
    const accentBg   = this._accentBg()                          // e.g. "bg-indigo-600"
    const accentRing = accentBg.replace("bg-", "ring-")          // e.g. "ring-indigo-600"
    const accentText = accentBg.replace("bg-", "text-")          // e.g. "text-indigo-600"

    // Exhaustive list of badge state classes we ever apply (so we can cleanly remove them)
    const BADGE_STATES = [
      accentBg, "text-white", "ring-4", "ring-offset-2", accentRing,
      "bg-gray-100", "text-gray-400"
    ]
    const LABEL_STATES = [
      "text-gray-500", "font-medium", accentText, "font-semibold", "text-gray-400"
    ]

    this.stepBadgeTargets.forEach(badge => {
      const stepNum = parseInt(badge.dataset.stepIndex, 10) + 1
      badge.classList.remove(...BADGE_STATES)
      if (stepNum < current) {
        badge.classList.add(accentBg, "text-white")
      } else if (stepNum === current) {
        badge.classList.add(accentBg, "text-white", "ring-4", "ring-offset-2", accentRing)
      } else {
        badge.classList.add("bg-gray-100", "text-gray-400")
      }
    })

    // Checkmark vs number
    this.stepNumberTargets.forEach(el => {
      el.classList.toggle("hidden", parseInt(el.dataset.stepIndex, 10) + 1 < current)
    })
    this.stepCheckTargets.forEach(el => {
      el.classList.toggle("hidden", parseInt(el.dataset.stepIndex, 10) + 1 >= current)
    })

    // Step labels
    this.stepLabelTargets.forEach(label => {
      const stepNum = parseInt(label.dataset.stepIndex, 10) + 1
      label.classList.remove(...LABEL_STATES)
      if (stepNum < current) {
        label.classList.add("text-gray-500", "font-medium")
      } else if (stepNum === current) {
        label.classList.add(accentText, "font-semibold")
      } else {
        label.classList.add("text-gray-400", "font-medium")
      }
    })

    // Connectors: filled up to the current step
    this.stepConnectorTargets.forEach(connector => {
      const filled = parseInt(connector.dataset.stepIndex, 10) + 1 < current
      connector.classList.toggle("bg-gray-200", !filled)
      connector.classList.toggle(accentBg, filled)
    })

    // Step buttons: only previous steps are clickable
    this.stepIndicatorTargets.forEach(btn => {
      const stepNum = parseInt(btn.dataset.step, 10)
      btn.disabled = stepNum >= current
      btn.style.cursor = stepNum < current ? "pointer" : "default"
    })
  }

  _accentBg() {
    return this.accentColorValue || "bg-indigo-600"
  }

  _accentText() {
    return this._accentBg().replace("bg-", "text-")
  }

  validateCurrentStep() {
    const currentStep = this.stepTargets[this.currentStepValue - 1]
    if (!currentStep) return true

    const inputs = currentStep.querySelectorAll("input[required], select[required], textarea[required]")
    let valid = true

    inputs.forEach(input => {
      const isEmpty = !input.value.trim()
      if (isEmpty) {
        input.classList.add("border-red-500", "focus:ring-red-500")
        input.classList.remove("border-gray-300")
        valid = false
        let errorMsg = input.parentElement.querySelector(".error-message")
        if (!errorMsg) {
          errorMsg = document.createElement("p")
          errorMsg.className = "error-message mt-1 text-sm text-red-600"
          errorMsg.textContent = this.fieldRequiredMsgValue
          input.parentElement.appendChild(errorMsg)
        }
      } else {
        input.classList.remove("border-red-500", "focus:ring-red-500")
        input.classList.add("border-gray-300")
        input.parentElement.querySelector(".error-message")?.remove()
      }
    })

    return valid
  }

  reset() {
    this.currentStepValue = 1
    this.stepTargets.forEach(step => {
      step.querySelectorAll(".error-message").forEach(msg => msg.remove())
      step.querySelectorAll("input, select, textarea").forEach(input => {
        input.classList.remove("border-red-500", "focus:ring-red-500")
        input.classList.add("border-gray-300")
      })
    })
  }
}
