import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"

vi.mock("sortablejs", () => ({
  default: { create: vi.fn(() => ({ destroy: vi.fn() })) },
}))

import Sortable from "sortablejs"
import Controller from "controllers/website_builder_controller"
import { mountController, click, controllerFor, tick } from "../support/stimulus.js"

const row = (i, extras = "") =>
  `<article data-website-builder-target="row" data-section-id="sec_${i}" data-section-type="quote" data-row="${i}">` +
  `<span data-website-builder-target="handle">⠿</span>` +
  `<input data-prop="quote" value="q${i}">` +
  `<button data-action="click->website-builder#moveUp">up</button>` +
  `<button data-action="click->website-builder#moveDown">down</button>` +
  `<button data-action="click->website-builder#removeSection">del</button>` +
  extras +
  `</article>`

const kitBtn = (type) =>
  `<button data-type="${type}" data-action="click->website-builder#addSection">add ${type}</button>`

const html = (opts = {}) => {
  const n = opts.rows ?? 3
  const rows = Array.from({ length: n }, (_, i) => row(i, opts.rowExtras?.(i) || "")).join("")
  const list = opts.list === false ? "" : `<div data-website-builder-target="list">${rows}</div>`
  const kit = opts.kit === false ? "" : `<div data-website-builder-target="kit" class="hidden">${kitBtn("quote")}${kitBtn("missing")}${kitBtn("plain")}${kitBtn("empty")}</div>`
  const json = opts.json === false ? "" : `<input data-website-builder-target="json" value="[]">`
  const unsaved = opts.unsaved === false ? "" : `<p data-website-builder-target="unsaved" class="hidden">unsaved</p>`
  const empty = opts.empty === false ? "" : `<div data-website-builder-target="empty" class="${n > 0 ? "hidden" : ""}">empty</div>`
  const frame = opts.frame
    ? `<iframe data-website-builder-target="previewFrame" src="${opts.src ?? "about:blank"}"></iframe>`
    : ""
  const loading = opts.loading
    ? `<div data-website-builder-target="previewLoading" class="hidden">loading</div>`
    : ""
  const templates = opts.templates === false
    ? ""
    : `<template data-section-template="quote"><article data-website-builder-target="row" data-section-id="__SECTION_ID__" data-section-type="quote" id="section___SECTION_ID___wrap"><details class="group/section"><input id="section___SECTION_ID___quote" name="section___SECTION_ID___quote" data-prop="quote" value=""><label for="section___SECTION_ID___quote">Quote</label></details><template data-item-template><label for="section___SECTION_ID___item">Item</label><input id="section___SECTION_ID___item" name="section___SECTION_ID___item"></template><button data-action="click->website-builder#moveUp">up</button><button data-action="click->website-builder#moveDown">down</button></article></template>` +
      `<template data-section-template="empty"></template>` +
      `<template data-section-template="plain"><article data-website-builder-target="row" data-section-id="__SECTION_ID__" data-section-type="quote"></article></template>`
  const kitToggle = opts.kitToggle === false ? "" : `<button data-kit-toggle data-action="click->website-builder#toggleKit" aria-expanded="false">Add section</button>`
  const arrayBlock = opts.array
    ? `<div data-array="${opts.arrayKey ?? "items"}" data-min="${opts.min ?? 0}" data-max="${opts.max ?? 6}">` +
      `<div data-array-list>${opts.arrayItems ?? `<div data-array-item data-item="a"><input data-prop="label" value="a"><input data-prop="value" value="1"><button data-action="click->website-builder#moveItemUp">item up</button><button data-action="click->website-builder#moveItemDown">item down</button><button data-action="click->website-builder#duplicateItem">dup</button><button data-remove-item data-action="click->website-builder#removeItem">rm</button></div>`}</div>` +
      `<template data-item-template><div data-array-item><input data-prop="label" value=""><input data-prop="value" value=""><button data-action="click->website-builder#moveItemUp">item up</button><button data-action="click->website-builder#moveItemDown">item down</button><button data-action="click->website-builder#duplicateItem">dup</button><button data-remove-item data-action="click->website-builder#removeItem">rm</button></div></template>` +
      `<button data-add-item data-action="click->website-builder#addItem">add item</button>` +
      `</div>`
    : ""
  const extra = opts.extra || ""
  const arrayRow = arrayBlock
    ? row(99, arrayBlock).replace('data-section-type="quote"', 'data-section-type="proof_strip"')
    : ""

  const lockedAttr = opts.structureLocked ? ` data-website-builder-structure-locked-value="true"` : ""
  const formatAttr = opts.charCountFormat ? ` data-website-builder-char-count-format-value="${opts.charCountFormat}"` : ""
  const resetAttr = opts.resetConfirm ? ` data-website-builder-reset-confirm-value="${opts.resetConfirm}"` : ""
  const expandAttr = opts.expandAll ? ` data-website-builder-expand-all-value="${opts.expandAll}"` : ""
  const collapseAttr = opts.collapseAll ? ` data-website-builder-collapse-all-value="${opts.collapseAll}"` : ""
  const toggleAll = opts.toggleAll
    ? `<button data-website-builder-target="toggleAll" data-action="click->website-builder#toggleAllSections">Expand all</button>`
    : ""

  return `<div data-controller="website-builder" data-action="turbo:submit-end->website-builder#reloadPreview" data-website-builder-delete-confirm-value="Remove this section from the page?"${lockedAttr}${formatAttr}${resetAttr}${expandAttr}${collapseAttr}>${toggleAll}${kitToggle}${kit}${empty}${list}${arrayRow}${json}${unsaved}${frame}${loading}${templates}${extra}</div>`
}

const order = (el) => [...el.querySelectorAll("[data-row]")].map((r) => r.dataset.row)
const jsonValue = (el) => JSON.parse(el.querySelector("[data-website-builder-target='json']").value)
const upBtn = (el, i) => el.querySelector(`[data-row='${i}'] [data-action*='moveUp']`)
const downBtn = (el, i) => el.querySelector(`[data-row='${i}'] [data-action*='moveDown']`)
const delBtn = (el, i) => el.querySelector(`[data-row='${i}'] [data-action*='removeSection']`)

const sectionTab = (id) =>
  `<button type="button" id="website-section-tab-${id}" role="tab" data-website-builder-target="sectionNav" data-section-id="${id}" aria-controls="website-section-panel-${id}" data-action="click->website-builder#focusSection keydown->website-builder#navigateSectionTabs"><span data-section-number></span><span data-section-label></span></button>`

const workspaceRow = (id, label, hidden = false) =>
  `<article id="website-section-panel-${id}" role="tabpanel" aria-labelledby="website-section-tab-${id}" data-website-builder-target="row" data-section-id="${id}" data-section-label="${label}" data-section-type="quote" class="${hidden ? "hidden" : ""}">` +
  `<input data-prop="quote" value="Copy ${id}">` +
  `<details data-secondary><summary>Secondary</summary><details data-url><summary>URL</summary><input data-prop="url" value="https://example.test/${id}"></details></details>` +
  `<details data-items open><summary>Items</summary><div data-array="items"><div data-array-item><input data-prop="label" value="Item ${id}"></div></div></details>` +
  `<button type="button" data-action="click->website-builder#moveUp">up</button>` +
  `<button type="button" data-action="click->website-builder#moveDown">down</button>` +
  `<button type="button" data-action="click->website-builder#removeSection">remove</button></article>`

const workspace = ({ locked = false, count = 3 } = {}) =>
  `<form data-controller="website-builder" data-website-workspace data-website-builder-structure-locked-value="${locked}">` +
  `<div role="tablist">${["editor", "preview"].map((pane) =>
    `<button type="button" id="website-workspace-tab-${pane}" role="tab" aria-controls="website-workspace-panel-${pane}" data-website-builder-target="paneBtn" data-pane="${pane}" data-action="click->website-builder#setWorkspacePane keydown->website-builder#navigatePaneTabs">${pane}</button>`
  ).join("")}</div>` +
  `<section id="website-workspace-panel-editor" role="tabpanel" aria-labelledby="website-workspace-tab-editor" data-website-builder-target="editorPane">` +
  `<div role="tablist" data-workspace-section-nav>${Array.from({ length: count }, (_, i) => sectionTab(`sec_${i}`)).join("")}</div>` +
  `<template data-section-nav-template>${sectionTab("SECTION_ID")}</template>` +
  `<div data-workspace-rail data-website-builder-target="list">${Array.from({ length: count }, (_, i) => workspaceRow(`sec_${i}`, `章节 ${i + 1}`, i > 0)).join("")}</div>` +
  `<template data-section-template="quote">${workspaceRow("__SECTION_ID__", "引言", true)}</template>${kitBtn("quote")}</section>` +
  `<section id="website-workspace-panel-preview" role="tabpanel" aria-labelledby="website-workspace-tab-preview" data-website-builder-target="previewPane"></section>` +
  `<input name="website_page[sections_json]" data-website-builder-target="json"><input data-outside value="Title"></form>`

const keydown = (el, key) => {
  const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
  el.dispatchEvent(event)
  return event
}

const linkControl = (id, value = "about") => `<div data-href-field>
  <label for="${id}">Destination</label><input id="${id}" data-prop="href" value="${value}" aria-describedby="${id}_error" data-action="input->website-builder#markDirty input->website-builder#checkHref">
  <button type="button" data-href-toggle aria-controls="${id}_picker_panel" aria-expanded="false" data-action="click->website-builder#toggleHrefPicker">Choose page</button>
  <div data-href-picker id="${id}_picker_panel" hidden data-action="keydown.esc->website-builder#closeHrefPicker"><select data-action="change->website-builder#applyHref"><option value="">Choose</option><option value="about">About</option><option value="contact">Contact</option></select></div>
  <p data-href-status id="${id}_error" class="hidden">请输入页面路径或 HTTPS 链接</p></div>`

const mediaControl = (id, value = "https://cdn.example/old.png") => `<div data-image-field>
  <img data-image-preview alt="" data-action="error->website-builder#imageError load->website-builder#imageLoaded">
  <span data-image-empty></span><span data-image-present>Photo added</span><span data-image-failed>Preview unavailable</span>
  <span data-image-add>Add</span><span data-image-replace>Replace</span>
  <input type="file" id="${id}_file" data-action="change->website-builder#uploadImage">
  <button type="button" data-image-clear data-action="click->website-builder#clearImage">Remove</button>
  <p data-image-status class="hidden"></p><details><summary>Edit image link</summary>
  <input id="${id}" data-prop="image_url" value="${value}" data-action="input->website-builder#markDirty input->website-builder#previewImage"></details></div>`

const contentItem = (id, title = "", simple = false, key = "title") => {
  const tag = simple ? "div" : "details"
  return `<${tag} data-array-item id="${id}" ${id === "a" && !simple ? "open" : ""}>
    <${simple ? "div" : "summary"}><span data-item-number></span><span data-item-title></span><img data-item-image alt="" data-action="error->website-builder#itemImageError"></${simple ? "div" : "summary"}>
    <button type="button" data-action="click->website-builder#moveItemUp">Up</button><button type="button" data-action="click->website-builder#moveItemDown">Down</button>
    <button type="button" data-duplicate-item data-action="click->website-builder#duplicateItem">Duplicate</button><button type="button" data-remove-item data-action="click->website-builder#removeItem">Remove</button>
    <label for="${id}_title">Title</label><input id="${id}_title" data-prop="${key}" value="${title}" data-action="input->website-builder#markDirty">
    <textarea data-prop="body" data-action="input->website-builder#markDirty">Original body</textarea>
    <select data-prop="choice"><option value="one">One</option><option value="two">Two</option></select>
    <input type="radio" name="${id}_span" data-prop="span" value="unit" checked><input type="radio" name="${id}_span" data-prop="span" value="hero">
    ${linkControl(`${id}_href`)}${mediaControl(`${id}_image`)}
  </${tag}>`
}

const contentEditor = ({ count = 2, simple = false, min = 0, max = 4, key = "title", kind = "cards" } = {}) =>
  `<form data-controller="website-builder" data-website-workspace data-website-builder-upload-url-value="/upload">
    <input name="website_page[sections_json]" data-website-builder-target="json"><p data-website-builder-target="unsaved" class="hidden">Unsaved</p>
    <article data-website-builder-target="row" data-section-id="content" data-section-type="card_grid">
      <button type="button" data-reset data-action="click->website-builder#resetSection">Reset</button>
      <div data-array="${kind}" data-array-kind="${kind}" data-item-title-key="${key}" data-min="${min}" data-max="${max}">
        <span data-array-count></span><span data-array-limit></span>
        <button type="button" data-add-item data-action="click->website-builder#addItem">Add</button>
        <div data-array-list>${Array.from({ length: count }, (_, i) => contentItem(String.fromCharCode(97 + i), i === 0 ? "First" : "", simple, key)).join("")}</div>
        <template data-item-template>${contentItem("new", "", simple, key)}</template>
      </div>
    </article></form>`

