import { Controller } from "@hotwired/stimulus"

// Handles the plan-comparison grid. Intercepts switch/subscribe form submissions
// and shows a native confirm dialog so the customer can back out before the
// plan change is POSTed.
//
// Usage (wired by PlanComparisonComponent):
//   data-controller="billing-plan-compare"
//
// Each plan CTA form:
//   data-action="submit->billing-plan-compare#confirmSwitch"
//   data-billing-plan-compare-plan-name-param="Pro Monthly"
export default class extends Controller {
  static values = {
    // i18n seam: English defaults byte-identical to the former hardcoded copy.
    confirmSwitchFormat: { type: String, default: "Switch to {plan}? Your billing will be updated immediately." },
    fallbackPlanLabel: { type: String, default: "this plan" }
  }

  confirmSwitch(event) {
    const planName = event.params.planName || this.fallbackPlanLabelValue
    const message  = this.confirmSwitchFormatValue.replace("{plan}", planName)

    if (!window.confirm(message)) {
      event.preventDefault()
    }
  }
}
