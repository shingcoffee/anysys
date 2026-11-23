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

// Client-side send-activity wizard: Audience → Content → Schedule → Review.
// Fields stay in the DOM; only the final Review submit hits the server.
export default class extends Controller {
  static targets = [
    "step", "stepIndicator", "stepBadge", "stepNumber", "stepCheck", "stepLabel", "stepConnector",
    "cancelButton", "prevButton", "nextButton", "submitButton",
    "scheduleFields", "scheduledAt", "timingRadio", "timingGroup",
    "timezoneFields", "timezoneSelect", "recurrenceSelect",
    "listSelect", "listsContainer", "listsFieldGroup", "addListButton", "refreshListsButton",
    "templateSelect", "refreshTemplatesButton",
    "reviewName", "reviewList", "reviewTemplate", "reviewSchedule",
    "reviewTimezone", "reviewTimezoneRow", "reviewRecurrence", "reviewAudienceCount"
  ]

  static values = {
    currentStep: { type: Number, default: 1 },
    totalSteps: { type: Number, default: 4 },
    fieldRequiredMsg: { type: String, default: "Please complete this field to continue." },
    timingRequiredMsg: { type: String, default: "Choose Send now or Schedule at to continue." },
    sendNowLabel: { type: String, default: "Send immediately" },
    emDash: { type: String, default: "—" },
    listsUrl: { type: String, default: "" },
    templatesUrl: { type: String, default: "" },
    selectListBlank: { type: String, default: "— select list —" },
    selectTemplateBlank: { type: String, default: "— select template —" },
    refreshListsError: { type: String, default: "We couldn't refresh the lists. Please try again." },
    refreshTemplatesError: { type: String, default: "We couldn't refresh the templates. Please try again." },
    maxLists: { type: Number, default: 10 },
    listsTooManyMsg: { type: String, default: "Select at most {max} lists to continue." },
    addListLabel: { type: String, default: "Add list" },
    removeListLabel: { type: String, default: "Remove list" }
  }

  connect() {
    this.render()
    this.applyTiming()
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
    if (this.hasTimingGroupTarget) this.#clearGroupError(this.timingGroupTarget)
  }

  recurrenceChanged() {
    this.applyTimezoneVisibility()
  }

  addList(event) {
    event?.preventDefault?.()
    if (!this.hasListSelectTarget || !this.hasListsContainerTarget) return

    const select = this.listSelectTarget
    const option = select.selectedOptions?.[0]
    const id = option?.value?.trim()
    if (!id) return

    if (this.#selectedListIds().has(id)) {
      this.#highlightListChip(id)
      return
    }

    const max = this.#listsMax()
    if (this.#selectedListIds().size >= max) {
      this.#showListsError(this.#listsMaxMessage(max))
      return
    }

    this.listsContainerTarget.insertAdjacentHTML(
      "beforeend",
      this.#listChipHtml(id, option.textContent?.trim() || id)
    )
    option.disabled = true
    select.value = ""
    this.#clearListsError()
  }

  removeList(event) {
    event?.preventDefault?.()
    const chip = event?.currentTarget?.closest?.("[data-list-item]")
    if (!chip) return

    const id = chip.dataset.listId
    chip.remove()
    if (this.hasListSelectTarget && id) {
      const option = this.#optionForListId(id)
      if (option) option.disabled = false
    }
    this.#clearListsError()
  }

  async refreshLists(event) {
    event?.preventDefault?.()
    if (!this.listsUrlValue || !this.hasListSelectTarget) return

    const button = this.hasRefreshListsButtonTarget ? this.refreshListsButtonTarget : null
    if (button) button.disabled = true

    try {
      const response = await fetch(this.listsUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const lists = await response.json()
      const selected = this.#selectedListIds()
      this.#replaceSelectOptions(
        this.listSelectTarget,
        Array.isArray(lists) ? lists : [],
        this.selectListBlankValue,
        selected
      )
      this.#clearListsError()
    } catch (_error) {
      this.#showListsError(this.refreshListsErrorValue)
    } finally {
      if (button) button.disabled = false
    }
  }

