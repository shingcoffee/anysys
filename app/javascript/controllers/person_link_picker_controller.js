import { Controller } from "@hotwired/stimulus"

const OPTION_CLASS = "w-full px-3 py-2.5 text-left hover:bg-surface-hover focus-visible:bg-accent-subtle"
const OPTION_ACTIVE = "bg-accent-subtle"

export default class extends Controller {
  static targets = ["trigger", "panel", "search", "list", "status", "confirm", "confirmName", "form", "userId"]
  static values = {
    candidatesUrl: String,
    wait: { type: Number, default: 250 },
    minQuery: { type: Number, default: 2 },
    typeToSearchLabel: { type: String, default: "Type a name or email to find an account." },
    loadingLabel: { type: String, default: "Searching…" },
    emptyLabel: { type: String, default: "No matching users" },
    errorLabel: { type: String, default: "Could not load users. Try again." },
    confirmTemplate: { type: String, default: "Link this entry to {name} ({email})?" }
  }

  connect() {
    this.timer = null
    this.abortController = null
    this.activeIndex = -1
    this.users = []
    this.openState = false
    this.boundOutside = (event) => this.outside(event)
    document.addEventListener("click", this.boundOutside)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.timer = null
    this.abortFetch()
    document.removeEventListener("click", this.boundOutside)
  }

  open(event) {
    event.preventDefault()
    this.reveal()
  }

  close() {
    this.collapsePanel({ focusTrigger: true })
  }

