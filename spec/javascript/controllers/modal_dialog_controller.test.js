import { describe, it, expect, vi, beforeAll } from "vitest"
import ModalDialog from "controllers/modal_dialog_controller"
import { mountController } from "../support/stimulus.js"

const html = (open = false) => `
  <div data-controller="modal-dialog" ${open ? 'data-modal-dialog-open-value="true"' : ""}>
    <button type="button" class="trigger" data-action="modal-dialog#open">Create profile</button>
    <dialog data-modal-dialog-target="dialog" data-action="click->modal-dialog#backdrop">
      <div class="body">
        <button type="button" class="close" data-action="modal-dialog#close">x</button>
      </div>
    </dialog>
  </div>`

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = vi.fn(function () { this.setAttribute("open", "") })
  HTMLDialogElement.prototype.close = vi.fn(function () { this.removeAttribute("open") })
})

async function mount(open) {
  HTMLDialogElement.prototype.showModal.mockClear()
  HTMLDialogElement.prototype.close.mockClear()
  const { element } = await mountController("modal-dialog", ModalDialog, html(open))
  return { element, dialog: element.querySelector("dialog") }
}

describe("modal-dialog controller", () => {
  it("stays closed on connect by default and opens from its trigger", async () => {
    const { element, dialog } = await mount()
    expect(dialog.showModal).not.toHaveBeenCalled()

    element.querySelector(".trigger").click()

    expect(dialog.showModal).toHaveBeenCalledTimes(1)
    expect(dialog.open).toBe(true)
  })

  it("opens on connect when the open value is set, without reopening an open dialog", async () => {
    const { element, dialog } = await mount(true)
    expect(dialog.showModal).toHaveBeenCalledTimes(1)

    element.querySelector(".trigger").click()

    expect(dialog.showModal).toHaveBeenCalledTimes(1)
  })

  it("closes from its close button", async () => {
    const { element, dialog } = await mount(true)

    element.querySelector(".close").click()

    expect(dialog.close).toHaveBeenCalledTimes(1)
    expect(dialog.open).toBe(false)
  })

  it("closes on a backdrop click but not on a click inside the content", async () => {
    const { element, dialog } = await mount(true)

    element.querySelector(".body").click()
    expect(dialog.close).not.toHaveBeenCalled()

    dialog.click()
    expect(dialog.close).toHaveBeenCalledTimes(1)
  })
})
