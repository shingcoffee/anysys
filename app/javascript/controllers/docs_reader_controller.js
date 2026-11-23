import { Controller } from "@hotwired/stimulus"

/**
 * Docs Reader Controller
 *
 * Reading aids for the documentation reader, alongside developer-docs-nav:
 *   - publishes the scroll container height as --docs-pane-height so the
 *     sticky contents/TOC rails fill exactly the visible pane
 *   - scroll-spy: marks the TOC link of the section being read with
 *     aria-current="location" (styled by Tailwind aria variants)
 *   - "/" focuses the visible search field
 *   - wraps each rendered code block with a copy button cloned from a
 *     server-rendered <template>
 *
 * Values:
 *   - copyLabel / copiedLabel: String — copy button wording
 *   - offset: Number — px below the pane top at which a heading becomes current
 *
 * Targets:
 *   - search: contents search inputs
 *   - tocLink: same-page heading links (inline and rail)
 *   - prose: rendered Markdown wrapper
 *   - copyTemplate: <template> holding the code block wrapper + button
 */
export default class extends Controller {
  static targets = ["search", "tocLink", "prose", "copyTemplate"]
  static values = {
    copyLabel: { type: String, default: "Copy" },
    copiedLabel: { type: String, default: "Copied" },
    offset: { type: Number, default: 120 }
  }

  connect() {
    this.timers = new Set()
    this.onKeydown = this.keydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
    this.enhanceCode()
    this.root = this.element.closest("main")
    if (!this.root) return

    this.onScroll = this.requestSpy.bind(this)
    this.root.addEventListener("scroll", this.onScroll, { passive: true })
    this.resizeObserver = new ResizeObserver(() => this.measure())
    this.resizeObserver.observe(this.root)
    this.measure()
    this.spy()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    this.timers.forEach((timer) => clearTimeout(timer))
    this.timers.clear()
    if (!this.root) return

    cancelAnimationFrame(this.frame)
    this.frame = null
    this.root.removeEventListener("scroll", this.onScroll)
    this.resizeObserver.disconnect()
  }

  measure() {
    this.element.style.setProperty("--docs-pane-height", `${this.root.clientHeight}px`)
  }

  requestSpy() {
    if (this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.spy()
    })
  }

  spy() {
    const headings = [...new Set(this.tocLinkTargets.map((link) => link.getAttribute("href").slice(1)))]
      .map((id) => document.getElementById(id))
      .filter(Boolean)
    if (headings.length === 0) return

    const line = this.root.getBoundingClientRect().top + this.offsetValue
    const atEnd = this.root.scrollTop > 0 && this.root.scrollTop + this.root.clientHeight >= this.root.scrollHeight - 2
    let active = headings[0]
    if (atEnd) {
      active = headings[headings.length - 1]
    } else {
      for (const heading of headings) {
        if (heading.getBoundingClientRect().top > line) break
        active = heading
      }
    }
    this.tocLinkTargets.forEach((link) => {
      if (link.getAttribute("href") === `#${active.id}`) link.setAttribute("aria-current", "location")
      else link.removeAttribute("aria-current")
    })
  }

  keydown(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey || event.defaultPrevented) return
    const origin = event.target
    if (origin instanceof Element && (origin.isContentEditable || origin.matches("input, textarea, select"))) return

    const field = this.searchTargets.find((input) => input.checkVisibility({ visibilityProperty: true }))
    if (!field) return
    event.preventDefault()
    field.focus()
    field.select()
  }

  enhanceCode() {
    if (!this.hasCopyTemplateTarget) return
    const template = this.copyTemplateTarget.content.firstElementChild
    this.proseTargets.forEach((prose) => {
      prose.querySelectorAll("pre").forEach((pre) => {
        if (pre.parentElement.hasAttribute("data-docs-code")) return
        const wrapper = template.cloneNode(true)
        pre.before(wrapper)
        wrapper.prepend(pre)
      })
    })
  }

  copy(event) {
    const button = event.currentTarget
    const text = button.closest("[data-docs-code]").querySelector("pre").textContent
    return this.writeText(text).then(() => this.copied(button), () => {})
  }

  writeText(text) {
    if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text)

    // Insecure (plain HTTP) origins have no async clipboard API.
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.append(area)
    area.select()
    const copied = document.execCommand("copy")
    area.remove()
    return copied ? Promise.resolve() : Promise.reject(new Error("copy failed"))
  }

  copied(button) {
    const label = button.querySelector("[data-docs-copy-label]")
    label.textContent = this.copiedLabelValue
    button.dataset.copied = "true"
    const timer = setTimeout(() => {
      this.timers.delete(timer)
      label.textContent = this.copyLabelValue
      delete button.dataset.copied
    }, 2000)
    this.timers.add(timer)
  }
}
