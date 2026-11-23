import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "key"]

  connect() {
    this.isNewRecord = !this.hasKeyTarget || this.keyTarget.value === ""
  }

  suggest() {
    if (!this.isNewRecord) return

    const slug = this.nameTarget.value
      .toLowerCase()
      .replace(/[^a-z0-9\s_]/g, "")
      .replace(/\s+/g, "_")
      .substring(0, 50)

    if (this.hasKeyTarget) {
      this.keyTarget.value = slug
    }
  }
}
