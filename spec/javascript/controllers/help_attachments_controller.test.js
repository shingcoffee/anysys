import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/help_attachments_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = `
  <form data-controller="help-attachments"
        data-help-attachments-max-files-value="2"
        data-help-attachments-max-bytes-value="10"
        data-help-attachments-accept-value="image/png,application/pdf"
        data-help-attachments-too-many-template-value="You can attach at most {count} files."
        data-help-attachments-type-label-value="That file type is not allowed."
        data-help-attachments-size-template-value="Each file must be {size} or smaller."
        data-help-attachments-remove-label-value="Remove">
    <input type="file" data-help-attachments-target="input" data-action="change->help-attachments#changed" data-role="input" multiple>
    <p class="hidden" data-help-attachments-target="error" data-role="error"></p>
    <ul data-help-attachments-target="list" data-role="list"></ul>
    <button type="submit" data-help-attachments-target="submit" data-role="submit">Send</button>
  </form>`

function file(name, type, size, lastModified = 1) {
  const blob = new Blob([new Uint8Array(size)], { type })
  return new File([blob], name, { type, lastModified })
}

describe("help-attachments controller", () => {
  let element
  let application
  let controller
  let stored

  beforeEach(async () => {
    vi.stubGlobal("URL", { createObjectURL: vi.fn(() => "blob:preview") })
    ;({ element, application } = await mountController("help-attachments", Controller, html))
    controller = controllerFor(application, element, "help-attachments")
    stored = []
    vi.spyOn(controller, "filesFromInput").mockImplementation(() => stored)
    vi.spyOn(controller, "writeFiles").mockImplementation((files) => { stored = files })
  })

  it("renders image chips and keeps submit enabled for a valid file", () => {
    stored = [file("shot.png", "image/png", 4)]
    controller.changed()
    expect(element.querySelector("[data-role='list'] img").getAttribute("src")).toBe("blob:preview")
    expect(element.querySelector("[data-role='submit']").disabled).toBe(false)
    expect(element.querySelector("[data-role='error']").classList.contains("hidden")).toBe(true)
  })

  it("revokes preview URLs when the list is re-rendered or the controller disconnects", async () => {
    const revoke = vi.fn()
    vi.stubGlobal("URL", { createObjectURL: vi.fn(() => "blob:preview"), revokeObjectURL: revoke })
    stored = [file("shot.png", "image/png", 4)]
    controller.changed()
    controller.changed()
    expect(revoke).toHaveBeenCalledWith("blob:preview")
    controller.disconnect()
    expect(revoke.mock.calls.length).toBeGreaterThanOrEqual(2)
  })

  it("renders a name-only chip for a non-image file", () => {
    stored = [file("doc.pdf", "application/pdf", 4)]
    controller.changed()
    expect(element.querySelector("[data-role='list'] img")).toBeNull()
    expect(element.querySelector("[data-role='list']").textContent).toContain("doc.pdf")
  })

  it("rejects too many files", () => {
    stored = [
      file("a.png", "image/png", 1),
      file("b.png", "image/png", 1),
      file("c.png", "image/png", 1)
    ]
    controller.changed()
    expect(element.querySelector("[data-role='error']").textContent).toBe("You can attach at most 2 files.")
    expect(element.querySelector("[data-role='submit']").disabled).toBe(true)
  })

  it("rejects a disallowed type", () => {
    stored = [file("note.txt", "text/plain", 4)]
    controller.changed()
    expect(element.querySelector("[data-role='error']").textContent).toBe("That file type is not allowed.")
  })

  it("rejects an oversized file", () => {
    stored = [file("big.png", "image/png", 20)]
    controller.changed()
    expect(element.querySelector("[data-role='error']").textContent).toBe("Each file must be 5MB or smaller.")
  })

  it("uses the sizeLabel value in the oversized message", async () => {
    const labeled = `
      <form data-controller="help-attachments"
            data-help-attachments-max-bytes-value="10"
            data-help-attachments-size-template-value="Each file must be {size} or smaller."
            data-help-attachments-size-label-value="1MB"
            data-help-attachments-remove-mark-value="Remove">
        <input type="file" data-help-attachments-target="input">
        <p class="hidden" data-help-attachments-target="error" data-role="error"></p>
        <ul data-help-attachments-target="list" data-role="list"></ul>
      </form>`
    const mounted = await mountController("help-attachments", Controller, labeled)
    const labeledController = controllerFor(mounted.application, mounted.element, "help-attachments")
    expect(labeledController.validate([file("big.png", "image/png", 20)])).toBe("Each file must be 1MB or smaller.")
    labeledController.render([file("shot.png", "image/png", 4)])
    expect(mounted.element.querySelector("[data-role='list'] button").textContent).toBe("Remove")
  })

  it("removes a file when the chip button is clicked", () => {
    stored = [file("a.png", "image/png", 1), file("b.png", "image/png", 1)]
    controller.changed()
    controller.remove({ currentTarget: { dataset: { index: "0" } } })
    expect(stored).toHaveLength(1)
    expect(stored[0].name).toBe("b.png")
    expect(element.querySelector("[data-role='list']").textContent).toContain("b.png")
    expect(element.querySelector("[data-role='list']").textContent).not.toContain("a.png")
  })

  it("accumulates files chosen in successive picker sessions", () => {
    stored = [file("a.png", "image/png", 1)]
    controller.changed()
    stored = [file("b.png", "image/png", 1)]
    controller.changed()
    expect(stored.map((row) => row.name)).toEqual(["a.png", "b.png"])
    expect(element.querySelector("[data-role='list']").textContent).toContain("a.png")
    expect(element.querySelector("[data-role='list']").textContent).toContain("b.png")
  })

  it("does not duplicate a file that is chosen again", () => {
    const shot = file("shot.png", "image/png", 1)
    stored = [shot]
    controller.changed()
    stored = [shot]
    controller.changed()
    expect(stored).toHaveLength(1)
  })

  it("treats a second File with the same name, size, and timestamp as a duplicate", () => {
    stored = [file("shot.png", "image/png", 4)]
    controller.changed()
    stored = [file("shot.png", "image/png", 4)]
    controller.changed()
    expect(stored).toHaveLength(1)
  })

  it("clears accumulated files when the form is reset", () => {
    stored = [file("a.png", "image/png", 1)]
    controller.changed()
    element.dispatchEvent(new Event("reset"))
    expect(stored).toHaveLength(0)
    expect(element.querySelector("[data-role='list']").children).toHaveLength(0)
    expect(element.querySelector("[data-role='submit']").disabled).toBe(false)
  })

  it("ignores a change event while files are being written back to the input", () => {
    controller.committing = true
    stored = [file("a.png", "image/png", 1)]
    controller.changed()
    expect(element.querySelector("[data-role='list']").children).toHaveLength(0)
  })

  it("listens for reset on a nested form when the controller wraps the form", async () => {
    const wrapped = `
      <div data-controller="help-attachments">
        <form data-role="form">
          <input type="file" data-help-attachments-target="input">
          <ul data-help-attachments-target="list" data-role="list"></ul>
        </form>
      </div>`
    const mounted = await mountController("help-attachments", Controller, wrapped)
    const wrappedController = controllerFor(mounted.application, mounted.element, "help-attachments")
    let nested = []
    vi.spyOn(wrappedController, "filesFromInput").mockImplementation(() => nested)
    vi.spyOn(wrappedController, "writeFiles").mockImplementation((files) => { nested = files })
    nested = [file("a.png", "image/png", 1)]
    wrappedController.changed()
    mounted.element.querySelector("[data-role='form']").dispatchEvent(new Event("reset"))
    expect(nested).toHaveLength(0)
    expect(mounted.element.querySelector("[data-role='list']").children).toHaveLength(0)
  })

  it("disconnect removes the form reset listener", () => {
    const removeSpy = vi.spyOn(element, "removeEventListener")
    controller.disconnect()
    expect(removeSpy).toHaveBeenCalledWith("reset", expect.any(Function))
  })

  it("connects and disconnects when there is no form", async () => {
    const bare = `
      <div data-controller="help-attachments">
        <input type="file" data-help-attachments-target="input">
      </div>`
    const mounted = await mountController("help-attachments", Controller, bare)
    const bareController = controllerFor(mounted.application, mounted.element, "help-attachments")
    expect(() => bareController.disconnect()).not.toThrow()
  })

  it("skips list and error updates when those targets are absent", async () => {
    const sparse = `
      <form data-controller="help-attachments">
        <input type="file" data-help-attachments-target="input">
      </form>`
    const mounted = await mountController("help-attachments", Controller, sparse)
    const sparseController = controllerFor(mounted.application, mounted.element, "help-attachments")
    expect(() => sparseController.render([file("shot.png", "image/png", 1)])).not.toThrow()
  })

  it("skips the thumbnail when createObjectURL is unavailable", () => {
    vi.stubGlobal("URL", {})
    stored = [file("shot.png", "image/png", 4)]
    controller.changed()
    expect(element.querySelector("[data-role='list'] img")).toBeNull()
    expect(element.querySelector("[data-role='list']").textContent).toContain("shot.png")
  })

  it("skips the thumbnail when URL is undefined", () => {
    vi.stubGlobal("URL", undefined)
    stored = [file("shot.png", "image/png", 4)]
    controller.changed()
    expect(element.querySelector("[data-role='list'] img")).toBeNull()
  })

  it("allows any type when accept is empty", async () => {
    const open = `
      <form data-controller="help-attachments" data-help-attachments-accept-value="">
        <input type="file" data-help-attachments-target="input">
        <p class="hidden" data-help-attachments-target="error" data-role="error"></p>
        <ul data-help-attachments-target="list" data-role="list"></ul>
      </form>`
    const mounted = await mountController("help-attachments", Controller, open)
    const openController = controllerFor(mounted.application, mounted.element, "help-attachments")
    expect(openController.validate([file("note.txt", "text/plain", 1)])).toBeNull()
  })

  it("filesFromInput reads the input FileList and writeFiles uses DataTransfer", async () => {
    const mounted = await mountController("help-attachments", Controller, html)
    const raw = controllerFor(mounted.application, mounted.element, "help-attachments")
    expect(raw.filesFromInput()).toEqual([])
    expect(() => raw.writeFiles([file("shot.png", "image/png", 1)])).not.toThrow()
  })

  it("treats a missing file type as a name-only chip", () => {
    const typeless = new File([new Uint8Array(1)], "mystery.bin")
    stored = [typeless]
    controller.changed()
    expect(element.querySelector("[data-role='list'] img")).toBeNull()
    expect(element.querySelector("[data-role='list']").textContent).toContain("mystery.bin")
  })
})
