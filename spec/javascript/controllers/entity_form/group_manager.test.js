// NOTE: showFloater() positions the floater with getBoundingClientRect +
// offsetWidth/offsetHeight, which return zeros in happy-dom — the pixel placement
// is Playwright's job (spec/e2e). These tests cover the pure logic: selection
// state, group CRUD on the JSON store, row-to-group assignment, and floater
// create/teardown (existence, not coordinates).
import { describe, it, expect, vi } from "vitest"
import { GroupManager } from "controllers/entity_form/group_manager"
import { buildController, fakeEvent } from "./support.js"

// Provide a schemaManager backed by a real JSON groups store so CRUD is exercised
// end-to-end, plus spies for the regroup/sync side effects.
function groupController(html = "", groups = []) {
  const { controller } = buildController(
    `<input data-entity-form-target="attributeGroupsInput" value='${JSON.stringify(groups)}'>` + html
  )
  const store = {
    readAttributeGroups: () => JSON.parse(controller.attributeGroupsInputTarget.value || "[]"),
    writeAttributeGroups: (g) => { controller.attributeGroupsInputTarget.value = JSON.stringify(g) },
    regroupAttributeRows: vi.fn(),
    syncPropertySchema: vi.fn(),
  }
  controller.schemaManager = store
  return controller
}

describe("GroupManager#colorBarClassFor", () => {
  it("maps known colors, falls back to slate", () => {
    const gm = new GroupManager({})
    expect(gm.colorBarClassFor("indigo")).toBe("bg-indigo-500")
    expect(gm.colorBarClassFor("unknown")).toBe("bg-slate-500")
  })
})

describe("GroupManager#buildGroup / nameInUse", () => {
  it("buildGroup produces an id + defaults", () => {
    const g = new GroupManager({}).buildGroup({ name: "Contact" })
    expect(g.id).toMatch(/^g_/)
    expect(g).toMatchObject({ name: "Contact", description: "", icon: "folder", color: "slate" })
  })

  it("nameInUse is case-insensitive and can exclude a group id", () => {
    const c = groupController("", [{ id: "g1", name: "Contact" }])
    const gm = new GroupManager(c)
    expect(gm.nameInUse("contact")).toBe(true)
    expect(gm.nameInUse("Contact", "g1")).toBe(false) // excluded
    expect(gm.nameInUse("Other")).toBe(false)
  })
})

describe("GroupManager selection state", () => {
  function selectionController() {
    const c = groupController(
      `<div data-entity-form-target="attributesContainer">` +
      `<div data-attribute-item data-attr-name-slug="a"><input type="checkbox"></div>` +
      `<div data-attribute-item data-attr-name-slug="b"><input type="checkbox"></div>` +
      `</div>` +
      `<div data-entity-form-target="groupingToolbar" class="hidden"></div>` +
      `<span data-entity-form-target="selectionCount"></span>`
    )
    return c
  }

  it("toggleAttributeSelection tracks slugs and reveals the toolbar with a count", () => {
    const c = selectionController()
    const gm = new GroupManager(c)
    const cb = c.element.querySelector('[data-attr-name-slug="a"] input')
    cb.checked = true
    gm.toggleAttributeSelection(fakeEvent({ target: cb }))
    expect(gm.selected.has("a")).toBe(true)
    expect(c.groupingToolbarTarget.classList.contains("hidden")).toBe(false)
    expect(c.selectionCountTarget.textContent).toBe("1")
  })

  it("unchecking removes the slug and hides the toolbar when empty", () => {
    const c = selectionController()
    const gm = new GroupManager(c)
    const cb = c.element.querySelector('[data-attr-name-slug="a"] input')
    cb.checked = true
    gm.toggleAttributeSelection(fakeEvent({ target: cb }))
    cb.checked = false
    gm.toggleAttributeSelection(fakeEvent({ target: cb }))
    expect(gm.selected.size).toBe(0)
    expect(c.groupingToolbarTarget.classList.contains("hidden")).toBe(true)
  })

  it("clearAttributeSelection unchecks all + empties the set", () => {
    const c = selectionController()
    const gm = new GroupManager(c)
    c.element.querySelectorAll('input[type="checkbox"]').forEach((cb) => { cb.checked = true; gm.selected.add(cb.closest("[data-attribute-item]").dataset.attrNameSlug) })
    gm.clearAttributeSelection()
    expect(gm.selected.size).toBe(0)
    expect([...c.element.querySelectorAll('input[type="checkbox"]')].every((cb) => !cb.checked)).toBe(true)
  })
})