const changeValue = (input, value, type = "input") => {
  input.value = value
  input.dispatchEvent(new Event(type, { bubbles: true }))
}
const pendingResponse = () => {
  let resolve, reject
  const promise = new Promise((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}

const reconnectController = async (application, element) => {
  const controller = controllerFor(application, element, "website-builder")
  // Detach the wrapper: happy-dom's form proxy cannot remove itself reliably.
  // Stimulus still observes the real DOM lifecycle and reuses the same instance.
  const host = element.parentElement
  const parent = host.parentElement
  const disconnect = vi.spyOn(controller, "disconnect")
  const connect = vi.spyOn(controller, "connect")
  host.remove()
  await tick()
  expect(disconnect).toHaveBeenCalledOnce()
  parent.appendChild(host)
  await tick()
  expect(connect).toHaveBeenCalledOnce()
  expect(controllerFor(application, element, "website-builder")).toBe(controller)
}

describe("website-builder compact content controls", () => {
  let application, element, ctrl
  const items = () => [...element.querySelectorAll("[data-array-item]")]
  const mount = async (options = {}) => {
    ;({ application, element } = await mountController("website-builder", Controller, contentEditor(options)))
    ctrl = controllerFor(application, element, "website-builder")
  }
  const upload = (field) => ctrl.dropImage({ currentTarget: field, preventDefault: vi.fn(), dataTransfer: { files: [new File(["photo"], "photo.png", { type: "image/png" })] } })
  beforeEach(() => {
    vi.spyOn(HTMLFormElement.prototype, "contains").mockImplementation(function (node) {
      return node === this || [...this.querySelectorAll("*")].includes(node)
    })
  })
  afterEach(() => {
    ctrl?.disconnect()
    application?.stop()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it.each([["cards", "title"], ["cells", "title"], ["items", "title"], ["people", "name"], ["items", "question"], ["items", "label"]])("refreshes live %s/%s summaries, counts and accessible action labels without persisting UI metadata", async (kind, key) => {
    await mount({ kind, key })
    expect(items().map((item) => item.querySelector("[data-item-title]").textContent)).toEqual(["First", "Item 2"])
    expect(items().map((item) => item.open)).toEqual([true, false])
    expect(element.querySelector("[data-array-count]").textContent).toBe("2")
    expect(element.querySelector("[data-array-limit]").textContent).toBe("2 of 4")
    const input = items()[1].querySelector(`[data-prop='${key}']`)
    changeValue(input, " <img src=x> $& ")
    expect(items()[1].querySelector("[data-item-title]").textContent).toBe("<img src=x> $&")
    expect(items()[1].querySelector("[data-item-title] img")).toBeNull()
    expect(items()[1].querySelector("[data-duplicate-item]").getAttribute("aria-label")).toBe("Duplicate item 2: <img src=x> $&")
    const props = jsonValue(element)[0].props[kind]
    expect(props[1][key]).toBe(" <img src=x> $& ")
    expect(props[1].image_url).toBe("https://cdn.example/old.png")
    expect(props[1].body).toBe("Original body")
    expect(props[1].open).toBeUndefined()
    expect(props[1].number).toBeUndefined()
  })

  it("adds and duplicates live controls with local IDs, independent radios and cleared transient state", async () => {
    const pending = pendingResponse()
    vi.stubGlobal("fetch", vi.fn(() => pending.promise))
    await mount()
    const source = items()[0]
    changeValue(source.querySelector("textarea"), "Edited\nbody")
    source.querySelector("select[data-prop]").value = "two"
    source.querySelector("[value='hero']").checked = true
    changeValue(source.querySelector("[data-prop='href']"), "http://invalid.test")
    await click(source.querySelector("[data-href-toggle]"))
    upload(source.querySelector("[data-image-field]"))
    await click(source.querySelector("[data-duplicate-item]"))
    const copy = items()[1]
    expect(copy.open).toBe(true)
    expect(document.activeElement).toBe(copy.querySelector("[data-prop='title']"))
    expect(copy.querySelector("textarea").value).toBe("Edited\nbody")
    expect(copy.querySelector("select[data-prop]").value).toBe("two")
    expect(copy.querySelector("[value='hero']").checked).toBe(true)
    expect(copy.querySelector("[value='hero']").name).not.toBe(source.querySelector("[value='hero']").name)
    copy.querySelector("[value='unit']").checked = true
    expect(source.querySelector("[value='hero']").checked).toBe(true)
    expect(copy.querySelector("[data-href-picker]").hidden).toBe(true)
    expect(copy.querySelector("[data-href-toggle]").getAttribute("aria-expanded")).toBe("false")
    expect(copy.querySelector("[data-prop='href']").validationMessage).toBe("请输入页面路径或 HTTPS 链接")
    expect(copy.querySelector("[data-image-field]").getAttribute("aria-busy")).toBe("false")
    expect(copy.querySelector("[type='file']").disabled).toBe(false)
    expect(copy.querySelector("[data-image-status]").textContent).toBe("")
    expect(source.querySelector("[data-image-field]").getAttribute("aria-busy")).toBe("true")
    expect(copy.querySelector("[data-href-toggle]").getAttribute("aria-controls")).toBe(copy.querySelector("[data-href-picker]").id)
    for (const label of copy.querySelectorAll("label")) expect(copy.querySelector(`[id='${label.htmlFor}']`)).not.toBeNull()
    const input = copy.querySelector("[data-prop='href']")
    expect(input.getAttribute("aria-describedby")).toBe(copy.querySelector("[data-href-status]").id)
    await click(element.querySelector("[data-add-item]"))
    expect(items()[3].open).toBe(true)
    expect(document.activeElement).toBe(items()[3].querySelector("[data-prop='title']"))
    expect(element.querySelector("[data-add-item]").disabled).toBe(true)
    expect(items().every((item) => item.querySelector("[data-duplicate-item]").disabled)).toBe(true)
    ctrl.duplicateItem({ currentTarget: copy.querySelector("[data-duplicate-item]") })
    expect(items()).toHaveLength(4)
    const ids = [...element.querySelectorAll("[id]")].map((el) => el.id)
    expect(new Set(ids).size).toBe(ids.length)
    pending.resolve({ ok: true, json: async () => ({ url: "/12345678/site/media/new" }) })
    await tick()
    expect(source.querySelector("[data-prop='image_url']").value).toBe("/12345678/site/media/new")
    expect(copy.querySelector("[data-prop='image_url']").value).toBe("https://cdn.example/old.png")
  })

  it("moves existing items with their disclosure state and restores action or boundary-summary focus", async () => {
    await mount({ count: 3 })
    const item = items()[2]
    const up = item.querySelector("[data-action*='moveItemUp']")
    up.focus()
    await click(up)
    expect(items()[1]).toBe(item)
    expect(item.open).toBe(false)
    expect(document.activeElement).toBe(up)
    await click(up)
    expect(items()[0]).toBe(item)
    expect(up.disabled).toBe(true)
    expect(document.activeElement).toBe(item.querySelector("summary"))
    item.open = true
    const down = item.querySelector("[data-action*='moveItemDown']")
    await click(down)
    expect(document.activeElement).toBe(down)
    await click(down)
    expect(document.activeElement).toBe(item.querySelector("summary"))
    expect(item.open).toBe(true)
    expect(item.querySelector("[data-item-number]").textContent).toBe("3")
  })

  it.each([false, true])("removes items with next/previous/empty focus (simple=%s) and honors min", async (simple) => {
    await mount({ count: 3, simple, min: 1 })
    const [first, second, third] = items()
    const target = (item) => item.querySelector(simple ? "input" : "summary")
    await click(second.querySelector("[data-remove-item]"))
    expect(document.activeElement).toBe(target(third))
    await click(third.querySelector("[data-remove-item]"))
    expect(document.activeElement).toBe(target(first))
    expect(first.querySelector("[data-remove-item]").disabled).toBe(true)
    ctrl.removeItem({ currentTarget: first.querySelector("[data-remove-item]") })
    expect(items()).toHaveLength(1)
    element.querySelector("[data-array]").dataset.min = "0"
    ctrl.removeItem({ currentTarget: first.querySelector("[data-remove-item]") })
    expect(document.activeElement).toBe(element.querySelector("[data-add-item]"))
    expect(element.querySelector("[data-array-count]").textContent).toBe("0")
    await click(element.querySelector("[data-add-item]"))
    expect(document.activeElement).toBe(items()[0].querySelector("input"))
  })

  it.each(["attribute", "class"])("opens/closes the page picker hidden by %s without dirtying; prompt is inert, selection validates and returns focus", async (visibility) => {
    await mount({ count: 1 })
    const field = element.querySelector("[data-href-field]")
    const toggle = field.querySelector("[data-href-toggle]")
    const panel = field.querySelector("[data-href-picker]")
    if (visibility === "class") {
      panel.hidden = false
      panel.classList.add("hidden")
    }
    const select = panel.querySelector("select")
    const input = field.querySelector("input")
    const before = element.querySelector("[data-website-builder-target='json']").value
    await click(toggle)
    expect(panel.hidden).toBe(false)
    expect(panel.classList.contains("hidden")).toBe(false)
    expect(document.activeElement).toBe(select)
    expect(select.value).toBe("about")
    changeValue(select, "", "change")
    expect(input.value).toBe("about")
    expect(panel.hidden).toBe(false)
    keydown(select, "Escape")
    expect(panel.hidden).toBe(true)
    expect(document.activeElement).toBe(toggle)
    await click(toggle)
    await click(toggle)
    expect(panel.hidden).toBe(true)
    expect(element.querySelector("[data-website-builder-target='unsaved']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-website-builder-target='json']").value).toBe(before)
    await click(toggle)
    changeValue(select, "contact", "change")
    expect(input.value).toBe("contact")
    expect(input.validity.valid).toBe(true)
    expect(panel.hidden).toBe(true)
    expect(toggle.getAttribute("aria-expanded")).toBe("false")
    expect(document.activeElement).toBe(input)
    expect(jsonValue(element)[0].props.cards[0].href).toBe("contact")
    changeValue(input, "missing-from-picker")
    expect(select.value).toBe("")
    expect(input.validity.valid).toBe(true)
    await click(toggle)
    expect(input.value).toBe("missing-from-picker")
  })

  it("initializes native href validity and reveals an inactive section and closed item before invalid focus", async () => {
    const markup = workspace({ count: 2 }).replace('<input data-prop="quote" value="Copy sec_1">', `<details data-array-item><summary>Card</summary>${linkControl("invalid", "http://unsafe.test")}</details>`)
    ;({ application, element } = await mountController("website-builder", Controller, markup))
    ctrl = controllerFor(application, element, "website-builder")
    const input = element.querySelector("#invalid")
    expect(input.validity.customError).toBe(true)
    expect(input.validationMessage).toBe(element.querySelector("[data-href-status]").textContent)
    expect(input.closest("article").classList.contains("hidden")).toBe(true)
    expect(input.closest("details").open).toBe(false)
    expect(input.checkValidity()).toBe(false)
    expect(input.closest("article").classList.contains("hidden")).toBe(false)
    expect(input.closest("details").open).toBe(true)
    changeValue(input, "https://safe.test/")
    expect(input.checkValidity()).toBe(true)
  })

  it.each(["/auth/sign_up", "/81721200/admin", "/path?query#frag", "/", "/path//child", " /auth/sign_up ", "/~profile", "\u00a0/auth/sign_up\u00a0", "/团队/😀"])("accepts %s on mount and after editing without blocking the form", async (href) => {
    const markup = workspace({ count: 1 }).replace('<input data-prop="quote" value="Copy sec_0">', linkControl("destination", href))
    ;({ application, element } = await mountController("website-builder", Controller, markup))
    ctrl = controllerFor(application, element, "website-builder")
    const input = element.querySelector("#destination")
    const status = element.querySelector("[data-href-status]")
    expect(input.getAttribute("aria-invalid")).toBe("false")
    expect(status.classList.contains("hidden")).toBe(true)
    expect(element.checkValidity()).toBe(true)
    expect(jsonValue(element)[0].props.href).toBe(href)
    expect(new URL(href, "https://app.example").origin).toBe("https://app.example")

    changeValue(input, "//evil.example/phish")
    expect(element.checkValidity()).toBe(false)
    changeValue(input, href)
    expect(input.validationMessage).toBe("")
    expect(input.getAttribute("aria-invalid")).toBe("false")
    expect(status.classList.contains("hidden")).toBe(true)
    expect(element.checkValidity()).toBe(true)
    expect(jsonValue(element)[0].props.href).toBe(href)
  })

  it.each([
    "//evil.example/phish", "///evil.example", "/\\evil.example/phish", "\\\\evil.example",
    "/path\\child", "/path?query=\\host", "/path#\\host", "/path with spaces",
    "https://safe.example\\@evil.example", "javascript:alert(1)", "data:text/html,hi", "http://evil.example"
  ])("blocks unsafe href %s in the mounted form", async (href) => {
    await mount({ count: 1 })
    const input = element.querySelector("[data-prop='href']")
    changeValue(input, href)
    expect(input.getAttribute("aria-invalid")).toBe("true")
    expect(input.validity.customError).toBe(true)
    expect(element.querySelector("[data-href-status]").classList.contains("hidden")).toBe(false)
    expect(element.checkValidity()).toBe(false)
  })

  it("rejects raw controls before trimming or URL parsing can erase them", async () => {
    // A textarea preserves CR/LF; text inputs strip them before input events.
    // Exercise the validator with the original value, not an already-sanitized input.
    const markup = workspace({ count: 1 }).replace('<input data-prop="quote" value="Copy sec_0">',
      `<div data-href-field><textarea data-prop="href" data-action="input->website-builder#checkHref"></textarea><p data-href-status>Invalid link</p></div>`)
    ;({ application, element } = await mountController("website-builder", Controller, markup))
    ctrl = controllerFor(application, element, "website-builder")
    const input = element.querySelector("textarea")
    const controls = [...Array.from({ length: 32 }, (_, i) => i), ...Array.from({ length: 33 }, (_, i) => 127 + i)]
    for (const code of controls) {
      const control = String.fromCharCode(code)
      for (const href of [control, `${control}/auth/sign_up`, `/auth/sign_up${control}`, `/${control}/evil.example`, `https://safe.example/${control}path`]) {
        changeValue(input, href)
        expect(input.validity.customError, JSON.stringify(href)).toBe(true)
        expect(element.checkValidity(), JSON.stringify(href)).toBe(false)
      }
    }
    changeValue(input, "/auth/sign_up")
    expect(element.checkValidity()).toBe(true)
  })

  it("keeps reset confirmation, restores first-open items and all derived field state, and retains reset focus", async () => {
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(false)
    await mount()
    const defaults = { cards: [{ title: "Starter", href: "http://invalid.test", image_url: "", span: "hero" }, { title: "Next", href: "contact" }] }
    element.querySelector("article").dataset.sectionDefaults = JSON.stringify(defaults)
    const reset = element.querySelector("[data-reset]")
    reset.focus()
    await click(reset)
    expect(confirm).toHaveBeenCalledWith(ctrl.resetConfirmValue)
    expect(items()[0].querySelector("[data-item-title]").textContent).toBe("First")
    confirm.mockReturnValue(true)
    await click(reset)
    expect(document.activeElement).toBe(reset)
    expect(items().map((item) => item.open)).toEqual([true, false])
    expect(items().map((item) => item.querySelector("[data-item-title]").textContent)).toEqual(["Starter", "Next"])
    expect(items()[0].querySelector("[data-prop='href']").validity.customError).toBe(true)
    expect(items()[1].querySelector("[data-prop='href']").validity.valid).toBe(true)
    expect(items()[0].querySelector("[value='hero']").checked).toBe(true)
    expect(items()[0].querySelector("[data-image-clear]").classList.contains("hidden")).toBe(true)
    expect(items()[0].querySelector("[data-item-image]").hasAttribute("src")).toBe(false)
    expect(element.querySelector("[data-array-count]").textContent).toBe("2")
  })

  it("shows failed compact previews without clearing the canonical URL and safely refreshes summary thumbnails", async () => {
    await mount({ count: 1 })
    const field = element.querySelector("[data-image-field]")
    const image = field.querySelector("img")
    const summaryImage = element.querySelector("[data-item-image]")
    const input = field.querySelector("[data-prop]")
    image.dispatchEvent(new Event("error"))
    expect(input.value).toBe("https://cdn.example/old.png")
    expect(field.querySelector("[data-image-failed]").classList.contains("hidden")).toBe(false)
    expect(field.querySelector("[data-image-empty]").classList.contains("hidden")).toBe(true)
    expect(field.querySelector("[data-image-replace]").classList.contains("hidden")).toBe(false)
    expect(field.querySelector("[data-image-clear]").classList.contains("hidden")).toBe(false)
    expect(field.querySelector("[data-image-status]").textContent).toBe("Image preview unavailable")
    summaryImage.dispatchEvent(new Event("error"))
    ctrl.markDirty()
    expect(summaryImage.classList.contains("hidden")).toBe(true)
    changeValue(input, "javascript:alert(1)")
    expect(summaryImage.hasAttribute("src")).toBe(false)
    expect(image.hasAttribute("src")).toBe(false)
    changeValue(input, " https://cdn.example/new.png ")
    expect(summaryImage.getAttribute("src")).toBe("https://cdn.example/new.png")
    expect(summaryImage.classList.contains("hidden")).toBe(false)
    image.dispatchEvent(new Event("load"))
    expect(field.querySelector("[data-image-present]").classList.contains("hidden")).toBe(false)
    image.dispatchEvent(new Event("error"))
    image.dispatchEvent(new Event("load"))
    expect(field.querySelector("[data-image-status]").textContent).toBe("")
    await click(field.querySelector("[data-image-clear]"))
    image.dispatchEvent(new Event("error"))
    expect(input.value).toBe("")
    expect(field.querySelector("[data-image-status]").textContent).toBe("")
    expect(field.querySelector("[data-image-clear]").classList.contains("hidden")).toBe(true)
    expect(field.querySelector("[data-image-empty]").classList.contains("hidden")).toBe(false)
  })

  it("disables repeat upload while pending, preserves the previous photo on failure, and recovers on retry", async () => {
    const pending = pendingResponse()
    const fetchMock = vi.fn().mockReturnValueOnce(pending.promise).mockResolvedValueOnce({ ok: true, json: async () => ({ url: "/12345678/site/media/retry" }) })
    vi.stubGlobal("fetch", fetchMock)
    await mount({ count: 1 })
    const field = element.querySelector("[data-image-field]")
    const file = field.querySelector("[type='file']")
    upload(field)
    expect(field.getAttribute("aria-busy")).toBe("true")
    expect(file.disabled).toBe(true)
    expect(field.querySelector("[data-image-status]").textContent).toBe("Uploading...")
    upload(field)
    expect(fetchMock).toHaveBeenCalledOnce()
    field.querySelector("img").dispatchEvent(new Event("error"))
    expect(field.querySelector("[data-image-status]").textContent).toBe("Uploading...")
    pending.resolve({ ok: false, json: async () => ({ error: "Upload rejected" }) })
    await tick()
    expect(field.getAttribute("aria-busy")).toBe("false")
    expect(file.disabled).toBe(false)
    expect(field.querySelector("[data-prop]").value).toBe("https://cdn.example/old.png")
    expect(field.querySelector("[data-image-status]").textContent).toBe("Upload rejected")
    upload(field)
    await tick()
    expect(field.querySelector("[data-prop]").value).toBe("/12345678/site/media/retry")
    expect(field.querySelector("[data-image-status]").textContent).toBe("")
    expect(element.querySelector("[data-item-image]").getAttribute("src")).toBe("/12345678/site/media/retry")
    expect(field.getAttribute("aria-busy")).toBe("false")
  })

  it.each(["clear", "reset", "input", "remove", "disconnect", "detach"])("ignores stale upload success after %s", async (operation) => {
    const pending = pendingResponse()
    const fetchMock = vi.fn(() => pending.promise)
    vi.stubGlobal("fetch", fetchMock)
    vi.spyOn(window, "confirm").mockReturnValue(true)
    await mount()
    const item = items()[0]
    const field = item.querySelector("[data-image-field]")
    const input = field.querySelector("[data-prop]")
    upload(field)
    const signal = fetchMock.mock.calls[0][1].signal
    if (operation === "clear") await click(field.querySelector("[data-image-clear]"))
    if (operation === "reset") await click(element.querySelector("[data-reset]"))
    if (operation === "input") changeValue(input, "https://cdn.example/typed.png")
    if (operation === "remove") await click(item.querySelector("[data-remove-item]"))
    if (operation === "disconnect") ctrl.disconnect()
    if (operation === "detach") item.remove()
    const value = input.value
    const json = element.querySelector("[data-website-builder-target='json']").value
    pending.resolve({ ok: true, json: async () => ({ url: "/12345678/site/media/stale" }) })
    await tick()
    expect(input.value).toBe(value)
    expect(element.querySelector("[data-website-builder-target='json']").value).toBe(json)
    expect(signal.aborted).toBe(operation !== "detach")
    expect(field.getAttribute("aria-busy")).toBe("false")
    expect(field.querySelector("[type='file']").disabled).toBe(false)
  })

  it("ignores an aborted upload rejection and does not clear a newer operation's busy/status state", async () => {
    const old = pendingResponse(), next = pendingResponse()
    const fetchMock = vi.fn().mockReturnValueOnce(old.promise).mockReturnValueOnce(next.promise)
    vi.stubGlobal("fetch", fetchMock)
    await mount({ count: 1 })
    const field = element.querySelector("[data-image-field]")
    upload(field)
    await click(field.querySelector("[data-image-clear]"))
    upload(field)
    old.reject(new DOMException("Aborted", "AbortError"))
    await tick()
    expect(field.getAttribute("aria-busy")).toBe("true")
    expect(field.querySelector("[data-image-status]").textContent).toBe("Uploading...")
    next.resolve({ ok: true, json: async () => ({ url: "/12345678/site/media/current" }) })
    await tick()
    expect(field.querySelector("[data-prop]").value).toBe("/12345678/site/media/current")
    expect(field.getAttribute("aria-busy")).toBe("false")
  })

  it.each(["rejected", "non-OK", "invalid JSON"])("reconnecting preserves the current upload when an old upload completes with %s", async (outcome) => {
    const older = pendingResponse(), latest = pendingResponse()
    const fetchMock = vi.fn().mockReturnValueOnce(outcome === "invalid JSON"
      ? Promise.resolve({ ok: true, json: () => older.promise })
      : older.promise).mockReturnValueOnce(latest.promise)
    vi.stubGlobal("fetch", fetchMock)
    ;({ application, element } = await mountController("website-builder", Controller, `<div>${contentEditor({ count: 1 })}</div>`))
    ctrl = controllerFor(application, element, "website-builder")
    const field = element.querySelector("[data-image-field]")
    const input = field.querySelector("[data-prop]")
    upload(field)
    await tick()
    const signal = fetchMock.mock.calls[0][1].signal
    await reconnectController(application, element)
    expect(signal.aborted).toBe(true)
    upload(field)
    const currentJson = element.querySelector("[data-website-builder-target='json']").value
    if (outcome === "non-OK") older.resolve({ ok: false, json: async () => ({ error: "Old upload rejected" }) })
    else older.reject(outcome === "invalid JSON" ? new SyntaxError("Invalid JSON") : new Error("Old upload failed"))
    await tick()
    expect(input.value).toBe("https://cdn.example/old.png")
    expect(element.querySelector("[data-website-builder-target='json']").value).toBe(currentJson)
    expect(field.getAttribute("aria-busy")).toBe("true")
    expect(field.querySelector("[type='file']").disabled).toBe(true)
    expect(field.querySelector("[data-image-status]").textContent).toBe("Uploading...")
    latest.resolve({ ok: true, json: async () => ({ url: "/12345678/site/media/reconnected" }) })
    await tick()
    expect(input.value).toBe("/12345678/site/media/reconnected")
    expect(field.getAttribute("aria-busy")).toBe("false")
    expect(field.querySelector("[type='file']").disabled).toBe(false)
    expect(field.querySelector("[data-image-status]").textContent).toBe("")
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it("tolerates missing optional picker/media hooks and unbounded collections", async () => {
    await mount()
    const before = jsonValue(element)
    ctrl.toggleHrefPicker({ currentTarget: element })
    ctrl.closeHrefPicker({ currentTarget: element })
    ctrl.imageLoaded({ currentTarget: element })
    const field = element.querySelector("[data-href-field]")
    field.querySelector("[data-href-picker]").remove()
    ctrl.toggleHrefPicker({ currentTarget: field.querySelector("[data-href-toggle]") })
    expect(field.querySelector("[data-href-toggle]").getAttribute("aria-expanded")).toBe("false")
    element.querySelector("[data-array]").removeAttribute("data-max")
    ctrl.markDirty()
    expect(element.querySelector("[data-array-limit]").textContent).toBe("")
    expect(element.querySelector("[data-add-item]").disabled).toBe(false)
    expect(jsonValue(element)).toEqual(before)
  })
})

describe("website-builder media acceptance", () => {
  let application, element, ctrl
  const artwork = "/site-images/anysys/anysys-home-workspace-hero.svg"
  const mount = async (value = artwork) => {
    ;({ application, element } = await mountController("website-builder", Controller, html({
      rows: 1,
      rowExtras: () => mediaControl("scalar_image", value),
      array: true,
      arrayItems: `<div data-array-item><img data-item-image alt="">${mediaControl("item_image", value)}</div>`
    })))
    ctrl = controllerFor(application, element, "website-builder")
  }
  const fields = () => [...element.querySelectorAll("[data-image-field]")]
  const images = () => [...element.querySelectorAll("[data-image-preview], [data-item-image]")]
  const expectPreview = (src) => {
    for (const image of images()) {
      expect(image.getAttribute("src")).toBe(src)
      expect(image.classList.contains("hidden")).toBe(src === null)
    }
  }
  const expectStored = (value) => {
    const sections = jsonValue(element)
    expect(sections[0].props.image_url).toBe(value)
    expect(sections[1].props.items[0].image_url).toBe(value)
  }
  afterEach(() => {
    ctrl?.disconnect()
    application?.stop()
    vi.restoreAllMocks()
  })

  it.each([
    artwork,
    "/site-images/anysys/anysys-ai-draft.svg",
    "/site-images/anysys/anysys-art-123.svg",
    "/site-images/anysys/anysys-photo-craft.webp",
    "/site-images/anysys/anysys-photo-desktop-night.webp",
    " \t\nhttps://cdn.example/photo.png\r\n ",
    " \t\n/12345678/site/media/abc--id\r\n "
  ])("shows scalar previews and item thumbnails for %j on mount and after editing", async (value) => {
    // HTML text inputs strip CR/LF; keep raw whitespace in a textarea for parity checks.
    const markupValue = value.trim()
    await mount(markupValue)
    expectPreview(markupValue)
    expectStored(markupValue)
    for (const field of fields()) {
      const input = field.querySelector("[data-prop]")
      const textarea = document.createElement("textarea")
      textarea.dataset.prop = "image_url"
      input.replaceWith(textarea)
      textarea.value = "invalid"
      ctrl.previewImage({ currentTarget: textarea })
      textarea.value = value
      ctrl.previewImage({ currentTarget: textarea })
    }
    ctrl.markDirty()
    expectPreview(value.trim())
    expectStored(value)
  })

  it.each([
    "/site-images/anysys/../anysys-home-workspace-hero.svg",
    "/site-images/anysys/anysys-../anysys-home-workspace-hero.svg",
    "/site-images/anysys/%2e%2e/anysys-home-workspace-hero.svg",
    "/site-images/anysys/anysys-%2e%2e.svg",
    `${artwork}?download=1`, `${artwork}#preview`, `${artwork}/extra`,
    "/site-images/anysys/nested/anysys-home-workspace-hero.svg",
    "/site-images/anysys/anysys-nested/art.svg",
    "/site-images/anysys//anysys-home-workspace-hero.svg",
    "/site-images/anysys/anysys-home\\workspace-hero.svg",
    "/site-images\\anysys/anysys-home-workspace-hero.svg",
    "//site-images/anysys/anysys-home-workspace-hero.svg",
    "/other/anysys-home-workspace-hero.svg",
    "/site-images/other/anysys-home-workspace-hero.svg",
    "/site-images/anysys/home-workspace-hero.svg",
    "/site-images/anysys/anysys-.svg",
    "/site-images/anysys/anysys-Home.svg",
    "/site-images/anysys/anysys-home_workspace.svg",
    "/site-images/anysys/anysys-home.png",
    "/site-images/anysys/anysys-home.SVG",
    "/site-images/anysys/anysys-craft.webp",
    "/site-images/anysys/anysys-photo-.webp",
    "/site-images/anysys/anysys-photo-Craft.webp",
    "/site-images/anysys/anysys-photo-craft.WEBP",
    "/site-images/anysys/anysys-photo-craft.webp?w=1",
    "/site-images/anysys/anysys-photo-../craft.webp",
    " /site-images/anysys/anysys-photo-craft.webp",
    ` ${artwork}`, `${artwork} `, `\u00a0${artwork}`, `${artwork}\u2028`,
    "/auth/sign_up", "/12345678/site/about", "http://cdn.example/photo.png", "data:image/svg+xml,hi"
  ])("hides scalar previews and item thumbnails for rejected media %j", async (value) => {
    await mount()
    expectPreview(artwork)
    for (const field of fields()) changeValue(field.querySelector("[data-prop]"), value)
    expectPreview(null)
    expectStored(value)
  })

  it("rejects raw controls anywhere in bundled paths before trim or URL normalization", async () => {
    await mount()
    const controls = [...Array.from({ length: 32 }, (_, i) => i), ...Array.from({ length: 33 }, (_, i) => 127 + i)]
    for (const field of fields()) {
      const textarea = document.createElement("textarea")
      textarea.dataset.prop = "image_url"
      field.querySelector("[data-prop]").replaceWith(textarea)
    }
    for (const code of controls) {
      const control = String.fromCharCode(code)
      for (const value of [`${control}${artwork}`, `${artwork}${control}`, `/site-images/anysys/anysys-${control}hero.svg`]) {
        for (const field of fields()) {
          const input = field.querySelector("[data-prop]")
          input.value = value
          ctrl.previewImage({ currentTarget: input })
        }
        ctrl.markDirty()
        expectPreview(null)
        expectStored(value)
      }
    }
  })
})

describe("website-builder controller", () => {
  let application, element

  beforeEach(() => {
    Sortable.create.mockClear()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("initializes SortableJS on the list with animation 150 and ghostClass opacity-40", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html()))
    expect(Sortable.create).toHaveBeenCalledOnce()
    const [list, options] = Sortable.create.mock.calls[0]
    expect(list).toBe(element.querySelector("[data-website-builder-target='list']"))
    expect(options.animation).toBe(150)
    expect(options.ghostClass).toBe("opacity-40")
    expect(options.handle).toBe("[data-website-builder-target='handle']")
    expect(jsonValue(element)).toHaveLength(3)
  })

  it("skips Sortable when the list target is missing", async () => {
    ;({ element } = await mountController("website-builder", Controller, html({ list: false, rows: 0 })))
    expect(Sortable.create).not.toHaveBeenCalled()
  })

  it("disables Up on the first row and Down on the last", async () => {
    ;({ element } = await mountController("website-builder", Controller, html()))
    expect(upBtn(element, 0).disabled).toBe(true)
    expect(downBtn(element, 2).disabled).toBe(true)
    expect(upBtn(element, 1).disabled).toBe(false)
  })

  it("moveDown on the first row swaps it below its neighbour", async () => {
    ;({ element } = await mountController("website-builder", Controller, html()))
    click(downBtn(element, 0))
    expect(order(element)).toEqual(["1", "0", "2"])
    expect(jsonValue(element).map((s) => s.id)).toEqual(["sec_1", "sec_0", "sec_2"])
    expect(element.querySelector("[data-website-builder-target='unsaved']").classList.contains("hidden")).toBe(false)
  })

  it("moveUp on the last row swaps it above its neighbour", async () => {
    ;({ element } = await mountController("website-builder", Controller, html()))
    click(upBtn(element, 2))
    expect(order(element)).toEqual(["0", "2", "1"])
  })

  it("moveUp on the first row is a no-op", async () => {
    ;({ element } = await mountController("website-builder", Controller, html()))
    click(upBtn(element, 0))
    expect(order(element)).toEqual(["0", "1", "2"])
  })

  it("moveDown on the last row is a no-op", async () => {
    ;({ element } = await mountController("website-builder", Controller, html()))
    click(downBtn(element, 2))
    expect(order(element)).toEqual(["0", "1", "2"])
  })

  it("moveUp/moveDown without a row ancestor are no-ops", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({ extra: `<button data-orphan-up data-action="click->website-builder#moveUp">up</button><button data-orphan-down data-action="click->website-builder#moveDown">down</button>` })
    ))
    click(element.querySelector("[data-orphan-up]"))
    click(element.querySelector("[data-orphan-down]"))
    expect(order(element)).toEqual(["0", "1", "2"])
  })

  it("onEnd after a drag refreshes order into the json field", async () => {
    ;({ element } = await mountController("website-builder", Controller, html()))
    const options = Sortable.create.mock.calls[0][1]
    const list = element.querySelector("[data-website-builder-target='list']")
    list.insertBefore(list.querySelector("[data-row='1']"), list.querySelector("[data-row='0']"))
    options.onEnd()
    expect(order(element)).toEqual(["1", "0", "2"])
    expect(jsonValue(element).map((s) => s.id)).toEqual(["sec_1", "sec_0", "sec_2"])
  })

  it("destroys the sortable instance on disconnect", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html()))
    const instance = Sortable.create.mock.results[0].value
    element.remove()
    await new Promise((r) => setTimeout(r, 0))
    expect(instance.destroy).toHaveBeenCalled()
    application.stop()
  })

  it("disconnect without a sortable is a no-op", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html({ list: false, rows: 0 })))
    element.remove()
    await new Promise((r) => setTimeout(r, 0))
    application.stop()
  })

  it("toggleKit shows and hides the picker and sets aria-expanded", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html()))
    const btn = element.querySelector("[data-kit-toggle]")
    const kit = element.querySelector("[data-website-builder-target='kit']")
    click(btn)
    expect(kit.classList.contains("hidden")).toBe(false)
    expect(btn.getAttribute("aria-expanded")).toBe("true")
    click(btn)
    expect(kit.classList.contains("hidden")).toBe(true)
    expect(btn.getAttribute("aria-expanded")).toBe("false")
  })

  it("toggleKit without a kit target or event is a no-op", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html({ kit: false })))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.toggleKit()
    ctrl.toggleKit({})
    ctrl.toggleKit({ currentTarget: {} })
  })

  it("addSection clones the matching template, prefixes a UUID, and closes the kit", async () => {
    vi.spyOn(crypto, "randomUUID").mockReturnValue("uuid-1")
    ;({ element } = await mountController("website-builder", Controller, html({ rows: 0 })))
    click(element.querySelector("[data-kit-toggle]"))
    click(element.querySelector("[data-type='quote']"))
    const added = element.querySelector("[data-website-builder-target='list'] [data-website-builder-target='row']")
    expect(added.dataset.sectionId).toBe("sec_uuid-1")
    expect(added.querySelector("details").open).toBe(true)
    expect(added.querySelector("input").id).toBe("section_sec_uuid-1_quote")
    expect(added.querySelector("input").getAttribute("name")).toBe("section_sec_uuid-1_quote")
    expect(added.querySelector("template").content.querySelector("input").id).toBe("section_sec_uuid-1_item")
    expect(added.querySelector("template").content.querySelector("input").getAttribute("name")).toBe("section_sec_uuid-1_item")
    expect(element.querySelector("[data-website-builder-target='kit']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-kit-toggle]").getAttribute("aria-expanded")).toBe("false")
    expect(element.querySelector("[data-website-builder-target='empty']").classList.contains("hidden")).toBe(true)
    expect(jsonValue(element)[0]).toEqual({ id: "sec_uuid-1", type: "quote", props: { quote: "" } })
  })

  it("addSection falls back to sec_${Date.now()}_${n} when randomUUID is missing", async () => {
    const original = crypto.randomUUID
    crypto.randomUUID = undefined
    vi.spyOn(Date, "now").mockReturnValue(12345)
    ;({ element } = await mountController("website-builder", Controller, html({ rows: 0 })))
    click(element.querySelector("[data-type='quote']"))
    const added = element.querySelector("[data-website-builder-target='list'] [data-website-builder-target='row']")
    expect(added.dataset.sectionId).toBe("sec_12345_1")
    click(element.querySelector("[data-type='plain']"))
    const plain = element.querySelectorAll("[data-website-builder-target='list'] [data-website-builder-target='row']")[1]
    expect(plain.dataset.sectionId).toBe("sec_12345_2")
    expect(plain.querySelector("details")).toBeNull()
    crypto.randomUUID = original
  })

  it("addSection no-ops without type, list, or a usable template", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html({ rows: 0 })))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.addSection({ currentTarget: { dataset: {} } })
    click(element.querySelector("[data-type='missing']"))
    click(element.querySelector("[data-type='empty']") || element.querySelector("[data-type='missing']"))
    const emptyTplBtn = document.createElement("button")
    emptyTplBtn.dataset.type = "empty"
    element.appendChild(emptyTplBtn)
    ctrl.addSection({ currentTarget: emptyTplBtn })
    expect(element.querySelectorAll("[data-website-builder-target='list'] [data-website-builder-target='row']")).toHaveLength(0)

    const noList = await mountController("website-builder", Controller, html({ list: false, rows: 0 }))
    const ctrl2 = controllerFor(noList.application, noList.element, "website-builder")
    ctrl2.addSection({ currentTarget: { dataset: { type: "quote" } } })
  })

  it("removeSection confirms then removes the row and shows empty when the list is drained", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    ;({ element } = await mountController("website-builder", Controller, html({ rows: 1 })))
    click(delBtn(element, 0))
    expect(element.querySelectorAll("[data-website-builder-target='list'] [data-website-builder-target='row']")).toHaveLength(0)
    expect(element.querySelector("[data-website-builder-target='empty']").classList.contains("hidden")).toBe(false)
    expect(jsonValue(element)).toEqual([])
  })

  it("removeSection keeps the row when confirm is cancelled", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(false)
    ;({ element } = await mountController("website-builder", Controller, html({ rows: 1 })))
    click(delBtn(element, 0))
    expect(order(element)).toEqual(["0"])
  })

  it("removeSection without a row ancestor is a no-op", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({ extra: `<button data-orphan-del data-action="click->website-builder#removeSection">del</button>` })
    ))
    click(element.querySelector("[data-orphan-del]"))
    expect(order(element)).toEqual(["0", "1", "2"])
  })

  it("markDirty reveals unsaved copy and is a no-op without that target", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html()))
    click(element.querySelector("[data-prop='quote']"))
    controllerFor(application, element, "website-builder").markDirty()
    expect(element.querySelector("[data-website-builder-target='unsaved']").classList.contains("hidden")).toBe(false)

    const other = await mountController("website-builder", Controller, html({ unsaved: false, json: false }))
    controllerFor(other.application, other.element, "website-builder").markDirty()
  })

  it("reloadPreview skips a failed Turbo save and reloads the iframe after success", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html({ frame: true, loading: true })))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.markDirty()
    const frame = element.querySelector("iframe")
    element.dispatchEvent(new CustomEvent("turbo:submit-end", { bubbles: true, detail: { success: false } }))
    expect(element.querySelector("[data-website-builder-target='unsaved']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-website-builder-target='previewLoading']").classList.contains("hidden")).toBe(true)

    element.dispatchEvent(new CustomEvent("turbo:submit-end", { bubbles: true, detail: { success: true } }))
    expect(element.querySelector("[data-website-builder-target='unsaved']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-website-builder-target='previewLoading']").classList.contains("hidden")).toBe(false)
    expect(frame.src).toContain("about:blank")

    ctrl.reloadPreview()
    ctrl.reloadPreview({ type: "click" })
    ctrl.reloadPreview({ type: "turbo:submit-end" })
  })

  it("reloadPreview no-ops without a frame, src, or loading overlay", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({ unsaved: false })
    ))
    controllerFor(application, element, "website-builder").reloadPreview()

    const withBlank = await mountController(
      "website-builder",
      Controller,
      html({ frame: true })
    )
    const frame = withBlank.element.querySelector("iframe")
    vi.spyOn(frame, "getAttribute").mockReturnValue("")
    Object.defineProperty(frame, "src", { configurable: true, get: () => "", set: vi.fn() })
    controllerFor(withBlank.application, withBlank.element, "website-builder").reloadPreview()
  })

  it("previewLoaded hides the overlay", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html({ frame: true, loading: true })))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.reloadPreview()
    ctrl.previewLoaded()
    expect(element.querySelector("[data-website-builder-target='previewLoading']").classList.contains("hidden")).toBe(true)

    const other = await mountController("website-builder", Controller, html({ frame: true }))
    controllerFor(other.application, other.element, "website-builder").previewLoaded()
  })

  it("serializes nested array props and ignores nameless array bags", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        array: true,
        extra: `<article data-website-builder-target="row" data-section-id="bare" data-section-type="quote"><div data-array><input data-prop="ignored" value="x"></div></article>`
      })
    ))
    const payload = jsonValue(element)
    const proof = payload.find((s) => s.type === "proof_strip")
    expect(proof.props.items).toEqual([{ label: "a", value: "1" }])
    const bare = payload.find((s) => s.id === "bare")
    expect(bare.props.ignored).toBeUndefined()
    expect(bare.props).toEqual({})
  })

  it("removeItem is a no-op at min and deletes when above min", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<div data-array="items" data-min="2">` +
          `<div data-array-item id="item-a"><button data-remove-item data-action="click->website-builder#removeItem">rm</button></div>` +
          `<div data-array-item id="item-b"><button data-remove-item data-action="click->website-builder#removeItem">rm</button></div>` +
          `</div>`
      })
    ))
    click(element.querySelector("#item-a [data-remove-item]"))
    expect(element.querySelectorAll("[data-array-item]")).toHaveLength(2)
    element.querySelector("[data-array]").dataset.min = "0"
    click(element.querySelector("#item-a [data-remove-item]"))
    expect(element.querySelector("#item-a")).toBeNull()
    expect(element.querySelectorAll("[data-array-item]")).toHaveLength(1)
  })

  it("addItem clones a card until max and removeItem stops at min", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({ rows: 0, array: true, min: 1, max: 2 })
    ))
    const add = element.querySelector("[data-add-item]")
    const list = element.querySelector("[data-array]")
    click(add)
    expect(list.querySelectorAll("[data-array-item]")).toHaveLength(2)
    expect(add.disabled).toBe(true)
    click(add)
    expect(list.querySelectorAll("[data-array-item]")).toHaveLength(2)

    click(list.querySelector("[data-remove-item]"))
    expect(list.querySelectorAll("[data-array-item]")).toHaveLength(1)
    expect(list.querySelector("[data-remove-item]").disabled).toBe(true)
    click(list.querySelector("[data-remove-item]"))
    expect(list.querySelectorAll("[data-array-item]")).toHaveLength(1)
  })

  it("addItem/removeItem no-op without a list, template, or item", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<button data-orphan-add data-action="click->website-builder#addItem">add</button>` +
          `<button data-orphan-rm data-action="click->website-builder#removeItem">rm</button>` +
          `<div data-array="items"><div data-array-list></div><button data-add-item data-action="click->website-builder#addItem">add</button><button data-inner-rm data-action="click->website-builder#removeItem">rm</button></div>`
      })
    ))
    click(element.querySelector("[data-orphan-add]"))
    click(element.querySelector("[data-orphan-rm]"))
    click(element.querySelector("[data-add-item]"))
    click(element.querySelector("[data-inner-rm]"))
  })

  it("refresh helpers tolerate rows without move buttons and arrays without add", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra: `<article data-website-builder-target="row" data-section-id="x" data-section-type="quote"></article>` +
          `<div data-array="items"><div data-array-item></div></div>`
      })
    ))
    expect(jsonValue(element).some((s) => s.id === "x")).toBe(true)
  })

  it("confirmSetHome prompts only when checking and reverts a cancelled check", async () => {
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(false)
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({ extra: `<input type="checkbox" data-home data-action="change->website-builder#confirmSetHome">` })
    ))
    const box = element.querySelector("[data-home]")
    box.checked = true
    box.dispatchEvent(new Event("change", { bubbles: true }))
    expect(confirm).toHaveBeenCalled()
    expect(box.checked).toBe(false)

    confirm.mockReturnValue(true)
    box.checked = true
    box.dispatchEvent(new Event("change", { bubbles: true }))
    expect(box.checked).toBe(true)

    box.checked = false
    box.dispatchEvent(new Event("change", { bubbles: true }))
    expect(confirm).toHaveBeenCalledTimes(2)
  })

  it("uses fallback min/max when data-min/max are missing", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="p" data-section-type="proof_strip">` +
          `<div data-array="items"><div data-array-list><div data-array-item><input data-prop="label" value="z"></div></div>` +
          `<template data-item-template><div data-array-item><input data-prop="label" value=""></div></template>` +
          `<button data-add-item data-action="click->website-builder#addItem">add</button></div></article>`
      })
    ))
    click(element.querySelector("[data-add-item]"))
    expect(element.querySelectorAll("[data-array-item]")).toHaveLength(2)
  })

  it("syncEmpty and closeKit tolerate missing empty / kit-toggle nodes", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({ empty: false, kitToggle: false, rows: 0 })
    ))
    click(element.querySelector("[data-type='quote']"))
  })

  it("moveUp without a list target and moveDown on an unregistered row are no-ops", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        list: false,
        rows: 0,
        extra: `${row(0)}<button data-action="click->website-builder#moveUp">up</button>`
      })
    ))
    const ctrl = controllerFor(application, element, "website-builder")
    click(element.querySelector("[data-row='0'] [data-action*='moveUp']"))

    const fake = document.createElement("article")
    fake.setAttribute("data-website-builder-target", "row")
    const btn = document.createElement("button")
    fake.appendChild(btn)
    document.body.appendChild(fake)
    ctrl.moveDown({ currentTarget: btn })
    fake.remove()
  })

  it("serializes blank ids/types and appends array items onto the bag when no list mount exists", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row"><input data-prop="quote" value="hi"></article>` +
          `<div data-array="items" data-max="4">` +
          `<template data-item-template><div data-array-item><input data-prop="label" value="n"></div></template>` +
          `<button data-add-item data-action="click->website-builder#addItem">add</button></div>`
      })
    ))
    expect(jsonValue(element)[0]).toEqual({ id: "", type: "", props: { quote: "hi" } })
    click(element.querySelector("[data-add-item]"))
    expect(element.querySelectorAll("[data-array-item]")).toHaveLength(1)
  })

  it("skips Sortable and structure mutations when the layout is locked", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({ structureLocked: true })
    ))
    expect(Sortable.create).not.toHaveBeenCalled()
    click(element.querySelector("[data-type='quote']"))
    click(downBtn(element, 0))
    click(upBtn(element, 2))
    click(delBtn(element, 0))
    expect(order(element)).toEqual(["0", "1", "2"])
    expect(window.confirm).not.toHaveBeenCalled()
  })

  it("applyHref writes a site slug and ignores custom/empty/orphan controls", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="h" data-section-type="cta_band">` +
          `<div data-href-field>` +
          `<input data-prop="button_href" value="">` +
          `<select data-action="change->website-builder#applyHref">` +
          `<option value="">Custom link</option>` +
          `<option value="about">About</option>` +
          `</select>` +
          `<p data-href-status class="hidden">bad</p>` +
          `</div></article>` +
          `<div data-href-field><select data-empty-href data-action="change->website-builder#applyHref"><option value="about">About</option></select></div>` +
          `<select data-orphan-href data-action="change->website-builder#applyHref"><option value="about">About</option></select>`
      })
    ))
    const select = element.querySelector("[data-href-field] select")
    select.value = "about"
    select.dispatchEvent(new Event("change", { bubbles: true }))
    expect(element.querySelector("[data-prop='button_href']").value).toBe("about")
    expect(element.querySelector("[data-href-status]").classList.contains("hidden")).toBe(true)

    select.value = ""
    select.dispatchEvent(new Event("change", { bubbles: true }))
    expect(element.querySelector("[data-prop='button_href']").value).toBe("about")

    element.querySelector("[data-empty-href]").value = "about"
    element.querySelector("[data-empty-href]").dispatchEvent(new Event("change", { bubbles: true }))
    element.querySelector("[data-orphan-href]").value = "about"
    element.querySelector("[data-orphan-href]").dispatchEvent(new Event("change", { bubbles: true }))
  })

  it("checkHref flags unsafe values and syncs the page picker", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="h" data-section-type="cta_band">` +
          `<div data-href-field>` +
          `<input data-prop="button_href" value="about" data-action="input->website-builder#checkHref">` +
          `<select data-action="change->website-builder#applyHref">` +
          `<option value="">Custom link</option>` +
          `<option value="about">About</option>` +
          `</select>` +
          `<p data-href-status class="hidden">bad</p>` +
          `</div></article>` +
          `<input data-orphan-check data-action="input->website-builder#checkHref">`
      })
    ))
    const input = element.querySelector("[data-prop='button_href']")
    const status = element.querySelector("[data-href-status]")
    const picker = element.querySelector("select")
    const ctrl = controllerFor(application, element, "website-builder")

    input.value = "javascript:alert(1)"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(status.classList.contains("hidden")).toBe(false)
    expect(input.getAttribute("aria-invalid")).toBe("true")
    expect(picker.value).toBe("")

    input.value = "http://example.com"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(status.classList.contains("hidden")).toBe(false)

    input.value = "data:text/html,x"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(status.classList.contains("hidden")).toBe(false)

    input.value = "https://example.com"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(status.classList.contains("hidden")).toBe(true)
    expect(picker.value).toBe("")

    input.value = "about"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(status.classList.contains("hidden")).toBe(true)
    expect(picker.value).toBe("about")

    input.value = ""
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(status.classList.contains("hidden")).toBe(true)

    input.value = "Not A Slug"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(status.classList.contains("hidden")).toBe(false)

    input.value = "https://"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(status.classList.contains("hidden")).toBe(false)

    input.value = "https://["
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(status.classList.contains("hidden")).toBe(false)

    const bare = document.createElement("div")
    bare.setAttribute("data-href-field", "")
    const bareInput = document.createElement("input")
    bare.appendChild(bareInput)
    document.body.appendChild(bare)
    ctrl.checkHref({ currentTarget: bareInput })
    bare.remove()

    element.querySelector("[data-orphan-check]").dispatchEvent(new Event("input", { bubbles: true }))
  })

  it("previews https images, hides invalid ones, and clears on error or clear", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="m" data-section-type="split_image_text">` +
          `<div data-image-field>` +
          `<input data-prop="image_url" value="" data-action="input->website-builder#previewImage">` +
          `<img data-image-preview class="hidden" data-action="error->website-builder#imageError">` +
          `<p data-image-empty>empty</p>` +
          `<span data-image-add>add</span>` +
          `<span data-image-replace class="hidden">replace</span>` +
          `<p data-image-status class="hidden"></p>` +
          `<button data-action="click->website-builder#clearImage">clear</button>` +
          `</div></article>` +
          `<input data-orphan-image data-action="input->website-builder#previewImage">` +
          `<img data-orphan-img data-action="error->website-builder#imageError">` +
          `<button data-orphan-clear data-action="click->website-builder#clearImage">clear</button>`
      })
    ))
    const input = element.querySelector("[data-prop='image_url']")
    const img = element.querySelector("[data-image-preview]")
    const empty = element.querySelector("[data-image-empty]")

    input.value = "https://cdn.example/a.jpg"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(img.getAttribute("src")).toBe("https://cdn.example/a.jpg")
    expect(img.classList.contains("hidden")).toBe(false)
    expect(empty.classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-image-add]").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-image-replace]").classList.contains("hidden")).toBe(false)

    input.value = "/12345678/site/media/abc--id"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(img.getAttribute("src")).toBe("/12345678/site/media/abc--id")
    expect(img.classList.contains("hidden")).toBe(false)

    input.value = "/12345678/site/about"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(img.classList.contains("hidden")).toBe(true)

    input.value = "not-https"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(img.hasAttribute("src")).toBe(false)
    expect(img.classList.contains("hidden")).toBe(true)
    expect(empty.classList.contains("hidden")).toBe(false)

    input.value = "http://cdn.example/a.jpg"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(img.classList.contains("hidden")).toBe(true)

    input.value = "javascript:x"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.value = "data:image/gif,x"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.value = ""
    input.dispatchEvent(new Event("input", { bubbles: true }))

    input.value = "https://cdn.example/a.jpg"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    img.dispatchEvent(new Event("error", { bubbles: true }))
    expect(img.classList.contains("hidden")).toBe(true)
    expect(empty.classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-image-add]").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-image-replace]").classList.contains("hidden")).toBe(true)

    input.value = "https://cdn.example/b.jpg"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    click(element.querySelector("[data-action='click->website-builder#clearImage']"))
    expect(input.value).toBe("")
    expect(img.classList.contains("hidden")).toBe(true)

    element.querySelector("[data-orphan-image]").dispatchEvent(new Event("input", { bubbles: true }))
    element.querySelector("[data-orphan-img]").dispatchEvent(new Event("error", { bubbles: true }))
    click(element.querySelector("[data-orphan-clear]"))

    const emptyField = document.createElement("div")
    emptyField.setAttribute("data-image-field", "")
    document.body.appendChild(emptyField)
    controllerFor(application, element, "website-builder").clearImage({ currentTarget: emptyField })
    emptyField.remove()
  })

  it("counts characters on copy fields", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        charCountFormat: "{count} characters",
        extra:
          `<article data-website-builder-target="row" data-section-id="c" data-section-type="rich_text">` +
          `<div data-count-field>` +
          `<input data-prop="heading" value="Hi" data-action="input->website-builder#countChars">` +
          `<p data-char-count></p>` +
          `</div>` +
          `<div data-count-field><input data-lonely-count data-action="input->website-builder#countChars"></div>` +
          `</article>` +
          `<input data-orphan-count data-action="input->website-builder#countChars">`
      })
    ))
    const heading = element.querySelector("[data-prop='heading']")
    heading.value = "Hello"
    heading.dispatchEvent(new Event("input", { bubbles: true }))
    expect(element.querySelector("[data-char-count]").textContent).toBe("5 characters")

    element.querySelector("[data-lonely-count]").dispatchEvent(new Event("input", { bubbles: true }))
    element.querySelector("[data-orphan-count]").dispatchEvent(new Event("input", { bubbles: true }))
  })

  it("serializes only the checked radio and skips unchecked siblings", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="tone" data-section-type="hero_cinematic">` +
          `<input type="radio" data-prop="tone" name="tone" value="light">` +
          `<input type="radio" data-prop="tone" name="tone" value="dark" checked>` +
          `<div data-array="items" data-min="0">` +
          `<div data-array-item>` +
          `<input type="radio" data-prop="span" name="span-a" value="hero">` +
          `<input type="radio" data-prop="span" name="span-a" value="unit" checked>` +
          `</div></div></article>`
      })
    ))
    expect(jsonValue(element)[0].props).toEqual({ tone: "dark", items: [{ span: "unit" }] })
  })

  it("duplicates and reorders array items until max", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="p" data-section-type="proof_strip">` +
          `<div data-array="items" data-min="1" data-max="3">` +
          `<div data-array-list>` +
          `<div data-array-item data-item="a"><input data-prop="label" value="a"><button data-action="click->website-builder#moveItemUp">up</button><button data-action="click->website-builder#moveItemDown">down</button><button data-action="click->website-builder#duplicateItem">dup</button></div>` +
          `<div data-array-item data-item="b"><input data-prop="label" value="b"><button data-action="click->website-builder#moveItemUp">up</button><button data-action="click->website-builder#moveItemDown">down</button><button data-action="click->website-builder#duplicateItem">dup</button></div>` +
          `</div></div></article>` +
          `<button data-orphan-dup data-action="click->website-builder#duplicateItem">dup</button>` +
          `<button data-orphan-item-up data-action="click->website-builder#moveItemUp">up</button>` +
          `<button data-orphan-item-down data-action="click->website-builder#moveItemDown">down</button>`
      })
    ))
    const list = element.querySelector("[data-array]")
    expect(list.querySelector("[data-item='a'] [data-action*='moveItemUp']").disabled).toBe(true)
    expect(list.querySelector("[data-item='b'] [data-action*='moveItemDown']").disabled).toBe(true)

    click(list.querySelector("[data-item='b'] [data-action*='moveItemUp']"))
    expect([...list.querySelectorAll("[data-array-item]")].map((n) => n.dataset.item)).toEqual(["b", "a"])

    click(list.querySelector("[data-item='b'] [data-action*='moveItemDown']"))
    expect([...list.querySelectorAll("[data-array-item]")].map((n) => n.dataset.item)).toEqual(["a", "b"])

    click(list.querySelector("[data-item='a'] [data-action*='moveItemUp']"))
    click(list.querySelector("[data-item='b'] [data-action*='moveItemDown']"))
    expect([...list.querySelectorAll("[data-array-item]")].map((n) => n.dataset.item)).toEqual(["a", "b"])

    click(list.querySelector("[data-item='a'] [data-action*='duplicateItem']"))
    expect(list.querySelectorAll("[data-array-item]")).toHaveLength(3)
    click(list.querySelector("[data-item='a'] [data-action*='duplicateItem']"))
    expect(list.querySelectorAll("[data-array-item]")).toHaveLength(3)

    click(element.querySelector("[data-orphan-dup]"))
    click(element.querySelector("[data-orphan-item-up]"))
    click(element.querySelector("[data-orphan-item-down]"))
  })

  it("resets a section to layout defaults including list items", async () => {
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(false)
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="q" data-section-type="quote" data-section-defaults='{"quote":"Starter","attribution":"Ada"}'>` +
          `<input data-prop="quote" value="Edited"><input data-prop="attribution" value="Bob">` +
          `<button data-reset data-action="click->website-builder#resetSection">reset</button>` +
          `</article>` +
          `<article data-website-builder-target="row" data-section-id="faq" data-section-type="faq" data-section-defaults='{"heading":"FAQ","items":[{"question":"Q","answer":"A"},"skip"]}'>` +
          `<input data-prop="heading" value="Nope">` +
          `<div data-array="items" data-min="1">` +
          `<div data-array-list><div data-array-item><input data-prop="question" value="old"><input data-prop="answer" value="old"></div></div>` +
          `<template data-item-template><div data-array-item><input data-prop="question" value=""><input data-prop="answer" value=""></div></template>` +
          `</div>` +
          `<button data-reset-faq data-action="click->website-builder#resetSection">reset</button>` +
          `</article>` +
          `<article data-website-builder-target="row" data-section-id="bad" data-section-type="quote" data-section-defaults="{nope">` +
          `<input data-prop="quote" value="keep">` +
          `<button data-reset-bad data-action="click->website-builder#resetSection">reset</button>` +
          `</article>` +
          `<article data-website-builder-target="row" data-section-id="arr" data-section-type="quote" data-section-defaults="[]">` +
          `<input data-prop="quote" value="stay">` +
          `<button data-reset-arr data-action="click->website-builder#resetSection">reset</button>` +
          `</article>` +
          `<article data-website-builder-target="row" data-section-id="bare-arr" data-section-type="faq" data-section-defaults='{"items":[]}'>` +
          `<div data-array="items" data-min="2"><div data-array-list></div></div>` +
          `<button data-reset-bare data-action="click->website-builder#resetSection">reset</button>` +
          `</article>` +
          `<article data-website-builder-target="row" data-section-id="pad" data-section-type="faq" data-section-defaults='{"items":[]}'>` +
          `<div data-array="items" data-min="2"><div data-array-list></div>` +
          `<template data-item-template><div data-array-item><input data-prop="label" value="x"></div></template></div>` +
          `<button data-reset-pad data-action="click->website-builder#resetSection">reset</button>` +
          `</article>` +
          `<article data-website-builder-target="row" data-section-id="nul" data-section-type="quote" data-section-defaults="null">` +
          `<input data-prop="quote" value="stay">` +
          `<button data-reset-null data-action="click->website-builder#resetSection">reset</button>` +
          `</article>` +
          `<button data-orphan-reset data-action="click->website-builder#resetSection">reset</button>`
      })
    ))
    click(element.querySelector("[data-reset]"))
    expect(element.querySelector("[data-prop='quote']").value).toBe("Edited")

    confirm.mockReturnValue(true)
    click(element.querySelector("[data-reset]"))
    expect(element.querySelector("[data-section-id='q'] [data-prop='quote']").value).toBe("Starter")
    expect(element.querySelector("[data-section-id='q'] [data-prop='attribution']").value).toBe("Ada")

    click(element.querySelector("[data-reset-faq]"))
    const faqItems = element.querySelectorAll("[data-section-id='faq'] [data-array-item]")
    expect(element.querySelector("[data-section-id='faq'] [data-prop='heading']").value).toBe("FAQ")
    expect(faqItems).toHaveLength(2)
    expect(faqItems[0].querySelector("[data-prop='question']").value).toBe("Q")

    click(element.querySelector("[data-reset-bad]"))
    expect(element.querySelector("[data-section-id='bad'] [data-prop='quote']").value).toBe("keep")

    click(element.querySelector("[data-reset-arr]"))
    expect(element.querySelector("[data-section-id='arr'] [data-prop='quote']").value).toBe("")

    click(element.querySelector("[data-reset-bare]"))
    expect(element.querySelectorAll("[data-section-id='bare-arr'] [data-array-item]")).toHaveLength(0)

    click(element.querySelector("[data-reset-pad]"))
    expect(element.querySelectorAll("[data-section-id='pad'] [data-array-item]")).toHaveLength(2)

    click(element.querySelector("[data-reset-null]"))
    expect(element.querySelector("[data-section-id='nul'] [data-prop='quote']").value).toBe("")

    click(element.querySelector("[data-orphan-reset]"))
  })

  it("toggles every section details element and swaps the button label", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 2,
        toggleAll: true,
        expandAll: "Expand all",
        collapseAll: "Collapse all",
        rowExtras: (i) => (i === 1 ? `<details class="group/section" open><summary>b</summary></details>` : `<details class="group/section"><summary>a</summary></details>`)
      })
    ))
    const btn = element.querySelector("[data-website-builder-target='toggleAll']")
    expect(btn.textContent).toBe("Expand all")
    click(btn)
    expect([...element.querySelectorAll("[data-website-builder-target='list'] details")].every((el) => el.open)).toBe(true)
    expect(btn.textContent).toBe("Collapse all")
    click(btn)
    expect([...element.querySelectorAll("[data-website-builder-target='list'] details")].every((el) => !el.open)).toBe(true)
    expect(btn.textContent).toBe("Expand all")
  })

  it("labels the toggle Collapse all when every section is already open", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 1,
        toggleAll: true,
        collapseAll: "Collapse all",
        rowExtras: () => `<details class="group/section" open><summary>a</summary></details>`
      })
    ))
    expect(element.querySelector("[data-website-builder-target='toggleAll']").textContent).toBe("Collapse all")
  })

  it("toggleAllSections no-ops without details", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({ rows: 0, list: false, extra: `<article data-website-builder-target="row" data-section-id="x" data-section-type="quote"></article>` })
    ))
    controllerFor(application, element, "website-builder").toggleAllSections()
  })

  it("refreshes href, media, count, and radios when a section is reset", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true)
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="rich" data-section-type="hero_cinematic" data-section-defaults='{"headline":"Hi","primary_href":"about","image_url":"https://cdn.example/a.jpg","tone":"dark"}'>` +
          `<div data-href-field>` +
          `<input data-prop="primary_href" value="bad href">` +
          `<select data-action="change->website-builder#applyHref"><option value="">Custom</option><option value="about">About</option></select>` +
          `<p data-href-status class="hidden">bad</p>` +
          `</div>` +
          `<div data-image-field>` +
          `<input data-prop="image_url" value="">` +
          `<img data-image-preview class="hidden">` +
          `<p data-image-empty>empty</p>` +
          `</div>` +
          `<div data-count-field>` +
          `<input data-prop="headline" value="Edited">` +
          `<p data-char-count></p>` +
          `</div>` +
          `<input type="radio" data-prop="tone" name="tone" value="light" checked>` +
          `<input type="radio" data-prop="tone" name="tone" value="dark">` +
          `<button data-reset-rich data-action="click->website-builder#resetSection">reset</button>` +
          `</article>` +
          `<article data-website-builder-target="row" data-section-id="empty-def" data-section-type="quote">` +
          `<input data-prop="quote" value="keep">` +
          `<button data-reset-empty data-action="click->website-builder#resetSection">reset</button>` +
          `</article>` +
          `<article data-website-builder-target="row" data-section-id="bad-items" data-section-type="faq" data-section-defaults='{"heading":"H","items":"nope"}'>` +
          `<input data-prop="heading" value="x">` +
          `<div data-array="items" data-min="0">` +
          `<template data-item-template><div data-array-item><input data-prop="question" value=""><input type="radio" data-prop="span" name="span-new" value="unit"></div></template>` +
          `<div data-array-item><input data-prop="question" value="old"></div>` +
          `</div>` +
          `<button data-reset-items data-action="click->website-builder#resetSection">reset</button>` +
          `</article>`
      })
    ))
    click(element.querySelector("[data-reset-rich]"))
    expect(element.querySelector("[data-section-id='rich'] [data-prop='headline']").value).toBe("Hi")
    expect(element.querySelector("[data-section-id='rich'] [data-prop='primary_href']").value).toBe("about")
    expect(element.querySelector("[data-section-id='rich'] [data-image-preview]").getAttribute("src")).toBe("https://cdn.example/a.jpg")
    expect(element.querySelector("[data-section-id='rich'] [data-char-count]").textContent).toContain("2")
    expect(element.querySelector("[data-section-id='rich'] [data-prop='tone'][value='dark']").checked).toBe(true)
    expect(element.querySelector("[data-section-id='rich'] [data-prop='tone'][value='light']").checked).toBe(false)

    click(element.querySelector("[data-reset-empty]"))
    expect(element.querySelector("[data-section-id='empty-def'] [data-prop='quote']").value).toBe("")

    click(element.querySelector("[data-reset-items]"))
    expect(element.querySelectorAll("[data-section-id='bad-items'] [data-array-item]")).toHaveLength(0)

    const ctrl = controllerFor(application, element, "website-builder")
    const countField = element.querySelector("[data-count-field]")
    ctrl.countChars({ currentTarget: { closest: () => countField, value: null } })
  })

  it("sizes the preview stage and toggles viewport buttons", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html({
      templates: false,
      extra:
        `<div data-website-builder-target="previewStage" data-viewport="desktop"></div>` +
        `<button type="button" data-website-builder-target="viewportBtn" data-viewport="desktop" aria-pressed="true">d</button>` +
        `<button type="button" data-website-builder-target="viewportBtn" data-viewport="tablet" aria-pressed="false">t</button>` +
        `<button type="button" data-website-builder-target="viewportBtn" data-viewport="mobile" aria-pressed="false">m</button>`
    })))
    const stage = element.querySelector("[data-website-builder-target='previewStage']")
    const desktop = element.querySelector("[data-website-builder-target='viewportBtn'][data-viewport='desktop']")
    const tablet = element.querySelector("[data-website-builder-target='viewportBtn'][data-viewport='tablet']")
    const mobile = element.querySelector("[data-website-builder-target='viewportBtn'][data-viewport='mobile']")
    const ctrl = controllerFor(application, element, "website-builder")
    expect(stage.style.maxWidth).toBe("100%")

    ctrl.setPreviewViewport({ currentTarget: tablet })
    expect(stage.style.maxWidth).toBe("768px")
    expect(stage.dataset.viewport).toBe("tablet")
    expect(tablet.getAttribute("aria-pressed")).toBe("true")
    expect(desktop.getAttribute("aria-pressed")).toBe("false")

    ctrl.setPreviewViewport({ currentTarget: mobile })
    expect(stage.style.maxWidth).toBe("390px")
    expect(mobile.getAttribute("aria-pressed")).toBe("true")

    ctrl.setPreviewViewport({ currentTarget: { dataset: { viewport: "nope" } } })
    expect(stage.dataset.viewport).toBe("desktop")
    expect(stage.style.maxWidth).toBe("100%")

    ctrl.setPreviewViewport({ currentTarget: null })
    expect(stage.dataset.viewport).toBe("desktop")
  })

  it("applyPreviewViewport is a no-op without a stage or buttons", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html({ list: false, rows: 0 })))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.setPreviewViewport({ currentTarget: { dataset: { viewport: "mobile" } } })
    expect(element.querySelector("[data-website-builder-target='previewStage']")).toBeNull()
  })

  it("saveShortcut submits a form on ctrl/meta+s and ignores other keys", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html()))
    const ctrl = controllerFor(application, element, "website-builder")
    const prevent = vi.fn()
    ctrl.saveShortcut({ key: "k", ctrlKey: true, preventDefault: prevent })
    ctrl.saveShortcut({ key: "s", preventDefault: prevent })
    ctrl.saveShortcut({ key: "s", ctrlKey: true, preventDefault: prevent })
    expect(prevent).not.toHaveBeenCalled()

    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      `<form data-controller="website-builder"></form>`
    ))
    const formCtrl = controllerFor(application, element, "website-builder")
    element.requestSubmit = vi.fn()
    const preventSubmit = vi.fn()
    formCtrl.saveShortcut({ key: "s", ctrlKey: true, preventDefault: preventSubmit })
    expect(preventSubmit).toHaveBeenCalled()
    expect(element.requestSubmit).toHaveBeenCalled()

    element.requestSubmit = undefined
    element.submit = vi.fn()
    formCtrl.saveShortcut({ key: "S", metaKey: true, preventDefault: vi.fn() })
    expect(element.submit).toHaveBeenCalled()
  })

  it("stamps unique ids and radio names when cloning array items", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="p" data-section-type="bento_grid">` +
          `<div data-array="cells" data-min="0" data-max="4">` +
          `<div data-array-list>` +
          `<div data-array-item>` +
          `<input id="cell_title" name="cell_title" data-prop="title" value="one">` +
          `<input type="radio" data-prop="span" name="cell_span" value="hero">` +
          `<input type="radio" data-prop="span" name="cell_span" value="unit" checked>` +
          `</div></div>` +
          `<template data-item-template><div data-array-item>` +
          `<input id="cell_title_new" name="cell_title_new" data-prop="title" value="">` +
          `<input type="radio" data-prop="span" name="cell_span_new" value="hero">` +
          `<input type="radio" data-prop="span" name="cell_span_new" value="unit">` +
          `</div></template>` +
          `<button data-add-item data-action="click->website-builder#addItem">add</button>` +
          `</div></article>`
      })
    ))
    click(element.querySelector("[data-add-item]"))
    click(element.querySelector("[data-add-item]"))
    const items = [...element.querySelectorAll("[data-array-item]")]
    expect(items).toHaveLength(3)
    const names = items.map((item) => item.querySelector("[data-prop='span']").getAttribute("name"))
    expect(new Set(names).size).toBe(3)
  })

  it("focusSection opens the matching row and updates the section navigator", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<button data-website-builder-target="sectionNav" data-section-id="sec_a" data-action="click->website-builder#focusSection" aria-current="false">A</button>` +
          `<button data-website-builder-target="sectionNav" data-section-id="sec_b" data-action="click->website-builder#focusSection" aria-current="false">B</button>` +
          `<article data-website-builder-target="row" data-section-id="sec_a" data-section-type="quote"><details class="group/section"><summary>A</summary></details></article>` +
          `<article data-website-builder-target="row" data-section-id="sec_b" data-section-type="quote"><details class="group/section"><summary>B</summary></details></article>`
      })
    ))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.focusSection({ currentTarget: { dataset: {} } })
    ctrl.focusSection({ currentTarget: { dataset: { sectionId: "missing" } } })
    click(element.querySelector("[data-section-id='sec_b'][data-website-builder-target='sectionNav']"))
    expect(element.querySelector("[data-section-id='sec_b'] details").open).toBe(true)
    expect(element.querySelector("[data-section-id='sec_b'][data-website-builder-target='sectionNav']").getAttribute("aria-current")).toBe("true")
    expect(element.querySelector("[data-section-id='sec_a'][data-website-builder-target='sectionNav']").getAttribute("aria-current")).toBe("false")

    const withRows = await mountController("website-builder", Controller, html())
    controllerFor(withRows.application, withRows.element, "website-builder").focusSection({ currentTarget: { dataset: { sectionId: "sec_0" } } })

    const noRows = await mountController("website-builder", Controller, html({ list: false, rows: 0 }))
    controllerFor(noRows.application, noRows.element, "website-builder").focusSection({ currentTarget: { dataset: { sectionId: "x" } } })
  })

  it("keeps the expand-all label in sync when a section is toggled", async () => {
    ;({ element } = await mountController(
      "website-builder",
      Controller,
      html({
        toggleAll: true,
        collapseAll: "Collapse all",
        expandAll: "Expand all",
        extra: `<article data-website-builder-target="row" data-section-id="sec_0" data-section-type="quote"><details class="group/section" open><summary>A</summary></details></article>`
      })
    ))
    const details = element.querySelector("details")
    details.open = false
    details.dispatchEvent(new Event("toggle", { bubbles: true }))
    expect(element.querySelector("[data-website-builder-target='toggleAll']").textContent).toBe("Expand all")
  })

  it("persist no-ops unless the host is a workspace form", async () => {
    const prevent = vi.fn()
    ;({ application, element } = await mountController("website-builder", Controller, html()))
    controllerFor(application, element, "website-builder").persist({ preventDefault: prevent })
    expect(prevent).not.toHaveBeenCalled()
  })

  it("persist posts the form in place and reloads the saved preview", async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true })
    vi.stubGlobal("fetch", fetchMock)
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      `<form data-controller="website-builder" data-website-workspace action="/pages/1" method="post">` +
      `<input data-website-builder-target="json" value="[]">` +
      `<p data-website-builder-target="unsaved">unsaved</p>` +
      `<iframe data-website-builder-target="previewFrame" data-preview-src="/preview" src="/preview" srcdoc="<p>old</p>"></iframe>` +
      `<div data-website-builder-target="previewLoading" class="hidden"></div>` +
      `</form>`
    ))
    const ctrl = controllerFor(application, element, "website-builder")
    const prevent = vi.fn()
    ctrl.persist({ preventDefault: prevent })
    ctrl.persist({ preventDefault: vi.fn() })
    await Promise.resolve()
    await Promise.resolve()
    expect(prevent).toHaveBeenCalled()
    expect(fetchMock).toHaveBeenCalledOnce()
    expect(fetchMock.mock.calls[0][1].headers["X-Website-Composer"]).toBe("1")
    expect(element.querySelector("[data-website-builder-target='unsaved']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("iframe").hasAttribute("srcdoc")).toBe(false)
  })

  it("persist leaves unsaved visible when the request fails or throws", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: false })
      .mockRejectedValueOnce(new Error("net"))
    vi.stubGlobal("fetch", fetchMock)
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      `<form data-controller="website-builder" data-website-workspace action="/pages/1">` +
      `<input data-website-builder-target="json" value="[]">` +
      `<p data-website-builder-target="unsaved">unsaved</p>` +
      `</form>`
    ))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.persist()
    await Promise.resolve()
    await Promise.resolve()
    expect(element.querySelector("[data-website-builder-target='unsaved']").classList.contains("hidden")).toBe(false)
    ctrl.persist()
    await Promise.resolve()
    await Promise.resolve()
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it("pushes a live preview after edits and injects a base tag", async () => {
    document.head.innerHTML = `<meta name="csrf-token" content="tok">`
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, text: async () => "<html><head></head><body>Draft</body></html>" })
      .mockResolvedValueOnce({ ok: true, text: async () => "<html><head><base href='https://example.test/'></head><body>B</body></html>" })
      .mockResolvedValueOnce({ ok: true, text: async () => "<p>no head</p>" })
      .mockResolvedValueOnce({ ok: false, text: async () => "nope" })
      .mockRejectedValueOnce(new Error("net"))
      .mockResolvedValueOnce({ ok: true, text: async () => "" })
    vi.stubGlobal("fetch", fetchMock)
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      `<form data-controller="website-builder" data-website-workspace data-website-builder-live-preview-ms-value="0" action="/pages/1">` +
      `<input name="_method" value="patch">` +
      `<input data-website-builder-target="json" value="[]">` +
      `<iframe data-website-builder-target="previewFrame" data-draft-url="/preview" src="/preview"></iframe>` +
      `<div data-website-builder-target="previewLoading" class="hidden">loading</div>` +
      `</form>`
    ))
    const ctrl = controllerFor(application, element, "website-builder")
    const frame = element.querySelector("iframe")
    ctrl.markDirty()
    await new Promise((r) => setTimeout(r, 0))
    await Promise.resolve()
    expect(fetchMock).toHaveBeenCalled()
    expect(fetchMock.mock.calls[0][1].method).toBe("POST")
    expect(frame.srcdoc).toContain("<base href=")
    expect(frame.srcdoc).toContain("Draft")

    ctrl.markDirty()
    await new Promise((r) => setTimeout(r, 0))
    await Promise.resolve()
    expect(frame.srcdoc).toContain("https://example.test/")

    ctrl.markDirty()
    await new Promise((r) => setTimeout(r, 0))
    await Promise.resolve()
    expect(frame.srcdoc).toContain("no head")

    ctrl.markDirty()
    await new Promise((r) => setTimeout(r, 0))
    await Promise.resolve()
    ctrl.markDirty()
    await new Promise((r) => setTimeout(r, 0))
    await Promise.resolve()
    expect(fetchMock).toHaveBeenCalledTimes(5)

    ctrl.markDirty()
    await new Promise((r) => setTimeout(r, 0))
    await Promise.resolve()
    expect(fetchMock).toHaveBeenCalledTimes(6)
    expect(frame.srcdoc).toBe("")
  })

  it("keeps the latest complete draft when an older response body finishes last", async () => {
    const olderBody = pendingResponse()
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, text: () => olderBody.promise })
      .mockResolvedValueOnce({ ok: true, text: async () => "<p>Latest complete draft</p>" })
    vi.stubGlobal("fetch", fetchMock)
    ;({ application, element } = await mountController("website-builder", Controller,
      `<form data-controller="website-builder" data-website-builder-live-preview-ms-value="0">
        <iframe data-website-builder-target="previewFrame" data-draft-url="/preview" src="/preview"></iframe>
      </form>`))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.markDirty()
    await new Promise((resolve) => setTimeout(resolve, 0))
    ctrl.markDirty()
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(element.querySelector("iframe").srcdoc).toBe("<p>Latest complete draft</p>")
    olderBody.resolve("<p>Older partial draft</p>")
    await Promise.resolve()
    await Promise.resolve()
    expect(element.querySelector("iframe").srcdoc).toBe("<p>Latest complete draft</p>")
  })

  it.each(["failed", "rejected"])("a stale %s response cannot dismiss the current preview's loading state", async (outcome) => {
    const older = pendingResponse()
    const latest = pendingResponse()
    vi.stubGlobal("fetch", vi.fn().mockReturnValueOnce(older.promise).mockReturnValueOnce(latest.promise))
    ;({ application, element } = await mountController("website-builder", Controller,
      `<form data-controller="website-builder" data-website-builder-live-preview-ms-value="0">
        <iframe data-website-builder-target="previewFrame" data-draft-url="/preview" src="/preview"></iframe>
        <div data-website-builder-target="previewLoading" class="hidden"></div>
      </form>`))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.markDirty()
    await new Promise((resolve) => setTimeout(resolve, 0))
    ctrl.markDirty()
    await new Promise((resolve) => setTimeout(resolve, 0))
    if (outcome === "failed") older.resolve({ ok: false })
    else older.reject(new Error("Old request failed"))
    await Promise.resolve()
    await Promise.resolve()
    expect(element.querySelector("[data-website-builder-target='previewLoading']").classList.contains("hidden")).toBe(false)
    latest.resolve({ ok: true, text: async () => "<p>Latest complete draft</p>" })
    await Promise.resolve()
    await Promise.resolve()
    expect(element.querySelector("iframe").srcdoc).toBe("<p>Latest complete draft</p>")
  })

  it.each(["edit", "save", "disconnect"])("invalidates in-flight draft HTML immediately on %s", async (operation) => {
    const body = pendingResponse()
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, text: () => body.promise })
    vi.stubGlobal("fetch", fetchMock)
    ;({ application, element } = await mountController("website-builder", Controller,
      `<form data-controller="website-builder" data-website-builder-live-preview-ms-value="0">
        <iframe data-website-builder-target="previewFrame" data-draft-url="/preview" data-preview-src="/preview" src="/preview" srcdoc="<p>Current</p>"></iframe>
      </form>`))
    const ctrl = controllerFor(application, element, "website-builder")
    const frame = element.querySelector("iframe")
    ctrl.markDirty()
    await new Promise((resolve) => setTimeout(resolve, 0))
    // Hold the next edit in debounce to test invalidation before its request starts.
    ctrl.livePreviewMsValue = 1000
    if (operation === "edit") ctrl.markDirty()
    if (operation === "save") ctrl.reloadPreview()
    if (operation === "disconnect") ctrl.disconnect()
    const current = frame.srcdoc
    body.resolve("<p>Outdated draft</p>")
    await Promise.resolve()
    await Promise.resolve()
    expect(frame.srcdoc).toBe(current)
    ctrl.disconnect()
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it.each(["response", "body"])("reconnecting cannot let an old deferred preview %s overwrite the new draft", async (stage) => {
    const older = pendingResponse()
    const fetchMock = vi.fn().mockReturnValueOnce(stage === "body"
      ? Promise.resolve({ ok: true, text: () => older.promise })
      : older.promise).mockResolvedValueOnce({ ok: true, text: async () => "<p>Latest reconnected draft</p>" })
    vi.stubGlobal("fetch", fetchMock)
    ;({ application, element } = await mountController("website-builder", Controller,
      `<div><form data-controller="website-builder" data-website-builder-live-preview-ms-value="0">
        <iframe data-website-builder-target="previewFrame" data-draft-url="/preview" src="about:blank"></iframe>
      </form></div>`))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.markDirty()
    await tick()
    await reconnectController(application, element)
    ctrl.markDirty()
    await tick()
    const frame = element.querySelector("iframe")
    expect(frame.srcdoc).toBe("<p>Latest reconnected draft</p>")
    older.resolve(stage === "body" ? "<p>Old connection draft</p>" : { ok: true, text: async () => "<p>Old connection draft</p>" })
    await tick()
    expect(frame.srcdoc).toBe("<p>Latest reconnected draft</p>")
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it.each(["rejected", "non-OK", "body error"])("reconnecting cannot let an old %s preview clear the new loading state", async (outcome) => {
    const older = pendingResponse(), latest = pendingResponse()
    const fetchMock = vi.fn().mockReturnValueOnce(outcome === "body error"
      ? Promise.resolve({ ok: true, text: () => older.promise })
      : older.promise).mockReturnValueOnce(latest.promise)
    vi.stubGlobal("fetch", fetchMock)
    ;({ application, element } = await mountController("website-builder", Controller,
      `<div><form data-controller="website-builder" data-website-builder-live-preview-ms-value="0">
        <iframe data-website-builder-target="previewFrame" data-draft-url="/preview" src="about:blank" srcdoc="<p>Current</p>"></iframe>
        <div data-website-builder-target="previewLoading" class="hidden"></div>
      </form></div>`))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.markDirty()
    await tick()
    await reconnectController(application, element)
    ctrl.markDirty()
    await tick()
    const frame = element.querySelector("iframe")
    const current = frame.srcdoc
    if (outcome === "non-OK") older.resolve({ ok: false })
    else older.reject(new Error("Old preview failed"))
    await tick()
    expect(element.querySelector("[data-website-builder-target='previewLoading']").classList.contains("hidden")).toBe(false)
    expect(frame.srcdoc).toBe(current)
    latest.resolve({ ok: true, text: async () => "<p>Latest reconnected draft</p>" })
    await tick()
    expect(frame.srcdoc).toBe("<p>Latest reconnected draft</p>")
    ctrl.previewLoaded()
    expect(element.querySelector("[data-website-builder-target='previewLoading']").classList.contains("hidden")).toBe(true)
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it("skips live preview without a draft URL or a form", async () => {
    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      `<form data-controller="website-builder" data-website-builder-live-preview-ms-value="0">` +
      `<iframe data-website-builder-target="previewFrame" src="/preview"></iframe>` +
      `</form>`
    ))
    controllerFor(application, element, "website-builder").markDirty()
    await new Promise((r) => setTimeout(r, 0))
    expect(fetchMock).not.toHaveBeenCalled()

    const delayed = await mountController(
      "website-builder",
      Controller,
      `<form data-controller="website-builder" data-website-builder-live-preview-ms-value="20">` +
      `<iframe data-website-builder-target="previewFrame" data-draft-url="/preview" src="/preview"></iframe>` +
      `</form>`
    )
    controllerFor(delayed.application, delayed.element, "website-builder").markDirty()
    delayed.element.querySelector("iframe").remove()
    await new Promise((r) => setTimeout(r, 40))
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("toggles editor and preview panes and shows unsaved on every pill", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        templates: false,
        extra:
          `<div data-website-builder-target="editorPane" class="max-xl:hidden">editor</div>` +
          `<div data-website-builder-target="previewPane">preview</div>` +
          `<button type="button" data-website-builder-target="paneBtn" data-pane="editor" data-action="click->website-builder#setWorkspacePane" aria-pressed="false">edit</button>` +
          `<button type="button" data-website-builder-target="paneBtn" data-pane="preview" data-action="click->website-builder#setWorkspacePane" aria-pressed="true">preview</button>` +
          `<p data-website-builder-target="unsaved" class="hidden" data-extra-unsaved>also</p>`
      })
    ))
    const editor = element.querySelector("[data-website-builder-target='editorPane']")
    const preview = element.querySelector("[data-website-builder-target='previewPane']")
    const editBtn = element.querySelector("[data-pane='editor']")
    const previewBtn = element.querySelector("[data-pane='preview']")
    expect(editor.classList.contains("max-xl:hidden")).toBe(false)
    expect(preview.classList.contains("max-xl:hidden")).toBe(true)
    expect(editBtn.getAttribute("aria-pressed")).toBe("true")
    expect(previewBtn.getAttribute("aria-pressed")).toBe("false")

    click(previewBtn)
    expect(editor.classList.contains("max-xl:hidden")).toBe(true)
    expect(preview.classList.contains("max-xl:hidden")).toBe(false)
    expect(previewBtn.getAttribute("aria-pressed")).toBe("true")

    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.setWorkspacePane({ currentTarget: null })
    expect(editor.classList.contains("max-xl:hidden")).toBe(false)
    expect(preview.classList.contains("max-xl:hidden")).toBe(true)

    ctrl.markDirty()
    expect([...element.querySelectorAll("[data-website-builder-target='unsaved']")].every((el) => !el.classList.contains("hidden"))).toBe(true)
  })

  it("focusSection returns to the editor pane", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<div data-website-builder-target="editorPane">editor</div>` +
          `<div data-website-builder-target="previewPane"></div>` +
          `<button data-website-builder-target="paneBtn" data-pane="editor" aria-pressed="true">edit</button>` +
          `<button data-website-builder-target="paneBtn" data-pane="preview" aria-pressed="false">preview</button>` +
          `<article data-website-builder-target="row" data-section-id="sec_a" data-section-type="quote"><details class="group/section"><summary>A</summary></details></article>`
      })
    ))
    const ctrl = controllerFor(application, element, "website-builder")
    ctrl.setWorkspacePane({ currentTarget: { dataset: { pane: "preview" } } })
    expect(element.querySelector("[data-website-builder-target='editorPane']").classList.contains("max-xl:hidden")).toBe(true)
    ctrl.focusSection({ currentTarget: { dataset: { sectionId: "sec_a" } } })
    expect(element.querySelector("[data-website-builder-target='editorPane']").classList.contains("max-xl:hidden")).toBe(false)
    expect(element.querySelector("[data-pane='editor']").getAttribute("aria-pressed")).toBe("true")
  })

  it("applyWorkspacePane is a no-op without pane targets", async () => {
    ;({ application, element } = await mountController("website-builder", Controller, html({ list: false, rows: 0 })))
    const ctrl = controllerFor(application, element, "website-builder")
    expect(() => ctrl.setWorkspacePane({ currentTarget: { dataset: { pane: "preview" } } })).not.toThrow()
  })

  it("uploads a dropped or chosen photo and writes the returned URL", async () => {
    const file = new File(["abc"], "a.png", { type: "image/png" })
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, json: async () => ({ url: "/12345678/site/media/new" }) })
      .mockResolvedValueOnce({ ok: false, json: async () => ({ error: "nope" }) })
      .mockResolvedValueOnce({ ok: false, json: async () => { throw new Error("bad json") } })
      .mockResolvedValueOnce({ ok: true, json: async () => ({}) })
      .mockRejectedValueOnce(new Error("net"))
    vi.stubGlobal("fetch", fetchMock)

    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<div data-controller-host>` +
          `<article data-website-builder-target="row" data-section-id="m" data-section-type="split_image_text">` +
          `<div data-image-field>` +
          `<input data-prop="image_url" value="">` +
          `<img data-image-preview class="hidden">` +
          `<p data-image-empty>empty</p>` +
          `<span data-image-add>add</span>` +
          `<span data-image-replace class="hidden">replace</span>` +
          `<p data-image-status class="hidden"></p>` +
          `<input type="file" data-file data-action="change->website-builder#uploadImage">` +
          `</div></article></div>`
      }).replace(
        "data-controller=\"website-builder\"",
        "data-controller=\"website-builder\" data-website-builder-upload-url-value=\"/upload\" data-website-builder-upload-failed-value=\"failed\" data-website-builder-uploading-value=\"wait\""
      )
    ))
    const ctrl = controllerFor(application, element, "website-builder")
    const field = element.querySelector("[data-image-field]")
    const prevent = vi.fn()

    ctrl.allowImageDrop({ preventDefault: prevent, currentTarget: field })
    ctrl.allowImageDrop({ preventDefault: prevent, currentTarget: document.body })
    ctrl.dropImage({ preventDefault: prevent, currentTarget: document.body, dataTransfer: { files: [file] } })
    ctrl.dropImage({ preventDefault: prevent, currentTarget: field, dataTransfer: { files: [] } })
    ctrl.dropImage({ preventDefault: prevent, currentTarget: field, dataTransfer: { files: [file] } })
    await Promise.resolve()
    await Promise.resolve()
    expect(element.querySelector("[data-prop='image_url']").value).toBe("/12345678/site/media/new")
    expect(element.querySelector("[data-image-preview]").getAttribute("src")).toBe("/12345678/site/media/new")

    const fileInput = element.querySelector("[data-file]")
    ctrl.uploadImage({ currentTarget: { closest: () => null, files: [file], value: "" } })
    ctrl.uploadImage({ currentTarget: fileInput })
    Object.defineProperty(fileInput, "files", { configurable: true, value: [file] })
    ctrl.uploadImage({ currentTarget: fileInput })
    await Promise.resolve()
    await Promise.resolve()
    expect(element.querySelector("[data-image-status]").textContent).toBe("nope")

    ctrl.uploadImage({ currentTarget: fileInput })
    await Promise.resolve()
    await Promise.resolve()
    expect(element.querySelector("[data-image-status]").textContent).toBe("failed")

    ctrl.uploadImage({ currentTarget: fileInput })
    await Promise.resolve()
    await Promise.resolve()
    expect(element.querySelector("[data-image-status]").textContent).toBe("failed")

    ctrl.uploadImage({ currentTarget: fileInput })
    await Promise.resolve()
    await Promise.resolve()
    expect(element.querySelector("[data-image-status]").textContent).toBe("failed")
    expect(fetchMock).toHaveBeenCalledTimes(5)
  })

  it("shows the upload failure when no upload URL is configured", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="m" data-section-type="split_image_text">` +
          `<div data-image-field>` +
          `<input data-prop="image_url" value="">` +
          `<p data-image-status class="hidden"></p>` +
          `</div></article>`
      }).replace(
        "data-controller=\"website-builder\"",
        "data-controller=\"website-builder\" data-website-builder-upload-failed-value=\"failed\""
      )
    ))
    const ctrl = controllerFor(application, element, "website-builder")
    const field = element.querySelector("[data-image-field]")
    ctrl.dropImage({
      preventDefault: vi.fn(),
      currentTarget: field,
      dataTransfer: { files: [new File(["abc"], "a.png", { type: "image/png" })] }
    })
    expect(element.querySelector("[data-image-status]").textContent).toBe("failed")
    expect(element.querySelector("[data-image-status]").classList.contains("hidden")).toBe(false)

    const bare = document.createElement("div")
    bare.setAttribute("data-image-field", "")
    document.body.appendChild(bare)
    ctrl.dropImage({ preventDefault: vi.fn(), currentTarget: bare, dataTransfer: { files: [new File(["a"], "a.png")] } })
    bare.remove()
  })

  it("rewrites section ARIA references, including those inside nested inert templates", async () => {
    vi.spyOn(crypto, "randomUUID").mockReturnValue("aria")
    ;({ element } = await mountController("website-builder", Controller, html({
      rows: 0, templates: false,
      extra: `<template data-section-template="quote"><article data-website-builder-target="row" data-section-id="__SECTION_ID__" id="panel-__SECTION_ID__" aria-labelledby="title-__SECTION_ID__">` +
        `<label id="title-__SECTION_ID__" for="input-__SECTION_ID__">Title</label>` +
        `<input id="input-__SECTION_ID__" data-prop="quote" aria-labelledby="title-__SECTION_ID__" aria-describedby="hint-__SECTION_ID__ external-help" aria-controls="panel-__SECTION_ID__">` +
        `<p id="hint-__SECTION_ID__"></p>` +
        `<template data-item-template><div><label id="item-label-__SECTION_ID__" for="item-__SECTION_ID__">Item</label><input id="item-__SECTION_ID__" aria-labelledby="item-label-__SECTION_ID__">` +
        `<template><input id="nested-__SECTION_ID__" aria-describedby="hint-__SECTION_ID__"></template></div></template></article></template>`
    })))
    await click(element.querySelector("[data-type='quote']"))
    const row = element.querySelector("[data-website-builder-target='row']")
    expect(row.id).toBe("panel-sec_aria")
    expect(row.getAttribute("aria-labelledby")).toBe("title-sec_aria")
    const input = row.querySelector("input")
    expect(input.getAttribute("aria-labelledby")).toBe(row.querySelector("label").id)
    expect(row.querySelector("label").htmlFor).toBe(input.id)
    expect(input.getAttribute("aria-describedby")).toBe("hint-sec_aria external-help")
    expect(input.getAttribute("aria-controls")).toBe(row.id)
    const item = row.querySelector("template").content
    expect(item.querySelector("input").getAttribute("aria-labelledby")).toBe(item.querySelector("label").id)
    expect(item.querySelector("template").content.querySelector("input").getAttribute("aria-describedby")).toBe("hint-sec_aria")
    expect(row.outerHTML).not.toContain("__SECTION_ID__")
    expect(element.querySelector("template[data-section-template]").innerHTML).toContain("__SECTION_ID__")
  })

  it("keeps cloned card labels and ARIA IDREF lists local while preserving external references", async () => {
    ;({ element } = await mountController("website-builder", Controller, html({
      rows: 0,
      extra: `<p id="external-help">Shared hint</p><article data-website-builder-target="row" data-section-id="cards" data-section-type="cards">` +
        `<div data-array="items"><div data-array-list></div><template data-item-template>` +
        `<div data-array-item id="card" aria-labelledby="title" aria-describedby="hint external-help">` +
        `<label id="title" for="field">Title</label><input id="field" name="field" data-prop="title" value="Copy" aria-labelledby="title" aria-describedby="hint external-help" aria-controls="card hint" aria-owns="hint" aria-details="hint" aria-errormessage="hint" aria-activedescendant="hint" aria-flowto="hint">` +
        `<span id="hint">Hint</span><input type="radio" name="tone" value="light" data-prop="tone" checked><input type="radio" name="tone" value="dark" data-prop="tone">` +
        `<button type="button" data-action="click->website-builder#duplicateItem">Duplicate</button></div></template>` +
        `<button type="button" data-add-item data-action="click->website-builder#addItem">Add</button></div></article>`
    })))
    await click(element.querySelector("[data-add-item]"))
    await click(element.querySelector("[data-action*='duplicateItem']"))
    const items = [...element.querySelectorAll("[data-array-item]")]
    expect(items).toHaveLength(2)
    const ids = [...element.querySelectorAll("[id]")].map((el) => el.id)
    expect(new Set(ids).size).toBe(ids.length)
    for (const item of items) {
      const label = item.querySelector("label")
      const input = item.querySelector("[data-prop='title']")
      const hint = item.querySelector("span")
      expect(label.htmlFor).toBe(input.id)
      expect(item.getAttribute("aria-labelledby")).toBe(label.id)
      expect(item.getAttribute("aria-describedby")).toBe(`${hint.id} external-help`)
      expect(input.getAttribute("aria-labelledby")).toBe(label.id)
      expect(input.getAttribute("aria-describedby")).toBe(`${hint.id} external-help`)
      expect(input.getAttribute("aria-controls")).toBe(`${item.id} ${hint.id}`)
      for (const attr of ["aria-owns", "aria-details", "aria-errormessage", "aria-activedescendant", "aria-flowto"]) {
        expect(input.getAttribute(attr)).toBe(hint.id)
      }
      expect(item.querySelectorAll("input[type='radio']")[0].name).toBe(item.querySelectorAll("input[type='radio']")[1].name)
    }
    expect(items[0].querySelector("input[type='radio']").name).not.toBe(items[1].querySelector("input[type='radio']").name)
    expect(jsonValue(element)[0].props.items).toEqual([{ title: "Copy", tone: "light" }, { title: "Copy", tone: "light" }])
  })

  describe("workspace tabs and disclosures", () => {
    beforeEach(() => {
      // happy-dom 15's form Proxy makes native contains() reject descendants.
      // Restore DOM containment so Stimulus can bind real click/keydown actions.
      vi.spyOn(HTMLFormElement.prototype, "contains").mockImplementation(function (node) {
        return node === this || [...this.querySelectorAll("*")].includes(node)
      })
    })
    const tabs = (root) => [...root.querySelectorAll("[data-website-builder-target='sectionNav']")]
    const rows = (root) => [...root.querySelectorAll("[data-website-builder-target='row']")]
    const assertSelected = (root, id) => {
      expect(rows(root).filter((row) => !row.classList.contains("hidden")).map((row) => row.dataset.sectionId)).toEqual([id])
      tabs(root).forEach((tab) => {
        const selected = tab.dataset.sectionId === id
        expect(tab.getAttribute("aria-current")).toBe(String(selected))
        expect(tab.getAttribute("aria-selected")).toBe(String(selected))
        expect(tab.tabIndex).toBe(selected ? 0 : -1)
        expect(tab.getAttribute("role")).toBe("tab")
        const panel = root.querySelector(`[id='${tab.getAttribute("aria-controls")}']`)
        expect(panel.getAttribute("role")).toBe("tabpanel")
        expect(panel.getAttribute("aria-labelledby")).toBe(tab.id)
      })
    }

    it("initializes localized tabs without opening secondary details and serializes hidden/closed fields", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, workspace({ locked: true })))
      expect(Sortable.create).not.toHaveBeenCalled()
      assertSelected(element, "sec_0")
      expect(tabs(element).map((tab) => tab.querySelector("[data-section-label]").textContent)).toEqual(["章节 1", "章节 2", "章节 3"])
      expect(tabs(element).map((tab) => tab.querySelector("[data-section-number]").textContent)).toEqual(["1", "2", "3"])
      const ctrl = controllerFor(application, element, "website-builder")
      ctrl.toggleAllSections()
      await click(tabs(element)[2])
      assertSelected(element, "sec_2")
      expect([...element.querySelectorAll("[data-secondary], [data-url]")].every((details) => !details.open)).toBe(true)
      expect([...element.querySelectorAll("[data-items]")].every((details) => details.open)).toBe(true)
      rows(element)[0].querySelector("[data-prop='url']").value = "https://changed.test/"
      ctrl.markDirty()
      expect(jsonValue(element)).toEqual([0, 1, 2].map((i) => ({
        id: `sec_${i}`, type: "quote", props: {
          quote: `Copy sec_${i}`, url: i === 0 ? "https://changed.test/" : `https://example.test/sec_${i}`,
          items: [{ label: `Item sec_${i}` }]
        }
      })))
      expect(JSON.parse(new FormData(element).get("website_page[sections_json]"))).toEqual(jsonValue(element))
    })

    it("wraps horizontal section navigation, supports Home/End, and scrolls only the selected tab", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, workspace()))
      const nav = tabs(element)
      nav.forEach((tab) => { tab.scrollIntoView = vi.fn() })
      const focus = vi.spyOn(nav[2], "focus")
      rows(element).forEach((row) => { row.scrollIntoView = vi.fn() })
      for (const [from, key, to] of [[0, "ArrowLeft", 2], [2, "ArrowRight", 0], [0, "ArrowRight", 1], [1, "ArrowLeft", 0], [0, "End", 2], [2, "Home", 0]]) {
        expect(keydown(nav[from], key).defaultPrevented).toBe(true)
        expect(document.activeElement).toBe(nav[to])
        assertSelected(element, `sec_${to}`)
        expect(nav[to].scrollIntoView).toHaveBeenLastCalledWith({ block: "nearest", inline: "nearest" })
      }
      expect(focus).toHaveBeenCalledWith({ preventScroll: true })
      expect(nav[1].scrollIntoView).toHaveBeenCalledOnce()
      rows(element).forEach((row) => expect(row.scrollIntoView).not.toHaveBeenCalled())
      nav[1].scrollIntoView = undefined
      await click(nav[1])
      assertSelected(element, "sec_1")
    })

    it.each(["Enter", " ", "Tab", "Escape"])("preserves native %s behavior for both tab groups", async (key) => {
      ;({ element } = await mountController("website-builder", Controller, workspace()))
      const section = tabs(element)[0]
      const pane = element.querySelector("[data-pane='editor']")
      for (const tab of [section, pane]) {
        tab.focus()
        const clickSpy = vi.spyOn(tab, "click")
        expect(keydown(tab, key).defaultPrevented).toBe(false)
        expect(document.activeElement).toBe(tab)
        expect(clickSpy).not.toHaveBeenCalled()
      }
      assertSelected(element, "sec_0")
    })

    it("navigates vertical section tabs with ArrowUp/ArrowDown and leaves pane ArrowDown native", async () => {
      ;({ element } = await mountController("website-builder", Controller, workspace()))
      const nav = tabs(element)
      nav.forEach((tab) => { tab.scrollIntoView = vi.fn() })
      expect(keydown(nav[0], "ArrowDown").defaultPrevented).toBe(true)
      assertSelected(element, "sec_1")
      expect(keydown(nav[1], "ArrowUp").defaultPrevented).toBe(true)
      assertSelected(element, "sec_0")
      const pane = element.querySelector("[data-pane='editor']")
      pane.focus()
      const clickSpy = vi.spyOn(pane, "click")
      expect(keydown(pane, "ArrowDown").defaultPrevented).toBe(false)
      expect(keydown(pane, "ArrowUp").defaultPrevented).toBe(false)
      expect(clickSpy).not.toHaveBeenCalled()
    })

    it("navigates pane tabs without aria-hiding or making desktop panels inert", async () => {
      ;({ element } = await mountController("website-builder", Controller, workspace()))
      const paneTabs = [...element.querySelectorAll("[data-website-builder-target='paneBtn']")]
      const focus = vi.spyOn(paneTabs[1], "focus")
      for (const [from, key, to] of [[0, "ArrowLeft", 1], [1, "ArrowRight", 0], [0, "End", 1], [1, "Home", 0]]) {
        expect(keydown(paneTabs[from], key).defaultPrevented).toBe(true)
        expect(document.activeElement).toBe(paneTabs[to])
        paneTabs.forEach((tab, index) => {
          const selected = index === to
          expect(tab.getAttribute("aria-selected")).toBe(String(selected))
          expect(tab.getAttribute("aria-pressed")).toBe(String(selected))
          expect(tab.tabIndex).toBe(selected ? 0 : -1)
          const panel = element.querySelector(`[id='${tab.getAttribute("aria-controls")}']`)
          expect(panel.getAttribute("aria-labelledby")).toBe(tab.id)
          expect(panel.classList.contains("max-xl:hidden")).toBe(!selected)
          expect(panel.hasAttribute("hidden")).toBe(false)
          expect(panel.hasAttribute("aria-hidden")).toBe(false)
          expect(panel.hasAttribute("inert")).toBe(false)
        })
      }
      expect(focus).toHaveBeenCalledWith({ preventScroll: true })
    })

    it("handles absent targets and singleton tab lists", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, workspace({ count: 1 })))
      expect(keydown(tabs(element)[0], "ArrowRight").defaultPrevented).toBe(true)
      assertSelected(element, "sec_0")
      const ctrl = controllerFor(application, element, "website-builder")
      const preventDefault = vi.fn()
      ctrl.navigateSectionTabs({ currentTarget: element, key: "Home", preventDefault })
      ctrl.navigatePaneTabs({ currentTarget: element, key: "End", preventDefault })
      expect(preventDefault).not.toHaveBeenCalled()
      ;({ application, element } = await mountController("website-builder", Controller, html({ rows: 0 })))
      const emptyCtrl = controllerFor(application, element, "website-builder")
      emptyCtrl.navigateSectionTabs({ currentTarget: element, key: "ArrowLeft", preventDefault })
      emptyCtrl.navigatePaneTabs({ currentTarget: element, key: "ArrowRight", preventDefault })
      expect(preventDefault).not.toHaveBeenCalled()
    })

    it("syncs unlocked add/remove/move/drag order, labels, and a single active section", async () => {
      vi.spyOn(crypto, "randomUUID").mockReturnValue("new")
      vi.spyOn(window, "confirm").mockReturnValue(true)
      ;({ element } = await mountController("website-builder", Controller, workspace()))
      await click(element.querySelector("[data-type='quote']"))
      assertSelected(element, "sec_new")
      const added = rows(element)[3]
      const addedTab = tabs(element)[3]
      expect(addedTab.id).toBe("website-section-tab-sec_new")
      expect(addedTab.querySelector("[data-section-label]").textContent).toBe("引言")
      expect(addedTab.querySelector("[data-section-number]").textContent).toBe("4")
      expect(added.querySelector("[data-secondary]").open).toBe(false)
      expect(added.querySelector("[data-items]").open).toBe(true)
      expect(element.querySelector("template[data-section-nav-template]").content.querySelector("[data-section-label]").textContent).toBe("")
      await click(added.querySelector("[data-action*='moveUp']"))
      expect(tabs(element).map((tab) => tab.dataset.sectionId)).toEqual(["sec_0", "sec_1", "sec_new", "sec_2"])
      assertSelected(element, "sec_new")
      await click(added.querySelector("[data-action*='moveDown']"))
      expect(tabs(element)[3]).toBe(addedTab)
      const list = element.querySelector("[data-workspace-rail]")
      list.prepend(added)
      Sortable.create.mock.calls[0][1].onEnd()
      expect(tabs(element).map((tab) => tab.dataset.sectionId)).toEqual(rows(element).map((row) => row.dataset.sectionId))
      expect(tabs(element).map((tab) => tab.querySelector("[data-section-number]").textContent)).toEqual(["1", "2", "3", "4"])
      assertSelected(element, "sec_new")
      await click(rows(element)[2].querySelector("[data-action*='removeSection']"))
      assertSelected(element, "sec_new")
      await click(added.querySelector("[data-action*='removeSection']"))
      expect(addedTab.isConnected).toBe(false)
      assertSelected(element, "sec_0")
      for (const row of rows(element)) await click(row.querySelector("[data-action*='removeSection']"))
      expect(tabs(element)).toHaveLength(0)
      expect(jsonValue(element)).toEqual([])
      await click(element.querySelector("[data-type='quote']"))
      assertSelected(element, "sec_new")
      expect(tabs(element)[0].querySelector("[data-section-number]").textContent).toBe("1")
    })

    it("mirrors the first copy field into the outline preview and skips unmatched rows", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, workspace()))
      tabs(element).forEach((tab) => {
        const span = document.createElement("span")
        span.setAttribute("data-section-preview", "")
        span.className = "hidden"
        tab.appendChild(span)
      })
      const ctrl = controllerFor(application, element, "website-builder")
      ctrl.markDirty()
      const preview = tabs(element)[0].querySelector("[data-section-preview]")
      expect(preview.textContent).toBe("Copy sec_0")
      expect(preview.classList.contains("hidden")).toBe(false)
      rows(element)[0].querySelector("[data-prop='quote']").value = "   "
      ctrl.markDirty()
      expect(preview.textContent).toBe("")
      expect(preview.classList.contains("hidden")).toBe(true)
      rows(element)[0].insertAdjacentHTML("beforeend", `<input data-prop="headline" value="Welcome">`)
      ctrl.markDirty()
      expect(preview.textContent).toBe("Welcome")
      rows(element)[0].insertAdjacentHTML("afterend", `<article data-website-builder-target="row" data-section-id="orphan"></article>`)
      ctrl.markDirty()
      expect(tabs(element)).toHaveLength(3)
    })

    it("tolerates incomplete navigation templates and missing localized labels", async () => {
      ;({ application, element } = await mountController("website-builder", Controller,
        workspace().replace(/data-section-label="[^"]*"/g, "").replace(/<template data-section-nav-template>.*?<\/template>/, "<template data-section-nav-template></template>")))
      expect(tabs(element).map((tab) => tab.querySelector("[data-section-label]").textContent)).toEqual(["", "", ""])
      await click(element.querySelector("[data-type='quote']"))
      expect(rows(element)).toHaveLength(4)
      expect(tabs(element)).toHaveLength(3)
      expect(rows(element).filter((row) => !row.classList.contains("hidden"))).toHaveLength(1)
    })

    it("reveals the first invalid control synchronously in its section and nested disclosures", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, workspace()))
      const ctrl = controllerFor(application, element, "website-builder")
      const first = rows(element)[1].querySelector("[data-prop='url']")
      const second = rows(element)[2].querySelector("[data-prop='url']")
      const unchanged = jsonValue(element)
      await click(element.querySelector("[data-pane='preview']"))
      // invalid does not bubble. Capture must reveal controls before target handlers/browser focus.
      const onInvalid = vi.fn(() => {
        assertSelected(element, "sec_1")
        expect(first.closest("[data-url]").open).toBe(true)
        expect(first.closest("[data-secondary]").open).toBe(true)
        expect(element.querySelector("[data-website-builder-target='editorPane']").classList.contains("max-xl:hidden")).toBe(false)
      })
      first.addEventListener("invalid", onInvalid)
      const invalid = new Event("invalid", { cancelable: true })
      first.dispatchEvent(invalid)
      // Native validation can checkpoint microtasks between invalid events.
      await Promise.resolve()
      second.dispatchEvent(new Event("invalid"))
      expect(onInvalid).toHaveBeenCalledOnce()
      expect(invalid.defaultPrevented).toBe(false)
      assertSelected(element, "sec_1")
      expect(jsonValue(element)).toEqual(unchanged)
      await tick()
      second.dispatchEvent(new Event("invalid"))
      assertSelected(element, "sec_2")
      expect(second.closest("[data-secondary]").open).toBe(true)
      await tick()
      await click(element.querySelector("[data-pane='preview']"))
      element.querySelector("[data-outside]").dispatchEvent(new Event("invalid"))
      expect(element.querySelector("[data-pane='editor']").getAttribute("aria-selected")).toBe("true")
      assertSelected(element, "sec_2")
      await tick()
      ctrl.disconnect()
      first.closest("[data-secondary]").open = false
      first.removeEventListener("invalid", onInvalid)
      first.dispatchEvent(new Event("invalid"))
      expect(first.closest("[data-secondary]").open).toBe(false)
      assertSelected(element, "sec_2")
    })

    it("nonworkspace section actions only toggle the true section disclosure", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, html({
        rows: 1, toggleAll: true,
        rowExtras: () => `<div><div><details class="group/section"><summary>Section</summary><details data-secondary><summary>URL</summary><input required></details></details></div></div>`
      })))
      const outer = element.querySelector("details")
      const inner = element.querySelector("[data-secondary]")
      await click(element.querySelector("[data-website-builder-target='toggleAll']"))
      expect(outer.open).toBe(true)
      expect(inner.open).toBe(false)
      inner.open = true
      inner.dispatchEvent(new Event("toggle"))
      expect(element.querySelector("[data-website-builder-target='toggleAll']").textContent).toBe("Collapse all")
      await click(element.querySelector("[data-website-builder-target='toggleAll']"))
      expect(outer.open).toBe(false)
      expect(inner.open).toBe(true)
      inner.open = false
      controllerFor(application, element, "website-builder").focusSection({ currentTarget: rows(element)[0] })
      expect(outer.open).toBe(true)
      expect(inner.open).toBe(false)
      inner.querySelector("input").dispatchEvent(new Event("invalid"))
      expect(inner.open).toBe(false)
    })
  })

  it("shows one writing-rail section at a time", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        list: false,
        rows: 0,
        extra:
          `<div data-workspace-rail data-website-builder-target="list">` +
          `<article data-website-builder-target="row" data-section-id="sec_a" data-section-type="quote">A</article>` +
          `<article data-website-builder-target="row" data-section-id="sec_b" data-section-type="quote">B</article>` +
          `</div>` +
          `<button data-website-builder-target="sectionNav" data-section-id="sec_a" data-action="click->website-builder#focusSection" aria-current="true">A</button>` +
          `<button data-website-builder-target="sectionNav" data-section-id="sec_b" data-action="click->website-builder#focusSection" aria-current="false">B</button>`
      })
    ))
    expect(element.querySelector("[data-section-id='sec_a']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-section-id='sec_b']").classList.contains("hidden")).toBe(true)

    click(element.querySelector("[data-section-id='sec_b'][data-website-builder-target='sectionNav']"))
    expect(element.querySelector("[data-section-id='sec_a']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-section-id='sec_b']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-section-id='sec_b'][data-website-builder-target='sectionNav']").getAttribute("aria-current")).toBe("true")

    const emptyRail = await mountController(
      "website-builder",
      Controller,
      html({ list: false, rows: 0, extra: `<div data-workspace-rail></div>` })
    )
    expect(emptyRail.element.querySelector("[data-workspace-rail]")).toBeTruthy()

    const hiddenRail = await mountController(
      "website-builder",
      Controller,
      html({
        list: false,
        rows: 0,
        extra:
          `<div data-workspace-rail data-website-builder-target="list">` +
          `<article data-website-builder-target="row" data-section-id="sec_a" data-section-type="quote" class="hidden">A</article>` +
          `<article data-website-builder-target="row" data-section-id="sec_b" data-section-type="quote" class="hidden">B</article>` +
          `</div>`
      })
    )
    expect(hiddenRail.element.querySelector("[data-section-id='sec_a']").classList.contains("hidden")).toBe(false)
  })

  it("resets the inspector scroll and hands focus to the tab when stepping between sections", async () => {
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        list: false,
        rows: 0,
        extra:
          `<div data-workspace-inspector><div data-workspace-rail data-website-builder-target="list">` +
          `<article data-website-builder-target="row" data-section-id="sec_a" data-section-type="quote">A` +
          `<button type="button" data-step="next" data-section-step="next" data-section-id="sec_b" data-action="click->website-builder#focusSection">Next</button></article>` +
          `<article data-website-builder-target="row" data-section-id="sec_b" data-section-type="quote">B` +
          `<button type="button" data-step="orphan" data-section-step="next" data-section-id="sec_c" data-action="click->website-builder#focusSection">Next</button></article>` +
          `<article data-website-builder-target="row" data-section-id="sec_c" data-section-type="quote">C</article>` +
          `</div></div>` +
          `<button data-website-builder-target="sectionNav" data-section-id="sec_a" data-action="click->website-builder#focusSection">A</button>` +
          `<button data-website-builder-target="sectionNav" data-section-id="sec_b" data-action="click->website-builder#focusSection">B</button>`
      })
    ))
    const inspector = element.querySelector("[data-workspace-inspector]")
    const scrolls = []
    inspector.scrollTo = (options) => scrolls.push(options)
    const tabA = element.querySelector("[data-website-builder-target='sectionNav'][data-section-id='sec_a']")
    const tabB = element.querySelector("[data-website-builder-target='sectionNav'][data-section-id='sec_b']")
    const visible = () => [...element.querySelectorAll("article")].filter((el) => !el.classList.contains("hidden")).map((el) => el.dataset.sectionId)

    click(element.querySelector("[data-step='next']"))
    expect(visible()).toEqual(["sec_b"])
    expect(document.activeElement).toBe(tabB)
    expect(scrolls).toEqual([{ top: 0 }])

    tabA.focus()
    click(tabA)
    expect(visible()).toEqual(["sec_a"])
    expect(document.activeElement).toBe(tabA)
    expect(scrolls).toHaveLength(2)

    click(tabB)
    tabB.focus()
    click(element.querySelector("[data-step='orphan']"))
    expect(visible()).toEqual(["sec_c"])
    expect(document.activeElement).toBe(tabB)
    expect(scrolls).toHaveLength(4)
  })

  it("scrolls the preview to the section being opened or edited", async () => {
    const scrolled = []
    const node = { scrollIntoView: (options) => scrolled.push(options) }
    const doc = {
      documentElement: { dataset: {} },
      addEventListener: () => {},
      querySelector: (selector) => selector.includes("sec_b") || selector.includes("sec_1") ? node : null
    }
    ;({ application, element } = await mountController(
      "website-builder",
      Controller,
      html({
        frame: true,
        rows: 0,
        extra:
          `<article data-website-builder-target="row" data-section-id="sec_1" data-section-type="quote"><input data-prop="quote" value="One"></article>` +
          `<button data-website-builder-target="sectionNav" data-section-id="sec_b" data-action="click->website-builder#focusSection">Card grid</button>` +
          `<article data-website-builder-target="row" data-section-id="sec_b" data-section-type="card_grid"><input data-prop="heading" value="On view"></article>` +
          `<article data-website-builder-target="row" data-section-id='a"b' data-section-type="quote"></article>`
      })
    ))
    const frame = element.querySelector("[data-website-builder-target='previewFrame']")
    Object.defineProperty(frame, "contentDocument", { configurable: true, get: () => doc })
    const ctrl = controllerFor(application, element, "website-builder")

    click(element.querySelector("[data-section-id='sec_b'][data-website-builder-target='sectionNav']"))
    expect(scrolled).toEqual([{ block: "start", behavior: "smooth" }])

    element.querySelector("[data-section-id='sec_1'] input").focus()
    ctrl.markDirty()
    expect(scrolled).toHaveLength(2)
    ctrl.markDirty()
    expect(scrolled).toHaveLength(2)

    ctrl.previewLoaded()
    expect(scrolled).toHaveLength(3)

    doc.querySelector = () => ({})
    ctrl.previewLoaded()
    expect(scrolled).toHaveLength(3)

    doc.querySelector = () => null
    ctrl.previewLoaded()
    expect(scrolled).toHaveLength(3)

    Object.defineProperty(frame, "contentDocument", { configurable: true, get: () => null })
    ctrl.previewLoaded()
    Object.defineProperty(frame, "contentDocument", { configurable: true, get: () => { throw new Error("blocked") } })
    ctrl.previewLoaded()
    expect(scrolled).toHaveLength(3)

    Object.defineProperty(frame, "contentDocument", { configurable: true, get: () => doc })
    const seen = []
    doc.querySelector = (selector) => {
      seen.push(selector)
      return selector.includes("a") ? node : null
    }
    ctrl.focusSection({ currentTarget: { dataset: { sectionId: 'a"b' } } })
    expect(seen.at(-1)).toBe('[data-site-section="a\\"b"]')
    expect(scrolled).toHaveLength(4)
  })

  describe("two-level workspace outline", () => {
    beforeEach(() => {
      vi.spyOn(HTMLFormElement.prototype, "contains").mockImplementation(function (node) {
        return node === this || [...this.querySelectorAll("*")].includes(node)
      })
    })

    const leveled = ({ detailsIdentity = false } = {}) => {
      const identity = detailsIdentity
        ? `<details data-identity-panel class="hidden"><input required data-identity-field></details>`
        : `<section data-identity-panel class="hidden"><input required data-identity-field></section>`
      return `<form data-controller="website-builder" data-website-workspace>` +
        `<div data-workspace-outline>` +
        `<button type="button" data-workspace-identity-nav data-action="click->website-builder#focusIdentity">Settings</button>` +
        `<div role="tablist" data-workspace-section-nav>${sectionTab("sec_0")}${sectionTab("sec_1")}</div>` +
        `</div>` +
        `<div data-workspace-detail class="hidden">` +
        `${identity}` +
        `<div data-workspace-inspector><div data-workspace-rail data-website-builder-target="list">` +
        `${workspaceRow("sec_0", "Hero")}${workspaceRow("sec_1", "Quote", true)}` +
        `</div></div></div>` +
        `<button type="button" data-back data-action="click->website-builder#showOutline">Back</button>` +
        `</form>`
    }

    it("lands on the outline and drills into a section, identity, then back", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, leveled()))
      const outline = element.querySelector("[data-workspace-outline]")
      const detail = element.querySelector("[data-workspace-detail]")
      const identity = element.querySelector("[data-identity-panel]")
      const identityNav = element.querySelector("[data-workspace-identity-nav]")
      expect(outline.classList.contains("hidden")).toBe(false)
      expect(detail.classList.contains("hidden")).toBe(true)
      expect(identity.classList.contains("hidden")).toBe(true)

      await click(element.querySelector("[data-website-builder-target='sectionNav'][data-section-id='sec_1']"))
      expect(outline.classList.contains("hidden")).toBe(true)
      expect(detail.classList.contains("hidden")).toBe(false)
      expect(identity.classList.contains("hidden")).toBe(true)
      expect(element.querySelector("[data-website-builder-target='row'][data-section-id='sec_1']").classList.contains("hidden")).toBe(false)
      expect(element.querySelector("[data-website-builder-target='row'][data-section-id='sec_0']").classList.contains("hidden")).toBe(true)

      await click(element.querySelector("[data-back]"))
      expect(outline.classList.contains("hidden")).toBe(false)
      expect(detail.classList.contains("hidden")).toBe(true)
      expect(document.activeElement).toBe(element.querySelector("[data-section-id='sec_1'][data-website-builder-target='sectionNav']"))

      await click(identityNav)
      expect(outline.classList.contains("hidden")).toBe(true)
      expect(detail.classList.contains("hidden")).toBe(false)
      expect(identity.classList.contains("hidden")).toBe(false)
      expect(identityNav.getAttribute("aria-current")).toBe("true")
      expect(element.querySelector("[data-website-builder-target='row'][data-section-id='sec_0']").classList.contains("hidden")).toBe(true)
      expect(element.querySelector("[data-website-builder-target='row'][data-section-id='sec_1']").classList.contains("hidden")).toBe(true)

      const ctrl = controllerFor(application, element, "website-builder")
      ctrl.showOutline()
      ctrl.focusIdentity()
      expect(identity.classList.contains("hidden")).toBe(false)
    })

    it("moves a roving focus through the outline with arrow keys without drilling in", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, leveled()))
      const outline = element.querySelector("[data-workspace-outline]")
      const tabs = [...element.querySelectorAll("[data-website-builder-target='sectionNav']")]
      const preventDefault = vi.fn()

      tabs[0].focus()
      tabs[0].dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
      expect(document.activeElement).toBe(tabs[1])
      expect(tabs.map((tab) => tab.getAttribute("tabindex"))).toEqual(["-1", "0"])
      expect(outline.classList.contains("hidden")).toBe(false)

      controllerFor(application, element, "website-builder").navigateSectionTabs({ currentTarget: tabs[1], key: "Home", preventDefault })
      expect(document.activeElement).toBe(tabs[0])
      expect(tabs.map((tab) => tab.getAttribute("tabindex"))).toEqual(["0", "-1"])
      expect(preventDefault).toHaveBeenCalled()
      expect(outline.classList.contains("hidden")).toBe(false)

      await click(tabs[0])
      expect(outline.classList.contains("hidden")).toBe(true)
    })

    it("opens identity from an invalid field and a details panel", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, leveled({ detailsIdentity: true })))
      const identity = element.querySelector("[data-identity-panel]")
      const field = identity.querySelector("[data-identity-field]")
      field.dispatchEvent(new Event("invalid", { bubbles: true }))
      expect(identity.classList.contains("hidden")).toBe(false)
      expect(identity.open).toBe(true)
      expect(element.querySelector("[data-workspace-outline]").classList.contains("hidden")).toBe(true)
    })

    it("no-ops outline helpers when the two-level chrome is absent", async () => {
      ;({ application, element } = await mountController("website-builder", Controller, html({ rows: 1 })))
      const ctrl = controllerFor(application, element, "website-builder")
      ctrl.showOutline()
      ctrl.focusIdentity()
      expect(element.querySelector("[data-workspace-outline]")).toBeNull()
    })
  })

  describe("design panel styles", () => {
    const trigger = (id, key) =>
      `<button type="button" data-style-trigger data-trigger="${key}" aria-controls="ws-${id}-${key}" aria-expanded="false" data-action="click->website-builder#toggleStyle">design</button>`
    const panelOpen = (id, key) =>
      `<div id="ws-${id}-${key}" hidden data-style-panel>` +
      `<button type="button" data-reset data-action="click->website-builder#resetStyles:prevent">reset</button>` +
      `<button type="button" data-close data-action="click->website-builder#toggleStyle" aria-controls="ws-${id}-${key}">close</button>`
    const styledRow = (id = "sec_s", { custom = "#123456", picked = "" } = {}) =>
      `<article data-website-builder-target="row" data-section-id="${id}" data-section-type="hero_split">` +
      `<div data-field="headline"><label>Headline</label>${trigger(id, "headline")}<input data-prop="headline" value="Hi">` +
      panelOpen(id, "headline") +
      `<div data-style-target="headline" data-style-kind="element">` +
      `<input type="radio" name="${id}_c" data-style-prop="color" value="" ${picked ? "" : "checked"}>` +
      `<input type="radio" name="${id}_c" data-style-prop="color" value="accent" ${picked === "accent" ? "checked" : ""}>` +
      `<span><input type="radio" name="${id}_c" data-style-prop="color" value="${custom}" data-style-custom-radio>` +
      `<input type="color" value="${custom}" data-style-custom-input data-action="input->website-builder#pickStyleColor"></span>` +
      `<select data-style-prop="font"><option value=""></option><option value="inter">Inter</option></select>` +
      `</div></div></div>` +
      `<details data-section-body><summary>${trigger(id, "section")}</summary>` +
      panelOpen(id, "section") +
      `<div data-style-target="section" data-style-kind="section">` +
      `<select data-style-prop="scale"><option value=""></option><option value="lg">lg</option></select>` +
      `</div></div></details>` +
      `<div data-field="primary_label">${trigger(id, "buttons")}` +
      panelOpen(id, "buttons") +
      `<div data-style-target="buttons" data-style-kind="buttons"><select data-style-prop="shape"><option value=""></option><option value="pill">pill</option></select></div></div></div>` +
      `<div data-list>${trigger(id, "cards")}` +
      panelOpen(id, "cards") +
      `<details data-style-target="cards" data-style-kind="items"><summary>Cards<span data-style-dot class="hidden"></span></summary>` +
      `<select data-style-prop="background"><option value=""></option><option value="band">band</option></select></details>` +
      `<details data-style-target="cards.title" data-style-kind="element"><summary>Title<span data-style-dot class="hidden"></span></summary></details>` +
      `</div></div>` +
      panelOpen(id, "orphan") + `</div>` +
      `<button type="button" data-unbound data-action="click->website-builder#toggleStyle">unbound</button>` +
      `<button type="button" data-missing aria-controls="ws-missing" data-action="click->website-builder#toggleStyle">missing</button>` +
      `</article>`

    const mountStyled = async (opts = {}) => {
      ;({ application, element } = await mountController(
        "website-builder",
        Controller,
        html({ rows: 0, extra: styledRow("sec_s", opts), ...opts.html })
      ))
      return controllerFor(application, element, "website-builder")
    }

    const stylesOf = (el) => jsonValue(el).find((section) => section.id === "sec_s").props.styles
    const triggerFor = (key) => element.querySelector(`[data-trigger='${key}']`)
    const panelFor = (key) => element.querySelector(`#ws-sec_s-${key}`)

    it("omits styles when every control is on the theme default", async () => {
      const ctrl = await mountStyled()
      ctrl.markDirty()
      expect(stylesOf(element)).toBeUndefined()
      expect(triggerFor("headline").hasAttribute("data-edited")).toBe(false)
      expect(element.querySelector("[data-style-target='cards'] [data-style-dot]").classList.contains("hidden")).toBe(true)
    })

    it("serializes checked radios and chosen selects per target and flags the edited triggers", async () => {
      const ctrl = await mountStyled({ picked: "accent" })
      element.querySelector("[data-style-target='section'] select").value = "lg"
      element.querySelector("[data-style-target='cards'] select").value = "band"
      ctrl.markDirty()
      expect(stylesOf(element)).toEqual({ headline: { color: "accent" }, section: { scale: "lg" }, cards: { background: "band" } })
      expect(triggerFor("headline").hasAttribute("data-edited")).toBe(true)
      expect(triggerFor("section").hasAttribute("data-edited")).toBe(true)
      expect(triggerFor("buttons").hasAttribute("data-edited")).toBe(false)
      expect(triggerFor("cards").hasAttribute("data-edited")).toBe(true)
      expect(element.querySelector("[data-style-target='cards'] [data-style-dot]").classList.contains("hidden")).toBe(false)
      expect(element.querySelector("[data-style-target='cards.title'] [data-style-dot]").classList.contains("hidden")).toBe(true)
      expect(jsonValue(element)[0].props.headline).toBe("Hi")
    })

    it("toggleStyle opens a panel beside its element and closes it again", async () => {
      await mountStyled()
      const button = triggerFor("headline")
      await click(button)
      expect(panelFor("headline").hidden).toBe(false)
      expect(button.getAttribute("aria-expanded")).toBe("true")
      expect(panelFor("buttons").hidden).toBe(true)

      button.focus()
      await click(button)
      expect(panelFor("headline").hidden).toBe(true)
      expect(button.getAttribute("aria-expanded")).toBe("false")
      expect(document.activeElement).toBe(button)
    })

    it("toggleStyle from the close button returns focus to the trigger", async () => {
      await mountStyled()
      await click(triggerFor("buttons"))
      const close = panelFor("buttons").querySelector("[data-close]")
      close.focus()
      await click(close)
      expect(panelFor("buttons").hidden).toBe(true)
      expect(document.activeElement).toBe(triggerFor("buttons"))
    })

    it("toggleStyle opens the collapsed details around a panel without toggling it itself", async () => {
      await mountStyled()
      const details = element.querySelector("[data-section-body]")
      const event = new MouseEvent("click", { bubbles: true, cancelable: true })
      triggerFor("section").dispatchEvent(event)
      expect(event.defaultPrevented).toBe(true)
      expect(details.open).toBe(true)
      expect(panelFor("section").hidden).toBe(false)
    })

    it("toggleStyle closes a panel that has no trigger and ignores buttons without a panel", async () => {
      await mountStyled()
      const orphan = panelFor("orphan")
      orphan.hidden = false
      const close = orphan.querySelector("[data-close]")
      close.focus()
      await click(close)
      expect(orphan.hidden).toBe(true)

      await click(element.querySelector("[data-unbound]"))
      await click(element.querySelector("[data-missing]"))
      expect([...element.querySelectorAll("[data-style-panel]")].every((panel) => panel.hidden)).toBe(true)
    })

    it("pickStyleColor copies the custom color into its radio and checks it", async () => {
      await mountStyled()
      const input = element.querySelector("[data-style-custom-input]")
      input.value = "#abcdef"
      input.dispatchEvent(new Event("input", { bubbles: true }))
      const radio = element.querySelector("[data-style-custom-radio]")
      expect(radio.value).toBe("#abcdef")
      expect(radio.checked).toBe(true)
      expect(input.style.background).not.toBe("")
      expect(stylesOf(element)).toEqual({ headline: { color: "#abcdef" } })
    })

    it("pickStyleColor ignores an input without a sibling custom radio", async () => {
      const ctrl = await mountStyled()
      const loose = document.createElement("input")
      document.createElement("div").appendChild(loose)
      const spy = vi.spyOn(ctrl, "markDirty")
      ctrl.pickStyleColor({ currentTarget: loose })
      ctrl.pickStyleColor({ currentTarget: document.createElement("input") })
      expect(spy).not.toHaveBeenCalled()
    })

    it("resetStyles returns only its own panel's controls to the theme default", async () => {
      const ctrl = await mountStyled()
      const input = element.querySelector("[data-style-custom-input]")
      input.value = "#abcdef"
      input.dispatchEvent(new Event("input", { bubbles: true }))
      element.querySelector("[data-style-target='headline'] select").value = "inter"
      element.querySelector("[data-style-target='section'] select").value = "lg"
      ctrl.markDirty()
      expect(stylesOf(element)).toEqual({ headline: { color: "#abcdef", font: "inter" }, section: { scale: "lg" } })

      await click(panelFor("headline").querySelector("[data-reset]"))
      expect(stylesOf(element)).toEqual({ section: { scale: "lg" } })
      expect(element.querySelector("[data-style-prop='color'][value='']").checked).toBe(true)
      expect(input.style.background).toBe("")
      expect(triggerFor("headline").hasAttribute("data-edited")).toBe(false)
      expect(triggerFor("section").hasAttribute("data-edited")).toBe(true)
    })

    it("resetStyles no-ops outside a Design panel", async () => {
      const ctrl = await mountStyled()
      const spy = vi.spyOn(ctrl, "markDirty")
      ctrl.resetStyles({ currentTarget: document.createElement("button") })
      expect(spy).not.toHaveBeenCalled()
    })

    describe("click-to-select in the preview", () => {
      const previewDoc = () => {
        const doc = document.implementation.createHTMLDocument("preview")
        doc.body.innerHTML =
          `<section data-site-section="sec_s"><h1 data-site-el="headline">Hi</h1><p data-site-el="subhead">Sub</p>` +
          `<div data-site-el="buttons"><a href="#">Go</a></div><span data-site-el="plain">no section</span>` +
          `<h3 data-site-el="cards.title">Card</h3></section>` +
          `<span data-site-el="headline" id="orphan">orphan</span>` +
          `<section data-site-section="sec_missing"><h1 data-site-el="headline" id="ghost">Ghost</h1></section>` +
          `<p id="unmarked">text</p>`
        return doc
      }

      const mountPreview = async () => {
        const ctrl = await mountStyled({ html: { frame: true } })
        const doc = previewDoc()
        const frame = element.querySelector("[data-website-builder-target='previewFrame']")
        Object.defineProperty(frame, "contentDocument", { configurable: true, get: () => doc })
        return { ctrl, doc }
      }

      const clickIn = (el) => {
        const event = new MouseEvent("click", { bubbles: true, cancelable: true })
        el.dispatchEvent(event)
        return event
      }

      it("opens the matching Design panel, focuses its first control and outlines the element", async () => {
        const { ctrl, doc } = await mountPreview()
        ctrl.previewLoaded()
        const group = element.querySelector("[data-style-target='headline']")
        group.scrollIntoView = vi.fn()

        const event = clickIn(doc.querySelector("h1[data-site-el='headline']"))
        expect(event.defaultPrevented).toBe(true)
        expect(panelFor("headline").hidden).toBe(false)
        expect(triggerFor("headline").getAttribute("aria-expanded")).toBe("true")
        expect(group.scrollIntoView).toHaveBeenCalledWith({ block: "nearest" })
        expect(document.activeElement).toBe(group.querySelector("input:checked"))
        const headline = doc.querySelector("h1[data-site-el='headline']")
        expect(headline.style.outline).toContain("#6366f1")
        expect(headline.style.outlineOffset).toBe("4px")

        clickIn(doc.querySelector("[data-site-el='buttons'] a"))
        expect(panelFor("buttons").hidden).toBe(false)
        expect(document.activeElement).toBe(panelFor("buttons").querySelector("select"))
        expect(headline.style.outline).toBe("")
        expect(doc.querySelector("[data-site-el='buttons']").style.outline).toContain("#6366f1")
      })

      it("opens a list panel's accordion row and focuses its summary", async () => {
        const { ctrl, doc } = await mountPreview()
        ctrl.previewLoaded()
        clickIn(doc.querySelector("[data-site-el='cards.title']"))
        const group = element.querySelector("[data-style-target='cards.title']")
        expect(panelFor("cards").hidden).toBe(false)
        expect(group.open).toBe(true)
        expect(element.querySelector("[data-style-target='cards']").open).toBe(false)
        expect(document.activeElement).toBe(group.querySelector("summary"))
      })

      it("binds the preview listener once per document", async () => {
        const { ctrl, doc } = await mountPreview()
        const spy = vi.spyOn(doc, "addEventListener")
        ctrl.previewLoaded()
        ctrl.previewLoaded()
        expect(spy).toHaveBeenCalledTimes(1)
        expect(doc.documentElement.dataset.websiteBuilderPicking).toBe("true")
      })

      it("lets clicks through when nothing in the editor matches", async () => {
        const { ctrl, doc } = await mountPreview()
        ctrl.previewLoaded()
        for (const selector of ["#unmarked", "#orphan", "#ghost", "[data-site-el='subhead']", "[data-site-el='plain']"]) {
          expect(clickIn(doc.querySelector(selector)).defaultPrevented).toBe(false)
        }
        doc.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))
        expect(panelFor("headline").hidden).toBe(true)
      })

      it("skips binding without a preview document", async () => {
        const ctrl = await mountStyled({ html: { frame: true } })
        const frame = element.querySelector("[data-website-builder-target='previewFrame']")
        Object.defineProperty(frame, "contentDocument", { configurable: true, get: () => null })
        expect(() => ctrl.previewLoaded()).not.toThrow()
      })
    })
  })
})
