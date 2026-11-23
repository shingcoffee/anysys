import { describe, it, expect } from "vitest"
import { SchemaManager } from "controllers/entity_form/schema_manager"
import { TemplateBuilder } from "controllers/entity_form/template_builder"
import { TypeManager } from "controllers/entity_form/type_manager"
import { ValidatorManager } from "controllers/entity_form/validator_manager"
import { buildController } from "./support.js"

function schema(html = "", values = {}) {
  const { controller } = buildController(html, { values: { attributeIndex: 0, ...values } })
  controller.typeManager = new TypeManager(controller)
  controller.validatorManager = new ValidatorManager(controller)
  controller.schemaManager = new SchemaManager(controller)
  controller.templateBuilder = new TemplateBuilder(controller)
  return controller
}

describe("SchemaManager#normalizeVisibility", () => {
  const sm = new SchemaManager({})
  it("defaults every scope to true", () => {
    expect(sm.normalizeVisibility(null)).toEqual({ admin: true, member: true, public: true })
    expect(sm.normalizeVisibility("nope")).toEqual({ admin: true, member: true, public: true })
  })
  it("only an explicit false disables a scope", () => {
    expect(sm.normalizeVisibility({ admin: false, member: true })).toEqual({ admin: false, member: true, public: true })
  })
})

describe("SchemaManager#coerceValidatorApply", () => {
  it("forces apply false when visibility is false", () => {
    const { controller } = buildController("")
    const sm = new SchemaManager(controller)
    expect(sm.coerceValidatorApply(
      { admin: false, member: true, public: false },
      { admin: true, member: true, public: true }
    )).toEqual({ admin: false, member: true, public: false })
  })

  it("keeps apply false when visibility is true", () => {
    const { controller } = buildController("")
    const sm = new SchemaManager(controller)
    expect(sm.coerceValidatorApply(
      { admin: true, member: true, public: true },
      { admin: true, member: false, public: true }
    )).toEqual({ admin: true, member: false, public: true })
  })

  it("defaults missing maps via normalizeVisibility then coerces", () => {
    const { controller } = buildController("")
    const sm = new SchemaManager(controller)
    expect(sm.coerceValidatorApply({ public: false }, null)).toEqual({
      admin: true, member: true, public: false
    })
  })

  it("forces apply false when editable is false even if visibility and apply are true", () => {
    const { controller } = buildController("")
    const sm = new SchemaManager(controller)
    expect(sm.coerceValidatorApply(
      { admin: true, member: true, public: true },
      { admin: true, member: true, public: true },
      { admin: true, member: false, public: true }
    )).toEqual({ admin: true, member: false, public: true })
  })
})

describe("SchemaManager#coerceEditable", () => {
  it("forces editable false when visibility is false", () => {
    const sm = new SchemaManager({})
    expect(sm.coerceEditable(
      { admin: false, member: true, public: false },
      { admin: true, member: true, public: true }
    )).toEqual({ admin: false, member: true, public: false })
  })

  it("keeps editable false when visibility is true", () => {
    const sm = new SchemaManager({})
    expect(sm.coerceEditable(
      { admin: true, member: true, public: true },
      { admin: true, member: false, public: true }
    )).toEqual({ admin: true, member: false, public: true })
  })

  it("defaults missing maps via normalizeVisibility then coerces", () => {
    const sm = new SchemaManager({})
    expect(sm.coerceEditable({ public: false }, null)).toEqual({
      admin: true, member: true, public: false
    })
  })
})

