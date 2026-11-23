import { describe, it, expect } from "vitest"
import * as barrel from "controllers/page_builder/index"

// index.js is a pure re-export barrel. Verify every symbol it promises to
// forward is actually exported (a broken/renamed source export would surface
// here as undefined).
describe("page_builder/index barrel", () => {
  const classExports = [
    "BaseManager", "UndoRedoManager", "ViewportManager", "TabManager",
    "DragDropManager", "FieldManager", "PageManager", "PropertyManager",
    "SaveManager", "KeyboardManager", "SelectionManager", "RulesManager",
    "CalculationsManager", "ZoomManager", "ContextMenuManager",
  ]

  it.each(classExports)("re-exports %s as a class", (name) => {
    expect(barrel[name]).toBeTypeOf("function")
    // Classes have a non-writable prototype.
    expect(barrel[name].prototype).toBeDefined()
  })

  it("re-exports the CSS constant (frozen object)", () => {
    expect(barrel.CSS).toBeTypeOf("object")
    expect(barrel.CSS.hidden).toBe("hidden")
    expect(Object.isFrozen(barrel.CSS)).toBe(true)
  })

  it("re-exports field-mapping constants", () => {
    expect(barrel.FIELD_TYPE_MAPPING).toBeTypeOf("object")
    expect(barrel.FIELD_ICONS).toBeTypeOf("object")
  })

  it("re-exports rules + calculations constants", () => {
    expect(Array.isArray(barrel.OPERATORS)).toBe(true)
    expect(Array.isArray(barrel.ACTION_TYPES)).toBe(true)
    expect(barrel.FORMULA_FUNCTIONS).toBeDefined()
  })

  it("exposes exactly the documented public surface (no accidental leakage)", () => {
    const expected = new Set([
      ...classExports,
      "CSS", "FIELD_TYPE_MAPPING", "FIELD_ICONS",
      "OPERATORS", "ACTION_TYPES", "FORMULA_FUNCTIONS",
    ])
    for (const key of Object.keys(barrel)) {
      expect(expected.has(key)).toBe(true)
    }
  })
})
