import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/ai_assistant_conversations_controller"
import { mountController, controllerFor, click, tick } from "../support/stimulus.js"

const flush = () => new Promise((resolve) => setTimeout(resolve, 0))

const COLLECTION_URL = "/81721200/admin/modules/ai_assistant/conversations"
const ALERT_SELECTOR = "#ai_assistant_conversations_alert"
const DIALOG_SELECTOR = "#ai_assistant_conversations_delete_dialog"

const ROWS = [
  { id: 11, title: "Invoice cleanup", archived: false },
  { id: 12, title: "Old ideas", archived: true }
]

// Mirrors ConversationListComponent: every row control carries its own URL and
// id as action params, the panel is a sibling of the toggle button, and both
// the error slot and the delete dialog are server-rendered.
function listHtml(overrides = {}) {
  const attr = (name) => `data-ai-assistant-conversations-${name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}-value`
  const value = (name, fallback) => {
    if (Object.prototype.hasOwnProperty.call(overrides, name)) return `${attr(name)}="${overrides[name]}"`
    return fallback == null ? "" : `${attr(name)}="${fallback}"`
  }

  const rows = (overrides.rows ?? ROWS).map((row) => `
    <li data-ai-assistant-conversations-target="row" data-conversation-id="${row.id}">
      ${row.link === false ? `<span>${row.title}</span>` : `<a href="/assistant?conversation=${row.id}" tabindex="-1">${row.title}</a>`}
      <button type="button"
              data-action="ai-assistant-conversations#rename"
              data-ai-assistant-conversations-id-param="${row.id}"
              ${row.omitRowUrl ? "" : `data-ai-assistant-conversations-url-param="${COLLECTION_URL}/${row.id}"`}
              data-ai-assistant-conversations-title-param="${row.title}">Rename</button>
      <button type="button"
              data-action="ai-assistant-conversations#archive"
              data-ai-assistant-conversations-id-param="${row.id}"
              ${row.omitRowUrl ? "" : `data-ai-assistant-conversations-url-param="${COLLECTION_URL}/${row.id}/archive"`}
              data-ai-assistant-conversations-archived-param="${row.archived}">Archive</button>
      <button type="button"
              data-action="ai-assistant-conversations#destroy"
              data-ai-assistant-conversations-id-param="${row.id}"
              ${row.omitRowUrl ? "" : `data-ai-assistant-conversations-url-param="${COLLECTION_URL}/${row.id}"`}>Delete</button>
    </li>
  `).join("")

  const panel = overrides.omitPanelTarget
    ? `<aside id="ai_assistant_conversations_panel" class="-translate-x-full"><ul>${rows}</ul></aside>`
    : `<aside id="ai_assistant_conversations_panel"
            class="${overrides.panelOpen ? "" : "-translate-x-full"}"
            data-ai-assistant-conversations-target="panel"><ul>${rows}</ul></aside>`

  const backdrop = overrides.omitBackdrop
    ? ""
    : `<div data-ai-assistant-conversations-target="backdrop"
            class="pointer-events-none opacity-0"
            data-action="click->ai-assistant-conversations#close"></div>`

  const alert = overrides.omitAlert
    ? ""
    : `<p id="ai_assistant_conversations_alert"
          class="hidden"
          role="alert"
          aria-live="assertive"
          data-ai-assistant-conversations-target="alert"></p>`

  const dialog = overrides.omitDialog
    ? ""
    : `<dialog id="ai_assistant_conversations_delete_dialog"
               data-ai-assistant-conversations-target="deleteDialog"
               data-action="cancel->ai-assistant-conversations#cancelDestroy">
         <button type="button" autofocus data-action="click->ai-assistant-conversations#cancelDestroy">Cancel</button>
         <button type="button" data-action="click->ai-assistant-conversations#confirmDestroy">Delete chat</button>
       </dialog>`

  const values = [
    value("createUrl", COLLECTION_URL),
    value("baseUrl", COLLECTION_URL),
    value("panelId", overrides.omitPanelTarget ? "ai_assistant_conversations_panel" : ""),
    value("renameLabel", "Chat name"),
    value("saveLabel", "Save"),
    value("cancelLabel", "Cancel"),
    value("failedLabel", "Could not update the chat.")
  ].filter(Boolean).join(" ")

  return `
    <div data-controller="ai-assistant-conversations"
         data-action="ai-assistant:newChat@window->ai-assistant-conversations#create"
         ${values}>
      ${alert}
      <button type="button" data-action="ai-assistant-conversations#create">New chat</button>
      <button type="button"
              aria-expanded="false"
              ${overrides.omitToggleTarget ? "" : `data-ai-assistant-conversations-target="toggle"`}
              data-action="ai-assistant-conversations#toggle">Chats</button>
      <button type="button" data-action="ai-assistant-conversations#close">Close</button>
      ${backdrop}
      ${panel}
      ${dialog}
    </div>
  `
}

function mockFetch(status, { reject = false, json = {}, jsonThrows = false } = {}) {
  const fetchMock = vi.fn().mockImplementation(() => {
    if (reject) return Promise.reject(new Error("network"))
    return Promise.resolve({
      status,
      ok: status >= 200 && status < 300,
      json: jsonThrows ? async () => { throw new Error("no json") } : async () => json
    })
  })
  vi.stubGlobal("fetch", fetchMock)
  return fetchMock
}