describe("GroupManager#assignSelectedToGroup", () => {
  it("stamps the group id onto selected rows + inputs, then regroups/syncs/clears", () => {
    const c = groupController(
      `<div data-entity-form-target="attributesContainer">` +
      `<div data-attribute-item data-attr-name-slug="a"><input type="checkbox"><input data-input="group_id" value=""></div>` +
      `<div data-attribute-item data-attr-name-slug="b"><input type="checkbox"><input data-input="group_id" value=""></div>` +
      `</div>`
    )
    const gm = new GroupManager(c)
    gm.selected.add("a")
    gm.assignSelectedToGroup("g5")
    const rowA = c.element.querySelector('[data-attr-name-slug="a"]')
    const rowB = c.element.querySelector('[data-attr-name-slug="b"]')
    expect(rowA.getAttribute("data-attr-group-id")).toBe("g5")
    expect(rowA.querySelector('input[data-input="group_id"]').value).toBe("g5")
    expect(rowB.getAttribute("data-attr-group-id")).toBeNull() // untouched
    expect(c.schemaManager.regroupAttributeRows).toHaveBeenCalled()
    expect(c.schemaManager.syncPropertySchema).toHaveBeenCalled()
    expect(gm.selected.size).toBe(0)
  })
})

describe("GroupManager#deleteGroup", () => {
  it("drops the group from the store and orphans its rows", () => {
    const c = groupController(
      `<div data-entity-form-target="attributesContainer">` +
      `<div data-attribute-item data-attr-group-id="g1"><input data-input="group_id" value="g1"></div>` +
      `</div>`,
      [{ id: "g1", name: "G1" }, { id: "g2", name: "G2" }]
    )
    new GroupManager(c).deleteGroup(fakeEvent({ currentTarget: { getAttribute: () => "g1" } }))
    expect(c.schemaManager.readAttributeGroups().map((g) => g.id)).toEqual(["g2"])
    const row = c.element.querySelector("[data-attribute-item]")
    expect(row.getAttribute("data-attr-group-id")).toBe("")
    expect(row.querySelector('input[data-input="group_id"]').value).toBe("")
  })

  it("no-ops when the group id is empty", () => {
    const c = groupController("", [{ id: "g1", name: "G1" }])
    new GroupManager(c).deleteGroup(fakeEvent({ currentTarget: { getAttribute: () => "" } }))
    expect(c.schemaManager.readAttributeGroups().length).toBe(1)
  })
})

describe("GroupManager#saveGroupEdit", () => {
  function editController(groups = [], name = "") {
    const c = groupController(
      `<div data-entity-form-target="attributesContainer"></div>` +
      `<div data-entity-form-target="groupEditModal"></div>` +
      `<input data-entity-form-target="groupEditName" value="${name}">` +
      `<textarea data-entity-form-target="groupEditDescription"></textarea>`,
      groups
    )
    // happy-dom inputs may lack constraint-validation methods; stub them.
    const input = c.groupEditNameTarget
    input.setCustomValidity = vi.fn()
    input.reportValidity = vi.fn()
    return c
  }

  it("create mode: appends a new group and assigns the current selection", () => {
    const c = editController([], "Billing")
    const gm = new GroupManager(c)
    gm.saveGroupEdit(fakeEvent())
    const groups = c.schemaManager.readAttributeGroups()
    expect(groups.length).toBe(1)
    expect(groups[0].name).toBe("Billing")
    expect(c.groupEditModalTarget.classList.contains("hidden")).toBe(true)
  })

  it("edit mode: updates the existing group in place", () => {
    const c = editController([{ id: "g1", name: "Old", color: "slate", icon: "folder" }], "New Name")
    const gm = new GroupManager(c)
    gm.editingGroupId = "g1"
    gm.colorChoice = "rose"
    gm.saveGroupEdit(fakeEvent())
    const g = c.schemaManager.readAttributeGroups()[0]
    expect(g.name).toBe("New Name")
    expect(g.color).toBe("rose")
    expect(c.schemaManager.regroupAttributeRows).toHaveBeenCalled()
  })

  it("rejects a blank name via the constraint API", () => {
    const c = editController([], "   ")
    const gm = new GroupManager(c)
    gm.saveGroupEdit(fakeEvent())
    expect(c.groupEditNameTarget.setCustomValidity).toHaveBeenCalledWith("Group name is required")
    expect(c.groupEditNameTarget.reportValidity).toHaveBeenCalled()
    expect(c.schemaManager.readAttributeGroups().length).toBe(0)
  })

  it("rejects a duplicate name", () => {
    const c = editController([{ id: "g1", name: "Contact" }], "contact")
    const gm = new GroupManager(c)
    gm.saveGroupEdit(fakeEvent())
    expect(c.groupEditNameTarget.setCustomValidity).toHaveBeenCalledWith("Group name must be unique")
    expect(c.schemaManager.readAttributeGroups().length).toBe(1)
  })
})

