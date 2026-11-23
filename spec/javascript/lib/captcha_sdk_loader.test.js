import { describe, it, expect, vi, afterEach } from "vitest"
import { loadCaptchaSdk, _resetForTests } from "lib/captcha_sdk_loader"

describe("captcha_sdk_loader", () => {
  afterEach(() => {
    document.head.innerHTML = ""
    _resetForTests()
    vi.restoreAllMocks()
  })

  it("resolves immediately without injecting a script when readyCheck() is already true", async () => {
    const appendSpy = vi.spyOn(document.head, "appendChild")

    await expect(loadCaptchaSdk("https://example.com/sdk.js", () => true)).resolves.toBeUndefined()
    expect(appendSpy).not.toHaveBeenCalled()
  })

  it("injects a <script src=url> tag when readyCheck() reports false", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const promise = loadCaptchaSdk("https://example.com/sdk.js", () => false)
    expect(scripts).toHaveLength(1)
    expect(scripts[0].src).toBe("https://example.com/sdk.js")
    expect(scripts[0].async).toBe(true)

    scripts[0].onload()
    await expect(promise).resolves.toBeUndefined()
  })

  it("injects a script when no readyCheck is supplied at all", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const promise = loadCaptchaSdk("https://example.com/no-check.js")
    expect(scripts).toHaveLength(1)

    scripts[0].onload()
    await expect(promise).resolves.toBeUndefined()
  })

  it("memoizes concurrent calls for the SAME url: only one script tag for many simultaneous callers", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const promises = [
      loadCaptchaSdk("https://example.com/sdk.js", () => false),
      loadCaptchaSdk("https://example.com/sdk.js", () => false),
      loadCaptchaSdk("https://example.com/sdk.js", () => false)
    ]
    expect(scripts).toHaveLength(1)

    scripts[0].onload()
    await expect(Promise.all(promises)).resolves.toEqual([undefined, undefined, undefined])
  })

  it("keys the memo per URL: a different url gets its own script tag", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const first = loadCaptchaSdk("https://example.com/a.js", () => false)
    const second = loadCaptchaSdk("https://example.com/b.js", () => false)
    expect(scripts).toHaveLength(2)
    expect(scripts.map((s) => s.src)).toEqual([
      "https://example.com/a.js",
      "https://example.com/b.js"
    ])

    scripts[0].onload()
    scripts[1].onload()
    await expect(Promise.all([first, second])).resolves.toEqual([undefined, undefined])
  })

  it("propagates the rejection to every concurrent caller when the script fails to load", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const first = loadCaptchaSdk("https://example.com/sdk.js", () => false)
    const second = loadCaptchaSdk("https://example.com/sdk.js", () => false)
    scripts[0].onerror()

    await expect(first).rejects.toThrow("Failed to load captcha SDK: https://example.com/sdk.js")
    await expect(second).rejects.toThrow("Failed to load captcha SDK: https://example.com/sdk.js")
    expect(scripts).toHaveLength(1)
  })

  it("retries with a fresh script tag for the same url after a prior load failed", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    const failed = loadCaptchaSdk("https://example.com/sdk.js", () => false)
    scripts[0].onerror()
    await expect(failed).rejects.toThrow("Failed to load captcha SDK: https://example.com/sdk.js")

    const retried = loadCaptchaSdk("https://example.com/sdk.js", () => false)
    expect(scripts).toHaveLength(2)
    scripts[1].onload()
    await expect(retried).resolves.toBeUndefined()
  })

  it("_resetForTests clears every memoized URL, not just one", async () => {
    const scripts = []
    vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      scripts.push(node)
      return node
    })

    loadCaptchaSdk("https://example.com/a.js", () => false)
    loadCaptchaSdk("https://example.com/b.js", () => false)
    expect(scripts).toHaveLength(2)

    _resetForTests()

    loadCaptchaSdk("https://example.com/a.js", () => false)
    expect(scripts).toHaveLength(3)
  })
})