  query() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetchUsers(), this.waitValue)
  }

  async fetchUsers() {
    const q = this.searchTarget.value.trim()
    if (q.length < this.minQueryValue) {
      this.resetList()
      this.showTypeToSearch()
      return
    }

    this.abortFetch()
    this.abortController = new AbortController()
    this.showLoading()

    try {
      const url = new URL(this.candidatesUrlValue, window.location.origin)
      url.searchParams.set("q", q)
      const response = await fetch(url.toString(), {
        credentials: "same-origin",
        headers: { Accept: "application/json" },
        signal: this.abortController.signal
      })
      if (!response.ok) {
        this.showError()
        return
      }
      const body = await response.json()
      this.renderUsers(body.users || [])
    } catch (error) {
      if (error.name === "AbortError") return
      this.showError()
    }
  }

  keydown(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        if (!this.openState) this.reveal()
        this.move(1)
        break
      case "ArrowUp":
        event.preventDefault()
        if (!this.openState) this.reveal()
        this.move(-1)
        break
      case "Enter":
        if (!this.openState) return
        event.preventDefault()
        if (this.activeIndex >= 0) this.choose(this.users[this.activeIndex])
        break
      case "Escape":
        if (!this.confirmTarget.classList.contains("hidden")) {
          event.preventDefault()
          this.dismissConfirm()
        } else if (this.openState) {
          event.preventDefault()
          this.close()
        }
        break
      case "Tab":
        if (this.openState) this.collapsePanel({ focusTrigger: false })
        break
      case "Home":
        if (this.openState && this.users.length) {
          event.preventDefault()
          this.setActive(0)
        }
        break
      case "End":
        if (this.openState && this.users.length) {
          event.preventDefault()
          this.setActive(this.users.length - 1)
        }
        break
    }
  }

  select(event) {
    const option = event.target.closest("[role='option']")
    if (!option) return
    const user = this.users.find((item) => String(item.id) === String(option.dataset.userId))
    if (!user) return
    this.choose(user)
  }

  cancel() {
    this.hideConfirm()
    this.stack().hidden = false
    this.reveal()
  }

  outside(event) {
    if (this.element.contains(event.target)) return
    if (this.openState) this.close()
  }

  reveal() {
    this.openState = true
    this.panelTarget.classList.remove("hidden")
    this.syncExpanded(true)
    this.searchTarget.focus()
  }

  collapsePanel({ focusTrigger }) {
    clearTimeout(this.timer)
    this.timer = null
    this.abortFetch()
    this.openState = false
    this.panelTarget.classList.add("hidden")
    this.syncExpanded(false)
    this.searchTarget.value = ""
    this.resetList()
    this.showTypeToSearch()
    if (focusTrigger) this.triggerTarget.focus()
  }

  dismissConfirm() {
    this.hideConfirm()
    this.stack().hidden = false
    this.close()
  }

  hideConfirm() {
    this.confirmTarget.classList.add("hidden")
    this.userIdTarget.value = ""
    this.confirmNameTarget.textContent = ""
  }

  choose(user) {
    this.collapsePanel({ focusTrigger: false })
    this.stack().hidden = true
    this.userIdTarget.value = String(user.id)
    this.confirmNameTarget.textContent = this.confirmTemplateValue
      .replace("{name}", user.name)
      .replace("{email}", user.email)
    this.confirmTarget.classList.remove("hidden")
    this.confirmTarget.querySelector('button[type="submit"]').focus()
  }

  move(delta) {
    if (this.users.length === 0) return
    if (this.activeIndex < 0) {
      this.setActive(delta > 0 ? 0 : this.users.length - 1)
      return
    }
    this.setActive((this.activeIndex + delta + this.users.length) % this.users.length)
  }

  setActive(index) {
    this.activeIndex = index
    const options = this.listTarget.querySelectorAll("[role='option']")
    options.forEach((option, i) => {
      const active = i === index
      option.classList.toggle(OPTION_ACTIVE, active)
      option.setAttribute("aria-selected", active ? "true" : "false")
      if (active) {
        this.searchTarget.setAttribute("aria-activedescendant", option.id)
        option.scrollIntoView({ block: "nearest" })
      }
    })
  }

  renderUsers(users) {
    this.users = users
    this.activeIndex = -1
    this.listTarget.replaceChildren()
    this.searchTarget.removeAttribute("aria-activedescendant")

    if (users.length === 0) {
      this.showStatus(this.emptyLabelValue)
      return
    }

    this.statusTarget.classList.add("hidden")
    this.listTarget.classList.remove("hidden")
    users.forEach((user) => this.listTarget.append(this.optionButton(user)))
  }

  optionButton(user) {
    const button = document.createElement("button")
    button.type = "button"
    button.setAttribute("role", "option")
    button.id = `person-link-option-${user.id}`
    button.dataset.userId = String(user.id)
    button.setAttribute("aria-selected", "false")
    button.className = OPTION_CLASS

    const name = document.createElement("div")
    name.className = "text-sm font-medium text-text-primary"
    name.textContent = user.name

    const email = document.createElement("div")
    email.className = "truncate text-xs text-text-muted"
    email.textContent = user.email

    button.append(name, email)
    return button
  }

  resetList() {
    this.users = []
    this.activeIndex = -1
    this.listTarget.replaceChildren()
    this.listTarget.classList.add("hidden")
    this.searchTarget.removeAttribute("aria-activedescendant")
  }

  showTypeToSearch() {
    this.showStatus(this.typeToSearchLabelValue)
  }

  showError() {
    this.resetList()
    this.statusTarget.classList.remove("hidden")
    this.statusTarget.setAttribute("role", "alert")
    this.statusTarget.replaceChildren()
    this.statusTarget.textContent = this.errorLabelValue
  }

  showStatus(text) {
    this.listTarget.classList.add("hidden")
    this.statusTarget.classList.remove("hidden")
    this.statusTarget.setAttribute("role", "status")
    this.statusTarget.replaceChildren()
    this.statusTarget.textContent = text
  }

  showLoading() {
    this.listTarget.classList.add("hidden")
    this.statusTarget.classList.remove("hidden")
    this.statusTarget.setAttribute("role", "status")
    this.statusTarget.replaceChildren()

    const wrap = document.createElement("span")
    wrap.className = "inline-flex items-center justify-center gap-2"

    const spinner = document.createElement("span")
    spinner.className = "size-5 animate-spin rounded-full border-2 border-border-strong border-t-accent"
    spinner.setAttribute("aria-hidden", "true")

    const label = document.createElement("span")
    label.textContent = this.loadingLabelValue

    wrap.append(spinner, label)
    this.statusTarget.append(wrap)
  }

  abortFetch() {
    if (this.abortController) {
      this.abortController.abort()
      this.abortController = null
    }
  }

  syncExpanded(open) {
    const value = open ? "true" : "false"
    this.triggerTarget.setAttribute("aria-expanded", value)
    this.searchTarget.setAttribute("aria-expanded", value)
  }

  stack() {
    return this.triggerTarget.parentElement
  }
}
