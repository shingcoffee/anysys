import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/assistant_workspace_controller"
import { click, controllerFor, mountController, tick } from "../support/stimulus.js"

const DESKTOP_QUERY = "(min-width: 1024px)"

function workspaceHtml({ semantics = true, artifact = null, dot = true } = {}) {
  // Authored as data, not as live attributes: the controller strips the live
  // ones at desktop, so a snapshot taken at connect can be empty.
  const panelRoles = (id) => (semantics
    ? `role="tabpanel" aria-labelledby="${id}-tab"
       data-assistant-workspace-role="tabpanel"
       data-assistant-workspace-labelled-by="${id}-tab"`
    : "")
  const artifactPane = artifact === null
    ? ""
    : `<div id="ai_assistant_artifact"
            data-assistant-workspace-target="artifact"
            data-artifact-present="${artifact}"></div>`

  return `
    <div data-controller="assistant-workspace"
         data-assistant-workspace-active-value="conversation">
      <div role="tablist">
        <button id="conversation-tab"
                role="tab"
                aria-selected="true"
                tabindex="0"
                data-assistant-workspace-target="tab"
                data-assistant-workspace-id="conversation"
                data-action="click->assistant-workspace#select keydown->assistant-workspace#keydown">
          Conversation
        </button>
        <button id="preview-tab"
                role="tab"
                aria-selected="false"
                tabindex="-1"
                data-assistant-workspace-target="tab"
                data-assistant-workspace-id="preview"
                data-action="click->assistant-workspace#select keydown->assistant-workspace#keydown">
          Preview
          ${dot ? `<span class="hidden" data-assistant-workspace-target="artifactDot"><span aria-hidden="true"></span><span class="sr-only">Preview ready</span></span>` : ""}
        </button>
      </div>
      <section tabindex="0"
               ${panelRoles("conversation")}
               data-assistant-workspace-target="panel"
               data-assistant-workspace-id="conversation"></section>
      <aside class="flex lg:flex"
             tabindex="-1"
             ${panelRoles("preview")}
             data-assistant-workspace-target="panel"
             data-assistant-workspace-id="preview">${artifactPane}</aside>
    </div>
  `
}

// happy-dom answers `(min-width: 1024px)` from its own default viewport, which
// would pin every example to one layout. A hand-rolled query list lets each
// example choose its breakpoint and fire `change` on demand.
function stubMatchMedia({ matches = false, listenable = true } = {}) {
  const listeners = []
  const query = {
    media: DESKTOP_QUERY,
    matches,
    emit(next) {
      query.matches = next
      listeners.slice().forEach((listener) => listener({ matches: next, media: DESKTOP_QUERY }))
    }
  }
  if (listenable) {
    query.addEventListener = vi.fn((name, listener) => {
      if (name === "change") listeners.push(listener)
    })
    query.removeEventListener = vi.fn((name, listener) => {
      const index = listeners.indexOf(listener)
      if (name === "change" && index >= 0) listeners.splice(index, 1)
    })
  }
  const matchMedia = vi.fn(() => query)
  vi.stubGlobal("matchMedia", matchMedia)
  return { query, matchMedia, listeners }
}

async function setup({ matches = false, listenable = true, semantics = true, absent = false, artifact = null, dot = true } = {}) {
  const media = absent ? { query: null, matchMedia: null, listeners: [] } : stubMatchMedia({ matches, listenable })
  if (absent) vi.stubGlobal("matchMedia", undefined)

  const mounted = await mountController("assistant-workspace", Controller, workspaceHtml({ semantics, artifact, dot }))
  const tabs = Array.from(mounted.element.querySelectorAll("[role='tab']"))
  const panels = Array.from(mounted.element.querySelectorAll("[data-assistant-workspace-target='panel']"))
  const controller = controllerFor(mounted.application, mounted.element, "assistant-workspace")
  return { ...mounted, controller, tabs, panels, ...media }
}

const layoutOf = (panel) => ({
  hidden: panel.classList.contains("hidden"),
  tabIndex: panel.tabIndex,
  role: panel.getAttribute("role"),
  labelledBy: panel.getAttribute("aria-labelledby")
})

