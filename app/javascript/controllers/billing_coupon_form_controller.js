import { Controller } from "@hotwired/stimulus"

// Toggles visibility of discount-type-specific fields (percent_off vs
// amount_off_cents) and the cycles field (only for "repeating" duration).
//
// Usage (added automatically by CouponFormComponent):
//   data-controller="billing-coupon-form"
//   data-billing-coupon-form-discount-type-value="percent|fixed"
//   data-billing-coupon-form-duration-value="once|repeating|forever"
export default class extends Controller {
  static targets = ["percentField", "fixedField", "cyclesField"]
  static values  = { discountType: String, duration: String }

  connect() {
    this.#updateDiscountFields(this.discountTypeValue)
    this.#updateCyclesField(this.durationValue)
  }

  discountTypeChanged(event) {
    this.#updateDiscountFields(event.target.value)
  }

  durationChanged(event) {
    this.#updateCyclesField(event.target.value)
  }

  #updateDiscountFields(type) {
    const isPercent = type === "percent"
    this.percentFieldTargets.forEach(el => el.classList.toggle("hidden", !isPercent))
    this.fixedFieldTargets.forEach(el => el.classList.toggle("hidden", isPercent))
  }

  #updateCyclesField(duration) {
    const show = duration === "repeating"
    this.cyclesFieldTargets.forEach(el => el.classList.toggle("hidden", !show))
  }
}