describe("SchemaManager#shouldStoreEditable", () => {
  const sm = new SchemaManager({})

  it("stores when a visible admin audience cannot edit", () => {
    expect(sm.shouldStoreEditable(
      { admin: true, member: false, public: false },
      { admin: false, member: true, public: true }
    )).toBe(true)
  })

  it("stores when a visible member audience cannot edit", () => {
    expect(sm.shouldStoreEditable(
      { admin: true, member: true, public: true },
      { admin: true, member: false, public: true }
    )).toBe(true)
  })

  it("stores when a visible public audience cannot edit", () => {
    expect(sm.shouldStoreEditable(
      { admin: true, member: true, public: true },
      { admin: true, member: true, public: false }
    )).toBe(true)
  })

  it("omits when every visible audience can edit", () => {
    expect(sm.shouldStoreEditable(
      { admin: true, member: true, public: false },
      { admin: true, member: true, public: false }
    )).toBe(false)
  })

  it("omits when only a hidden audience cannot edit", () => {
    expect(sm.shouldStoreEditable(
      { admin: true, member: true, public: false },
      { admin: true, member: true, public: false }
    )).toBe(false)
  })
})

describe("SchemaManager JSON parsers", () => {
  const sm = new SchemaManager({})
  it("parseVisibilityJson: object or null", () => {
    expect(sm.parseVisibilityJson('{"admin":false}')).toEqual({ admin: false })
    expect(sm.parseVisibilityJson("")).toBeNull()
    expect(sm.parseVisibilityJson("[1,2]")).toEqual([1, 2]) // arrays are objects
    expect(sm.parseVisibilityJson("bad")).toBeNull()
    expect(sm.parseVisibilityJson("123")).toBeNull() // valid JSON but not an object
  })
  it("parseValidatorsJson: array or []", () => {
    expect(sm.parseValidatorsJson('["a"]')).toEqual(["a"])
    expect(sm.parseValidatorsJson('{"x":1}')).toEqual([])
    expect(sm.parseValidatorsJson("")).toEqual([])
    expect(sm.parseValidatorsJson("bad")).toEqual([])
  })
  it("parseConfigJson: object or null", () => {
    expect(sm.parseConfigJson('{"a":1}')).toEqual({ a: 1 })
    expect(sm.parseConfigJson("null")).toBeNull()
    expect(sm.parseConfigJson("")).toBeNull()
    expect(sm.parseConfigJson("bad")).toBeNull()
    expect(sm.parseConfigJson("123")).toBeNull() // valid JSON but not an object
  })
})

describe("SchemaManager attribute-groups round trip", () => {
  it("reads [] when input is missing, absent, or malformed; writes back JSON", () => {
    const empty = schema()
    expect(empty.schemaManager.readAttributeGroups()).toEqual([])

    const c = schema(`<input data-entity-form-target="attributeGroupsInput" value="bad json">`)
    expect(c.schemaManager.readAttributeGroups()).toEqual([]) // parse error -> []
    c.schemaManager.writeAttributeGroups([{ id: "g1", name: "G" }])
    expect(JSON.parse(c.attributeGroupsInputTarget.value)).toEqual([{ id: "g1", name: "G" }])
    expect(c.schemaManager.readAttributeGroups()).toEqual([{ id: "g1", name: "G" }])
  })

  it("readAttributeGroups coerces a non-array JSON payload to []", () => {
    const c = schema(`<input data-entity-form-target="attributeGroupsInput" value='{"x":1}'>`)
    expect(c.schemaManager.readAttributeGroups()).toEqual([])
  })

  it("readAttributeGroups treats an empty input value as []", () => {
    const c = schema(`<input data-entity-form-target="attributeGroupsInput" value="">`)
    expect(c.schemaManager.readAttributeGroups()).toEqual([])
  })

  it("writeAttributeGroups no-ops without an attributeGroupsInput target", () => {
    expect(() => schema().schemaManager.writeAttributeGroups([{ id: "a" }])).not.toThrow()
  })
})