// A write the test decides when to settle, for asserting what the page looks
// like while the request is still out.
function deferredFetch({ status = 200, json = {} } = {}) {
  let settle
  const fetchMock = vi.fn().mockImplementation(() => new Promise((resolve) => {
    settle = () => resolve({
      status,
      ok: status >= 200 && status < 300,
      json: async () => json
    })
  }))
  vi.stubGlobal("fetch", fetchMock)
  return { fetchMock, settle: () => settle() }
}

// `window.location.assign` is not implemented in happy-dom, and navigating
// would tear the fixture down anyway.
function stubLocation(href = "https://app.test/81721200/admin/assistant") {
  const assign = vi.fn()
  const previous = Object.getOwnPropertyDescriptor(window, "location")
  Object.defineProperty(window, "location", { configurable: true, value: { href, assign } })
  return { assign, restore: () => { if (previous) Object.defineProperty(window, "location", previous) } }
}

function stubTurbo() {
  const visit = vi.fn()
  vi.stubGlobal("Turbo", { visit })
  return visit
}

const alertIn = (element) => element.querySelector(ALERT_SELECTOR)
const alertText = (element) => {
  const alert = alertIn(element)
  if (!alert || alert.classList.contains("hidden")) return null
  return alert.textContent
}
const dialogIn = (element) => element.querySelector(DIALOG_SELECTOR)
const dialogButton = (element, action) =>
  dialogIn(element).querySelector(`[data-action="click->ai-assistant-conversations#${action}"]`)
const rowFor = (element, id) => element.querySelector(`[data-conversation-id="${id}"]`)
const buttonIn = (element, id, action) =>
  rowFor(element, id).querySelector(`[data-action="ai-assistant-conversations#${action}"]`)
const renameInputIn = (element) => element.querySelector("input[type='text']")
const renameButtonIn = (element, label) =>
  Array.from(element.querySelectorAll("div > button")).find((button) => button.textContent === label)
const createIn = (element) => element.querySelector("[data-action='ai-assistant-conversations#create']")
const toggleIn = (element) => element.querySelector("[data-action='ai-assistant-conversations#toggle']")
const closeIn = (element) => element.querySelector("[data-action='ai-assistant-conversations#close']")
const panelIn = (element) => element.querySelector("#ai_assistant_conversations_panel")
const backdropIn = (element) => element.querySelector("[data-ai-assistant-conversations-target='backdrop']")
const slideClosed = (panel) => panel.classList.contains("-translate-x-full")

// The workspace wraps the list in a host element that Turbo never replaces.
// That wrapper is what carries the disclosure state across a broadcast, so the
// default mount includes it and `omitHost` drops it.
async function mount({ omitHost = false, ...overrides } = {}) {
  const list = listHtml(overrides)
  const html = omitHost ? list : `<div data-ai-assistant-chats-host>${list}</div>`
  const mounted = await mountController("ai-assistant-conversations", Controller, html)
  const ctrl = controllerFor(mounted.application, mounted.element, "ai-assistant-conversations")
  return { ...mounted, ctrl }
}

// Stream.broadcast_conversations swaps the list element itself and leaves the
// host wrapper alone. Re-mounting would wipe the wrapper too, which is a page
// load, not a broadcast.
async function rebroadcast(mounted, overrides = {}) {
  const host = mounted.element.parentElement
  mounted.element.outerHTML = listHtml(overrides)
  await new Promise((resolve) => setTimeout(resolve, 0))

  const element = host.querySelector("[data-controller~='ai-assistant-conversations']")
  const ctrl = controllerFor(mounted.application, element, "ai-assistant-conversations")
  return { application: mounted.application, element, ctrl }
}

// Opens the dialog for a row and hands back the control that opened it.
async function askToDelete(element, id = 11) {
  const trigger = buttonIn(element, id, "destroy")
  await click(trigger)
  return trigger
}