describe("GroupManager#chooseGroup", () => {
  it("assigns the selection to the chosen group and closes the floater", () => {
    const c = groupController(`<div data-entity-form-target="attributesContainer"></div>`)
    const gm = new GroupManager(c)
    const assign = vi.spyOn(gm, "assignSelectedToGroup")
    const close = vi.spyOn(gm, "closeFloater")
    gm.chooseGroup(fakeEvent({ currentTarget: { getAttribute: () => "g9" } }))
    expect(assign).toHaveBeenCalledWith("g9")
    expect(close).toHaveBeenCalled()
  })

  it("empty group id assigns null (ungrouped)", () => {
    const c = groupController(`<div data-entity-form-target="attributesContainer"></div>`)
    const gm = new GroupManager(c)
    const assign = vi.spyOn(gm, "assignSelectedToGroup")
    gm.chooseGroup(fakeEvent({ currentTarget: { getAttribute: () => "" } }))
    expect(assign).toHaveBeenCalledWith(null)
  })
})

describe("GroupManager icon/color selection", () => {
  it("selectGroupIcon updates iconChoice and toggles the active ring", () => {
    const c = groupController(
      `<div data-entity-form-target="groupEditIcon">` +
      `<button class="group-icon-option" data-icon-key="folder"></button>` +
      `<button class="group-icon-option" data-icon-key="star"></button>` +
      `</div>`
    )
    const gm = new GroupManager(c)
    gm.selectGroupIcon(fakeEvent({ currentTarget: { getAttribute: () => "star" } }))
    expect(gm.iconChoice).toBe("star")
    const star = c.groupEditIconTarget.querySelector('[data-icon-key="star"]')
    expect(star.classList.contains("ring-accent")).toBe(true)
  })

  it("selectGroupColor updates colorChoice and toggles the active ring", () => {
    const c = groupController(
      `<div data-entity-form-target="groupEditColor">` +
      `<button class="group-color-option" data-color-key="slate"></button>` +
      `<button class="group-color-option" data-color-key="rose"></button>` +
      `</div>`
    )
    const gm = new GroupManager(c)
    gm.selectGroupColor(fakeEvent({ currentTarget: { getAttribute: () => "rose" } }))
    expect(gm.colorChoice).toBe("rose")
    expect(c.groupEditColorTarget.querySelector('[data-color-key="rose"]').classList.contains("ring-2")).toBe(true)
  })
})

describe("GroupManager#escapeHtml", () => {
  it("escapes the five HTML-significant characters", () => {
    expect(new GroupManager({}).escapeHtml(`<a b="c">&'`)).toBe("&lt;a b=&quot;c&quot;&gt;&amp;&#39;")
  })
})