describe("SchemaManager#extractAttributeFromRow", () => {
  it("reads hidden inputs, defaults html_type, derives slug, normalizes visibility", () => {
    const c = schema(
      `<div data-attribute-item data-attr-group-id="g1">` +
      `<input data-input="name" value="Full Name">` +
      `<input data-input="display_label" value="">` +
      `<input data-input="validators" value='["presence"]'>` +
      `<input data-input="visibility" value='{"public":false}'>` +
      `<input data-input="config" value="null">` +
      `<input data-input="group_id" value="g1">` +
      `</div>`
    )
    const row = c.element.querySelector("[data-attribute-item]")
    expect(c.schemaManager.extractAttributeFromRow(row)).toEqual({
      name: "Full Name",
      name_slug: "full_name",
      display_label: "Full Name",
      html_type: "text",
      description: "",
      validators: ["presence"],
      visibility: { admin: true, member: true, public: false },
      validator_apply: { admin: true, member: true, public: false },
      group_id: "g1",
      config: null,
    })
    expect(c.schemaManager.extractAttributeFromRow(row)).not.toHaveProperty("editable")
  })

  it("includes editable only when a visible audience cannot edit", () => {
    const stored = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Order Number">` +
      `<input data-input="visibility" value='{"admin":true,"member":true,"public":true}'>` +
      `<input data-input="editable" value='{"admin":true,"member":false,"public":false}'>` +
      `<input data-input="validator_apply" value='{"admin":true,"member":true,"public":true}'>` +
      `</div>`
    )
    expect(stored.schemaManager.extractAttributeFromRow(
      stored.element.querySelector("[data-attribute-item]")
    )).toMatchObject({
      editable: { admin: true, member: false, public: false },
      validator_apply: { admin: true, member: false, public: false },
    })
  })

  it("omits editable when the hidden map is all-on for visible audiences", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Email">` +
      `<input data-input="visibility" value='{"admin":true,"member":true,"public":true}'>` +
      `<input data-input="editable" value='{"admin":true,"member":true,"public":true}'>` +
      `</div>`
    )
    expect(c.schemaManager.extractAttributeFromRow(
      c.element.querySelector("[data-attribute-item]")
    )).not.toHaveProperty("editable")
  })

  it("omits editable on Computed rows even when a visible audience cannot edit", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Average Score">` +
      `<input data-input="type" value="Computed">` +
      `<input data-input="editable" value='{"admin":true,"member":false,"public":false}'>` +
      `</div>`
    )
    expect(c.schemaManager.extractAttributeFromRow(
      c.element.querySelector("[data-attribute-item]")
    )).not.toHaveProperty("editable")
  })

  it("returns null when the row has no name", () => {
    const c = schema(`<div data-attribute-item><input data-input="name" value="  "></div>`)
    expect(c.schemaManager.extractAttributeFromRow(c.element.querySelector("[data-attribute-item]"))).toBeNull()
  })

  it("falls back to data-attr-* attributes when hidden inputs are absent", () => {
    const c = schema(`<div data-attribute-item data-attr-name="X" data-attr-name-slug="x"></div>`)
    const attr = c.schemaManager.extractAttributeFromRow(c.element.querySelector("[data-attribute-item]"))
    expect(attr.name).toBe("X")
    expect(attr.name_slug).toBe("x")
  })

  it("omits type when the hidden type input is blank so data attributes keep their current shape", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Age">` +
      `<input data-input="type" value="">` +
      `</div>`
    )
    const attr = c.schemaManager.extractAttributeFromRow(c.element.querySelector("[data-attribute-item]"))
    expect(attr).not.toHaveProperty("type")
    expect(attr).not.toHaveProperty("readonly")
    expect(attr).not.toHaveProperty("storage")
  })

  it("includes a non-empty type and marks Computed rows as computed + readonly", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Average Score">` +
      `<input data-input="type" value="Computed">` +
      `</div>`
    )
    expect(c.schemaManager.extractAttributeFromRow(c.element.querySelector("[data-attribute-item]"))).toMatchObject({
      type: "Computed",
      readonly: true,
      storage: "computed",
    })
  })

  it("includes a non-Computed type without readonly/storage", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Title">` +
      `<input data-input="type" value="String">` +
      `</div>`
    )
    const attr = c.schemaManager.extractAttributeFromRow(c.element.querySelector("[data-attribute-item]"))
    expect(attr.type).toBe("String")
    expect(attr).not.toHaveProperty("readonly")
    expect(attr).not.toHaveProperty("storage")
  })

  it("includes owner: true only when the hidden owner input is true", () => {
    const flagged = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Student">` +
      `<input data-input="owner" value="true">` +
      `</div>`
    )
    expect(flagged.schemaManager.extractAttributeFromRow(
      flagged.element.querySelector("[data-attribute-item]")
    ).owner).toBe(true)

    const omitted = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Student">` +
      `<input data-input="owner" value="">` +
      `</div>`
    )
    expect(omitted.schemaManager.extractAttributeFromRow(
      omitted.element.querySelector("[data-attribute-item]")
    )).not.toHaveProperty("owner")
  })

  const lifecycleRow = (htmlType, lifecycle) => {
    const c = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Status">` +
      `<input data-input="html_type" value="${htmlType}">` +
      `<input data-input="lifecycle" value='${lifecycle}'>` +
      `</div>`
    )
    return c.schemaManager.extractAttributeFromRow(c.element.querySelector("[data-attribute-item]"))
  }
  const transitions = '{"transitions":[{"from":"draft","to":"submitted","by":["member"]}]}'

  it("keeps the stored lifecycle on select and radio rows", () => {
    expect(lifecycleRow("select", transitions).lifecycle).toEqual({
      transitions: [{ from: "draft", to: "submitted", by: ["member"] }],
    })
    expect(lifecycleRow("radio", transitions).lifecycle).toEqual({
      transitions: [{ from: "draft", to: "submitted", by: ["member"] }],
    })
  })

  it("drops the lifecycle once the row is no longer a select or radio", () => {
    expect(lifecycleRow("text", transitions)).not.toHaveProperty("lifecycle")
  })

  it("omits a blank or non-object lifecycle", () => {
    expect(lifecycleRow("select", "")).not.toHaveProperty("lifecycle")
    expect(lifecycleRow("select", "[1]")).not.toHaveProperty("lifecycle")
  })
})

