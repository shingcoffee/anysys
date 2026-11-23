import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { SaveManager } from "controllers/page_builder/save_manager"
import { makeCtrl } from "../../support/page_builder.js"

function ctrlFor(overrides = {}) {
  const saveText = document.createElement("span")
  const saveBtn = document.createElement("button")
  const ctrl = makeCtrl({
    configuration: {
      pages: [{ id: "p1", fields: [] }],
      form_settings: {},
      wizard_settings: {},
      rules: [],
      calculations: [],
      theme: {},
    },
    metadata: { entity_id: 1 },
    activePageValue: "p1",
    isSaving: false,
    isDirty: false,
    currentSaveAbort: null,
    lastSavedAt: null,
    // Save controls exist in multiple places (toolbar + settings-modal footer),
    // so the manager drives them as Stimulus target *arrays*.
    saveTextTargets: [saveText],
    saveBtnTargets: [saveBtn],
    ...overrides,
  })
  return { ctrl, saveText, saveBtn }
}

// The save-error notification is appended to document.body (mirroring the
// flowchart editor); query it via this selector.
const NOTICE = ".fixed.top-4.right-4"

// Build the settings-modal DOM (panel → scroll pane → error banner) and wire it
// onto the stub controller, so the manager can route the error into the modal.
function attachSettingsModal(ctrl, { open = true } = {}) {
  const panel = document.createElement("div")
  panel.setAttribute("data-tab-panel", "settings")
  if (!open) panel.classList.add("hidden")
  const scroller = document.createElement("div")
  scroller.className = "overflow-y-auto"
  const banner = document.createElement("div")
  banner.classList.add("hidden")
  const message = document.createElement("p")
  banner.appendChild(message)
  scroller.appendChild(banner)
  panel.appendChild(scroller)
  document.body.appendChild(panel)

  ctrl.hasSettingsSaveErrorTarget = true
  ctrl.settingsSaveErrorTarget = banner
  ctrl.settingsSaveErrorMessageTarget = message
  return { panel, scroller, banner, message }
}

