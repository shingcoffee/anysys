import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { VersionHistoryMixin } from "controllers/flowchart_canvas/version_history_mixin"
import { mixinHost } from "../../support/flowchart.js"

function host(extra = {}) {
  document.body.innerHTML = `<div data-list></div><span data-count></span>`
  return mixinHost(VersionHistoryMixin, {
    idValue: 7,
    customerIdValue: 42,
    hasVersionListTarget: true,
    versionListTarget: document.querySelector("[data-list]"),
    hasVersionCountTarget: true,
    versionCountTarget: document.querySelector("[data-count]"),
    _toggleBottomTab: vi.fn(),
    openBottomPanel: vi.fn(),
    closeBottomPanel: vi.fn(),
    loadVersions: VersionHistoryMixin.loadVersions,
    canvas: { loadConfiguration: vi.fn() },
    _updateUnsavedIndicator: vi.fn(),
    undoRedoManager: { undoStack: [1], redoStack: [2], saveInitialState: vi.fn() },
    minimapManager: { update: vi.fn() },
    hasUnsavedChanges: true,
    showToast: vi.fn(),
    _adoptHeadVersion: vi.fn(),
    urlsValue: {
      versions: "/tenant/flowcharts/7/versions"
    },
    ...extra,
  })
}

const jsonHeaders = { get: () => "application/json; charset=utf-8" }
const htmlHeaders = { get: () => "text/html" }

const VERSIONS = [
  { id: 1, version_number: 3, description: "Third", created_at: "2026-01-02T10:00:00Z" },
  { id: 2, version_number: 2, description: null, created_at: "2026-01-01T10:00:00Z" },
]

// Every restoreVersion test dispatches the same button event (version 2).
const restoreEvent = { currentTarget: { dataset: { versionId: "2", versionNumber: "2" } } }

afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals() })

describe("VersionHistoryMixin — panel toggles", () => {
  it("delegate to the bottom-panel helpers", () => {
    const h = host()
    h.toggleVersionPanel(); expect(h._toggleBottomTab).toHaveBeenCalledWith("history")
    h.openVersionPanel();   expect(h.openBottomPanel).toHaveBeenCalledWith("history")
    h.closeVersionPanel();  expect(h.closeBottomPanel).toHaveBeenCalled()
  })
})

describe("VersionHistoryMixin.loadVersions", () => {
  it("bails out without id/customer", async () => {
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const h = host({ idValue: null })
    await h.loadVersions()
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it("bails out without a versions URL", async () => {
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const h = host({ urlsValue: {} })
    await h.loadVersions()
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it("renders the version list on a 200 response", async () => {
    const fetchMock = vi.fn(async () => ({ ok: true, json: async () => VERSIONS }))
    vi.stubGlobal("fetch", fetchMock)
    const h = host()
    await h.loadVersions()
    expect(fetchMock).toHaveBeenCalledWith(
      "/tenant/flowcharts/7/versions",
      expect.objectContaining({ headers: expect.any(Object) })
    )
    expect(h.versionCountTarget.textContent).toBe("2 versions")
    const buttons = h.versionListTarget.querySelectorAll("button[data-version-id]")
    expect(buttons.length).toBe(2)
    expect(h.versionListTarget.innerHTML).toContain("v3")
    expect(h.versionListTarget.innerHTML).toContain("No description") // null description
  })

  it("renders an error message on a non-OK response", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false })))
    const h = host()
    await h.loadVersions()
    expect(h.versionListTarget.innerHTML).toContain("Failed to load versions")
  })

  it("renders a network-error message when fetch throws", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("boom") }))
    const h = host()
    await h.loadVersions()
    expect(h.versionListTarget.innerHTML).toContain("Network error: boom")
  })
})

describe("VersionHistoryMixin._renderVersionList", () => {
  it("shows an empty-state and singular count", () => {
    const h = host()
    h._renderVersionList([])
    expect(h.versionCountTarget.textContent).toBe("0 versions")
    expect(h.versionListTarget.innerHTML).toContain("No versions saved yet")
  })

  it("uses a singular label for exactly one version", () => {
    const h = host()
    h._renderVersionList([VERSIONS[0]])
    expect(h.versionCountTarget.textContent).toBe("1 version")
  })

  it("no-ops without a version-list target", () => {
    const h = host({ hasVersionListTarget: false })
    expect(() => h._renderVersionList(VERSIONS)).not.toThrow()
  })
})

describe("P5-6 VersionHistoryMixin — locale-aware timestamps and version label", () => {
  const expected = (locale, iso) =>
    new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "short" }).format(new Date(iso))

  it("formats the timestamp with the app locale (no browser locale, no ' at ' literal)", () => {
    const h = host()
    h._renderVersionList([VERSIONS[0]])
    const stamp = h.versionListTarget.querySelector(".text-xs.text-slate-500").textContent
    expect(stamp).toBe(expected("en", VERSIONS[0].created_at))

    const zh = host({ appLocaleValue: "zh-CN" })
    zh._renderVersionList([VERSIONS[0]])
    expect(zh.versionListTarget.querySelector(".text-xs.text-slate-500").textContent)
      .toBe(expected("zh-CN", VERSIONS[0].created_at))
  })

  it("labels the version through the {number} format value", () => {
    const h = host({ versionLabelFormatValue: "版本 {number}" })
    h._renderVersionList([VERSIONS[0]])
    expect(h.versionListTarget.querySelector(".bg-indigo-100").textContent).toBe("版本 3")
    expect(h.versionListTarget.innerHTML).not.toContain(">v3<")
  })

  it("leaves the timestamp empty for an unparseable created_at", () => {
    const h = host()
    h._renderVersionList([{ ...VERSIONS[0], created_at: "not-a-date" }])
    expect(h.versionListTarget.querySelector(".text-xs.text-slate-500").textContent).toBe("")
  })
})

