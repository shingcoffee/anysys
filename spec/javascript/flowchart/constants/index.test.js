import { describe, it, expect } from "vitest"
import * as barrel from "flowchart/constants/index"
import * as canvas from "flowchart/constants/canvas"
import * as elements from "flowchart/constants/elements"
import * as registry from "flowchart/constants/element_registry"

describe("constants/index barrel", () => {
  it("re-exports every named export from canvas, elements, and the element registry", () => {
    for (const mod of [canvas, elements, registry]) {
      for (const name of Object.keys(mod)) {
        expect(barrel, `missing re-export: ${name}`).toHaveProperty(name)
        expect(barrel[name], `re-export identity: ${name}`).toBe(mod[name])
      }
    }
  })

  it("surfaces representative constants from each module", () => {
    expect(barrel.GRID_SIZE).toBe(canvas.GRID_SIZE)
    expect(barrel.ELEMENT_COLORS).toBe(elements.ELEMENT_COLORS)
    expect(barrel.setElementCatalog).toBe(registry.setElementCatalog)
    expect(typeof barrel.getDefaultPropertiesForType).toBe("function")
    expect(typeof barrel.persistableProperties).toBe("function")
  })
})
