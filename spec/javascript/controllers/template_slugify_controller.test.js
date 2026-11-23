import { describe, it, expect } from "vitest"
import Controller from "controllers/template_slugify_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (keyVal = "") => `
<div data-controller="template-slugify">
  <input data-template-slugify-target="name" data-action="input->template-slugify#suggest" value="" />
  <input data-template-slugify-target="key" value="${keyVal}" />
</div>
`

describe("template-slugify controller", () => {
  it("slugifies standard text successfully", async () => {
    const { application, element } = await mountController("template-slugify", Controller, html())
    const ctrl = controllerFor(application, element, "template-slugify")

    element.querySelector("[data-template-slugify-target='name']").value = "Welcome Email Template!"
    ctrl.suggest()

    expect(element.querySelector("[data-template-slugify-target='key']").value).toBe("welcome_email_template")
  })

  it("does not overwrite an existing key values on load", async () => {
    const { application, element } = await mountController("template-slugify", Controller, html("fixed_key"))
    const ctrl = controllerFor(application, element, "template-slugify")

    element.querySelector("[data-template-slugify-target='name']").value = "New Title"
    ctrl.suggest()

    expect(element.querySelector("[data-template-slugify-target='key']").value).toBe("fixed_key")
  })
})