describe("SchemaManager#collectAllAttributes / syncPropertySchema", () => {
  it("maps every named row and skips nameless ones, writing JSON to propertySchema", () => {
    const c = schema(
      `<div data-entity-form-target="attributesContainer">` +
      `<div data-attribute-item><input data-input="name" value="A"></div>` +
      `<div data-attribute-item><input data-input="name" value=""></div>` +
      `</div>` +
      `<input data-entity-form-target="propertySchema">`
    )
    expect(c.schemaManager.collectAllAttributes().map((a) => a.name)).toEqual(["A"])
    c.schemaManager.syncPropertySchema()
    expect(JSON.parse(c.propertySchemaTarget.value).length).toBe(1)
  })

  it("collectAllAttributes returns [] without a container", () => {
    expect(schema().schemaManager.collectAllAttributes()).toEqual([])
  })
})

describe("SchemaManager#collectAllAssociations", () => {
  it("parses data-association-data, skipping invalid JSON", () => {
    const c = schema(
      `<div data-entity-form-target="associationsContainer">` +
      `<div data-association-item data-association-data='{"target_entity_id":1}'></div>` +
      `<div data-association-item data-association-data='not json'></div>` +
      `</div>`
    )
    expect(c.schemaManager.collectAllAssociations()).toEqual([{ target_entity_id: 1 }])
  })

  it("returns [] without an associations container", () => {
    expect(schema().schemaManager.collectAllAssociations()).toEqual([])
  })
})

describe("SchemaManager#syncAssociationsSchema", () => {
  it("writes the collected associations as JSON", () => {
    const c = schema(
      `<div data-entity-form-target="associationsContainer">` +
      `<div data-association-item data-association-data='{"a":1}'></div>` +
      `</div>` +
      `<input data-entity-form-target="associationsSchema">`
    )
    c.schemaManager.syncAssociationsSchema()
    expect(JSON.parse(c.associationsSchemaTarget.value)).toEqual([{ a: 1 }])
  })

  it("no-ops without an associationsSchema target", () => {
    const c = schema(`<div data-entity-form-target="associationsContainer"></div>`)
    expect(() => c.schemaManager.syncAssociationsSchema()).not.toThrow()
  })
})

