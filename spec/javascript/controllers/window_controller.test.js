import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/window_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

describe("window controller", () => {
  afterEach(() => vi.restoreAllMocks())

  it("close() calls window.close()", async () => {
    const spy = vi.spyOn(window, "close").mockImplementation(() => {})
    const { application, element } = await mountController(
      "window", Controller,
      `<div data-controller="window"><button data-action="click->window#close">x</button></div>`
    )
    const ctrl = controllerFor(application, element, "window")
    ctrl.close()
    expect(spy).toHaveBeenCalledOnce()
  })
})