describe("VersionHistoryMixin._renderVersionError", () => {
  it("no-ops without a version-list target", () => {
    const h = host({ hasVersionListTarget: false })
    expect(() => h._renderVersionError("boom")).not.toThrow()
  })
})

describe("VersionHistoryMixin.restoreVersion", () => {
  it("returns early when the user cancels the confirm", async () => {
    vi.stubGlobal("confirm", vi.fn(() => false))
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const h = host()
    await h.restoreVersion({ currentTarget: { dataset: { versionId: "2", versionNumber: "2" } } })
    expect(fetchSpy).not.toHaveBeenCalled()
    vi.unstubAllGlobals()
  })

  it("confirms with the new-head wording, interpolating the version number", async () => {
    const confirmSpy = vi.fn(() => false)
    vi.stubGlobal("confirm", confirmSpy)
    const h = host()
    await h.restoreVersion(restoreEvent)
    expect(confirmSpy).toHaveBeenCalledWith(
      "Restore version 2? This creates a new head version with its content; the current head stays in the version history."
    )
  })

  it("adopts the new head version id and revision returned by the restore", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ version_id: 55, head_revision: "r55" }) })))
    const h = host()
    vi.spyOn(h, "loadVersions").mockResolvedValue()
    await h.restoreVersion(restoreEvent)
    expect(h._adoptHeadVersion).toHaveBeenCalledWith(55, "r55")
  })

  it("loads the restored configuration and resets undo history on success", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    const config = { elements: [], connections: [] }
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ configuration: config }) })))
    const h = host()
    const loadSpy = vi.spyOn(h, "loadVersions").mockResolvedValue()
    await h.restoreVersion({ currentTarget: { dataset: { versionId: "2", versionNumber: "2" } } })
    expect(h.canvas.loadConfiguration).toHaveBeenCalledWith(config)
    expect(h.hasUnsavedChanges).toBe(false)
    expect(h.undoRedoManager.undoStack).toEqual([])
    expect(h.undoRedoManager.redoStack).toEqual([])
    expect(h.undoRedoManager.saveInitialState).toHaveBeenCalled()
    expect(h.minimapManager.update).toHaveBeenCalled()
    expect(loadSpy).toHaveBeenCalled() // refreshes the list
    vi.unstubAllGlobals()
  })

  it("toasts the server message on a failed restore", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, headers: jsonHeaders, json: async () => ({ message: "cannot restore" }) })))
    const h = host()
    await h.restoreVersion({ currentTarget: { dataset: { versionId: "2", versionNumber: "2" } } })
    expect(h.showToast).toHaveBeenCalledWith("cannot restore", "error")
    vi.unstubAllGlobals()
  })

  it("toasts the HTTP-status fallback when the JSON failure payload has no message", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, headers: jsonHeaders, json: async () => ({}) })))
    const h = host()
    await h.restoreVersion(restoreEvent)
    expect(h.showToast).toHaveBeenCalledWith("Restore failed (HTTP 422)", "error")
  })

  it("never parses a non-JSON failure body and toasts the HTTP status", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    const json = vi.fn(async () => { throw new SyntaxError("Unexpected token <") })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 502, headers: htmlHeaders, json })))
    const h = host()
    await h.restoreVersion(restoreEvent)
    expect(json).not.toHaveBeenCalled()
    expect(h.showToast).toHaveBeenCalledWith("Restore failed (HTTP 502)", "error")
  })

  it("treats a missing content-type as non-JSON", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500, headers: { get: () => null }, json: vi.fn() })))
    const h = host()
    await h.restoreVersion(restoreEvent)
    expect(h.showToast).toHaveBeenCalledWith("Restore failed (HTTP 500)", "error")
  })

  it("toasts a network-error message when fetch throws", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("boom") }))
    const h = host()
    await h.restoreVersion({ currentTarget: { dataset: { versionId: "2", versionNumber: "2" } } })
    expect(h.showToast).toHaveBeenCalledWith("Network error: boom", "error")
    vi.unstubAllGlobals()
  })

  it("POSTs restore to urlsValue.versions", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    const fetchMock = vi.fn(async () => ({ ok: true, json: async () => ({}) }))
    vi.stubGlobal("fetch", fetchMock)
    const h = host()
    vi.spyOn(h, "loadVersions").mockResolvedValue()
    await h.restoreVersion({ currentTarget: { dataset: { versionId: "2", versionNumber: "2" } } })
    expect(fetchMock).toHaveBeenCalledWith(
      "/tenant/flowcharts/7/versions",
      expect.objectContaining({ method: "POST" })
    )
    vi.unstubAllGlobals()
  })

  it("bails out when versions URL is missing after confirm", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const h = host({ urlsValue: {} })
    await h.restoreVersion({ currentTarget: { dataset: { versionId: "2", versionNumber: "2" } } })
    expect(fetchSpy).not.toHaveBeenCalled()
    vi.unstubAllGlobals()
  })

  it("bails out when versionId is missing from the event", async () => {
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const h = host()
    await h.restoreVersion({ currentTarget: { dataset: {} } })
    expect(fetchSpy).not.toHaveBeenCalled()
    vi.unstubAllGlobals()
  })
})

describe("P5-4 VersionHistoryMixin — leave preview before restore", () => {
  it("leaves preview then refuses when canMutate is false", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const leave = vi.fn()
    const h = host({
      _leavePreviewMode: leave,
      canvas: { loadConfiguration: vi.fn(), canMutate: () => false },
    })
    await h.restoreVersion(restoreEvent)
    expect(leave).toHaveBeenCalledWith({ restore: true })
    expect(fetchSpy).not.toHaveBeenCalled()
  })
})