describe("ai-assistant-conversations controller", () => {
  beforeEach(() => {
    document.head.innerHTML = ""
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    document.head.innerHTML = ""
  })

  describe("create", () => {
    it("opens the chat the server just created without rebuilding the page", async () => {
      const fetchMock = mockFetch(201, { json: { conversation: { id: 99 } } })
      const visit = stubTurbo()
      const location = stubLocation()
      try {
        const { element } = await mount()

        await click(createIn(element))
        await flush()

        const [url, options] = fetchMock.mock.calls[0]
        expect(url).toBe(COLLECTION_URL)
        expect(options.method).toBe("POST")
        expect(options.headers["Content-Type"]).toBe("application/json")
        expect(options.body).toBeUndefined()
        // Turbo keeps the shell, and with it the socket the transcript streams over.
        expect(visit).toHaveBeenCalledWith("https://app.test/81721200/admin/assistant?conversation=99")
        expect(location.assign).not.toHaveBeenCalled()
      } finally {
        location.restore()
      }
    })

    it("falls back to a full load when Turbo is not on the page", async () => {
      mockFetch(201, { json: { conversation: { id: 99 } } })
      vi.stubGlobal("Turbo", undefined)
      const location = stubLocation()
      try {
        const { element } = await mount()

        await click(createIn(element))
        await flush()

        expect(location.assign).toHaveBeenCalledWith("https://app.test/81721200/admin/assistant?conversation=99")
      } finally {
        location.restore()
      }
    })

    it("falls back when Turbo is present but cannot visit", async () => {
      mockFetch(201, { json: { conversation: { id: 99 } } })
      vi.stubGlobal("Turbo", {})
      const location = stubLocation()
      try {
        const { element } = await mount()

        await click(createIn(element))
        await flush()

        expect(location.assign).toHaveBeenCalledWith("https://app.test/81721200/admin/assistant?conversation=99")
      } finally {
        location.restore()
      }
    })

    it("replaces an existing conversation query rather than stacking one", async () => {
      mockFetch(201, { json: { conversation: { id: 5 } } })
      const visit = stubTurbo()
      const location = stubLocation("https://app.test/81721200/admin/assistant?conversation=4")
      try {
        const { ctrl } = await mount()

        ctrl.create()
        await flush()

        expect(visit).toHaveBeenCalledWith("https://app.test/81721200/admin/assistant?conversation=5")
      } finally {
        location.restore()
      }
    })

    it("does nothing without a create endpoint", async () => {
      const fetchMock = mockFetch(201, { json: { conversation: { id: 1 } } })
      const { element } = await mount({ createUrl: "" })

      await click(createIn(element))
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    // The round trip plus the reload show nothing, so the button is easy to
    // press twice — and twice means two empty chats.
    it("shows the request is in flight and refuses a second press", async () => {
      const { fetchMock, settle } = deferredFetch({ json: { conversation: { id: 7 } } })
      stubTurbo()
      const location = stubLocation()
      try {
        const { element } = await mount()
        const button = createIn(element)

        await click(button)

        expect(button.disabled).toBe(true)
        expect(button.classList.contains("opacity-60")).toBe(true)
        expect(button.classList.contains("cursor-wait")).toBe(true)

        await click(button)
        expect(fetchMock).toHaveBeenCalledOnce()

        settle()
        await flush()
      } finally {
        location.restore()
      }
    })

    it("hands the button back when the create is refused", async () => {
      mockFetch(422)
      const { element } = await mount()
      const button = createIn(element)

      await click(button)
      await flush()

      expect(button.disabled).toBe(false)
      expect(button.classList.contains("opacity-60")).toBe(false)
      expect(alertText(element)).toBe("Could not update the chat.")
    })

    // The composer's "Start a new chat" escape hatch is outside this element,
    // so it asks for the chat with an event instead of a Stimulus action.
    it("starts a chat from a window event, with no control to disable", async () => {
      const fetchMock = mockFetch(201, { json: { conversation: { id: 3 } } })
      const visit = stubTurbo()
      const location = stubLocation()
      try {
        const { ctrl } = await mount()

        window.dispatchEvent(new globalThis.CustomEvent("ai-assistant:newChat", { bubbles: true }))
        await flush()

        expect(fetchMock).toHaveBeenCalledOnce()
        expect(visit).toHaveBeenCalledWith("https://app.test/81721200/admin/assistant?conversation=3")
        expect(ctrl.pendingControl).toBeNull()
      } finally {
        location.restore()
      }
    })

    it("announces a refused create instead of navigating", async () => {
      mockFetch(422)
      stubTurbo()
      const location = stubLocation()
      try {
        const { ctrl, element } = await mount()

        ctrl.create()
        await flush()

        expect(alertText(element)).toBe("Could not update the chat.")
        expect(alertIn(element).getAttribute("role")).toBe("alert")
        expect(alertIn(element).getAttribute("aria-live")).toBe("assertive")
        expect(window.Turbo.visit).not.toHaveBeenCalled()
      } finally {
        location.restore()
      }
    })

    it("announces a create that never reached the server", async () => {
      mockFetch(0, { reject: true })
      const { ctrl, element } = await mount()

      ctrl.create()
      await flush()

      expect(alertText(element)).toBe("Could not update the chat.")
    })

    // A 2xx with no conversation in it is a server bug, not a new chat: there
    // is nothing to navigate to, so it reads as a failure.
    it("announces a create that came back without a conversation", async () => {
      mockFetch(201, { json: {} })
      const visit = stubTurbo()
      const { ctrl, element } = await mount()

      ctrl.create()
      await flush()

      expect(visit).not.toHaveBeenCalled()
      expect(alertText(element)).toBe("Could not update the chat.")
    })

    it("announces a create whose body was not JSON at all", async () => {
      mockFetch(201, { jsonThrows: true })
      const { ctrl, element } = await mount()

      ctrl.create()
      await flush()

      expect(alertText(element)).toBe("Could not update the chat.")
    })

    it("reuses the one alert slot instead of stacking a second", async () => {
      mockFetch(422)
      const { ctrl, element } = await mount()

      ctrl.create()
      await flush()
      ctrl.create()
      await flush()

      expect(element.querySelectorAll(ALERT_SELECTOR)).toHaveLength(1)
    })

    it("clears a stale alert once a write succeeds", async () => {
      mockFetch(422)
      const { ctrl, element } = await mount()
      ctrl.archive({ preventDefault() {}, params: { url: `${COLLECTION_URL}/11/archive`, archived: false } })
      await flush()
      expect(alertText(element)).toBe("Could not update the chat.")

      mockFetch(200)
      ctrl.archive({ preventDefault() {}, params: { url: `${COLLECTION_URL}/11/archive`, archived: false } })
      await flush()

      expect(alertText(element)).toBeNull()
      expect(alertIn(element).textContent).toBe("")
    })

    // The list is re-rendered by a broadcast that would take a JS-built slot
    // with it, but a render without the slot must still not throw.
    it("says nothing when the page ships no error slot", async () => {
      mockFetch(422)
      const { ctrl, element } = await mount({ omitAlert: true })

      ctrl.create()
      await flush()
      expect(alertIn(element)).toBeNull()

      mockFetch(200)
      ctrl.archive({ preventDefault() {}, params: { url: `${COLLECTION_URL}/11/archive`, archived: false } })
      await flush()

      expect(alertIn(element)).toBeNull()
    })

    // The whole list is replaced by a Turbo broadcast, and that offline render
    // mints a token against a throwaway session — so the token has to come
    // from the layout's meta tag, which belongs to the real one.
    it("reads the CSRF token from the meta tag", async () => {
      const meta = document.createElement("meta")
      meta.name = "csrf-token"
      meta.content = "meta-csrf"
      document.head.appendChild(meta)

      try {
        const fetchMock = mockFetch(422)
        const { ctrl } = await mount()

        ctrl.create()
        await flush()

        expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("meta-csrf")
      } finally {
        meta.remove()
      }
    })

    it("sends an empty token when the meta tag is absent", async () => {
      const fetchMock = mockFetch(422)
      const { ctrl } = await mount()

      ctrl.create()
      await flush()

      expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("")
    })
  })

  describe("rename", () => {
    it("turns the row label into an inline field with the title already in it", async () => {
      mockFetch(200)
      const { element } = await mount()

      await click(buttonIn(element, 11, "rename"))

      const input = renameInputIn(element)
      expect(input.value).toBe("Invoice cleanup")
      expect(input.getAttribute("aria-label")).toBe("Chat name")
      expect(document.activeElement).toBe(input)
      expect(rowFor(element, 11).querySelector("a").classList.contains("hidden")).toBe(true)
      expect(renameButtonIn(element, "Save")).toBeTruthy()
      expect(renameButtonIn(element, "Cancel")).toBeTruthy()
    })

    it("saves the new title on Save", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      renameInputIn(element).value = "  Invoices Q3  "

      await click(renameButtonIn(element, "Save"))
      await flush()

      const [url, options] = fetchMock.mock.calls[0]
      expect(url).toBe(`${COLLECTION_URL}/11`)
      expect(options.method).toBe("PATCH")
      expect(JSON.parse(options.body)).toEqual({ title: "Invoices Q3" })
      expect(renameInputIn(element)).toBeNull()
      expect(rowFor(element, 11).querySelector("a").classList.contains("hidden")).toBe(false)
    })

    it("saves on Enter", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      const input = renameInputIn(element)
      input.value = "Renamed"

      const event = new globalThis.KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
      input.dispatchEvent(event)
      await flush()

      expect(event.defaultPrevented).toBe(true)
      expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ title: "Renamed" })
    })

    it("dismisses the field on Escape without writing", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      const input = renameInputIn(element)

      const event = new globalThis.KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true })
      input.dispatchEvent(event)
      await flush()

      expect(event.defaultPrevented).toBe(true)
      expect(fetchMock).not.toHaveBeenCalled()
      expect(renameInputIn(element)).toBeNull()
      // Dismissing the field must not drop the reader out of the list.
      expect(document.activeElement).toBe(rowFor(element, 11).querySelector("a"))
    })

    it("dismisses the field from the Cancel button", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))

      await click(renameButtonIn(element, "Cancel"))
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
      expect(renameInputIn(element)).toBeNull()
    })

    it("ignores keys that are neither Enter nor Escape", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      const input = renameInputIn(element)

      const event = new globalThis.KeyboardEvent("keydown", { key: "a", bubbles: true, cancelable: true })
      input.dispatchEvent(event)
      await flush()

      expect(event.defaultPrevented).toBe(false)
      expect(fetchMock).not.toHaveBeenCalled()
      expect(renameInputIn(element)).toBeTruthy()
    })

    // A chat with no name is what the server refuses anyway, and asking it
    // costs the round trip and the field.
    it("does not send a blank title at all", async () => {
      const fetchMock = mockFetch(422)
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      renameInputIn(element).value = "   "

      await click(renameButtonIn(element, "Save"))
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
      expect(renameInputIn(element)).toBeTruthy()
      expect(document.activeElement).toBe(renameInputIn(element))
      expect(alertText(element)).toBeNull()
    })

    it("sends an unchanged title too", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))

      await click(renameButtonIn(element, "Save"))
      await flush()

      expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ title: "Invoice cleanup" })
    })

    // The field used to be torn down before the request left, so a refusal
    // left the typed name unrecoverable behind a generic error.
    it("keeps the typed name when the write is refused", async () => {
      mockFetch(422)
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      const input = renameInputIn(element)
      input.value = "Invoices Q3"

      await click(renameButtonIn(element, "Save"))
      await flush()

      expect(renameInputIn(element)).toBe(input)
      expect(input.value).toBe("Invoices Q3")
      expect(input.disabled).toBe(false)
      expect(renameButtonIn(element, "Save").disabled).toBe(false)
      expect(input.classList.contains("opacity-60")).toBe(false)
      expect(alertText(element)).toBe("Could not update the chat.")
    })

    it("disables the field while the write is in flight and ignores a second Save", async () => {
      const { fetchMock, settle } = deferredFetch()
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      const input = renameInputIn(element)
      input.value = "Invoices Q3"

      await click(renameButtonIn(element, "Save"))

      expect(input.disabled).toBe(true)
      expect(input.classList.contains("opacity-60")).toBe(true)
      expect(renameButtonIn(element, "Save").disabled).toBe(true)
      expect(renameButtonIn(element, "Cancel").disabled).toBe(true)

      input.dispatchEvent(new globalThis.KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
      await flush()
      expect(fetchMock).toHaveBeenCalledOnce()

      settle()
      await flush()
      expect(renameInputIn(element)).toBeNull()
    })

    it("has nothing to re-enable when the list is torn down mid-write", async () => {
      const { settle } = deferredFetch({ status: 422 })
      const { ctrl, element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      renameInputIn(element).value = "Invoices Q3"
      await click(renameButtonIn(element, "Save"))

      ctrl.disconnect()
      settle()
      await flush()

      expect(renameInputIn(element)).toBeNull()
    })

    // Opening a second rename must not leave the first field orphaned in the
    // list with no way to dismiss it.
    it("closes an open field before opening another", async () => {
      mockFetch(200)
      const { element } = await mount()

      await click(buttonIn(element, 11, "rename"))
      await click(buttonIn(element, 12, "rename"))

      expect(element.querySelectorAll("input[type='text']")).toHaveLength(1)
      expect(renameInputIn(element).value).toBe("Old ideas")
      expect(rowFor(element, 11).querySelector("a").classList.contains("hidden")).toBe(false)
    })

    it("falls back to the row label when the control carries no title", async () => {
      mockFetch(200)
      const { ctrl, element } = await mount()

      ctrl.rename({ preventDefault() {}, params: { id: 11 } })

      expect(renameInputIn(element).value).toBe("Invoice cleanup")
    })

    it("opens a field on a row with no label to hide", async () => {
      mockFetch(200)
      const { ctrl, element } = await mount({ rows: [{ id: 11, title: "Linkless", archived: false, link: false }] })

      ctrl.rename({ preventDefault() {}, params: { id: 11 } })
      expect(renameInputIn(element).value).toBe("")

      ctrl.rename({ preventDefault() {}, params: { id: 11, title: "Linkless" } })
      expect(renameInputIn(element).value).toBe("Linkless")
    })

    it("ignores a rename for a row that is not in the list", async () => {
      const fetchMock = mockFetch(200)
      const { ctrl, element } = await mount()

      ctrl.rename({ preventDefault() {}, params: { id: 999, url: `${COLLECTION_URL}/999` } })

      expect(renameInputIn(element)).toBeNull()
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("ignores a rename with no URL to write to", async () => {
      mockFetch(200)
      const { ctrl, element } = await mount({ baseUrl: "" })

      ctrl.rename({ preventDefault() {}, params: { id: 11 } })

      expect(renameInputIn(element)).toBeNull()
    })

    it("builds the member URL from the id when the control carries none", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount({ rows: [{ id: 11, title: "Invoice cleanup", archived: false, omitRowUrl: true }] })

      await click(buttonIn(element, 11, "rename"))
      await click(renameButtonIn(element, "Save"))
      await flush()

      expect(fetchMock.mock.calls[0][0]).toBe(`${COLLECTION_URL}/11`)
    })

    it("announces a rename that never reached the server", async () => {
      mockFetch(0, { reject: true })
      const { element } = await mount()
      await click(buttonIn(element, 11, "rename"))

      await click(renameButtonIn(element, "Save"))
      await flush()

      expect(alertText(element)).toBe("Could not update the chat.")
    })

    it("drops an open field when the list is torn down", async () => {
      mockFetch(200)
      const { ctrl, element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      expect(renameInputIn(element)).toBeTruthy()

      ctrl.disconnect()

      expect(renameInputIn(element)).toBeNull()
      expect(() => ctrl.disconnect()).not.toThrow()
    })

    it("has nothing to save once the field is closed", async () => {
      const fetchMock = mockFetch(200)
      const { ctrl, element } = await mount()
      await click(buttonIn(element, 11, "rename"))
      const save = renameButtonIn(element, "Save")

      ctrl.disconnect()
      save.dispatchEvent(new Event("click", { bubbles: true }))
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })
  })

  describe("archive", () => {
    it("archives an active chat", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount()

      await click(buttonIn(element, 11, "archive"))
      await flush()

      const [url, options] = fetchMock.mock.calls[0]
      expect(url).toBe(`${COLLECTION_URL}/11/archive`)
      expect(options.method).toBe("POST")
      expect(JSON.parse(options.body)).toEqual({ archived: true })
    })

    it("unarchives a chat that is already archived", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount()

      await click(buttonIn(element, 12, "archive"))
      await flush()

      expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ archived: false })
    })

    it("shows the request is in flight and hands the control back after", async () => {
      const { fetchMock, settle } = deferredFetch()
      const { element } = await mount()
      const button = buttonIn(element, 11, "archive")

      await click(button)
      expect(button.disabled).toBe(true)
      expect(button.classList.contains("cursor-wait")).toBe(true)

      await click(button)
      expect(fetchMock).toHaveBeenCalledOnce()

      settle()
      await flush()

      expect(button.disabled).toBe(false)
      expect(button.classList.contains("cursor-wait")).toBe(false)
    })

    it("ignores an archive control with no URL", async () => {
      const fetchMock = mockFetch(200)
      const { element } = await mount({ rows: [{ id: 11, title: "No URL", archived: false, omitRowUrl: true }] })

      await click(buttonIn(element, 11, "archive"))
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("ignores an archive fired without params at all", async () => {
      const fetchMock = mockFetch(200)
      const { ctrl } = await mount()

      ctrl.archive()
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("announces a refused archive", async () => {
      mockFetch(403)
      const { element } = await mount()

      await click(buttonIn(element, 11, "archive"))
      await flush()

      expect(alertText(element)).toBe("Could not update the chat.")
    })
  })

  describe("destroy", () => {
    it("asks in a dialog before deleting anything", async () => {
      const fetchMock = mockFetch(204)
      const { element } = await mount()

      await askToDelete(element)

      expect(dialogIn(element).open).toBe(true)
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("deletes the chat once the reader confirms", async () => {
      const fetchMock = mockFetch(204)
      const { element } = await mount()
      await askToDelete(element)

      await click(dialogButton(element, "confirmDestroy"))
      await flush()

      expect(dialogIn(element).open).toBe(false)
      expect(fetchMock.mock.calls[0][0]).toBe(`${COLLECTION_URL}/11`)
      expect(fetchMock.mock.calls[0][1].method).toBe("DELETE")
      expect(fetchMock.mock.calls[0][1].body).toBeUndefined()
    })

    it("leaves the chat alone when the reader cancels, and puts them back on the row", async () => {
      const fetchMock = mockFetch(204)
      const { element } = await mount()
      const trigger = await askToDelete(element)

      await click(dialogButton(element, "cancelDestroy"))
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
      expect(dialogIn(element).open).toBe(false)
      expect(document.activeElement).toBe(trigger)
    })

    // Escape closes a dialog on its own, which would skip the focus hand-back.
    it("handles Escape through the same path as Cancel", async () => {
      mockFetch(204)
      const { element } = await mount()
      const trigger = await askToDelete(element)

      const event = new globalThis.Event("cancel", { bubbles: true, cancelable: true })
      dialogIn(element).dispatchEvent(event)
      await tick()

      expect(event.defaultPrevented).toBe(true)
      expect(dialogIn(element).open).toBe(false)
      expect(document.activeElement).toBe(trigger)
    })

    it("falls back to the row when the control that opened the dialog is gone", async () => {
      mockFetch(204)
      const { ctrl, element } = await mount()

      ctrl.destroy({ preventDefault() {}, params: { id: 11, url: `${COLLECTION_URL}/11` } })
      ctrl.cancelDestroy()

      expect(document.activeElement).toBe(rowFor(element, 11).querySelector("a"))
    })

    it("has nowhere to put focus when the row went with the dialog", async () => {
      mockFetch(204)
      const { element } = await mount()
      const trigger = await askToDelete(element)
      rowFor(element, 11).remove()

      expect(trigger.isConnected).toBe(false)
      expect(() => dialogButton(element, "cancelDestroy").click()).not.toThrow()
      expect(dialogIn(element).open).toBe(false)
    })

    // Losing a whole transcript is not something to do on a browser that
    // cannot ask first.
    it("refuses to delete when the page ships no dialog", async () => {
      const fetchMock = mockFetch(204)
      const { element } = await mount({ omitDialog: true })

      await askToDelete(element)
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("refuses to delete when the browser cannot open a modal", async () => {
      const fetchMock = mockFetch(204)
      const { element } = await mount()
      dialogIn(element).showModal = undefined

      await askToDelete(element)
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("does nothing on a confirm with nothing pending, with or without a dialog", async () => {
      const fetchMock = mockFetch(204)
      const { ctrl } = await mount()

      ctrl.confirmDestroy()
      ctrl.cancelDestroy()
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()

      const bare = await mount({ omitDialog: true })
      expect(() => bare.ctrl.cancelDestroy()).not.toThrow()
    })

    it("ignores a destroy with no URL to call", async () => {
      const fetchMock = mockFetch(204)
      const { ctrl } = await mount({ baseUrl: "" })

      ctrl.destroy({ preventDefault() {}, params: { id: 11 } })
      await flush()

      expect(fetchMock).not.toHaveBeenCalled()
    })

    it("will not open the dialog while another write is in flight", async () => {
      const { settle } = deferredFetch()
      const { element } = await mount()
      await click(buttonIn(element, 11, "archive"))

      await askToDelete(element)

      expect(dialogIn(element).open).toBe(false)
      settle()
      await flush()
    })

    it("will not delete if another write started while the dialog was open", async () => {
      const { fetchMock, settle } = deferredFetch()
      const { element } = await mount()
      await askToDelete(element)
      await click(buttonIn(element, 11, "archive"))

      await click(dialogButton(element, "confirmDestroy"))
      await flush()

      expect(fetchMock).toHaveBeenCalledOnce()
      expect(fetchMock.mock.calls[0][1].method).toBe("POST")
      settle()
      await flush()
    })

    it("announces a refused destroy and hands the control back", async () => {
      mockFetch(403)
      const { element } = await mount()
      const trigger = await askToDelete(element)

      await click(dialogButton(element, "confirmDestroy"))
      await flush()

      expect(alertText(element)).toBe("Could not update the chat.")
      expect(trigger.disabled).toBe(false)
    })

    // Deleting the thread on screen is the one write the list re-render cannot
    // settle: the transcript and the composer would still point at a row that
    // no longer exists, and the next send would 404.
    describe("when the deleted chat is the one on screen", () => {
      // mountController replaces document.body, so the workspace panel this
      // controller looks for has to be added after the list is mounted.
      const openPanel = (id) => {
        const panel = document.createElement("div")
        panel.setAttribute("data-ai-assistant-conversation-id-value", String(id))
        document.body.appendChild(panel)
        return panel
      }

      it("reopens the workspace on the default chat", async () => {
        mockFetch(204)
        const visit = stubTurbo()
        const location = stubLocation("https://app.test/81721200/admin/assistant?conversation=11")
        let panel

        try {
          const { element } = await mount()
          panel = openPanel(11)
          await askToDelete(element)
          await click(dialogButton(element, "confirmDestroy"))
          await flush()

          expect(visit).toHaveBeenCalledWith("https://app.test/81721200/admin/assistant")
        } finally {
          panel?.remove()
          location.restore()
        }
      })

      it("stays put when a different chat was deleted", async () => {
        mockFetch(204)
        const visit = stubTurbo()
        const location = stubLocation("https://app.test/81721200/admin/assistant?conversation=99")
        let panel

        try {
          const { element } = await mount()
          panel = openPanel(99)
          await askToDelete(element)
          await click(dialogButton(element, "confirmDestroy"))
          await flush()

          expect(visit).not.toHaveBeenCalled()
        } finally {
          panel?.remove()
          location.restore()
        }
      })

      it("stays put when the workspace panel is not on the page", async () => {
        mockFetch(204)
        const visit = stubTurbo()
        const location = stubLocation("https://app.test/81721200/admin/assistant")

        try {
          const { element } = await mount()
          await askToDelete(element)
          await click(dialogButton(element, "confirmDestroy"))
          await flush()

          expect(visit).not.toHaveBeenCalled()
        } finally {
          location.restore()
        }
      })
    })
  })

  describe("toggle", () => {
    it("expands and collapses the list, reporting the state to the control", async () => {
      const { ctrl, element } = await mount()
      const toggle = toggleIn(element)

      await click(toggle)

      expect(ctrl.expanded).toBe(true)
      expect(panelIn(element).classList.contains("-translate-x-full")).toBe(false)
      expect(panelIn(element).getAttribute("aria-hidden")).toBe("false")
      expect(panelIn(element).inert).toBe(false)
      expect(toggle.getAttribute("aria-expanded")).toBe("true")
      expect(backdropIn(element).classList.contains("pointer-events-none")).toBe(false)
      expect(backdropIn(element).classList.contains("opacity-0")).toBe(false)

      await click(toggle)

      expect(ctrl.expanded).toBe(false)
      expect(panelIn(element).classList.contains("-translate-x-full")).toBe(true)
      expect(panelIn(element).inert).toBe(true)
      expect(toggle.getAttribute("aria-expanded")).toBe("false")
    })

    // The controller owns the disclosure now, so a panel the server laid out
    // open is closed again on connect unless the reader left it open.
    it("normalises a panel that is laid out open to begin with", async () => {
      const { ctrl, element } = await mount({ panelOpen: true })

      expect(ctrl.expanded).toBe(false)
      expect(panelIn(element).classList.contains("-translate-x-full")).toBe(true)

      await click(toggleIn(element))

      expect(ctrl.expanded).toBe(true)
      expect(panelIn(element).classList.contains("-translate-x-full")).toBe(false)
    })

    it("finds the panel by id when it is not a target", async () => {
      const { element } = await mount({ omitPanelTarget: true })

      await click(toggleIn(element))

      expect(panelIn(element).classList.contains("-translate-x-full")).toBe(false)
    })

    it("does nothing when there is no panel to toggle at all", async () => {
      const { ctrl, element } = await mount({ omitPanelTarget: true, panelId: "" })

      await click(toggleIn(element))

      expect(ctrl.expanded).toBe(false)
      expect(panelIn(element).classList.contains("-translate-x-full")).toBe(true)
      expect(toggleIn(element).getAttribute("aria-expanded")).toBe("false")
    })

    it("toggles without an event", async () => {
      const { ctrl, element } = await mount()

      ctrl.toggle()

      expect(ctrl.expanded).toBe(true)
      expect(panelIn(element).classList.contains("-translate-x-full")).toBe(false)
    })

    it("expands a list whose control is not a target to label", async () => {
      const { ctrl, element } = await mount({ omitToggleTarget: true })

      await click(toggleIn(element))

      expect(ctrl.expanded).toBe(true)
      expect(panelIn(element).classList.contains("-translate-x-full")).toBe(false)
      expect(toggleIn(element).getAttribute("aria-expanded")).toBe("false")
    })

    // Stream.broadcast_conversations replaces this whole element after every
    // write, restoring the server's collapsed markup — so send a message on a
    // phone and the list you just opened would snap shut.
    describe("across a broadcast that replaces the list", () => {
      it("comes back open when it was left open", async () => {
        const first = await mount()
        await click(toggleIn(first.element))

        const { ctrl, element } = await rebroadcast(first)

        expect(ctrl.expanded).toBe(true)
        expect(panelIn(element).classList.contains("-translate-x-full")).toBe(false)
        expect(toggleIn(element).getAttribute("aria-expanded")).toBe("true")
      })

      it("comes back closed when it was left closed", async () => {
        const first = await mount()
        await click(toggleIn(first.element))
        await click(toggleIn(first.element))

        const { ctrl, element } = await rebroadcast(first)

        expect(ctrl.expanded).toBe(false)
        expect(panelIn(element).classList.contains("-translate-x-full")).toBe(true)
      })
    })

    // The list always starts collapsed on a page load: the transcript is what
    // the reader came for, and a disclosure left open in an earlier visit is
    // not a preference worth carrying over.
    describe("on a fresh page load", () => {
      it("starts collapsed even though it was left open in the previous visit", async () => {
        const first = await mount()
        await click(toggleIn(first.element))
        expect(first.ctrl.expanded).toBe(true)

        const { ctrl, element } = await mount()

        expect(ctrl.expanded).toBe(false)
        expect(panelIn(element).classList.contains("-translate-x-full")).toBe(true)
        expect(toggleIn(element).getAttribute("aria-expanded")).toBe("false")
      })

      it("still toggles when there is no host to record the state in", async () => {
        const { ctrl, element } = await mount({ omitHost: true })

        expect(ctrl.expanded).toBe(false)

        await click(toggleIn(element))

        expect(ctrl.expanded).toBe(true)
        expect(panelIn(element).classList.contains("-translate-x-full")).toBe(false)
      })
    })
  })

  describe("close", () => {
    it("dismisses the slide-over from the close control", async () => {
      const { ctrl, element } = await mount()
      await click(toggleIn(element))

      await click(closeIn(element))

      expect(ctrl.expanded).toBe(false)
      expect(slideClosed(panelIn(element))).toBe(true)
      expect(panelIn(element).getAttribute("aria-hidden")).toBe("true")
      expect(backdropIn(element).classList.contains("pointer-events-none")).toBe(true)
      expect(backdropIn(element).classList.contains("opacity-0")).toBe(true)
    })

    it("dismisses the slide-over from the backdrop", async () => {
      const { ctrl, element } = await mount()
      await click(toggleIn(element))

      await click(backdropIn(element))

      expect(ctrl.expanded).toBe(false)
      expect(slideClosed(panelIn(element))).toBe(true)
    })

    it("closes without an event", async () => {
      const { ctrl, element } = await mount()
      await click(toggleIn(element))

      ctrl.close()

      expect(ctrl.expanded).toBe(false)
      expect(slideClosed(panelIn(element))).toBe(true)
    })

    it("still records closed when there is no host to store state on", async () => {
      const { ctrl, element } = await mount({ omitHost: true })
      await click(toggleIn(element))

      ctrl.close()

      expect(ctrl.expanded).toBe(false)
      expect(slideClosed(panelIn(element))).toBe(true)
    })
  })

  describe("keydown", () => {
    function press(key) {
      document.dispatchEvent(new globalThis.KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }))
    }

    it("closes the slide-over on Escape", async () => {
      const { ctrl, element } = await mount()
      await click(toggleIn(element))

      press("Escape")

      expect(ctrl.expanded).toBe(false)
      expect(slideClosed(panelIn(element))).toBe(true)
    })

    it("ignores keys other than Escape", async () => {
      const { ctrl, element } = await mount()
      await click(toggleIn(element))

      press("Tab")

      expect(ctrl.expanded).toBe(true)
      expect(slideClosed(panelIn(element))).toBe(false)
    })

    it("ignores Escape while the slide-over is already closed", async () => {
      const { ctrl, element } = await mount()

      press("Escape")

      expect(ctrl.expanded).toBe(false)
      expect(slideClosed(panelIn(element))).toBe(true)
    })

    it("leaves the slide-over open while a delete dialog is showing", async () => {
      const { ctrl, element } = await mount()
      await click(toggleIn(element))
      dialogIn(element).open = true

      press("Escape")

      expect(ctrl.expanded).toBe(true)
      expect(slideClosed(panelIn(element))).toBe(false)
      dialogIn(element).open = false
    })

    it("leaves the slide-over open while a rename field is up", async () => {
      const { ctrl, element } = await mount()
      await click(toggleIn(element))
      await click(buttonIn(element, 11, "rename"))

      press("Escape")

      expect(ctrl.expanded).toBe(true)
      expect(slideClosed(panelIn(element))).toBe(false)
    })

    it("does not close the slide-over when Escape dismisses a rename", async () => {
      const { ctrl, element } = await mount()
      await click(toggleIn(element))
      await click(buttonIn(element, 11, "rename"))

      const event = new globalThis.KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true })
      renameInputIn(element).dispatchEvent(event)

      expect(ctrl.expanded).toBe(true)
      expect(slideClosed(panelIn(element))).toBe(false)
      expect(renameInputIn(element)).toBeNull()
    })
  })

  it("opens the slide-over without a backdrop to restyle", async () => {
    const { ctrl, element } = await mount({ omitBackdrop: true })

    await click(toggleIn(element))

    expect(ctrl.expanded).toBe(true)
    expect(slideClosed(panelIn(element))).toBe(false)
    expect(backdropIn(element)).toBeNull()
  })

  it("connects with no field open, no alert showing and nothing in flight", async () => {
    const { ctrl, element } = await mount()

    expect(ctrl.expanded).toBe(false)
    expect(ctrl.rename_).toBeNull()
    expect(ctrl.pending).toBe(false)
    expect(ctrl.pendingDestroy).toBeNull()
    expect(alertText(element)).toBeNull()

    element.remove()
    await tick()
  })
})
