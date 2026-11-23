import { describe, it, expect, vi } from "vitest"
import { requestPins, subscribePinResults } from "controllers/property_editor/pin_request"

const deferred = () => {
  let resolve, reject
  const promise = new Promise((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}

describe("shared pin requests", () => {
  it("coalesces identical in-flight reads, commits once and notifies active subscribers", async () => {
    const canvas = {}, response = deferred(), commit = vi.fn(), listener = vi.fn()
    const read = () => ({ action: "find_model" })
    const load = vi.fn(() => response.promise)
    const stop = subscribePinResults(canvas, "step:1", listener)
    const first = requestPins(canvas, "step:1", read, load, commit)
    expect(requestPins(canvas, "step:1", read, load, commit)).toBe(first)
    response.resolve({ outputs: ["model"] })
    await first
    expect(load).toHaveBeenCalledTimes(1)
    expect(commit).toHaveBeenCalledTimes(1)
    expect(listener).toHaveBeenCalledWith({ outputs: ["model"] })
    stop()
    await requestPins(canvas, "step:1", read, load, commit)
    expect(load).toHaveBeenCalledTimes(2)
    expect(listener).toHaveBeenCalledTimes(1)
  })

  it.each(["old", "fresh"])("rejects superseded results when %s finishes first", async order => {
    const canvas = {}, old = deferred(), fresh = deferred(), commit = vi.fn()
    let config = { value: 1 }
    const first = requestPins(canvas, "element:1", () => config, () => old.promise, commit)
    config.value = 2
    const second = requestPins(canvas, "element:1", () => config, () => fresh.promise, commit)
    if (order === "old") { old.resolve("old"); await first; expect(commit).not.toHaveBeenCalled() }
    fresh.resolve("fresh")
    await second
    if (order === "fresh") { old.resolve("old"); await first }
    expect(commit.mock.calls).toEqual([["fresh"]])
  })

  it("rejects configuration mutation/removal without a newer request", async () => {
    const canvas = {}, response = deferred(), commit = vi.fn()
    let config = { value: 1 }
    const pending = requestPins(canvas, "element:1", () => config, () => response.promise, commit)
    config = undefined
    response.resolve("obsolete")
    expect(await pending).toBeUndefined()
    expect(commit).not.toHaveBeenCalled()
  })

  it("isolates canvas and record keys", async () => {
    const canvas = {}, commit = vi.fn(), response = deferred()
    const first = requestPins(canvas, "element:1", () => 1, () => response.promise, commit)
    await requestPins({}, "element:1", () => 1, async () => "other canvas", commit)
    await requestPins(canvas, "step:1", () => 1, async () => "other record", commit)
    response.resolve("first")
    await first
    expect(commit.mock.calls).toEqual([["other canvas"], ["other record"], ["first"]])
  })

  it("cleans up rejected requests so a later retry can load again", async () => {
    const canvas = {}, response = deferred(), commit = vi.fn()
    const pending = requestPins(canvas, "element:1", () => 1, () => response.promise, commit)
    response.reject(new Error("offline"))
    await expect(pending).rejects.toThrow("offline")
    expect(await requestPins(canvas, "element:1", () => 1, async () => "retry", commit)).toBe("retry")
  })
})