describe("SaveManager", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    delete global.fetch
    document.body.innerHTML = ""
  })

  describe("markDirty", () => {
    it("sets dirty flags and shows the unsaved indicator", () => {
      const { ctrl, saveText } = ctrlFor()
      new SaveManager(ctrl).markDirty()
      expect(ctrl.isDirty).toBe(true)
      expect(typeof ctrl.lastDirtyAt).toBe("number")
      expect(saveText.textContent).toBe("Save*")
    })

    it("mirrors the indicator across every Save control (toolbar + modal footer)", () => {
      const toolbar = document.createElement("span")
      const modal = document.createElement("span")
      const { ctrl } = ctrlFor({ saveTextTargets: [toolbar, modal] })
      new SaveManager(ctrl).markDirty()
      expect(toolbar.textContent).toBe("Save*")
      expect(modal.textContent).toBe("Save*")
    })
  })

  describe("preview", () => {
    it("serializes the configuration into the preview input and submits", () => {
      const input = document.createElement("input")
      const form = { submit: vi.fn() }
      const { ctrl } = ctrlFor({
        hasPreviewConfigInputTarget: true,
        previewConfigInputTarget: input,
        hasPreviewFormTarget: true,
        previewFormTarget: form,
      })
      new SaveManager(ctrl).preview()
      const payload = JSON.parse(input.value)
      expect(payload.preview_active_page).toBe("p1")
      expect(payload.pages).toEqual(ctrl.configuration.pages)
      expect(form.submit).toHaveBeenCalled()
    })

    it("falls back to an empty pages array when configuration.pages is unset", () => {
      const input = document.createElement("input")
      const { ctrl } = ctrlFor({
        configuration: { pages: undefined, form_settings: {}, wizard_settings: {}, rules: [], calculations: [], theme: {} },
        hasPreviewConfigInputTarget: true,
        previewConfigInputTarget: input,
        hasPreviewFormTarget: false,
      })
      new SaveManager(ctrl).preview()
      const payload = JSON.parse(input.value)
      expect(payload.pages).toEqual([])
    })
  })

  describe("performSave", () => {
    it("PATCHes and clears the dirty flag on success", async () => {
      global.fetch = vi.fn(async () => ({
        status: 200,
        ok: true,
        json: async () => ({ updated_at: "2026-01-01T00:00:00Z" }),
      }))
      const { ctrl, saveText } = ctrlFor({ isDirty: true })
      await new SaveManager(ctrl).performSave()
      expect(global.fetch).toHaveBeenCalledWith(
        "/123/admin/maintenance/pages/1",
        expect.objectContaining({ method: "PATCH" }),
      )
      expect(ctrl.isDirty).toBe(false)
      expect(ctrl.lastSavedAt).toBe("2026-01-01T00:00:00Z")
      expect(saveText.textContent).toBe("Saved")
      expect(ctrl.isSaving).toBe(false)
    })

    it("bails out immediately when a save is already in flight", async () => {
      global.fetch = vi.fn()
      const { ctrl } = ctrlFor({ isSaving: true })
      await new SaveManager(ctrl).performSave()
      expect(global.fetch).not.toHaveBeenCalled()
    })

    it("surfaces the server's joined reasons in a banner and keeps the button dirty on rejection", async () => {
      vi.spyOn(console, "error").mockImplementation(() => {})
      global.fetch = vi.fn(async () => ({
        status: 422,
        ok: false,
        json: async () => ({ status: "error", errors: ["Handoff module is not enabled", "Amount is required"] }),
      }))
      const { ctrl, saveText } = ctrlFor()
      await new SaveManager(ctrl).performSave()
      expect(ctrl.isDirty).toBe(true)
      expect(saveText.textContent).toBe("Save*")
      const notice = document.querySelector(NOTICE)
      expect(notice).not.toBeNull()
      expect(notice.textContent).toBe("Handoff module is not enabled, Amount is required")
      expect(notice.className).toContain("bg-red-100")
    })

    it("prompts a conflict resolution on 409", async () => {
      const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false)
      global.fetch = vi.fn(async () => ({
        status: 409,
        ok: false,
        json: async () => ({}),
      }))
      const { ctrl, saveText } = ctrlFor()
      await new SaveManager(ctrl).performSave()
      expect(saveText.textContent).toBe("Conflict")
      expect(confirmSpy).toHaveBeenCalled()
    })

    it("keeps the unsaved marker when new edits arrive mid-request", async () => {
      const { ctrl, saveText } = ctrlFor()
      global.fetch = vi.fn(async () => {
        // Simulate a fresh edit landing after the request started.
        ctrl.lastDirtyAt = Date.now() + 10_000
        return { status: 200, ok: true, json: async () => ({ updated_at: "t" }) }
      })
      await new SaveManager(ctrl).performSave()
      expect(saveText.textContent).toBe("Save*")
    })

    it("swallows AbortError without showing a notification", async () => {
      const err = new Error("aborted")
      err.name = "AbortError"
      global.fetch = vi.fn(async () => { throw err })
      const { ctrl } = ctrlFor()
      await new SaveManager(ctrl).performSave()
      expect(document.querySelector(NOTICE)).toBeNull()
    })

    it("preserves existing captcha config when the toggle input isn't rendered", async () => {
      const { ctrl } = ctrlFor({
        configuration: {
          pages: [{ id: "p1", fields: [] }],
          form_settings: {},
          wizard_settings: {},
          rules: [],
          calculations: [],
          theme: {},
          captcha: { enabled: true },
        },
      })
      global.fetch = vi.fn(async (_url, opts) => {
        const body = JSON.parse(opts.body)
        const config = JSON.parse(body.page.configuration)
        expect(config.captcha).toEqual({ enabled: true })
        return { status: 200, ok: true, json: async () => ({}) }
      })
      await new SaveManager(ctrl).performSave()
      expect(global.fetch).toHaveBeenCalled()
    })

    it("sends no CSRF token when the meta tag is absent", async () => {
      const { ctrl } = ctrlFor()
      global.fetch = vi.fn(async (_url, opts) => {
        expect(opts.headers["X-CSRF-Token"]).toBeUndefined()
        return { status: 200, ok: true, json: async () => ({}) }
      })
      await new SaveManager(ctrl).performSave()
      expect(global.fetch).toHaveBeenCalled()
    })

    it("reads the CSRF token from the meta tag when present", async () => {
      const meta = document.createElement("meta")
      meta.setAttribute("name", "csrf-token")
      meta.setAttribute("content", "tok-123")
      document.head.appendChild(meta)
      const { ctrl } = ctrlFor()
      global.fetch = vi.fn(async (_url, opts) => {
        expect(opts.headers["X-CSRF-Token"]).toBe("tok-123")
        return { status: 200, ok: true, json: async () => ({}) }
      })
      await new SaveManager(ctrl).performSave()
      expect(global.fetch).toHaveBeenCalled()
      meta.remove()
    })

    it("clears the 'Saved' indicator back to 'Save' after the timeout, if still not dirty", async () => {
      vi.useFakeTimers()
      global.fetch = vi.fn(async () => ({
        status: 200,
        ok: true,
        json: async () => ({ updated_at: "t" }),
      }))
      const { ctrl, saveText } = ctrlFor()
      await new SaveManager(ctrl).performSave()
      expect(saveText.textContent).toBe("Saved")
      vi.advanceTimersByTime(2000)
      expect(saveText.textContent).toBe("Save")
      vi.useRealTimers()
    })

    it("leaves the 'Saved' indicator alone if a new edit landed before the timeout fires", async () => {
      vi.useFakeTimers()
      global.fetch = vi.fn(async () => ({
        status: 200,
        ok: true,
        json: async () => ({ updated_at: "t" }),
      }))
      const { ctrl, saveText } = ctrlFor()
      await new SaveManager(ctrl).performSave()
      ctrl.isDirty = true
      vi.advanceTimersByTime(2000)
      expect(saveText.textContent).toBe("Saved")
      vi.useRealTimers()
    })

    it("logs and shows a generic banner on a non-abort exception", async () => {
      vi.spyOn(console, "error").mockImplementation(() => {})
      global.fetch = vi.fn(async () => { throw new Error("network down") })
      const { ctrl, saveText } = ctrlFor()
      await new SaveManager(ctrl).performSave()
      expect(saveText.textContent).toBe("Save*")
      expect(document.querySelector(NOTICE).textContent).toBe("Couldn't save the page. Please try again.")
      expect(console.error).toHaveBeenCalledWith("Save error:", expect.any(Error))
    })

    it("shows the failure atop the settings modal (and scrolls it up) when the modal is open", async () => {
      vi.spyOn(console, "error").mockImplementation(() => {})
      global.fetch = vi.fn(async () => ({
        status: 422, ok: false, json: async () => ({ errors: ["Amount is required"] }),
      }))
      const { ctrl } = ctrlFor()
      const { banner, message, scroller } = attachSettingsModal(ctrl, { open: true })
      scroller.scrollTop = 500 // user had scrolled down
      await new SaveManager(ctrl).performSave()
      expect(banner.classList.contains("hidden")).toBe(false)
      expect(message.textContent).toBe("Amount is required")
      expect(scroller.scrollTop).toBe(0)
      expect(document.querySelector(NOTICE)).toBeNull() // no top-right toast while modal is open
    })

    it("falls back to the top-right notification when the settings modal is closed", async () => {
      vi.spyOn(console, "error").mockImplementation(() => {})
      global.fetch = vi.fn(async () => ({
        status: 422, ok: false, json: async () => ({ errors: ["Amount is required"] }),
      }))
      const { ctrl } = ctrlFor()
      const { banner } = attachSettingsModal(ctrl, { open: false })
      await new SaveManager(ctrl).performSave()
      expect(banner.classList.contains("hidden")).toBe(true)
      expect(document.querySelector(NOTICE)).not.toBeNull()
    })

    it("reloads the page when the user accepts the conflict prompt", async () => {
      const originalLocation = window.location
      window.location = { ...originalLocation, reload: vi.fn() }
      vi.spyOn(window, "confirm").mockReturnValue(true)
      global.fetch = vi.fn(async () => ({
        status: 409,
        ok: false,
        json: async () => ({}),
      }))
      const { ctrl } = ctrlFor()
      await new SaveManager(ctrl).performSave()
      expect(window.location.reload).toHaveBeenCalled()
      window.location = originalLocation
    })
  })

  describe("save-error notification", () => {
    it("appends a top-right error banner carrying the message", () => {
      const { ctrl } = ctrlFor()
      new SaveManager(ctrl)._notify("Amount is required")
      const notice = document.querySelector(NOTICE)
      expect(notice.textContent).toBe("Amount is required")
      expect(notice.getAttribute("role")).toBe("alert")
      expect(notice.className).toContain("bg-red-100")
    })

    it("writes the message with textContent so server text can't inject markup", () => {
      const { ctrl } = ctrlFor()
      new SaveManager(ctrl)._notify("<img src=x onerror=alert(1)>")
      const notice = document.querySelector(NOTICE)
      expect(notice.querySelector("img")).toBeNull()
      expect(notice.textContent).toContain("<img")
    })

    it("auto-dismisses after 5s (slides out, then removes)", () => {
      vi.useFakeTimers()
      const { ctrl } = ctrlFor()
      new SaveManager(ctrl)._notify("boom")
      expect(document.querySelector(NOTICE)).not.toBeNull()
      vi.advanceTimersByTime(5000)
      expect(document.querySelector(NOTICE).style.opacity).toBe("0")
      vi.advanceTimersByTime(300)
      expect(document.querySelector(NOTICE)).toBeNull()
      vi.useRealTimers()
    })
  })

  describe("settings-modal save error", () => {
    it("routes to the top-right notification when no in-modal banner exists", () => {
      const { ctrl } = ctrlFor()
      new SaveManager(ctrl)._handleSaveError(["boom"])
      expect(document.querySelector(NOTICE).textContent).toBe("boom")
    })

    it("_showModalError tolerates a banner with no scroll container", () => {
      const { ctrl } = ctrlFor()
      const banner = document.createElement("div")
      banner.classList.add("hidden")
      const message = document.createElement("p")
      banner.appendChild(message)
      document.body.appendChild(banner) // not inside an .overflow-y-auto pane
      ctrl.hasSettingsSaveErrorTarget = true
      ctrl.settingsSaveErrorTarget = banner
      ctrl.settingsSaveErrorMessageTarget = message
      expect(() => new SaveManager(ctrl)._showModalError("x")).not.toThrow()
      expect(banner.classList.contains("hidden")).toBe(false)
    })

    it("hideModalError hides the banner", () => {
      const { ctrl } = ctrlFor()
      const { banner } = attachSettingsModal(ctrl, { open: true })
      banner.classList.remove("hidden")
      new SaveManager(ctrl).hideModalError()
      expect(banner.classList.contains("hidden")).toBe(true)
    })

    it("hideModalError is a no-op when there is no banner target", () => {
      const { ctrl } = ctrlFor()
      expect(() => new SaveManager(ctrl).hideModalError()).not.toThrow()
    })
  })

  describe("save", () => {
    it("aborts an in-flight request before starting a new one", async () => {
      const abort = { abort: vi.fn() }
      global.fetch = vi.fn(async () => ({ status: 200, ok: true, json: async () => ({}) }))
      const { ctrl } = ctrlFor({ currentSaveAbort: abort })
      await new SaveManager(ctrl).save()
      expect(abort.abort).toHaveBeenCalled()
    })
  })
})
