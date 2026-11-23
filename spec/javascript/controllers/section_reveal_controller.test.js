import { afterEach, describe, it, expect } from "vitest"
import Controller from "controllers/section_reveal_controller"
import { mountController, click } from "../support/stimulus.js"

const html = `
  <section id="outside"><details><summary>Outside</summary></details></section>
  <div data-controller="section-reveal">
    <nav>
      <a id="to-domain" href="#domain" data-action="section-reveal#open">Domain</a>
      <a id="to-plain" href="#plain" data-action="section-reveal#open">Plain</a>
      <a id="to-outside" href="#outside" data-action="section-reveal#open">Outside</a>
      <a id="to-missing" href="#missing" data-action="section-reveal#open">Missing</a>
    </nav>
    <section id="domain"><details><summary>Domain</summary><div>Body</div></details></section>
    <section id="plain"><div><details><summary>Nested</summary></details></div></section>
  </div>`

const details = (id) => document.querySelector(`#${id} details`)

describe("section reveal controller", () => {
  afterEach(() => window.history.replaceState(null, "", window.location.pathname))

  it("opens the targeted section's own details when an index link is clicked", async () => {
    await mountController("section-reveal", Controller, html)
    expect(details("domain").open).toBe(false)

    await click(document.getElementById("to-domain"))

    expect(details("domain").open).toBe(true)
  })

  it("ignores targets without a direct details child, outside the controller, or missing", async () => {
    await mountController("section-reveal", Controller, html)

    await click(document.getElementById("to-plain"))
    await click(document.getElementById("to-outside"))
    await click(document.getElementById("to-missing"))

    expect(details("plain").open).toBe(false)
    expect(details("outside").open).toBe(false)
    expect(details("domain").open).toBe(false)
  })

  it("opens the section named by the URL fragment on connect", async () => {
    window.history.replaceState(null, "", "#domain")
    await mountController("section-reveal", Controller, html)

    expect(details("domain").open).toBe(true)
  })

  it("leaves every section as rendered without a URL fragment", async () => {
    await mountController("section-reveal", Controller, html)

    expect(Array.from(document.querySelectorAll("details")).some((node) => node.open)).toBe(false)
  })
})
