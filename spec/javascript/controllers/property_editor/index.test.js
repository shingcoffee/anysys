import { describe, it, expect } from "vitest"
import * as index from "controllers/property_editor/index"
import { BaseManager } from "controllers/property_editor/base_manager"
import { StepManager } from "controllers/property_editor/step_manager"
import { BranchManager } from "controllers/property_editor/branch_manager"
import { ElementIoManager } from "controllers/property_editor/element_io_manager"
import { FormBuilder } from "controllers/property_editor/form_builder"
import { TabManager } from "controllers/property_editor/tab_manager"

// index.js is a pure barrel — assert every re-export resolves to the same
// class object as its source module (no accidental re-wrapping or drops).
describe("property_editor/index barrel", () => {
  it("re-exports exactly the documented managers", () => {
    expect(Object.keys(index).sort()).toEqual(
      ["BaseManager", "BranchManager", "ElementIoManager", "FormBuilder", "StepManager", "TabManager"].sort()
    )
  })

  it("each export is the identical class from its source module", () => {
    expect(index.BaseManager).toBe(BaseManager)
    expect(index.StepManager).toBe(StepManager)
    expect(index.BranchManager).toBe(BranchManager)
    expect(index.ElementIoManager).toBe(ElementIoManager)
    expect(index.FormBuilder).toBe(FormBuilder)
    expect(index.TabManager).toBe(TabManager)
  })

  it("exports are constructable classes", () => {
    expect(typeof index.StepManager).toBe("function")
    expect(index.StepManager.prototype.constructor).toBe(StepManager)
  })
})
