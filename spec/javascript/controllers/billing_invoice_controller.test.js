import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/billing_invoice_controller"
import { mountController, click } from "../support/stimulus.js"

const html = `<div data-controller="billing-invoice">
                <button data-action="click->billing-invoice#print">Print</button>
              </div>`

describe("billing-invoice controller", () => {
  afterEach(() => vi.restoreAllMocks())

  it("print() calls window.print", async () => {
    const spy = vi.spyOn(window, "print").mockImplementation(() => {})
    const { element } = await mountController("billing-invoice", Controller, html)
    click(element.querySelector("button"))
    expect(spy).toHaveBeenCalledOnce()
  })
})
