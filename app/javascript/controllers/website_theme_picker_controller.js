import { Controller } from "@hotwired/stimulus"

// Live theme preview + in-page section nav. Token class maps and nav
// class lists are supplied by the server via Stimulus values/classes.
// Preset radios carry their token set in data-tokens; picking one checks
// the matching token radios, and drifting from it reveals "customized".
export default class extends Controller {
  static targets = [
    "token", "preview", "stage", "kicker", "headline", "body", "button", "nav", "section", "preset", "customized"
  ]
  static values = { tokens: { type: Object, default: {} } }
  static classes = ["navActive", "navInactive"]

  connect() {
    this.observe()
    this.apply()
    this.syncNavFromHash()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
  }

  apply() {
    this.syncCustomized()
    const appearance = this.selectedValue("appearance")
    const accent = this.selectedValue("accent")
    const type = this.selectedValue("type")
    const density = this.selectedValue("density")
    const corners = this.selectedValue("corners")
    const neutral = this.selectedValue("neutral")
    const looks = this.tokensValue[appearance]
    if (!looks) return

    const accentPack = (looks.accents || {})[accent] || {}
    const typePack = (this.tokensValue.types || {})[type] || {}
    const densityPack = (this.tokensValue.densities || {})[density] || {}
    const cornerPack = (this.tokensValue.corners || {})[corners] || {}
    const neutralPack = (this.tokensValue.neutrals || {})[neutral] || {}

    this.stylePreview(looks, typePack, densityPack, [typePack.style, cornerPack.style, neutralPack.style])
    this.styleKicker(accentPack)
    this.styleHeadline(typePack)
    this.styleBody(looks, typePack)
    this.styleButton(accentPack, cornerPack)
    this.writePreviewData({ appearance, accent, type, density, corners, neutral })
  }

  applyPreset(event) {
    const tokens = this.presetTokens(event.currentTarget)
    this.tokenTargets.forEach((el) => {
      if (el.dataset.token in tokens) el.checked = el.value === tokens[el.dataset.token]
    })
    this.apply()
  }

  syncCustomized() {
    if (!this.hasCustomizedTarget) return
    const preset = this.hasPresetTarget ? this.presetTargets.find((el) => el.checked) : null
    const tokens = preset ? this.presetTokens(preset) : {}
    const drifted = Object.keys(tokens).some((token) => this.selectedValue(token) !== tokens[token])
    this.customizedTargets.forEach((badge) => {
      badge.classList.toggle("hidden", !(preset && drifted && badge.dataset.preset === preset.value))
    })
  }

  presetTokens(el) {
    try {
      const tokens = JSON.parse(el.dataset.tokens || "{}")
      return tokens && typeof tokens === "object" ? tokens : {}
    } catch {
      return {}
    }
  }

  highlight(event) {
    this.setActiveNav(event.currentTarget.getAttribute("href"))
  }

  onIntersect(entries) {
    const visible = entries.filter((entry) => entry.isIntersecting).pop()
    if (!visible) return
    const labelled = visible.target.getAttribute?.("aria-labelledby")
    const id = labelled || visible.target.id
    if (!id) return
    this.setActiveNav(`#${id}`)
  }

  selectedValue(token) {
    if (!this.hasTokenTarget) return ""
    const input = this.tokenTargets.find((el) => el.dataset.token === token && el.checked)
    return input ? input.value : ""
  }

  observe() {
    if (typeof IntersectionObserver !== "function") return
    if (!this.hasSectionTarget) return
    this.observer = new IntersectionObserver((entries) => this.onIntersect(entries), {
      rootMargin: "-20% 0px -60% 0px",
      threshold: 0
    })
    this.sectionTargets.forEach((section) => this.observer.observe(section))
  }

  syncNavFromHash() {
    if (window.location.hash) {
      this.setActiveNav(window.location.hash)
      return
    }
    if (this.hasNavTarget) this.setActiveNav(this.navTargets[0].getAttribute("href"))
  }

  setActiveNav(href) {
    if (!this.hasNavTarget || !href) return
    this.navTargets.forEach((link) => {
      const active = link.getAttribute("href") === href
      this.navActiveClasses.forEach((cls) => link.classList.toggle(cls, active))
      this.navInactiveClasses.forEach((cls) => link.classList.toggle(cls, !active))
      if (active) {
        link.setAttribute("aria-current", "location")
        this.revealNav(link)
      } else {
        link.removeAttribute("aria-current")
      }
    })
  }

  // Below xl the nav is a horizontal chip strip; keep the active chip in view
  // without moving the page vertically.
  revealNav(link) {
    const strip = link.parentElement
    if (!strip || strip.scrollWidth <= strip.clientWidth) return
    const offset = link.getBoundingClientRect().left - strip.getBoundingClientRect().left
    strip.scrollBy({ left: offset - (strip.clientWidth - link.offsetWidth) / 2, behavior: "smooth" })
  }

  stylePreview(looks, typePack, densityPack, styles) {
    if (!this.hasPreviewTarget) return
    const extras = [looks.page, typePack.body]
    if (!this.hasStageTarget) extras.push(densityPack.pad)
    this.applyClass(this.previewTarget, extras.filter(Boolean).join(" "))
    this.previewTarget.style.cssText = styles.filter(Boolean).join(" ")
    if (this.hasStageTarget) this.applyClass(this.stageTarget, densityPack.pad)
  }

  styleKicker(accentPack) {
    if (!this.hasKickerTarget) return
    this.applyClass(this.kickerTarget, accentPack.kicker)
  }

  styleHeadline(typePack) {
    if (!this.hasHeadlineTarget) return
    this.applyClass(this.headlineTarget, typePack.headline)
  }

  styleBody(looks, typePack) {
    if (!this.hasBodyTarget) return
    this.applyClass(this.bodyTarget, [looks.muted, typePack.body].filter(Boolean).join(" "))
  }

  styleButton(accentPack, cornerPack) {
    if (!this.hasButtonTarget) return
    this.applyClass(this.buttonTarget, [cornerPack.button, accentPack.button].filter(Boolean).join(" "))
  }

  writePreviewData(tokens) {
    if (!this.hasPreviewTarget) return
    Object.entries(tokens).forEach(([token, value]) => { this.previewTarget.dataset[token] = value })
  }

  applyClass(el, extra) {
    const base = el.dataset.baseClass || ""
    el.className = [base, extra].filter(Boolean).join(" ")
  }
}
