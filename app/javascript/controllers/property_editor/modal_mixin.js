/**
 * Modal Mixin Module
 * Provides shared modal handling utilities for StepManager and BranchManager.
 * Extracted to eliminate code duplication between the two managers.
 */

/**
 * ModalMixin provides common modal operations.
 * Apply to a class using Object.assign(YourClass.prototype, ModalMixin)
 */
export const ModalMixin = {
  /**
   * Open a modal by selector.
   * @param {HTMLElement} container - The container element to search in
   * @param {string} modalSelector - Data attribute selector for the modal (e.g., "[data-branch-modal]")
   * @param {Object} options - Optional configuration
   * @param {Function} options.onOpen - Callback after modal is shown
   * @param {string} options.focusSelector - Selector for element to focus after open
   */
  _openModal(container, modalSelector, options = {}) {
    if (!container) return null

    const modal = container.querySelector(modalSelector)
    if (!modal) return null

    modal.classList.remove("hidden")

    // Execute optional callback
    if (options.onOpen) {
      options.onOpen(modal)
    }

    // Focus element if specified
    if (options.focusSelector) {
      const focusElement = modal.querySelector(options.focusSelector)
      if (focusElement) {
        setTimeout(() => focusElement.focus(), 100)
      }
    }

    return modal
  },

  /**
   * Close a modal by selector.
   * @param {HTMLElement} container - The container element to search in
   * @param {string} modalSelector - Data attribute selector for the modal
   * @param {Object} options - Optional configuration
   * @param {Function} options.onClose - Callback after modal is hidden
   */
  _closeModal(container, modalSelector, options = {}) {
    if (!container) return

    const modal = container.querySelector(modalSelector)
    if (!modal) return

    modal.classList.add("hidden")

    // Execute optional callback
    if (options.onClose) {
      options.onClose(modal)
    }
  },

  /**
   * Reset form fields within a modal.
   * @param {HTMLElement} modal - The modal element
   * @param {Object} fieldSelectors - Object mapping field types to their selectors
   */
  _resetModalFields(modal, fieldSelectors = {}) {
    if (!modal) return

    // Reset textareas
    if (fieldSelectors.textareas) {
      const selectors = Array.isArray(fieldSelectors.textareas)
        ? fieldSelectors.textareas
        : [fieldSelectors.textareas]

      selectors.forEach(selector => {
        const textarea = modal.querySelector(selector)
        if (textarea) textarea.value = ""
      })
    }

    // Reset inputs
    if (fieldSelectors.inputs) {
      const selectors = Array.isArray(fieldSelectors.inputs)
        ? fieldSelectors.inputs
        : [fieldSelectors.inputs]

      selectors.forEach(selector => {
        const input = modal.querySelector(selector)
        if (input) input.value = ""
      })
    }

    // Reset selects to first option or specified default
    if (fieldSelectors.selects) {
      const selectors = Array.isArray(fieldSelectors.selects)
        ? fieldSelectors.selects
        : [fieldSelectors.selects]

      selectors.forEach(item => {
        if (typeof item === "string") {
          const select = modal.querySelector(item)
          if (select && select.options.length > 0) {
            select.selectedIndex = 0
          }
        } else if (item.selector && item.defaultValue !== undefined) {
          const select = modal.querySelector(item.selector)
          if (select) select.value = item.defaultValue
        }
      })
    }
  },

  /**
   * Enable or disable a submit button.
   * @param {HTMLElement} modal - The modal element
   * @param {string} buttonSelector - Selector for the submit button
   * @param {boolean} enabled - Whether the button should be enabled
   */
  _setSubmitButtonState(modal, buttonSelector, enabled) {
    if (!modal) return

    const button = modal.querySelector(buttonSelector)
    if (button) {
      button.disabled = !enabled
    }
  },

  /**
   * Highlight a form field with error styling.
   * @param {HTMLElement} field - The field element to highlight
   * @param {number} duration - Duration in ms to show highlight (default 2000)
   */
  _highlightFieldError(field, duration = 2000) {
    if (!field) return

    const errorClasses = ["ring-2", "ring-red-500", "border-red-500"]
    field.classList.add(...errorClasses)
    field.focus()

    setTimeout(() => {
      field.classList.remove(...errorClasses)
    }, duration)
  },

  /**
   * Show success animation on an element.
   * @param {HTMLElement} element - The element to animate
   * @param {number} duration - Duration in ms (default 300)
   */
  _showSuccessAnimation(element, duration = 300) {
    if (!element) return

    const successClasses = ["ring-2", "ring-green-400", "bg-green-50"]
    element.classList.add(...successClasses)

    setTimeout(() => {
      element.classList.remove(...successClasses)
    }, duration)
  }
}

/**
 * Apply ModalMixin to a class prototype.
 * @param {Function} targetClass - The class to extend
 */
export function applyModalMixin(targetClass) {
  Object.assign(targetClass.prototype, ModalMixin)
}

export default ModalMixin
