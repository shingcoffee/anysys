import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "runButton", "buttonText", "placeholder", "results", "error",
    "status", "signal", "trace", "nodes", "context", "errorMessage"
  ]
  static values = {
    url: String,
    // i18n seam: English defaults byte-identical to the former hardcoded copy.
    runningLabel: { type: String, default: "Running..." },
    runLabel: { type: String, default: "Run Activity" },
    successLabel: { type: String, default: "Success" },
    failureLabel: { type: String, default: "Failure" },
    signalPrefix: { type: String, default: "Signal: " },
    noTraceAvailable: { type: String, default: "No trace available" }
  }

  async run() {
    this.setLoading(true)
    this.hideAll()

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ input: {} })
      })

      const data = await response.json()

      if (data.error) {
        this.showError(data.error)
      } else {
        this.showResults(data)
      }
    } catch (error) {
      this.showError(error.message)
    } finally {
      this.setLoading(false)
    }
  }

  setLoading(loading) {
    this.runButtonTarget.disabled = loading
    this.buttonTextTarget.textContent = loading ? this.runningLabelValue : this.runLabelValue
  }

  hideAll() {
    this.placeholderTarget.classList.add("hidden")
    this.resultsTarget.classList.add("hidden")
    this.errorTarget.classList.add("hidden")
  }

  showResults(data) {
    // Update status badge
    const statusEl = this.statusTarget
    if (data.success) {
      statusEl.textContent = this.successLabelValue
      statusEl.className = "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-green-100 text-green-800"
    } else {
      statusEl.textContent = this.failureLabelValue
      statusEl.className = "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-red-100 text-red-800"
    }

    // Update signal
    this.signalTarget.textContent = data.signal ? `${this.signalPrefixValue}${data.signal}` : ""

    // Update trace output
    this.traceTarget.textContent = data.trace || this.noTraceAvailableValue

    // Update nodes visualization
    this.renderNodes(data.trace_nodes || [])

    // Update context
    this.contextTarget.textContent = JSON.stringify(data.context || {}, null, 2)

    this.resultsTarget.classList.remove("hidden")
  }

  renderNodes(nodes) {
    const container = this.nodesTarget
    container.innerHTML = ""

    nodes.forEach(node => {
      const div = document.createElement("div")
      div.className = "flex items-center gap-2 py-1"

      const icon = document.createElement("span")
      if (node.status === "success") {
        icon.innerHTML = `<svg class="w-5 h-5 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>`
      } else {
        icon.innerHTML = `<svg class="w-5 h-5 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>`
      }

      const label = document.createElement("span")
      label.className = "text-sm text-gray-700"
      label.textContent = node.label

      const signal = document.createElement("span")
      signal.className = "text-xs text-gray-400"
      signal.textContent = `(${node.signal})`

      div.appendChild(icon)
      div.appendChild(label)
      div.appendChild(signal)
      container.appendChild(div)
    })
  }

  showError(message) {
    this.errorMessageTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
