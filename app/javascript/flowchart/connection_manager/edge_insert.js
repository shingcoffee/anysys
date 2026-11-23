/**
 * EdgeInsertMixin - Hovering a connection shows a "+" button at its midpoint;
 * clicking it opens a menu of insertable element types, and choosing one
 * inserts that element into the connection (see insertElementOnConnection).
 * Hidden on read-only canvases.
 */

import { createGroup, createCircle, createLine, createSvgElement } from "utils"
import { SUPPORTED_ELEMENT_TYPES } from "flowchart/constants"
import { elementLabel } from "flowchart/constants/element_registry"

/** Palette element types offered by the "+" menu (Start and End excluded). */
export const EDGE_INSERT_TYPES = SUPPORTED_ELEMENT_TYPES.filter((type) => type !== "start" && type !== "end")

const HIDE_DELAY_MS = 200
const BUTTON_RADIUS = 9
const MENU_WIDTH = 160
const MENU_ITEM_HEIGHT = 32
const MENU_PADDING = 4

const stop = (e) => e.stopPropagation()

export const EdgeInsertMixin = {
  _edgeInsertMessage(key) {
    return this.labels?.[key] ?? ""
  },

  _showEdgeInsertButton(connectionId) {
    clearTimeout(this._edgeInsertHideTimer)
    if ((this.canMutate ? !this.canMutate() : this.isReadOnly) || this.isDragging || this.isDrawingConnection || this.isDraggingConnectionEndpoint) return
    if (this._edgeInsertMenu) return
    if (this._edgeInsertButton?.dataset.edgeInsertFor === connectionId) return

    this._removeEdgeInsertButton()
    const connection = this.connections.find(c => c.id === connectionId)
    if (!connection) return

    const { x, y } = this._connectionMidpoint(connection)
    const label = this._edgeInsertMessage("edgeInsertButtonLabel")
    const button = createGroup({
      "data-edge-insert-for": connectionId,
      role: "button",
      tabindex: "0",
      "aria-label": label
    })
    button.style.cursor = "pointer"

    const title = createSvgElement("title")
    title.textContent = label
    button.appendChild(title)
    button.appendChild(createCircle(x, y, BUTTON_RADIUS, { fill: "#ffffff", stroke: "#6366f1", "stroke-width": "1.5" }))
    const arm = BUTTON_RADIUS / 2
    const plus = { stroke: "#6366f1", "stroke-width": "2", "stroke-linecap": "round" }
    button.appendChild(createLine(x - arm, y, x + arm, y, plus))
    button.appendChild(createLine(x, y - arm, x, y + arm, plus))

    button.addEventListener("mouseenter", () => clearTimeout(this._edgeInsertHideTimer))
    button.addEventListener("mouseleave", () => this._scheduleHideEdgeInsertButton())
    button.addEventListener("mousedown", stop)
    button.addEventListener("dblclick", stop)
    button.addEventListener("click", (e) => {
      e.stopPropagation()
      this._openEdgeInsertMenu(connectionId, x, y)
    })
    button.addEventListener("keydown", (e) => {
      e.stopPropagation()
      if (e.key !== "Enter" && e.key !== " ") return
      e.preventDefault()
      this._openEdgeInsertMenu(connectionId, x, y)
    })

    this.handleLayer.appendChild(button)
    this._edgeInsertButton = button
  },

  _scheduleHideEdgeInsertButton() {
    if (this._edgeInsertMenu) return
    clearTimeout(this._edgeInsertHideTimer)
    this._edgeInsertHideTimer = setTimeout(() => this._removeEdgeInsertButton(), HIDE_DELAY_MS)
  },

  _removeEdgeInsertButton() {
    this._edgeInsertButton?.remove()
    this._edgeInsertButton = null
  },

  _openEdgeInsertMenu(connectionId, x, y) {
    this._closeEdgeInsertMenu()

    const height = EDGE_INSERT_TYPES.length * MENU_ITEM_HEIGHT + MENU_PADDING * 2
    const menu = createSvgElement("foreignObject", {
      x: x + BUTTON_RADIUS + 4,
      y: y - height / 2,
      width: MENU_WIDTH,
      height,
      "data-edge-insert-menu": connectionId
    })

    const list = document.createElement("div")
    list.setAttribute("role", "menu")
    list.setAttribute("aria-label", this._edgeInsertMessage("edgeInsertMenuLabel"))
    list.className = "flex flex-col rounded-lg border border-slate-200 bg-white p-1 shadow-lg"

    const items = EDGE_INSERT_TYPES.map(type => {
      const item = document.createElement("button")
      item.type = "button"
      item.setAttribute("role", "menuitem")
      item.dataset.edgeInsertType = type
      item.className = "rounded-md px-2 py-1.5 text-left text-xs font-medium text-slate-700 hover:bg-indigo-50 hover:text-indigo-700 focus:bg-indigo-50 focus:outline-none"
      item.textContent = elementLabel(type) ?? type
      item.addEventListener("click", (e) => {
        e.stopPropagation()
        this._chooseEdgeInsertType(connectionId, type)
      })
      list.appendChild(item)
      return item
    })

    menu.addEventListener("mousedown", stop)
    menu.addEventListener("click", stop)
    menu.addEventListener("dblclick", stop)
    menu.addEventListener("keydown", (e) => {
      e.stopPropagation()
      if (e.key === "Escape") {
        e.preventDefault()
        this._hideEdgeInsertButton()
        return
      }
      if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return
      e.preventDefault()
      const step = e.key === "ArrowDown" ? 1 : -1
      const current = items.indexOf(document.activeElement)
      items[(current + step + items.length) % items.length].focus()
    })

    menu.appendChild(list)
    this.handleLayer.appendChild(menu)
    this._edgeInsertMenu = menu

    this._edgeInsertOutsideHandler = () => this._hideEdgeInsertButton()
    document.addEventListener("mousedown", this._edgeInsertOutsideHandler)
    items[0].focus()
  },

  _closeEdgeInsertMenu() {
    if (this._edgeInsertOutsideHandler) {
      document.removeEventListener("mousedown", this._edgeInsertOutsideHandler)
      this._edgeInsertOutsideHandler = null
    }
    this._edgeInsertMenu?.remove()
    this._edgeInsertMenu = null
  },

  _hideEdgeInsertButton() {
    clearTimeout(this._edgeInsertHideTimer)
    this._closeEdgeInsertMenu()
    this._removeEdgeInsertButton()
  },

  /**
   * A re-render can move or remove the hovered connection: drop a stale
   * button, and close the menu once its connection is gone.
   */
  _refreshEdgeInsert() {
    const menuFor = this._edgeInsertMenu?.getAttribute("data-edge-insert-menu")
    if (menuFor && this.connections.some(c => c.id === menuFor)) return
    this._hideEdgeInsertButton()
  },

  _chooseEdgeInsertType(connectionId, type) {
    this._hideEdgeInsertButton()
    this.insertElementOnConnection(connectionId, type)
  }
}
