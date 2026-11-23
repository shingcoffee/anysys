import { describe, it, expect, beforeEach, afterEach } from "vitest"
import {
  setActionCatalog,
  getActionsByCategory,
  searchActions,
  getActionConfig,
  getSingleUseActions,
  getAllActions,
  getActionCategories,
  actionFields,
  fieldName,
} from "flowchart/constants/action_registry"
import { SAMPLE_ACTION_CATALOG, installSampleActionCatalog, clearActionCatalog } from "../../support/action_catalog.js"

beforeEach(() => installSampleActionCatalog())
afterEach(() => installSampleActionCatalog())

describe("setActionCatalog", () => {
  it("starts empty before a valid catalog is installed", () => {
    clearActionCatalog()
    expect(getAllActions()).toEqual([])
    expect(getActionCategories()).toEqual([])
    expect(getActionsByCategory()).toEqual([])
    expect(getActionConfig("find_model")).toBeUndefined()
    expect(getSingleUseActions()).toEqual([])
  })

  it("ignores payloads that lack categories and actions arrays", () => {
    const before = getAllActions()
    setActionCatalog({})
    setActionCatalog({ locale: "en" })
    setActionCatalog("nope")
    expect(getAllActions()).toBe(before)
  })

  it("null / undefined empties the store", () => {
    expect(getAllActions().length).toBeGreaterThan(0)
    setActionCatalog(null)
    expect(getAllActions()).toEqual([])
    setActionCatalog(undefined)
    expect(getAllActions()).toEqual([])
  })

  it("skips malformed category and action rows and duplicate keys", () => {
    setActionCatalog({
      categories: [null, { key: "" }, { key: 1 }, { key: "model", label: "Records" }, { key: "model", label: "Dup" }, 3],
      actions: [
        null,
        { key: "" },
        { key: 2 },
        { key: "find_model", category: "model", label: "Find", aliases: ["find"], extra: "kept" },
        { key: "find_model", category: "model", label: "Dup" },
        { key: "other", category: "missing", label: "Other", aliases: ["", 1, "find"] },
      ],
    })
    expect(getActionCategories()).toEqual([{ key: "model", label: "Records" }])
    expect(getActionConfig("find_model").label).toBe("Find")
    expect(getActionConfig("find_model").extra).toBe("kept")
    expect(getActionConfig("find").label).toBe("Find")
    expect(getAllActions().map((a) => a.key)).toEqual(["find_model", "other"])
    expect(getActionsByCategory().find((g) => g.category.key === "model").actions[0].key).toBe("find_model")
  })

  it("uses the category key as the label when label is missing", () => {
    setActionCatalog({
      categories: [{ key: "data" }],
      actions: [{ key: "assign_value", category: "data" }],
    })
    expect(getActionCategories()[0].label).toBe("data")
  })
})

describe("getAllActions", () => {
  it("returns the installed canonical actions with unique keys", () => {
    const all = getAllActions()
    expect(all.length).toBe(SAMPLE_ACTION_CATALOG.actions.length)
    const keys = all.map((a) => a.key)
    expect(new Set(keys).size).toBe(keys.length)
  })

  it("returns the same cached array reference on repeated calls", () => {
    const all = getAllActions()
    expect(getAllActions()).toBe(all)
  })
})

describe("getActionsByCategory", () => {
  it("returns one group per category, in category order", () => {
    const groups = getActionsByCategory()
    expect(groups.map((g) => g.category.key)).toEqual(SAMPLE_ACTION_CATALOG.categories.map((c) => c.key))
  })

  it("each group's actions all belong to that category", () => {
    for (const g of getActionsByCategory()) {
      for (const a of g.actions) {
        expect(a.category).toBe(g.category.key)
      }
    }
  })

  it("the union of all groups equals getAllActions()", () => {
    const flat = getActionsByCategory().flatMap((g) => g.actions)
    expect(flat.length).toBe(getAllActions().length)
  })
})

describe("getActionConfig", () => {
  it("looks up a known action by canonical key", () => {
    const first = getAllActions()[0]
    expect(getActionConfig(first.key)).toBe(first)
  })

  it("resolves aliases to the canonical row", () => {
    setActionCatalog({
      categories: [{ key: "communication", label: "Communication" }],
      actions: [{ key: "api_call", category: "communication", label: "HTTP request", aliases: ["API_call"] }],
    })
    const api = getActionConfig("api_call")
    expect(api.key).toBe("api_call")
    expect(getActionConfig("API_call")).toBe(api)
  })

  it("returns undefined for an unknown value", () => {
    expect(getActionConfig("__does_not_exist__")).toBeUndefined()
    expect(getActionConfig(undefined)).toBeUndefined()
    expect(getActionConfig(null)).toBeUndefined()
  })
})

describe("getSingleUseActions", () => {
  it("returns exactly the keys of actions flagged singleUse:true", () => {
    const expected = getAllActions().filter((a) => a.singleUse === true).map((a) => a.key)
    expect(getSingleUseActions().sort()).toEqual(expected.sort())
  })
})

describe("searchActions", () => {
  it("returns all actions for empty / non-string queries", () => {
    const all = getAllActions()
    expect(searchActions("")).toBe(all)
    expect(searchActions(null)).toBe(all)
    expect(searchActions(undefined)).toBe(all)
    expect(searchActions(42)).toBe(all)
  })

  it("is case-insensitive and matches on label", () => {
    const sample = getAllActions()[0]
    const results = searchActions(sample.label.toUpperCase())
    expect(results).toContain(sample)
  })

  it("matches on description substrings", () => {
    const sample = getAllActions().find((a) => a.description && a.description.length > 4)
    const fragment = sample.description.slice(0, 4).toLowerCase()
    expect(searchActions(fragment)).toContain(sample)
  })

  it("matches on the category label", () => {
    const cat = getActionCategories()[0]
    const results = searchActions(cat.label)
    const inCategory = getAllActions().filter((a) => a.category === cat.key)
    for (const a of inCategory) expect(results).toContain(a)
  })

  it("returns an empty array when nothing matches", () => {
    expect(searchActions("zzz_no_such_action_zzz")).toEqual([])
  })

  it("tolerates an action whose category isn't a declared category key", () => {
    const action = getAllActions()[0]
    const originalCategory = action.category
    action.category = "__stray_category_not_in_table__"
    try {
      expect(() => searchActions("anything")).not.toThrow()
    } finally {
      action.category = originalCategory
    }
  })

  it("treats missing labels and descriptions as empty strings", () => {
    setActionCatalog({
      categories: [{ key: "x", label: "" }],
      actions: [{ key: "blank", category: "x" }],
    })
    expect(searchActions("blank")).toEqual([])
    expect(searchActions("x")).toEqual([])
    getActionCategories().push({ key: "ghost" })
    expect(getActionsByCategory().at(-1).actions).toEqual([])
  })
})

describe("actionFields / fieldName", () => {
  it("returns the export fields array or []", () => {
    expect(actionFields(getActionConfig("find_model")).length).toBeGreaterThan(0)
    expect(actionFields(null)).toEqual([])
    expect(actionFields({})).toEqual([])
  })

  it("prefers name then key", () => {
    expect(fieldName({ name: "a", key: "b" })).toBe("a")
    expect(fieldName({ key: "b" })).toBe("b")
    expect(fieldName(null)).toBeUndefined()
  })
})