describe("SchemaManager#collectAttributes", () => {
  it("syncs both the property schema and the associations schema", () => {
    const c = schema(
      `<div data-entity-form-target="attributesContainer">` +
      `<div data-attribute-item><input data-input="name" value="A"></div>` +
      `</div>` +
      `<input data-entity-form-target="propertySchema">` +
      `<div data-entity-form-target="associationsContainer">` +
      `<div data-association-item data-association-data='{"target_entity_id":2}'></div>` +
      `</div>` +
      `<input data-entity-form-target="associationsSchema">`
    )
    c.schemaManager.collectAttributes()
    expect(JSON.parse(c.propertySchemaTarget.value).length).toBe(1)
    expect(JSON.parse(c.associationsSchemaTarget.value)).toEqual([{ target_entity_id: 2 }])
  })
})

describe("SchemaManager#syncAttributeGroups", () => {
  it("is a no-op placeholder — writes go through writeAttributeGroups directly", () => {
    expect(() => schema().schemaManager.syncAttributeGroups()).not.toThrow()
  })
})

describe("SchemaManager#ensureTableExists / appendAttribute", () => {
  it("inserts a table on first call and tags an untagged existing table", () => {
    const c = schema(`<div data-entity-form-target="attributesContainer"></div>`)
    c.schemaManager.ensureTableExists()
    expect(c.attributesContainerTarget.querySelector("table")).not.toBeNull()

    // pre-existing untagged table gets the attributesTable marker
    const c2 = schema(`<div data-entity-form-target="attributesContainer"><table></table></div>`)
    c2.schemaManager.ensureTableExists()
    expect(c2.attributesContainerTarget.querySelector("table").getAttribute("data-entity-form-target")).toBe("attributesTable")
  })

  it("appendAttribute builds a table + row and regroups", () => {
    const c = schema(`<div data-entity-form-target="attributesContainer"></div>`)
    c.schemaManager.appendAttribute({
      name: "Age", name_slug: "age", display_label: "Age", html_type: "number",
      description: "", validators: [], visibility: {}, group_id: null, config: null,
    })
    const rows = c.attributesContainerTarget.querySelectorAll("[data-attribute-item]")
    expect(rows.length).toBe(1)
    expect(rows[0].querySelector('input[data-input="name"]').value).toBe("Age")
  })
})

describe("SchemaManager#regroupAttributeRows", () => {
  it("adds group headers and appends an Ungrouped header for orphan rows", () => {
    const c = schema(
      `<div data-entity-form-target="attributesContainer"><table><tbody>` +
      `<tr data-attribute-item data-attr-group-id="g1"><td><input data-input="name" value="A"></td></tr>` +
      `<tr data-attribute-item data-attr-group-id=""><td><input data-input="name" value="B"></td></tr>` +
      `</tbody></table></div>` +
      `<input data-entity-form-target="attributeGroupsInput" value='[{"id":"g1","name":"Group One","color":"sky"}]'>`
    )
    c.schemaManager.regroupAttributeRows()
    const headers = c.attributesContainerTarget.querySelectorAll("[data-attribute-group-header]")
    const texts = [...headers].map((h) => h.textContent)
    expect(texts.some((t) => t.includes("Group One"))).toBe(true)
    expect(texts.some((t) => t.includes("Ungrouped"))).toBe(true)
  })

  it("no-ops when there is no table yet", () => {
    const c = schema(`<div data-entity-form-target="attributesContainer"></div>`)
    expect(() => c.schemaManager.regroupAttributeRows()).not.toThrow()
  })

  it("no-ops when the table has no tbody", () => {
    const c = schema(`<div data-entity-form-target="attributesContainer"><table></table></div>`)
    expect(() => c.schemaManager.regroupAttributeRows()).not.toThrow()
  })
})