describe("GroupManager floater teardown (geometry positioning is Playwright's job)", () => {
  it("openGroupMenu creates a floater; closeFloater removes it", () => {
    const c = groupController(``)
    const gm = new GroupManager(c)
    const anchor = document.createElement("button")
    anchor.getBoundingClientRect = () => ({ left: 0, top: 0, bottom: 0, right: 0 })
    c.element.appendChild(anchor)
    gm.openGroupMenu(fakeEvent({ currentTarget: anchor, stopPropagation: () => {} }))
    expect(c.element.querySelector("[data-entity-form-floater]")).not.toBeNull()
    gm.closeFloater()
    expect(c.element.querySelector("[data-entity-form-floater]")).toBeNull()
  })

  it("clamps the floater to the viewport when it would overflow the edges", () => {
    const c = groupController(``)
    const gm = new GroupManager(c)
    const anchor = document.createElement("button")
    // A far bottom-right anchor forces both the right- and bottom-edge clamps.
    anchor.getBoundingClientRect = () => ({ left: 500, top: 500, bottom: 520, right: 560 })
    c.element.appendChild(anchor)
    const iw = window.innerWidth, ih = window.innerHeight
    window.innerWidth = 100
    window.innerHeight = 100
    try {
      gm.showFloater(anchor, "<ul></ul>")
      const f = c.element.querySelector("[data-entity-form-floater]")
      expect(f.style.left).toBe("92px") // max(8, 100 - 0 - 8)
      expect(f.style.top).toBe("496px") // max(8, rect.top(500) - fh(0) - 4)
    } finally {
      window.innerWidth = iw
      window.innerHeight = ih
    }
  })

  it("the outside-click handler closes the floater; an inside click keeps it", () => {
    vi.useFakeTimers()
    try {
      const c = groupController(``)
      const gm = new GroupManager(c)
      const anchor = document.createElement("button")
      anchor.getBoundingClientRect = () => ({ left: 0, top: 0, bottom: 0, right: 0 })
      c.element.appendChild(anchor)
      gm.showFloater(anchor, "<ul><li id='inside'>x</li></ul>")
      vi.runAllTimers() // register the document click listener
      const floater = c.element.querySelector("[data-entity-form-floater]")

      // Click inside -> stays open
      gm._closeFloaterHandler({ target: floater.querySelector("#inside") })
      expect(c.element.querySelector("[data-entity-form-floater]")).not.toBeNull()

      // Click outside -> closes
      gm._closeFloaterHandler({ target: document.body })
      expect(c.element.querySelector("[data-entity-form-floater]")).toBeNull()
    } finally {
      vi.useRealTimers()
    }
  })
})

describe("GroupManager selection key fallbacks", () => {
  it("falls back through name-slug -> name -> empty string", () => {
    const c = groupController(
      `<div data-entity-form-target="attributesContainer">` +
      `<div data-attribute-item data-attr-name="OnlyName"><input type="checkbox"></div>` +
      `<div data-attribute-item><input type="checkbox"></div>` +
      `</div>` +
      `<div data-entity-form-target="groupingToolbar" class="hidden"></div>`
    )
    const gm = new GroupManager(c)
    const [nameOnly, neither] = c.element.querySelectorAll('input[type="checkbox"]')
    nameOnly.checked = true
    gm.toggleAttributeSelection(fakeEvent({ target: nameOnly }))
    expect(gm.selected.has("OnlyName")).toBe(true)
    neither.checked = true
    gm.toggleAttributeSelection(fakeEvent({ target: neither }))
    expect(gm.selected.has("")).toBe(true)
  })

  it("toggleAttributeSelection ignores clicks outside a row", () => {
    const c = groupController(`<div data-entity-form-target="attributesContainer"></div>`)
    const gm = new GroupManager(c)
    gm.toggleAttributeSelection(fakeEvent({ target: document.createElement("span") }))
    expect(gm.selected.size).toBe(0)
  })
})

