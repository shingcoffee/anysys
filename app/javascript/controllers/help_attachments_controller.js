import { Controller } from "@hotwired/stimulus"

const IMAGE_PREFIX = "image/"

export default class extends Controller {
  static targets = ["input", "list", "error", "submit"]
  static values = {
    maxFiles: { type: Number, default: 5 },
    maxBytes: { type: Number, default: 5 * 1024 * 1024 },
    accept: { type: String, default: "image/jpeg,image/png,image/gif,image/webp" },
    tooManyTemplate: { type: String, default: "You can attach at most {count} files." },
    typeLabel: { type: String, default: "That file type is not allowed." },
    sizeTemplate: { type: String, default: "Each file must be {size} or smaller." },
    sizeLabel: { type: String, default: "5MB" },
    removeLabel: { type: String, default: "Remove" },
    removeMark: { type: String, default: "×" }
  }

  previewUrls = []
  selectedFiles = []
  committing = false

  connect() {
    this.selectedFiles = []
    this.boundReset = () => this.resetFiles()
    this.formElement()?.addEventListener("reset", this.boundReset)
  }

  disconnect() {
    this.formElement()?.removeEventListener("reset", this.boundReset)
    this.revokePreviews()
  }

  changed() {
    if (this.committing) return
    this.commit(this.mergeFiles(this.selectedFiles, this.filesFromInput()))
  }

  remove(event) {
    const index = Number(event.currentTarget.dataset.index)
    this.commit(this.selectedFiles.filter((_file, i) => i !== index))
  }

  resetFiles() {
    this.commit([])
  }

  filesFromInput() {
    return Array.from(this.inputTarget.files)
  }

  render(files) {
    const error = this.validate(files)
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = error || ""
      this.errorTarget.classList.toggle("hidden", !error)
    }
    if (this.hasSubmitTarget) this.submitTarget.disabled = Boolean(error)
    this.renderList(files)
  }

  validate(files) {
    if (files.length > this.maxFilesValue) {
      return this.tooManyTemplateValue.replace("{count}", String(this.maxFilesValue))
    }
    const allowed = this.acceptValue.split(",").map((type) => type.trim()).filter(Boolean)
    for (const file of files) {
      if (allowed.length && !allowed.includes(file.type)) return this.typeLabelValue
      if (file.size > this.maxBytesValue) {
        return this.sizeTemplateValue.replace("{size}", this.sizeLabelValue)
      }
    }
    return null
  }

  renderList(files) {
    if (!this.hasListTarget) return
    this.revokePreviews()
    this.listTarget.replaceChildren()
    files.forEach((file, index) => {
      this.listTarget.appendChild(this.chip(file, index))
    })
  }

  chip(file, index) {
    const item = document.createElement("li")
    item.className = "flex items-center gap-2 rounded-md border border-border bg-surface-hover px-2 py-1 text-xs"

    if (file.type && file.type.startsWith(IMAGE_PREFIX) && typeof URL !== "undefined" && URL.createObjectURL) {
      const img = document.createElement("img")
      const url = URL.createObjectURL(file)
      this.previewUrls.push(url)
      img.src = url
      img.alt = file.name
      img.className = "size-8 rounded object-cover"
      item.appendChild(img)
    }

    const name = document.createElement("span")
    name.className = "max-w-[8rem] truncate text-text-secondary"
    name.textContent = file.name
    item.appendChild(name)

    const button = document.createElement("button")
    button.type = "button"
    button.dataset.action = "click->help-attachments#remove"
    button.dataset.index = String(index)
    button.setAttribute("aria-label", this.removeLabelValue)
    button.className = "text-text-muted hover:text-text-primary"
    button.textContent = this.removeMarkValue
    item.appendChild(button)
    return item
  }

  revokePreviews() {
    if (typeof URL !== "undefined" && URL.revokeObjectURL) {
      this.previewUrls.forEach((url) => URL.revokeObjectURL(url))
    }
    this.previewUrls = []
  }

  commit(files) {
    this.selectedFiles = files
    this.committing = true
    try {
      this.writeFiles(files)
    } finally {
      this.committing = false
    }
    this.render(files)
  }

  mergeFiles(existing, incoming) {
    const next = [ ...existing ]
    incoming.forEach((file) => {
      if (!next.some((row) => this.sameFile(row, file))) next.push(file)
    })
    return next
  }

  sameFile(left, right) {
    return left === right || (
      left.name === right.name &&
      left.size === right.size &&
      left.lastModified === right.lastModified
    )
  }

  formElement() {
    if (this.element.matches("form")) return this.element
    return this.element.querySelector("form")
  }

  writeFiles(files) {
    const transfer = new DataTransfer()
    files.forEach((file) => transfer.items.add(file))
    this.inputTarget.files = transfer.files
  }
}
