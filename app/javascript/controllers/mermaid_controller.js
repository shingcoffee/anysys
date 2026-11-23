import { Controller } from "@hotwired/stimulus"
import { escapeHtml } from "utils"

// Mermaid keeps a scratch element per render id, so every render gets its own.
let renderCount = 0

export default class extends Controller {
  static targets = ["diagram"]
  static values = {
    source: String,
    alternate: String,
    // i18n seam: English default byte-identical to the former hardcoded copy.
    renderErrorFormat: { type: String, default: "Error rendering diagram: {error}" }
  }

  connect() {
    if (!this.sourceValue) return

    // Mermaid sizes each box from the font in use when it renders; waiting for
    // the web font keeps labels from being clipped on the first render.
    this.mermaid = Promise.all([import("mermaid"), document.fonts?.ready]).then(([{ default: mermaid }]) => {
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        theme: "base",
        themeVariables: {
          fontFamily: "\"Inter var\", Inter, ui-sans-serif, system-ui, sans-serif",
          fontSize: "13px",
          lineColor: "#94a3b8",
          primaryTextColor: "#1e293b",
          edgeLabelBackground: "#ffffff"
        },
        flowchart: {
          useMaxWidth: true,
          htmlLabels: true,
          curve: "basis",
          padding: 12,
          nodeSpacing: 40,
          rankSpacing: 48
        }
      })
      return mermaid
    })
    return this.render(this.sourceValue)
  }

  // Swaps between the designed path and the one with every failure route.
  switch(event) {
    return this.render(event.target.checked ? this.alternateValue : this.sourceValue)
  }

  async render(code) {
    const ticket = this.ticket = (this.ticket || 0) + 1
    renderCount += 1
    const id = `mermaid-diagram-${renderCount}`

    try {
      const mermaid = await this.mermaid
      const { svg } = await mermaid.render(id, code)
      this.show(ticket, svg)
    } catch (error) {
      console.error("Mermaid rendering error:", error)
      const message = this.renderErrorFormatValue.replace("{error}", error.message)
      this.show(ticket, `<div class="text-red-500 text-sm">${escapeHtml(message)}</div>`)
    }
  }

  // A render finishing after a newer one started is dropped.
  show(ticket, html) {
    if (ticket === this.ticket) this.diagramTarget.innerHTML = html
  }
}