describe("assistant workspace controller", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  describe("below the lg breakpoint", () => {
    it("starts on the conversation panel with the authored tab semantics", async () => {
      const { tabs, panels } = await setup({ matches: false })

      expect(tabs[0].getAttribute("aria-selected")).toBe("true")
      expect(tabs[0].tabIndex).toBe(0)
      expect(tabs[0].classList.contains("bg-surface")).toBe(true)
      expect(tabs[1].getAttribute("aria-selected")).toBe("false")
      expect(tabs[1].tabIndex).toBe(-1)
      expect(tabs[1].classList.contains("text-text-muted")).toBe(true)
      expect(layoutOf(panels[0])).toEqual({
        hidden: false,
        tabIndex: 0,
        role: "tabpanel",
        labelledBy: "conversation-tab"
      })
      expect(layoutOf(panels[1])).toEqual({
        hidden: true,
        tabIndex: -1,
        role: "tabpanel",
        labelledBy: "preview-tab"
      })
    })

    it("selects preview from a clicked tab", async () => {
      const { tabs, panels } = await setup({ matches: false })

      await click(tabs[1])

      expect(tabs[0].getAttribute("aria-selected")).toBe("false")
      expect(tabs[1].getAttribute("aria-selected")).toBe("true")
      expect(tabs[1].classList.contains("bg-surface")).toBe(true)
      expect(panels[0].classList.contains("hidden")).toBe(true)
      expect(panels[1].classList.contains("hidden")).toBe(false)
    })

    it("ignores an unknown tab id and a select event without a current target", async () => {
      const { controller, tabs } = await setup({ matches: false })

      controller.selectTab("unknown")
      controller.select({})

      expect(controller.activeValue).toBe("conversation")
      expect(tabs[0].getAttribute("aria-selected")).toBe("true")
    })

    it.each([
      ["ArrowRight", 0, 1],
      ["ArrowLeft", 1, 0],
      ["Home", 1, 0],
      ["End", 0, 1]
    ])("supports %s keyboard navigation", async (key, startingIndex, expectedIndex) => {
      const { tabs } = await setup({ matches: false })
      if (startingIndex === 1) await click(tabs[1])

      tabs[startingIndex].focus()
      const event = new globalThis.KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
      tabs[startingIndex].dispatchEvent(event)

      expect(event.defaultPrevented).toBe(true)
      expect(tabs[expectedIndex].getAttribute("aria-selected")).toBe("true")
      expect(globalThis.document.activeElement).toBe(tabs[expectedIndex])
    })

    it("ignores unrelated keys and key events from unknown elements", async () => {
      const { controller, tabs } = await setup({ matches: false })
      const unrelated = new globalThis.KeyboardEvent("keydown", { key: "Enter", cancelable: true })

      controller.keydown(unrelated)
      controller.keydown({
        key: "Home",
        currentTarget: globalThis.document.createElement("button"),
        preventDefault() {}
      })

      expect(unrelated.defaultPrevented).toBe(false)
      expect(tabs[0].getAttribute("aria-selected")).toBe("true")
    })

    // Nothing to restore: the template authored no tab semantics on these
    // panels, so the mobile pass must not invent them.
    it("leaves panels bare when the template authored no role or label", async () => {
      const { panels } = await setup({ matches: false, semantics: false })

      expect(panels[0].getAttribute("role")).toBeNull()
      expect(panels[0].getAttribute("aria-labelledby")).toBeNull()
      expect(panels[0].classList.contains("hidden")).toBe(false)
      expect(panels[1].classList.contains("hidden")).toBe(true)
    })
  })

  describe("at the lg breakpoint and up", () => {
    // Two regions with no tablist to move between are two tab stops on the way
    // to the composer and nothing else, so they come off the tab order.
    it("lays both panels out as plain visible regions outside the tab order", async () => {
      const { matchMedia, panels } = await setup({ matches: true })

      expect(matchMedia).toHaveBeenCalledWith(DESKTOP_QUERY)
      expect(layoutOf(panels[0])).toEqual({ hidden: false, tabIndex: -1, role: null, labelledBy: null })
      expect(layoutOf(panels[1])).toEqual({ hidden: false, tabIndex: -1, role: null, labelledBy: null })
    })

    // The tab state is still tracked for the way back down, but showing one
    // panel here would hide half the workspace.
    it("tracks the selected tab without hiding the other panel", async () => {
      const { controller, tabs, panels } = await setup({ matches: true })

      await click(tabs[1])

      expect(controller.activeValue).toBe("preview")
      expect(tabs[1].getAttribute("aria-selected")).toBe("true")
      expect(panels[0].classList.contains("hidden")).toBe(false)
      expect(panels[1].classList.contains("hidden")).toBe(false)
      expect(panels[0].tabIndex).toBe(-1)
      expect(panels[1].tabIndex).toBe(-1)
    })
  })

  // The pane behind the Preview tab is refreshed by its own Turbo broadcast,
  // which never reaches the tablist — so on a phone the pane would fill up with
  // no sign of it until a full reload.
  describe("the Preview tab's artifact mark", () => {
    const dotIn = (element) => element.querySelector("[data-assistant-workspace-target='artifactDot']")

    it("stays hidden while there is nothing to preview", async () => {
      const { element } = await setup({ artifact: false })

      expect(dotIn(element).classList.contains("hidden")).toBe(true)
    })

    it("shows once the pane arrives carrying an artifact", async () => {
      const { element } = await setup({ artifact: true })

      expect(dotIn(element).classList.contains("hidden")).toBe(false)
      expect(dotIn(element).querySelector(".sr-only").textContent).toBe("Preview ready")
    })

    it("follows the pane a broadcast puts in its place", async () => {
      const { element } = await setup({ artifact: false })
      const pane = element.querySelector("#ai_assistant_artifact")

      const replacement = pane.cloneNode()
      replacement.setAttribute("data-artifact-present", "true")
      pane.replaceWith(replacement)
      await tick()

      expect(dotIn(element).classList.contains("hidden")).toBe(false)
    })

    it("has nothing to mark when the tablist is not rendered", async () => {
      const { element } = await setup({ artifact: true, dot: false })

      expect(dotIn(element)).toBeNull()
    })
  })

  describe("crossing the breakpoint at runtime", () => {
    it("reinstates the tabs on the way down and drops them again on the way up", async () => {
      const { query, panels } = await setup({ matches: true })

      query.emit(false)

      expect(layoutOf(panels[0])).toEqual({
        hidden: false,
        tabIndex: 0,
        role: "tabpanel",
        labelledBy: "conversation-tab"
      })
      expect(layoutOf(panels[1])).toEqual({
        hidden: true,
        tabIndex: -1,
        role: "tabpanel",
        labelledBy: "preview-tab"
      })

      query.emit(true)

      expect(layoutOf(panels[0])).toEqual({ hidden: false, tabIndex: -1, role: null, labelledBy: null })
      expect(layoutOf(panels[1])).toEqual({ hidden: false, tabIndex: -1, role: null, labelledBy: null })
    })

    // A panel that arrives after connect carries its own semantics, so it is
    // restored like any other rather than being left bare.
    it("restores a panel that appeared after connect", async () => {
      const { element, query } = await setup({ matches: true })
      const late = globalThis.document.createElement("div")
      late.setAttribute("data-assistant-workspace-target", "panel")
      late.setAttribute("data-assistant-workspace-id", "late")
      late.setAttribute("data-assistant-workspace-role", "tabpanel")
      late.setAttribute("data-assistant-workspace-labelled-by", "preview-tab")
      element.appendChild(late)
      await tick()

      query.emit(false)

      expect(late.getAttribute("role")).toBe("tabpanel")
      expect(late.getAttribute("aria-labelledby")).toBe("preview-tab")
      expect(late.classList.contains("hidden")).toBe(true)
    })

    it("stops listening once the controller disconnects", async () => {
      const { controller, query, panels, listeners } = await setup({ matches: true })
      const handler = controller.onLayoutChange

      controller.disconnect()

      expect(query.removeEventListener).toHaveBeenCalledWith("change", handler)
      expect(listeners).toEqual([])
      expect(controller.desktopQuery).toBeNull()

      query.emit(false)

      expect(panels[1].classList.contains("hidden")).toBe(false)
    })
  })

  describe("without a usable media query", () => {
    it("stays in the tab behaviour when matchMedia is missing", async () => {
      const { controller, panels } = await setup({ absent: true })

      expect(controller.desktopQuery).toBeNull()
      expect(panels[0].classList.contains("hidden")).toBe(false)
      expect(panels[1].classList.contains("hidden")).toBe(true)
      expect(() => controller.disconnect()).not.toThrow()
    })

    it("applies the layout from a query list that cannot be listened to", async () => {
      const { controller, panels } = await setup({ matches: true, listenable: false })

      expect(controller.desktopQuery.addEventListener).toBeUndefined()
      expect(layoutOf(panels[1])).toEqual({ hidden: false, tabIndex: -1, role: null, labelledBy: null })
      expect(() => controller.disconnect()).not.toThrow()
    })
  })
})
