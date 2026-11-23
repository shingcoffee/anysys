import { describe, it, expect } from "vitest"
import * as index from "controllers/entity_form/index"

// index.js is a pure barrel — assert every documented symbol is re-exported and
// classes are constructable (they extend BaseManager, so `new X({})` succeeds).
describe("entity_form/index barrel", () => {
  it("re-exports the manager classes", () => {
    const classes = [
      "BaseManager", "TypeManager", "ValidatorManager", "TemplateBuilder",
      "SchemaManager", "ModalManager", "ConstantsManager", "ReferenceManager", "AttributeManager",
      "AssociationManager", "GroupManager", "DndManager", "ComputedManager",
    ]
    classes.forEach((name) => {
      expect(typeof index[name], name).toBe("function")
      expect(() => new index[name]({})).not.toThrow()
    })
  })

  it("re-exports shared constants + helpers", () => {
    expect(index.CSS.hidden).toBe("hidden")
    expect(typeof index.escapeHtml).toBe("function")
    expect(index.SELECTION_TYPES).toEqual(["select", "radio", "checkbox"])
    expect(index.CONFIG_TYPE_MAP.select).toBe("selection")
    expect(index.VALIDATOR_CONFIG_TYPES.inclusion).toBe("list")
    expect(index.VALIDATOR_CONFIG_LABELS.length_minimum).toBe("Minimum Length")
    expect(index.ENTITY_ENTRIES).toBe("entity_entries")
  })
})