  async refreshTemplates(event) {
    event?.preventDefault?.()
    if (!this.templatesUrlValue || !this.hasTemplateSelectTarget) return

    const button = this.hasRefreshTemplatesButtonTarget ? this.refreshTemplatesButtonTarget : null
    if (button) button.disabled = true

    try {
      const response = await fetch(this.templatesUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const templates = await response.json()
      this.#replaceSelectOptions(
        this.templateSelectTarget,
        Array.isArray(templates) ? templates : [],
        this.selectTemplateBlankValue
      )
      this.#clearFieldError(this.templateSelectTarget)
    } catch (_error) {
      this.#showFieldError(this.templateSelectTarget, this.refreshTemplatesErrorValue)
    } finally {
      if (button) button.disabled = false
    }
  }

  #replaceSelectOptions(select, items, blankLabel, disabledIds = null) {
    const selected = new Set(
      Array.from(select.selectedOptions)
        .map((option) => option.value)
        .filter((value) => value !== "")
    )
    const disabled = disabledIds instanceof Set ? disabledIds : new Set()

    select.innerHTML = ""

    if (blankLabel != null) {
      const blank = document.createElement("option")
      blank.value = ""
      blank.textContent = blankLabel
      select.appendChild(blank)
    }

    items.forEach((item) => {
      const option = document.createElement("option")
      option.value = String(item.id)
      option.textContent = item.name
      if (selected.has(String(item.id))) option.selected = true
      if (disabled.has(String(item.id))) option.disabled = true
      select.appendChild(option)
    })
  }

  #selectedListIds() {
    if (!this.hasListsContainerTarget) return new Set()
    return new Set(
      Array.from(this.listsContainerTarget.querySelectorAll("[data-list-item]"))
        .map((chip) => chip.dataset.listId)
        .filter(Boolean)
    )
  }

  #selectedListLabels() {
    if (!this.hasListsContainerTarget) return []
    return Array.from(this.listsContainerTarget.querySelectorAll("[data-list-item] span"))
      .map((span) => span.textContent?.trim())
      .filter(Boolean)
  }

  #listsMax() {
    if (this.hasListsFieldGroupTarget) {
      const fromDataset = Number(this.listsFieldGroupTarget.dataset.wizardMax)
      if (fromDataset > 0) return fromDataset
    }
    return this.maxListsValue
  }

  #listsMaxMessage(max) {
    const template = (this.hasListsFieldGroupTarget && this.listsFieldGroupTarget.dataset.wizardMaxMsg)
      || this.listsTooManyMsgValue
    return template.replace("{max}", String(max)).replace("%{max}", String(max))
  }

  #listChipHtml(id, label) {
    const safeId = this.#escapeHtml(id)
    const safeLabel = this.#escapeHtml(label)
    const removeLabel = this.#escapeHtml(this.removeListLabelValue)
    return `
      <div data-list-item data-list-id="${safeId}"
           class="inline-flex items-center gap-1 px-2 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded border border-blue-200">
        <input type="hidden" name="email_send_activity[email_list_ids][]" value="${safeId}">
        <span title="${safeLabel}">${safeLabel}</span>
        <button type="button" data-action="click->email-send-activity-wizard#removeList"
                class="p-0.5 hover:bg-blue-100 rounded transition-colors"
                title="${removeLabel}" aria-label="${removeLabel}">
          <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `
  }

  #escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }

  #highlightListChip(id) {
    const chip = this.#chipForListId(id)
    if (!chip) return
    chip.classList.add("ring-2", "ring-accent")
    setTimeout(() => chip.classList.remove("ring-2", "ring-accent"), 800)
  }

  #chipForListId(id) {
    return Array.from(this.listsContainerTarget.querySelectorAll("[data-list-item]"))
      .find((chip) => chip.dataset.listId === String(id)) || null
  }

  #optionForListId(id) {
    return Array.from(this.listSelectTarget.options)
      .find((option) => option.value === String(id)) || null
  }

  #showListsError(message) {
    if (this.hasListsFieldGroupTarget) {
      this.#showGroupError(this.listsFieldGroupTarget, message)
      return
    }
    if (this.hasListSelectTarget) this.#showFieldError(this.listSelectTarget, message)
  }

  #clearListsError() {
    if (this.hasListsFieldGroupTarget) {
      this.#clearGroupError(this.listsFieldGroupTarget)
      return
    }
    if (this.hasListSelectTarget) this.#clearFieldError(this.listSelectTarget)
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
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.classList.toggle("hidden", !isLast)
  }

  #renderProgress(current) {
    this.stepIndicatorTargets.forEach((el) => {
      const idx = Number(el.dataset.stepIndex)
      if (idx === current) {
        el.setAttribute("aria-current", "step")
      } else {
        el.removeAttribute("aria-current")
      }
    })

    this.stepBadgeTargets.forEach((badge) => {
      const idx = Number(badge.dataset.stepIndex)
      badge.classList.remove(...BADGE_ALL)
      BADGE_BASE.forEach((cls) => {
        if (!badge.classList.contains(cls)) badge.classList.add(cls)
      })
      if (idx < current) {
        badge.classList.add(...BADGE_COMPLETED)
      } else if (idx === current) {
        badge.classList.add(...BADGE_CURRENT)
      } else {
        badge.classList.add(...BADGE_UPCOMING)
      }
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
      if (idx < current) {
        label.classList.add(...LABEL_COMPLETED)
      } else if (idx === current) {
        label.classList.add(...LABEL_CURRENT)
      } else {
        label.classList.add(...LABEL_UPCOMING)
      }
    })

    this.stepConnectorTargets.forEach((connector) => {
      const filled = Number(connector.dataset.stepIndex) < current
      connector.classList.toggle("bg-accent", filled)
      connector.classList.toggle("bg-border", !filled)
    })
  }

  applyTiming() {
    const mode = this.selectedTiming()
    const later = mode === "later"
    if (this.hasScheduleFieldsTarget) {
      this.scheduleFieldsTarget.classList.toggle("hidden", !later)
    }
    if (this.hasScheduledAtTarget) {
      this.scheduledAtTarget.required = later
      if (!later) {
        this.scheduledAtTarget.value = ""
        this.#clearFieldError(this.scheduledAtTarget)
      }
    }
    this.applyTimezoneVisibility()
  }

  applyTimezoneVisibility() {
    const show = this.timezoneNeeded()
    if (this.hasTimezoneFieldsTarget) {
      this.timezoneFieldsTarget.classList.toggle("hidden", !show)
      if (!show && this.hasTimezoneSelectTarget) this.#clearFieldError(this.timezoneSelectTarget)
    }
  }

  timezoneNeeded() {
    return this.selectedTiming() === "later" || this.hasRecurrence()
  }

  hasRecurrence() {
    if (!this.hasRecurrenceSelectTarget) return false
    const value = this.recurrenceSelectTarget.value
    return Boolean(value) && value !== "none"
  }

  selectedTiming() {
    const checked = this.timingRadioTargets.find((el) => el.checked)
    return checked?.value || "now"
  }

  validateCurrentStep() {
    const panel = this.stepTargets[this.currentStepValue - 1]
    if (!panel) return true

    this.#clearPanelErrors(panel)

    if (panel.dataset.step === "schedule") {
      const mode = this.selectedTiming()
      if (mode !== "now" && mode !== "later") {
        const host = this.hasTimingGroupTarget ? this.timingGroupTarget : panel
        const message = host.dataset.wizardRequiredMsg || this.timingRequiredMsgValue
        this.#showGroupError(host, message)
        return false
      }
      if (mode === "later") {
        if (this.hasScheduledAtTarget && !this.scheduledAtTarget.value) {
          this.#showFieldError(
            this.scheduledAtTarget,
            this.scheduledAtTarget.dataset.wizardRequiredMsg || this.timingRequiredMsgValue
          )
          this.scheduledAtTarget.focus()
          return false
        }
      }
    }

    const fields = panel.querySelectorAll("[data-wizard-field]")
    for (const field of fields) {
      if (field.closest(".hidden")) continue

      if (field.dataset.wizardField === "lists") {
        const selectedCount = this.#selectedListIds().size
        if (selectedCount === 0) {
          const message = field.dataset.wizardRequiredMsg || this.fieldRequiredMsgValue
          this.#showListsError(message)
          if (this.hasListSelectTarget) this.listSelectTarget.focus()
          return false
        }
        const max = Number(field.dataset.wizardMax || this.maxListsValue)
        if (max > 0 && selectedCount > max) {
          this.#showListsError(this.#listsMaxMessage(max))
          if (this.hasListSelectTarget) this.listSelectTarget.focus()
          return false
        }
        continue
      }

      if (field.required && !String(field.value || "").trim()) {
        const message = field.dataset.wizardRequiredMsg || this.fieldRequiredMsgValue
        this.#showFieldError(field, message)
        field.focus()
        return false
      }
    }
    return true
  }

  #clearPanelErrors(panel) {
    panel.querySelectorAll(".wizard-field-error").forEach((el) => el.remove())
    panel.querySelectorAll(".border-danger").forEach((el) => el.classList.remove("border-danger"))
  }

  #fieldGroup(field) {
    return field.closest("[data-wizard-field-group]") || field.parentElement
  }

  #showFieldError(field, message) {
    field.classList.add("border-danger")
    this.#showGroupError(this.#fieldGroup(field), message)
  }

  #clearFieldError(field) {
    field.classList.remove("border-danger")
    this.#clearGroupError(this.#fieldGroup(field))
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
    group?.querySelectorAll(".wizard-field-error").forEach((el) => el.remove())
  }

  refreshReview() {
    const form = this.element
    const name = form.querySelector('[name="email_send_activity[name]"]')?.value
    const template = form.querySelector('[name="email_send_activity[email_template_id]"]')
    const timezone = form.querySelector('[name="email_send_activity[timezone]"]')?.value
    const recurrence = form.querySelector('[name="email_send_activity[recurrence_preset]"]')
    const scheduledAt = this.hasScheduledAtTarget ? this.scheduledAtTarget.value : ""
    const timing = this.selectedTiming()
    const showTimezone = this.timezoneNeeded()

    if (this.hasReviewNameTarget) this.reviewNameTarget.textContent = name?.trim() || this.emDashValue
    if (this.hasReviewListTarget) {
      const labels = this.#selectedListLabels()
      this.reviewListTarget.textContent = labels.length ? labels.join(", ") : this.emDashValue
    }
    if (this.hasReviewTemplateTarget) {
      this.reviewTemplateTarget.textContent = template?.selectedOptions?.[0]?.text?.trim() || this.emDashValue
    }
    if (this.hasReviewRecurrenceTarget) {
      this.reviewRecurrenceTarget.textContent = recurrence?.selectedOptions?.[0]?.text?.trim() || this.emDashValue
    }
    if (this.hasReviewScheduleTarget) {
      this.reviewScheduleTarget.textContent =
        timing === "now" || !scheduledAt ? this.sendNowLabelValue : scheduledAt
    }
    if (this.hasReviewTimezoneRowTarget) {
      this.reviewTimezoneRowTarget.classList.toggle("hidden", !showTimezone)
    }
    if (this.hasReviewTimezoneTarget) {
      this.reviewTimezoneTarget.textContent = showTimezone ? (timezone || this.emDashValue) : this.emDashValue
    }
  }
}
