import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { flowchartUrl, flowchartShowUrl } from "flowchart/urls"

const URLS_A = {
  update: "/tenant-a/flowcharts/1",
  versions: "/tenant-a/flowcharts/1/versions",
  list: "/tenant-a/admin/maintenance/flowcharts.json",
  stepIoParams: "/tenant-a/flowcharts/step_actions/__ACTION__/io_params",
  elementIoParams: "/tenant-a/flowcharts/element_types/__TYPE__/io_params",
}

const URLS_B = {
  update: "/platform/flowcharts/2",
  versions: "/platform/flowcharts/2/versions",
  list: "/platform/admin/maintenance/flowcharts.json",
}

function mountCanvas(urls, extras = "") {
  const el = document.createElement("div")
  el.setAttribute("data-controller", extras ? `other ${"flowchart-canvas"} extra` : "flowchart-canvas")
  if (urls) el.setAttribute("data-flowchart-canvas-urls-value", JSON.stringify(urls))
  document.body.appendChild(el)
  return el
}

describe("flowchartUrl", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  it("reads a named URL from the controller urlsValue and applies encoded replacements", () => {
    const controller = { urlsValue: URLS_A }
    expect(flowchartUrl(controller, "update")).toBe("/tenant-a/flowcharts/1")
    expect(flowchartUrl(controller, "stepIoParams", { __ACTION__: "a/b" }))
      .toBe("/tenant-a/flowcharts/step_actions/a%2Fb/io_params")
    expect(flowchartUrl(controller, "elementIoParams", { __TYPE__: "x y" }))
      .toBe("/tenant-a/flowcharts/element_types/x%20y/io_params")
  })

  it("reads the CURRENT document canvas data attribute at call time when no controller is given", () => {
    expect(flowchartUrl(null, "update")).toBeNull()
    mountCanvas(URLS_A)
    expect(flowchartUrl(null, "versions")).toBe("/tenant-a/flowcharts/1/versions")
  })

  it("never leaks a previous editor's URLs after the canvas is replaced", () => {
    const a = mountCanvas(URLS_A)
    expect(flowchartUrl(null, "list")).toBe(URLS_A.list)

    a.remove()
    expect(flowchartUrl(null, "list")).toBeNull()

    mountCanvas(URLS_B)
    expect(flowchartUrl(null, "list")).toBe(URLS_B.list)
    expect(flowchartUrl(null, "update")).toBe(URLS_B.update)
    expect(flowchartUrl(null, "list")).not.toBe(URLS_A.list)
  })

  it("matches data-controller~=flowchart-canvas even when other tokens are present", () => {
    mountCanvas(URLS_B, "token")
    expect(flowchartUrl(null, "update")).toBe(URLS_B.update)
  })

  it("returns null for a missing name, missing canvas, invalid DOM JSON, or a non-object urls value", () => {
    expect(flowchartUrl({ urlsValue: URLS_A }, "missing")).toBeNull()
    expect(flowchartUrl(null, "update")).toBeNull()
    document.body.innerHTML = `<div data-controller="flowchart-canvas" data-flowchart-canvas-urls-value="{bad"></div>`
    expect(flowchartUrl(null, "update")).toBeNull()
    document.body.innerHTML = `<div data-controller="flowchart-canvas" data-flowchart-canvas-urls-value="true"></div>`
    expect(flowchartUrl(null, "update")).toBeNull()
    document.body.innerHTML = `<div data-controller="flowchart-canvas"></div>`
    expect(flowchartUrl(null, "update")).toBeNull()
    expect(flowchartUrl({ urlsValue: null }, "update")).toBeNull()
    mountCanvas(URLS_A)
    expect(flowchartUrl({ urlsValue: {} }, "update")).toBeNull()
  })
})

describe("flowchartShowUrl", () => {
  beforeEach(() => { document.body.innerHTML = "" })
  afterEach(() => { document.body.innerHTML = "" })

  it("inserts the flowchart id into urls.list before .json", () => {
    const controller = { urlsValue: URLS_A }
    expect(flowchartShowUrl(controller, "sf-1")).toBe("/tenant-a/admin/maintenance/flowcharts/sf-1.json")
    expect(flowchartShowUrl({ urlsValue: { list: "/c/flowcharts.json?x=1" } }, "ab"))
      .toBe("/c/flowcharts/ab.json?x=1")
  })

  it("returns null when list is missing or the id is blank", () => {
    expect(flowchartShowUrl({ urlsValue: {} }, "sf-1")).toBeNull()
    expect(flowchartShowUrl({ urlsValue: URLS_A }, "")).toBeNull()
  })
})
