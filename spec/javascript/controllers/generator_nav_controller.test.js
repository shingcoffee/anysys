import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/generator_nav_controller"
import { mountController } from "../support/stimulus.js"

const link = (id) => `
  <a id="${id}" data-generator-nav-target="link" data-action="click->generator-nav#activate"
     class="text-gray-600 hover:bg-gray-50 hover:text-gray-900">
    <svg class="text-gray-400"></svg>
    <span>label</span>
    <span class="text-gray-400">5</span>
  </a>`

const html = `
  <nav data-controller="generator-nav">
    <div data-generator-nav-target="group">
      <button id="toggle" data-action="click->generator-nav#toggle">Group</button>
      <svg data-generator-nav-target="chevron"></svg>
      <div data-generator-nav-target="groupContent">
        ${link("l1")}${link("l2")}
      </div>
    </div>
  </nav>`

const linkEl = (el, id) => el.querySelector(`#${id}`)

describe("generator-nav controller", () => {
  let element
  beforeEach(async () => {
    ;({ element } = await mountController("generator-nav", Controller, html))
  })

  it("activate marks the clicked link active and its icon/count", () => {
    linkEl(element, "l1").dispatchEvent(new Event("click", { bubbles: true }))
    const l1 = linkEl(element, "l1")
    expect(l1.classList.contains("bg-indigo-50")).toBe(true)
    expect(l1.classList.contains("text-indigo-700")).toBe(true)
    expect(l1.classList.contains("text-gray-600")).toBe(false)
    expect(l1.querySelector("svg").classList.contains("text-indigo-500")).toBe(true)
    const count = l1.querySelector("span:last-child")
    expect(count.classList.contains("bg-indigo-100")).toBe(true)
  })

  it("activate deactivates other links", () => {
    linkEl(element, "l1").dispatchEvent(new Event("click", { bubbles: true }))
    linkEl(element, "l2").dispatchEvent(new Event("click", { bubbles: true }))
    expect(linkEl(element, "l1").classList.contains("bg-indigo-50")).toBe(false)
    expect(linkEl(element, "l1").classList.contains("text-gray-600")).toBe(true)
    expect(linkEl(element, "l2").classList.contains("bg-indigo-50")).toBe(true)
  })

  it("toggle collapses the group content and rotates the chevron", () => {
    const content = element.querySelector("[data-generator-nav-target='groupContent']")
    const chevron = element.querySelector("[data-generator-nav-target='chevron']")
    expect(content.classList.contains("hidden")).toBe(false)

    element.querySelector("#toggle").dispatchEvent(new Event("click", { bubbles: true }))
    expect(content.classList.contains("hidden")).toBe(true)
    expect(chevron.classList.contains("rotate-90")).toBe(true)

    element.querySelector("#toggle").dispatchEvent(new Event("click", { bubbles: true }))
    expect(content.classList.contains("hidden")).toBe(false)
    expect(chevron.classList.contains("rotate-90")).toBe(false)
  })
})