describe("GroupManager#openMoveToGroup / openNewGroupModal / editGroup", () => {
  function menuController(groups = []) {
    const c = groupController(
      `<div data-entity-form-target="attributesContainer"></div>` +
      `<div data-entity-form-target="groupEditModal" class="hidden"></div>` +
      `<input data-entity-form-target="groupEditName">` +
      `<textarea data-entity-form-target="groupEditDescription"></textarea>` +
      `<h2 data-entity-form-target="groupModalTitle"></h2>` +
      `<button data-entity-form-target="groupModalSubmit"></button>` +
      `<div data-entity-form-target="groupEditIcon"><button class="group-icon-option" data-icon-key="folder"></button></div>` +
      `<div data-entity-form-target="groupEditColor"><button class="group-color-option" data-color-key="slate"></button></div>`,
      groups
    )
    const input = c.groupEditNameTarget
    input.setCustomValidity = vi.fn()
    input.focus = vi.fn()
    return c
  }

  it("openMoveToGroup builds a floater menu listing the groups", () => {
    const c = menuController([{ id: "g1", name: "Billing", color: "rose" }])
    const gm = new GroupManager(c)
    const anchor = document.createElement("button")
    anchor.getBoundingClientRect = () => ({ left: 0, top: 0, bottom: 0, right: 0 })
    c.element.appendChild(anchor)
    gm.openMoveToGroup(fakeEvent({ currentTarget: anchor }))
    const floater = c.element.querySelector("[data-entity-form-floater]")
    expect(floater).not.toBeNull()
    expect(floater.textContent).toContain("Billing")
    expect(floater.textContent).toContain("Ungrouped")
    expect(floater.textContent).toContain("New group")
  })

  it("openNewGroupModal resets create-mode state and opens the modal", () => {
    const c = menuController([])
    const gm = new GroupManager(c)
    gm.editingGroupId = "stale"
    gm.openNewGroupModal(fakeEvent())
    expect(gm.editingGroupId).toBeNull()
    expect(gm.iconChoice).toBe("folder")
    expect(c.groupModalTitleTarget.textContent).toBe("New Group")
    expect(c.groupModalSubmitTarget.textContent).toBe("Create Group")
    expect(c.groupEditModalTarget.classList.contains("hidden")).toBe(false)
  })

  it("editGroup loads the group into the modal in edit mode", () => {
    const c = menuController([{ id: "g1", name: "Billing", description: "Money", icon: "star", color: "rose" }])
    const gm = new GroupManager(c)
    gm.editGroup(fakeEvent({ currentTarget: { getAttribute: () => "g1" } }))
    expect(gm.editingGroupId).toBe("g1")
    expect(c.groupEditNameTarget.value).toBe("Billing")
    expect(c.groupEditDescriptionTarget.value).toBe("Money")
    expect(gm.iconChoice).toBe("star")
    expect(gm.colorChoice).toBe("rose")
    expect(c.groupModalTitleTarget.textContent).toBe("Edit Group")
    expect(c.groupEditModalTarget.classList.contains("hidden")).toBe(false)
  })

  it("editGroup bails for an unknown group id", () => {
    const c = menuController([{ id: "g1", name: "Billing" }])
    const gm = new GroupManager(c)
    gm.editGroup(fakeEvent({ currentTarget: { getAttribute: () => "nope" } }))
    expect(gm.editingGroupId).toBeNull()
    expect(c.groupEditModalTarget.classList.contains("hidden")).toBe(true)
  })

  it("editGroup applies default icon/color/description for a bare group", () => {
    const c = menuController([{ id: "g1", name: "Bare" }])
    const gm = new GroupManager(c)
    gm.iconChoice = "star"
    gm.colorChoice = "rose"
    gm.editGroup(fakeEvent({ currentTarget: { getAttribute: () => "g1" } }))
    expect(gm.iconChoice).toBe("folder") // defaulted
    expect(gm.colorChoice).toBe("slate") // defaulted
    expect(c.groupEditDescriptionTarget.value).toBe("") // defaulted
  })
})

describe("GroupManager refresh helpers without targets", () => {
  it("refreshGroupIconSelection / refreshGroupColorSelection bail when their targets are absent", () => {
    const c = groupController(``)
    const gm = new GroupManager(c)
    expect(() => gm.refreshGroupIconSelection()).not.toThrow()
    expect(() => gm.refreshGroupColorSelection()).not.toThrow()
  })
})

