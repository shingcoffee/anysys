import { describe, it, expect } from "vitest"
import * as flowchart from "flowchart/index"
import FlowchartCanvasDefault from "flowchart/index"

// index.js is a barrel re-export. Verify the public surface it promises is
// actually wired up (the app imports these names from "flowchart" / "flowchart/index").

describe("flowchart/index barrel", () => {
  it("re-exports FlowchartCanvas and the default export", () => {
    expect(typeof flowchart.FlowchartCanvas).toBe("function")
    expect(flowchart.default).toBe(flowchart.FlowchartCanvas)
    expect(FlowchartCanvasDefault).toBe(flowchart.FlowchartCanvas)
  })

  it("re-exports the renderer classes/mixins", () => {
    expect(typeof flowchart.ElementRenderer).toBe("function")
    expect(typeof flowchart.ElementRendererMixin).toBe("object")
  })

  it("re-exports connection + selection mixins/classes", () => {
    expect(typeof flowchart.ConnectionManagerMixin).toBe("object")
    expect(typeof flowchart.ConnectionRenderer).toBe("function")
    expect(flowchart.CONNECTION_STYLE).toBeTruthy()
    expect(typeof flowchart.SelectionManager).toBe("function")
    expect(typeof flowchart.SelectionManagerMixin).toBe("object")
  })

  it("re-exports drag/resize mixins", () => {
    expect(typeof flowchart.DragHandlerMixin).toBe("object")
    expect(typeof flowchart.ResizeHandlerMixin).toBe("object")
  })

  it("re-exports constants (via `export *`)", () => {
    expect(flowchart.GRID_SIZE).toBe(15)
    expect(flowchart.ELEMENT_COLORS).toBeTruthy()
    expect(flowchart.DEFAULT_ELEMENT_WIDTH).toBe(100)
  })
})
