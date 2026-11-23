import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { loadStripeJs, _resetForTests } from "lib/stripe_js_loader"

describe("stripe_js_loader", () => {
  afterEach(() => {
    delete window.Stripe
    document.head.innerHTML = ""
    _resetForTests()
    vi.restoreAllMocks()
  })

  it("resolves immediately without injecting a script when Stripe is already present", async () => {
    window.Stripe = vi.fn()
    const appendSpy = vi.spyOn(document.head, "appendChild")

    await expect(loadStripeJs()).resolves.toBeUndefined()
    expect(appendSpy).not.toHaveBeenCalled()
  })

  it("injects exactly one <script src=\"https://js.stripe.com/v3/\"> tag", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const promise = loadStripeJs()
    expect(scripts).toHaveLength(1)
    expect(scripts[0].src).toBe("https://js.stripe.com/v3/")
    expect(scripts[0].async).toBe(true)

    scripts[0].onload()
    await expect(promise).resolves.toBeUndefined()
  })

  it("memoizes concurrent calls: only one script tag for many simultaneous callers", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const promises = [loadStripeJs(), loadStripeJs(), loadStripeJs()]
    expect(scripts).toHaveLength(1)

    scripts[0].onload()
    await expect(Promise.all(promises)).resolves.toEqual([undefined, undefined, undefined])
  })

  it("propagates the rejection to every concurrent caller when the script fails to load", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const first = loadStripeJs()
    const second = loadStripeJs()
    scripts[0].onerror()

    await expect(first).rejects.toThrow("Failed to load Stripe.js")
    await expect(second).rejects.toThrow("Failed to load Stripe.js")
    expect(scripts).toHaveLength(1)
  })

  it("retries with a fresh script tag after a prior load failed", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const failed = loadStripeJs()
    scripts[0].onerror()
    await expect(failed).rejects.toThrow("Failed to load Stripe.js")

    const retried = loadStripeJs()
    expect(scripts).toHaveLength(2)
    scripts[1].onload()
    await expect(retried).resolves.toBeUndefined()
  })
})