describe("GroupManager#saveGroupEdit extra branches", () => {
  it("bails without a name target", () => {
    const c = groupController(``)
    expect(() => new GroupManager(c).saveGroupEdit(fakeEvent())).not.toThrow()
  })

  it("edit mode leaves non-matching groups untouched and works without a description target", () => {
    const c = groupController(
      `<div data-entity-form-target="attributesContainer"></div>` +
      `<div data-entity-form-target="groupEditModal"></div>` +
      `<input data-entity-form-target="groupEditName" value="Renamed">`,
      [{ id: "g1", name: "One" }, { id: "g2", name: "Two" }]
    )
    c.groupEditNameTarget.setCustomValidity = vi.fn()
    const gm = new GroupManager(c)
    gm.editingGroupId = "g2"
    gm.saveGroupEdit(fakeEvent())
    const groups = c.schemaManager.readAttributeGroups()
    expect(groups.find((g) => g.id === "g1").name).toBe("One") // untouched
    expect(groups.find((g) => g.id === "g2").name).toBe("Renamed")
    expect(groups.find((g) => g.id === "g2").description).toBe("") // no description target
  })
})

describe("GroupManager#deleteGroup CSS.escape branches", () => {
  const rowsHtml =
    `<div data-entity-form-target="attributesContainer">` +
    `<div data-attribute-item data-attr-group-id="g1"><input data-input="group_id" value="g1"></div>` +
    `</div>`

  it("uses CSS.escape when available", () => {
    const saved = globalThis.CSS
    globalThis.CSS = { escape: (s) => s }
    try {
      const c = groupController(rowsHtml, [{ id: "g1", name: "G1" }])
      new GroupManager(c).deleteGroup(fakeEvent({ currentTarget: { getAttribute: () => "g1" } }))
      expect(c.element.querySelector("[data-attribute-item]").getAttribute("data-attr-group-id")).toBe("")
    } finally {
      globalThis.CSS = saved
    }
  })

  it("falls back to manual quoting when CSS.escape is unavailable", () => {
    const saved = globalThis.CSS
    globalThis.CSS = undefined
    try {
      const c = groupController(rowsHtml, [{ id: "g1", name: "G1" }])
      new GroupManager(c).deleteGroup(fakeEvent({ currentTarget: { getAttribute: () => "g1" } }))
      expect(c.element.querySelector("[data-attribute-item]").getAttribute("data-attr-group-id")).toBe("")
    } finally {
      globalThis.CSS = saved
    }
  })
})

describe("GroupManager#assignSelectedToGroup null group + missing input", () => {
  it("assigns ungrouped (null) and tolerates rows without a group_id input", () => {
    const c = groupController(
      `<div data-entity-form-target="attributesContainer">` +
      `<div data-attribute-item data-attr-name-slug="a"></div>` + // no group_id input
      `</div>`
    )
    const gm = new GroupManager(c)
    gm.selected.add("a")
    gm.assignSelectedToGroup(null)
    expect(c.element.querySelector('[data-attr-name-slug="a"]').getAttribute("data-attr-group-id")).toBe("")
  })

  it("resolves the row key via name fallback and clears its input when assigning null", () => {
    const c = groupController(
      `<div data-entity-form-target="attributesContainer">` +
      `<div data-attribute-item data-attr-name="OnlyName"><input data-input="group_id" value="g9"></div>` + // name-only + input
      `<div data-attribute-item></div>` + // neither slug nor name -> key ""
      `</div>`
    )
    const gm = new GroupManager(c)
    gm.selected.add("OnlyName")
    gm.selected.add("")
    gm.assignSelectedToGroup(null)
    const [named, blank] = c.element.querySelectorAll("[data-attribute-item]")
    expect(named.getAttribute("data-attr-group-id")).toBe("")
    expect(named.querySelector('input[data-input="group_id"]').value).toBe("") // groupId || ""
    expect(blank.getAttribute("data-attr-group-id")).toBe("")
  })
})

describe("GroupManager#saveGroupEdit empty name value", () => {
  it("rejects a truly empty name (|| '' branch)", () => {
    const c = groupController(
      `<div data-entity-form-target="groupEditModal"></div>` +
      `<input data-entity-form-target="groupEditName">`, // value attribute absent -> ""
      []
    )
    c.groupEditNameTarget.setCustomValidity = vi.fn()
    c.groupEditNameTarget.reportValidity = vi.fn()
    new GroupManager(c).saveGroupEdit(fakeEvent())
    expect(c.groupEditNameTarget.setCustomValidity).toHaveBeenCalledWith("Group name is required")
    expect(c.schemaManager.readAttributeGroups().length).toBe(0)
  })
})