describe("SchemaManager#moveGroupTo", () => {
  it("reorders a group to sit before the target group", () => {
    const c = schema(`<input data-entity-form-target="attributeGroupsInput" value='[{"id":"a","name":"A"},{"id":"b","name":"B"},{"id":"c","name":"C"}]'>`)
    c.schemaManager.moveGroupTo("c", "a")
    expect(c.schemaManager.readAttributeGroups().map((g) => g.id)).toEqual(["c", "a", "b"])
  })
  it("moving before a null target appends to the end", () => {
    const c = schema(`<input data-entity-form-target="attributeGroupsInput" value='[{"id":"a","name":"A"},{"id":"b","name":"B"}]'>`)
    c.schemaManager.moveGroupTo("a", null)
    expect(c.schemaManager.readAttributeGroups().map((g) => g.id)).toEqual(["b", "a"])
  })
  it("no-ops for an unknown group id", () => {
    const c = schema(`<input data-entity-form-target="attributeGroupsInput" value='[{"id":"a","name":"A"}]'>`)
    c.schemaManager.moveGroupTo("zzz", "a")
    expect(c.schemaManager.readAttributeGroups().map((g) => g.id)).toEqual(["a"])
  })
  it("appends to the end when the target group id is not found among the remaining groups", () => {
    const c = schema(`<input data-entity-form-target="attributeGroupsInput" value='[{"id":"a","name":"A"},{"id":"b","name":"B"}]'>`)
    c.schemaManager.moveGroupTo("a", "zzz")
    expect(c.schemaManager.readAttributeGroups().map((g) => g.id)).toEqual(["b", "a"])
  })
})

describe("SchemaManager#moveRowTo", () => {
  it("sets the row group id, moves it before the target, and syncs schema", () => {
    const c = schema(
      `<div data-entity-form-target="attributesContainer"><table><tbody>` +
      `<tr id="r1" data-attribute-item><td><input data-input="name" value="A"><input data-input="group_id" value=""></td></tr>` +
      `<tr id="r2" data-attribute-item><td><input data-input="name" value="B"><input data-input="group_id" value=""></td></tr>` +
      `</tbody></table></div>` +
      `<input data-entity-form-target="propertySchema">` +
      `<input data-entity-form-target="attributeGroupsInput" value="[]">`
    )
    const r1 = c.element.querySelector("#r1")
    const r2 = c.element.querySelector("#r2")
    c.schemaManager.moveRowTo(r1, { groupId: "g9", beforeRow: r2 })
    expect(r1.getAttribute("data-attr-group-id")).toBe("g9")
    expect(r1.querySelector('input[data-input="group_id"]').value).toBe("g9")
    expect(JSON.parse(c.propertySchemaTarget.value).length).toBe(2)
  })

  it("no-ops without a row element", () => {
    expect(() => schema().schemaManager.moveRowTo(null, { groupId: "g", beforeRow: null })).not.toThrow()
  })

  it("clears the group id when groupId is falsy and appends to tbody without a beforeRow", () => {
    const c = schema(
      `<div data-entity-form-target="attributesContainer"><table><tbody>` +
      `<tr id="r1" data-attribute-item data-attr-group-id="g1"><td><input data-input="name" value="A"><input data-input="group_id" value="g1"></td></tr>` +
      `</tbody></table></div>`
    )
    const r1 = c.element.querySelector("#r1")
    c.schemaManager.moveRowTo(r1, { groupId: null, beforeRow: null })
    expect(r1.getAttribute("data-attr-group-id")).toBe("")
    expect(r1.querySelector('input[data-input="group_id"]').value).toBe("")
    expect(c.attributesContainerTarget.querySelector("tbody").contains(r1)).toBe(true)
  })

  it("skips writing the group id input when the row has no matching hidden input", () => {
    const c = schema(
      `<div data-entity-form-target="attributesContainer"><table><tbody>` +
      `<tr id="r1" data-attribute-item><td><input data-input="name" value="A"></td></tr>` +
      `</tbody></table></div>`
    )
    const r1 = c.element.querySelector("#r1")
    expect(() => c.schemaManager.moveRowTo(r1, { groupId: "g1", beforeRow: null })).not.toThrow()
    expect(r1.getAttribute("data-attr-group-id")).toBe("g1")
  })
})

