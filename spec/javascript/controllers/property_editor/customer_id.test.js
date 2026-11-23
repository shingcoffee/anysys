import { describe, it, expect, beforeEach } from "vitest"
import { customerIdFromPath } from "controllers/property_editor/customer_id"

const setPath = (path) => {
  window.happyDOM?.setURL?.(`http://localhost${path}`)
  if (window.location.pathname !== path) {
    Object.defineProperty(window, "location", {
      configurable: true,
      value: { ...window.location, pathname: path },
    })
  }
}

describe("customerIdFromPath", () => {
  beforeEach(() => {
    setPath("/12345678/admin/maintenance/flowcharts/1/edit")
  })

  it("reads the 8-digit tenant id from an explicit path", () => {
    expect(customerIdFromPath("/81721200/admin/pages")).toBe("81721200")
  })

  it("returns null when the path has no tenant id", () => {
    expect(customerIdFromPath("/no-tenant/here")).toBeNull()
  })

  it("defaults to window.location.pathname", () => {
    expect(customerIdFromPath()).toBe("12345678")
  })
})
