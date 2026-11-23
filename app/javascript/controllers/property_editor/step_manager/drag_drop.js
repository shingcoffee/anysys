/**
 * DragDropMixin — drag-and-drop reordering for step items.
 * Apply to a class using Object.assign(YourClass.prototype, DragDropMixin)
 */
export const DragDropMixin = {
  // ===================
  // Drag and Drop
  // ===================

  handleStepDragStart(event) {
    const stepItem = event.target.closest("[data-step-item]")
    if (!stepItem) return

    this._draggedItem = stepItem

    // Add dragging visual effects — lifted schematic card
    stepItem.classList.add(
      "opacity-70",
      "scale-[1.015]",
      "shadow-lg",
      "bg-indigo-50/40",
      "z-10",
      "ring-2",
      "ring-indigo-300"
    )

    // Set drag data
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", stepItem.dataset.stepIndex)

    // Add dragging state to container
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (container) {
      container.classList.add("step-dragging-active")
    }
  },

  handleStepDragEnd(event) {
    const stepItem = event.target.closest("[data-step-item]")
    if (stepItem) {
      // Remove all dragging visual effects
      stepItem.classList.remove(
        "opacity-70",
        "scale-[1.015]",
        "shadow-lg",
        "bg-indigo-50/40",
        "z-10",
        "ring-2",
        "ring-indigo-300"
      )
    }
    this._draggedItem = null

    // Remove any drop indicators and container state
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (container) {
      container.classList.remove("step-dragging-active")
      container.querySelectorAll("[data-step-item]").forEach(item => {
        item.classList.remove(
          "border-t-2",
          "border-b-2",
          "border-indigo-500",
          "bg-indigo-50/50",
          "scale-[0.98]"
        )
      })
    }
  },

  handleStepDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const container = event.currentTarget
    const stepItems = [...container.querySelectorAll("[data-step-item]")]

    // Remove existing indicators from all items
    stepItems.forEach(item => {
      if (item !== this._draggedItem) {
        item.classList.remove(
          "border-t-2",
          "border-b-2",
          "border-indigo-500",
          "bg-indigo-50/50",
          "scale-[0.98]"
        )
      }
    })

    // Find the step item we're hovering over
    const targetItem = event.target.closest("[data-step-item]")
    if (!targetItem || targetItem === this._draggedItem) return

    // Determine if we're in the top or bottom half of the target
    const rect = targetItem.getBoundingClientRect()
    const midpoint = rect.top + rect.height / 2

    // Add hover effect to target
    targetItem.classList.add("bg-indigo-50/50", "scale-[0.98]")

    if (event.clientY < midpoint) {
      targetItem.classList.add("border-t-2", "border-indigo-500")
    } else {
      targetItem.classList.add("border-b-2", "border-indigo-500")
    }
  },

  handleStepDrop(event) {
    event.preventDefault()

    const container = event.currentTarget
    const targetItem = event.target.closest("[data-step-item]")

    if (!this._draggedItem || !targetItem || targetItem === this._draggedItem) {
      return
    }

    // Determine insert position
    const rect = targetItem.getBoundingClientRect()
    const midpoint = rect.top + rect.height / 2
    const insertBefore = event.clientY < midpoint

    // Move the dragged item
    if (insertBefore) {
      container.insertBefore(this._draggedItem, targetItem)
    } else {
      container.insertBefore(this._draggedItem, targetItem.nextSibling)
    }

    // Re-index all steps
    this._reindexSteps()

    // Clean up drop indicators
    container.querySelectorAll("[data-step-item]").forEach(item => {
      item.classList.remove(
        "border-t-2",
        "border-b-2",
        "border-indigo-500",
        "bg-indigo-50/50",
        "scale-[0.98]"
      )
    })

    // Add drop success animation to the moved item using mixin method
    this._showSuccessAnimation(this._draggedItem)

    // Dispatch event to trigger auto-sync to canvas
    this._dispatchEvent("stepReordered")
  },

  // ===================
  // Private Helpers
  // ===================

  _collapseAllSteps(container) {
    const stepItems = container.querySelectorAll("[data-step-item]")
    stepItems.forEach(item => this._setStepExpanded(item, false))
  },

  _setStepExpanded(stepItem, expanded) {
    const detailsSection = stepItem.querySelector("[data-step-details]")
    const expandIcon = stepItem.querySelector("[data-step-expand-icon] svg")

    if (expanded) {
      if (detailsSection) detailsSection.classList.remove("hidden")
      if (expandIcon) expandIcon.classList.add("rotate-90")
      stepItem.classList.add("step-expanded")
    } else {
      if (detailsSection) detailsSection.classList.add("hidden")
      if (expandIcon) expandIcon.classList.remove("rotate-90")
      stepItem.classList.remove("step-expanded")
    }
  },

  _reindexSteps() {
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (!container) return

    const stepItems = container.querySelectorAll("[data-step-item]")
    stepItems.forEach((item, index) => {
      // Update data attribute
      item.dataset.stepIndex = index

      // Update hidden input names. Filter by name prefix in JS rather than a
      // `[name^='steps[']` selector — the `[` in the value throws in happy-dom.
      const inputs = [...item.querySelectorAll("[name]")].filter(el => el.getAttribute("name").startsWith("steps["))
      inputs.forEach(input => {
        input.name = input.name.replace(/steps\[\d+\]/, `steps[${index}]`)
      })

      // Update textarea name if exists
      const textarea = [...item.querySelectorAll("textarea[name]")].find(el => el.getAttribute("name").startsWith("steps["))
      if (textarea) {
        textarea.name = textarea.name.replace(/steps\[\d+\]/, `steps[${index}]`)
      }
    })

    // Update stepIndex for new items
    this.stepIndex = stepItems.length
  }
}