describe("SchemaManager#updateAttributeRow", () => {
  it("writes field cells + hidden inputs from the supplied attribute", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<span data-field="name"></span><span data-field="name_slug"></span>` +
      `<span data-field="display_label"></span><span data-field="html_type"></span>` +
      `<span data-field="validators"></span><span data-field="visibility"></span><span data-field="description"></span>` +
      `<input data-input="name"><input data-input="name_slug"><input data-input="display_label">` +
      `<input data-input="html_type"><input data-input="description"><input data-input="validators">` +
      `<input data-input="visibility"><input data-input="validator_apply"><input data-input="editable"><input data-input="group_id"><input data-input="config">` +
      `</div>`
    )
    const row = c.element.querySelector("[data-attribute-item]")
    c.schemaManager.updateAttributeRow(row, {
      name: "Score", name_slug: "score", display_label: "", html_type: "number",
      description: "pts", validators: ["presence"], visibility: { public: false },
      validator_apply: { member: false }, editable: { member: false }, group_id: "g1", config: null,
    })
    expect(row.querySelector('[data-field="name"]').textContent).toBe("Score")
    expect(row.querySelector('[data-field="html_type"]').textContent).toBe("Number")
    expect(row.querySelector('input[data-input="display_label"]').value).toBe("Score") // falls back to name
    expect(row.getAttribute("data-attr-group-id")).toBe("g1")
    expect(JSON.parse(row.querySelector('input[data-input="visibility"]').value)).toEqual({ admin: true, member: true, public: false })
    expect(JSON.parse(row.querySelector('input[data-input="validator_apply"]').value)).toEqual({ admin: true, member: false, public: false })
    expect(JSON.parse(row.getAttribute("data-attr-validator-apply"))).toEqual({ admin: true, member: false, public: false })
    expect(JSON.parse(row.querySelector('input[data-input="editable"]').value)).toEqual({ admin: true, member: false, public: false })
    expect(JSON.parse(row.getAttribute("data-attr-editable"))).toEqual({ admin: true, member: false, public: false })
  })

  it("leaves the lifecycle hidden input untouched so a modal edit keeps it", () => {
    const lifecycle = '{"transitions":[{"from":"draft","to":"submitted","by":["member"]}]}'
    const c = schema(
      `<div data-attribute-item>` +
      `<input data-input="name" value="Status"><input data-input="display_label"><input data-input="html_type" value="select">` +
      `<input data-input="lifecycle" value='${lifecycle}'>` +
      `</div>`
    )
    const row = c.element.querySelector("[data-attribute-item]")
    c.schemaManager.updateAttributeRow(row, {
      name: "Status", name_slug: "status", display_label: "State", html_type: "select",
      description: "", validators: [], visibility: {}, group_id: "", config: { source: "manual", options: [] },
    })
    expect(c.schemaManager.extractAttributeFromRow(row)).toMatchObject({
      display_label: "State",
      lifecycle: { transitions: [{ from: "draft", to: "submitted", by: ["member"] }] },
    })
  })

  it("falls back to blank defaults when the optional fields are falsy", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<input data-input="name"><input data-input="name_slug"><input data-input="display_label">` +
      `<input data-input="html_type"><input data-input="description"><input data-input="validators">` +
      `<input data-input="visibility"><input data-input="validator_apply"><input data-input="group_id"><input data-input="config">` +
      `</div>`
    )
    const row = c.element.querySelector("[data-attribute-item]")
    c.schemaManager.updateAttributeRow(row, {
      name: "", name_slug: "", display_label: "", html_type: "", description: "",
      validators: [], visibility: {}, validator_apply: {}, group_id: null, config: null,
    })
    expect(row.getAttribute("data-attr-group-id")).toBe("")
    expect(row.querySelector('input[data-input="display_label"]').value).toBe("")
    expect(row.querySelector('input[data-input="html_type"]').value).toBe("")
    expect(row.querySelector('input[data-input="description"]').value).toBe("")
    expect(row.querySelector('input[data-input="group_id"]').value).toBe("")
    expect(JSON.parse(row.querySelector('input[data-input="validator_apply"]').value)).toEqual({
      admin: true, member: true, public: true
    })
  })

  it("writes type onto the row and inserts a Computed badge next to html_type", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<span data-field="html_type">Number</span>` +
      `<input data-input="type">` +
      `</div>`
    )
    const row = c.element.querySelector("[data-attribute-item]")
    c.schemaManager.updateAttributeRow(row, {
      name: "Avg", name_slug: "avg", display_label: "Avg", html_type: "number",
      description: "", validators: [], visibility: {}, validator_apply: {}, group_id: null, config: null,
      type: "Computed",
    })
    expect(row.getAttribute("data-attr-type")).toBe("Computed")
    expect(row.querySelector('input[data-input="type"]').value).toBe("Computed")
    expect(row.querySelector('[data-field="attr_type"]').textContent).toBe("Computed")
  })

  it("updates an existing Computed badge and removes it when type is cleared", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<span data-field="html_type">Number</span>` +
      `<span data-field="attr_type">Stale</span>` +
      `<input data-input="type" value="Computed">` +
      `</div>`
    )
    const row = c.element.querySelector("[data-attribute-item]")
    c.schemaManager.updateAttributeRow(row, {
      name: "Avg", name_slug: "avg", display_label: "Avg", html_type: "number",
      description: "", validators: [], visibility: {}, validator_apply: {}, group_id: null, config: null,
      type: "Computed",
    })
    expect(row.querySelector('[data-field="attr_type"]').textContent).toBe("Computed")

    c.schemaManager.updateAttributeRow(row, {
      name: "Avg", name_slug: "avg", display_label: "Avg", html_type: "number",
      description: "", validators: [], visibility: {}, validator_apply: {}, group_id: null, config: null,
    })
    expect(row.querySelector('[data-field="attr_type"]')).toBeNull()
    expect(row.getAttribute("data-attr-type")).toBe("")
    expect(row.querySelector('input[data-input="type"]').value).toBe("")
  })

  it("skips inserting a Computed badge when the html_type cell is missing", () => {
    const c = schema(`<div data-attribute-item></div>`)
    const row = c.element.querySelector("[data-attribute-item]")
    expect(() => c.schemaManager.updateAttributeRow(row, {
      name: "Avg", name_slug: "avg", display_label: "Avg", html_type: "number",
      description: "", validators: [], visibility: {}, validator_apply: {}, group_id: null, config: null,
      type: "Computed",
    })).not.toThrow()
    expect(row.querySelector('[data-field="attr_type"]')).toBeNull()
  })

  it("writes the owner hidden input and data attribute", () => {
    const c = schema(
      `<div data-attribute-item>` +
      `<input data-input="name"><input data-input="owner">` +
      `</div>`
    )
    const row = c.element.querySelector("[data-attribute-item]")
    c.schemaManager.updateAttributeRow(row, {
      name: "Student", name_slug: "student", display_label: "Student", html_type: "select",
      description: "", validators: [], visibility: {}, validator_apply: {}, group_id: null, config: null,
      owner: true,
    })
    expect(row.querySelector('input[data-input="owner"]').value).toBe("true")
    expect(row.getAttribute("data-attr-owner")).toBe("true")

    c.schemaManager.updateAttributeRow(row, {
      name: "Student", name_slug: "student", display_label: "Student", html_type: "select",
      description: "", validators: [], visibility: {}, validator_apply: {}, group_id: null, config: null,
    })
    expect(row.querySelector('input[data-input="owner"]').value).toBe("")
    expect(row.getAttribute("data-attr-owner")).toBe("")
  })
})
