import { describe, it, expect, afterEach } from "vitest"
import {
  TOPBAR_MENU_OPEN,
  announceTopbarMenuOpen,
  onPeerTopbarMenuOpen
} from "controllers/shared/topbar_menu"

describe("topbar_menu helpers", () => {
  afterEach(() => {
    document.querySelectorAll("[data-test-root]").forEach((el) => el.remove())
  })

  it("announceTopbarMenuOpen dispatches with the source element", () => {
    const source = document.createElement("div")
    let received = null
    const handler = (event) => { received = event }
    document.addEventListener(TOPBAR_MENU_OPEN, handler)
    announceTopbarMenuOpen(source)
    document.removeEventListener(TOPBAR_MENU_OPEN, handler)
    expect(received?.detail?.source).toBe(source)
  })

  it("onPeerTopbarMenuOpen closes only for other sources", () => {
    const self = document.createElement("div")
    self.dataset.testRoot = "1"
    document.body.appendChild(self)
    const closeFn = vi.fn()
    const handler = onPeerTopbarMenuOpen(self, closeFn)

    document.dispatchEvent(new CustomEvent(TOPBAR_MENU_OPEN, { detail: { source: self } }))
    expect(closeFn).not.toHaveBeenCalled()

    document.dispatchEvent(new CustomEvent(TOPBAR_MENU_OPEN, {
      detail: { source: document.createElement("div") }
    }))
    expect(closeFn).toHaveBeenCalledTimes(1)

    document.removeEventListener(TOPBAR_MENU_OPEN, handler)
  })
})
