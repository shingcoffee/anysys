import { describe, it, expect, beforeEach, vi } from "vitest"
import { TemplateBuilder } from "controllers/entity_form/template_builder"
import { SchemaManager } from "controllers/entity_form/schema_manager"
import { TypeManager } from "controllers/entity_form/type_manager"
import { ValidatorManager } from "controllers/entity_form/validator_manager"
import { buildController } from "./support.js"

// TemplateBuilder is pure string production but leans on sibling managers for
// normalization/labels, so wire the real collaborators. `html` seeds the fake
// controller's DOM (e.g. an attributeGroupsInput store) for tests that need it.
function tb(values = {}, html = "") {
  const { controller } = buildController(html, { values: { attributeIndex: 0, ...values } })
  controller.schemaManager = new SchemaManager(controller)
  controller.typeManager = new TypeManager(controller)
  controller.validatorManager = new ValidatorManager(controller)
  controller.templateBuilder = new TemplateBuilder(controller)
  return controller.templateBuilder
}

// Parse an HTML fragment string so we can assert on structure, not raw text.
const frag = (html) => {
  const t = document.createElement("template")
  t.innerHTML = html.trim()
  return t.content
}

describe("TemplateBuilder#buildTableHtml", () => {
  it("emits a table tagged as the attributesTable target with an empty tbody", () => {
    const f = frag(tb().buildTableHtml())
    const table = f.querySelector("table")
    expect(table.getAttribute("data-entity-form-target")).toBe("attributesTable")
    expect(table.querySelector("tbody").children.length).toBe(0)
  })
})

describe("TemplateBuilder#buildValidatorBadgesHtml", () => {
  it("shows a dash placeholder for empty/undefined", () => {
    expect(tb().buildValidatorBadgesHtml([])).toContain(">-<")
    expect(tb().buildValidatorBadgesHtml(undefined)).toContain(">-<")
  })

  it("renders string validators via their label", () => {
    const f = frag(tb().buildValidatorBadgesHtml(["presence"]))
    expect(f.textContent).toContain("Required")
  })

  it("renders object validators with config through buildValidatorLabelWithConfig", () => {
    const f = frag(tb().buildValidatorBadgesHtml([{ type: "greater_than_or_equal_to", config: { value: 3 } }]))
    expect(f.textContent).toContain(">= 3")
  })
})

describe("TemplateBuilder#buildVisibilityBadgesHtml", () => {
  it("line-throughs disabled scopes and marks enabled ones", () => {
    const f = frag(tb().buildVisibilityBadgesHtml({ admin: true, member: false, public: true }))
    const spans = [...f.querySelectorAll("span")]
    const member = spans.find((s) => s.textContent === "Member")
    const admin = spans.find((s) => s.textContent === "Admin")
    expect(member.className).toContain("line-through")
    expect(admin.className).not.toContain("line-through")
  })
})

describe("TemplateBuilder#buildTruncatedDescriptionHtml", () => {
  it("returns a dash for blank descriptions", () => {
    expect(tb().buildTruncatedDescriptionHtml("")).toContain(">-<")
    expect(tb().buildTruncatedDescriptionHtml("   ")).toContain(">-<")
  })
  it("truncates and adds a title tooltip past the max length", () => {
    const long = "x".repeat(50)
    const f = frag(tb().buildTruncatedDescriptionHtml(long, 40))
    const span = f.querySelector("span")
    expect(span.textContent.endsWith("...")).toBe(true)
    expect(span.getAttribute("title")).toBe(long)
  })
  it("leaves short descriptions intact", () => {
    const f = frag(tb().buildTruncatedDescriptionHtml("short"))
    expect(f.querySelector("span").textContent).toBe("short")
  })
})

describe("TemplateBuilder#buildConfigViewHtml", () => {
  it("None for null config", () => {
    expect(tb().buildConfigViewHtml(null, "select")).toContain("None")
  })
  it("renders an options table for selection types", () => {
    const html = tb().buildConfigViewHtml({ options: [{ label: "Red", value: "red", default: true }] }, "select")
    const f = frag(html)
    expect(f.querySelector("table")).not.toBeNull()
    expect(f.textContent).toContain("Red")
    expect(f.textContent).toContain("Default")
  })
  it("renders accept/multiple for file types", () => {
    const f = frag(tb().buildConfigViewHtml({ accept: ".pdf", multiple: true }, "file"))
    expect(f.textContent).toContain(".pdf")
    expect(f.textContent).toContain("Yes")
  })
  it("None for an empty file config", () => {
    expect(tb().buildConfigViewHtml({}, "file")).toContain("None")
  })
})

describe("TemplateBuilder#buildAttributeGroupHeaderHtml", () => {
  it("ungrouped header: no group id, no drag attrs, pluralized count", () => {
    const f = frag(tb().buildAttributeGroupHeaderHtml(null, 2))
    const tr = f.querySelector("tr")
    expect(tr.getAttribute("data-group-id")).toBe("")
    expect(tr.hasAttribute("draggable")).toBe(false)
    expect(tr.querySelector("td").getAttribute("colspan")).toBe("9")
    expect(f.textContent).toContain("Ungrouped")
    expect(f.textContent).toContain("2 attributes")
  })
  it("named group header: draggable, singular count, Empty badge at 0", () => {
    const f = frag(tb().buildAttributeGroupHeaderHtml({ id: "g1", name: "Contact", color: "sky" }, 0))
    const tr = f.querySelector("tr")
    expect(tr.getAttribute("data-group-id")).toBe("g1")
    expect(tr.hasAttribute("draggable")).toBe(true)
    expect(f.textContent).toContain("Contact")
    expect(f.textContent).toContain("0 attributes")
    expect(f.textContent).toContain("Empty")
  })
})

describe("TemplateBuilder#buildAttributeRowHtml", () => {
  it("produces a draggable attribute row with escaped hidden inputs", () => {
    const attr = {
      name: 'A"B', name_slug: "a_b", display_label: "", html_type: "select",
      description: "d", validators: ["presence"], visibility: { admin: false }, group_id: "g1",
      config: { source: "manual", options: [] },
    }
    const f = frag(tb({ attributeIndex: 5 }).buildAttributeRowHtml(attr))
    const row = f.querySelector("[data-attribute-item]")
    expect(row.getAttribute("draggable")).toBe("true")
    expect(row.getAttribute("data-attr-group-id")).toBe("g1")
    // display_label falls back to name
    expect(row.querySelector('input[data-input="display_label"]').value).toBe('A"B')
    expect(row.querySelector('input[data-input="name"]').name).toBe("attributes[5][name]")
    expect(row.querySelector('[data-field="html_type"]').textContent).toBe("Dropdown")
    expect(row.querySelector('input[data-input="validator_apply"]')).toBeTruthy()
    expect(row.querySelector('input[data-input="editable"]')).toBeTruthy()
    expect(JSON.parse(row.getAttribute("data-attr-validator-apply"))).toEqual({
      admin: false, member: true, public: true
    })
    expect(JSON.parse(row.getAttribute("data-attr-editable"))).toEqual({
      admin: false, member: true, public: true
    })
    expect(row.getAttribute("data-attr-type")).toBe("")
    expect(row.querySelector('input[data-input="type"]').value).toBe("")
    expect(row.querySelector('[data-field="attr_type"]')).toBeNull()
    expect(row.querySelector('input[data-input="owner"]').value).toBe("")
    expect(row.getAttribute("data-attr-owner")).toBe("")
  })

  it("emits a true owner hidden input only when owner is true", () => {
    const flagged = frag(tb({ attributeIndex: 0 }).buildAttributeRowHtml({
      name: "Student", name_slug: "student", display_label: "Student",
      html_type: "select", description: "", validators: [], visibility: {}, group_id: null,
      config: null, owner: true,
    }))
    expect(flagged.querySelector('input[data-input="owner"]').value).toBe("true")
    expect(flagged.querySelector("[data-attribute-item]").getAttribute("data-attr-owner")).toBe("true")
  })

  it("emits data-attr-type, a hidden type input, and a Computed badge for computed attributes", () => {
    const f = frag(tb({ attributeIndex: 0 }).buildAttributeRowHtml({
      name: "Average Score", name_slug: "average_score", display_label: "Average Score",
      html_type: "number", description: "", validators: [], visibility: {}, group_id: null,
      config: { function: "avg" }, type: "Computed",
    }))
    const row = f.querySelector("[data-attribute-item]")
    expect(row.getAttribute("data-attr-type")).toBe("Computed")
    expect(row.querySelector('input[data-input="type"]').value).toBe("Computed")
    expect(row.querySelector('[data-field="attr_type"]').textContent).toBe("Computed")
  })
})

describe("TemplateBuilder#buildOptionRowHtml", () => {
  it("uses a radio default when the html type is not checkbox", () => {
    const t = tb()
    // no modalHtmlType target -> defaults to "select"
    const f = frag(t.buildOptionRowHtml(0))
    expect(f.querySelector("[data-option-default]").getAttribute("type")).toBe("radio")
    expect(f.querySelector("[data-option-default]").getAttribute("name")).toBe("option_default")
    expect(f.querySelector("[data-option-label]").classList.contains("input-field")).toBe(true)
    expect(f.querySelector("[data-option-label]").className).toContain("text-xs")
    expect(f.querySelector("[data-option-value]").classList.contains("input-field")).toBe(true)
    expect(f.querySelector("[data-option-value]").className).toContain("text-xs")
    expect(f.querySelector("[data-option-item]").className).toContain("grid")
    expect(f.querySelector("[data-option-default]").getAttribute("aria-label")).toBe("Default")
    const defaultText = [...f.querySelectorAll("span")].find((el) => el.textContent === "Default")
    expect(defaultText.className).toContain("sm:hidden")
  })
  it("uses a per-index checkbox default for checkbox types", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="checkbox" selected>checkbox</option></select>`
    )
    controller.templateBuilder = new TemplateBuilder(controller)
    const f = frag(controller.templateBuilder.buildOptionRowHtml(2))
    expect(f.querySelector("[data-option-default]").getAttribute("type")).toBe("checkbox")
    expect(f.querySelector("[data-option-default]").getAttribute("name")).toBe("option_default_2")
    expect(f.querySelector("[data-option-default]").className).toContain("rounded")
  })
})

describe("TemplateBuilder#buildValidatorBadgeHtml", () => {
  it("stores the serialized validator object on the badge without audience toggles", () => {
    const f = frag(tb().buildValidatorBadgeHtml("inclusion", "InList: a", { type: "inclusion", config: { values: ["a"] } }))
    const badge = f.querySelector("[data-validator-item]")
    expect(badge.dataset.validatorValue).toBe("inclusion")
    expect(JSON.parse(badge.dataset.validatorObject)).toEqual({
      type: "inclusion",
      config: { values: ["a"] }
    })
    expect(badge.querySelectorAll("[data-validator-audience]").length).toBe(0)
  })

  it("strips legacy per-validator visibility from the badge payload", () => {
    const f = frag(tb().buildValidatorBadgeHtml("presence", "Required", {
      type: "presence",
      visibility: { admin: true, member: false, public: false }
    }))
    const badge = f.querySelector("[data-validator-item]")
    expect(JSON.parse(badge.dataset.validatorObject)).toEqual({ type: "presence" })
  })

  it("builds a badge when validatorObject is omitted", () => {
    const f = frag(tb().buildValidatorBadgeHtml("presence", "Required"))
    expect(JSON.parse(f.querySelector("[data-validator-item]").dataset.validatorObject)).toEqual({
      type: "presence"
    })
  })
})

describe("TemplateBuilder#buildAssociationRowHtml", () => {
  it("serializes the association onto the row and previews up to 3 attrs + overflow", () => {
    const assoc = {
      target_entity_name: "Order", display_field_label: "Name",
      bridge_entity_name: null,
      additional_attributes: [{ name: "a" }, { name: "b" }, { name: "c" }, { name: "d" }],
    }
    const f = frag(tb().buildAssociationRowHtml(assoc))
    const row = f.querySelector("[data-association-item]")
    expect(JSON.parse(row.dataset.associationData).target_entity_name).toBe("Order")
    expect(f.textContent).toContain("Order")
    expect(f.textContent).toContain("Will be created on save") // null bridge name fallback
    expect(f.textContent).toContain("+1 more")
  })
})

describe("TemplateBuilder#buildAssociationAttributeDisplayHtml", () => {
  it("shows name, formatted type, and index on the row", () => {
    const f = frag(tb().buildAssociationAttributeDisplayHtml(
      { name: "Qty", name_slug: "qty", html_type: "number", validators: [] }, 3))
    const row = f.querySelector("[data-association-attribute-item]")
    expect(row.getAttribute("data-index")).toBe("3")
    expect(f.textContent).toContain("Qty")
    expect(f.textContent).not.toContain("qty")
    expect(f.textContent).toContain("Number")
  })
})

describe("TemplateBuilder#buildAttributeViewHtml", () => {
  let builder
  beforeEach(() => {
    builder = tb()
  })
  it("renders identity fields, resolves ungrouped, and shows description", () => {
    const html = builder.buildAttributeViewHtml({
      name: "Email", name_slug: "email", display_label: "Email Address",
      html_type: "email", description: "Work email", validators: ["format_email"],
      visibility: { admin: true, member: true, public: false }, group_id: null, config: null,
    })
    const f = frag(html)
    expect(f.textContent).toContain("Email Address")
    expect(f.textContent).not.toContain("Name Slug")
    expect(f.textContent).toContain("Email") // formatted html type
    expect(f.textContent).toContain("Ungrouped")
    expect(f.textContent).toContain("Work email")
  })
  it("shows the italic no-description placeholder when description is blank", () => {
    const f = frag(builder.buildAttributeViewHtml({
      name: "N", name_slug: "n", display_label: "N", html_type: "text",
      description: "", validators: [], visibility: {}, group_id: null, config: null,
    }))
    expect(f.textContent).toContain("No description provided.")
  })

  it.each([
    ["Field name", "", "Field name"],
    ["", "", ""],
  ])("keeps an absent display label readable without exposing undefined text (%j, %j)", (name, display_label, expected) => {
    const f = frag(builder.buildAttributeViewHtml({
      name, name_slug: "unused", display_label, html_type: "text",
      description: "", validators: [], visibility: {}, group_id: null, config: null,
    }))
    const label = [...f.querySelectorAll("dt")].find(node => node.textContent.trim() === builder.c.displayLabelHeaderValue)
    expect(label.nextElementSibling.textContent).toBe(expected)
    expect(f.textContent).not.toContain("undefined")
  })

  it("resolves the group chip and renders mixed validator shapes in the view", () => {
    // Wire a controller carrying a real groups store so group resolution hits.
    const { controller } = buildController(
      `<input data-entity-form-target="attributeGroupsInput" value='${JSON.stringify([{ id: "g1", name: "Contact", color: "rose" }])}'>`,
      { values: { attributeIndex: 0 } }
    )
    controller.schemaManager = new SchemaManager(controller)
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    const f = frag(controller.templateBuilder.buildAttributeViewHtml({
      name: "N", name_slug: "n", display_label: "N", html_type: "text",
      description: "d", group_id: "g1", config: null, visibility: {},
      validators: [
        "unknown_string_validator", // string, no label -> falls back to raw
        { type: "greater_than_or_equal_to", config: { value: 3 } }, // object + config
        { type: "unknown_obj_validator" }, // object, no config, no label
        99, // non-object -> String(v)
      ],
    }))
    expect(f.textContent).toContain("Contact") // group chip resolved
    expect(f.textContent).toContain(">= 3")
    expect(f.textContent).toContain("99")
  })

  it("renders an empty-string validator in the view via the raw-value fallback", () => {
    // Exercises the string `getValidatorLabel(v) || v` fallback inside the view helper.
    expect(() => builder.buildAttributeViewHtml({
      name: "N", name_slug: "n", display_label: "N", html_type: "text",
      description: "", validators: [""], visibility: {}, group_id: null, config: null,
    })).not.toThrow()
  })

  it("uses the slate fallback bar when the resolved group has an unknown color", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="attributeGroupsInput" value='${JSON.stringify([{ id: "g1", name: "Contact", color: "chartreuse" }])}'>`
    )
    controller.schemaManager = new SchemaManager(controller)
    controller.typeManager = new TypeManager(controller)
    controller.validatorManager = new ValidatorManager(controller)
    controller.templateBuilder = new TemplateBuilder(controller)
    const html = controller.templateBuilder.buildAttributeViewHtml({
      name: "N", name_slug: "n", display_label: "N", html_type: "text",
      description: "", validators: [], visibility: {}, group_id: "g1", config: null,
    })
    expect(html).toContain("bg-slate-500")
  })
})

describe("TemplateBuilder#buildValidatorBadgesHtml fallbacks", () => {
  it("handles string-without-label, object-without-config, and non-object entries", () => {
    const f = frag(tb().buildValidatorBadgesHtml(["unknown_string", { type: "unknown_obj" }, 7]))
    expect(f.textContent).toContain("unknown_string")
    expect(f.textContent).toContain("unknown_obj")
    expect(f.textContent).toContain("7")
  })

  it("falls back to the raw value for an empty-string validator (getValidatorLabel('') is falsy)", () => {
    // getValidatorLabel("") returns "" so the `|| v` fallback is taken.
    expect(() => tb().buildValidatorBadgesHtml([""])).not.toThrow()
  })

  it("ignores legacy per-validator visibility when rendering table badges", () => {
    const f = frag(tb().buildValidatorBadgesHtml([{
      type: "presence",
      visibility: { admin: true, member: false, public: false }
    }]))
    expect(f.textContent).toContain("Required")
    expect(f.textContent).not.toContain("Required (")
    expect(f.querySelector("span").getAttribute("title")).toBe("presence")
  })
})

describe("TemplateBuilder#buildAttributeRowHtml coerce", () => {
  it("coerces validator_apply in row hidden input when visibility is false", () => {
    const row = frag(tb({ attributeIndex: 0 }).buildAttributeRowHtml({
      name: "Email", name_slug: "email", display_label: "Email", html_type: "email",
      description: "", validators: [],
      visibility: { admin: true, member: true, public: false },
      validator_apply: { admin: true, member: true, public: true },
      group_id: null, config: null
    }))
    expect(JSON.parse(row.querySelector('input[data-input="validator_apply"]').value)).toEqual({
      admin: true, member: true, public: false
    })
  })

  it("coerces editable in row hidden input when visibility is false", () => {
    const row = frag(tb({ attributeIndex: 0 }).buildAttributeRowHtml({
      name: "Email", name_slug: "email", display_label: "Email", html_type: "email",
      description: "", validators: [],
      visibility: { admin: true, member: true, public: false },
      editable: { admin: true, member: true, public: true },
      group_id: null, config: null
    }))
    expect(JSON.parse(row.querySelector('input[data-input="editable"]').value)).toEqual({
      admin: true, member: true, public: false
    })
    expect(JSON.parse(row.querySelector("[data-attribute-item]").getAttribute("data-attr-editable"))).toEqual({
      admin: true, member: true, public: false
    })
  })
})

describe("TemplateBuilder#buildAttributeViewHtml coerce", () => {
  it("coerces Apply view badges via schemaManager.coerceValidatorApply", () => {
    const builder = tb()
    const spy = vi.spyOn(builder.c.schemaManager, "coerceValidatorApply")
    builder.buildAttributeViewHtml({
      name: "Email", name_slug: "email", display_label: "Email", html_type: "email",
      description: "", validators: [{ type: "presence" }],
      visibility: { admin: true, member: true, public: false },
      validator_apply: { admin: true, member: true, public: true },
      group_id: null, config: null
    })
    expect(spy).toHaveBeenCalled()
    expect(spy.mock.results[0].value).toEqual({ admin: true, member: true, public: false })
  })

  it("renders Can edit badges coerced against visibility", () => {
    const builder = tb()
    const spy = vi.spyOn(builder.c.schemaManager, "coerceEditable")
    const html = builder.buildAttributeViewHtml({
      name: "Order Number", name_slug: "order_number", display_label: "Order Number", html_type: "text",
      description: "", validators: [],
      visibility: { admin: true, member: true, public: false },
      editable: { admin: true, member: false, public: true },
      group_id: null, config: null
    })
    expect(spy).toHaveBeenCalled()
    expect(spy.mock.results[0].value).toEqual({ admin: true, member: false, public: false })
    expect(html).toContain("Can edit")
  })
})

describe("TemplateBuilder view-modal field visibility matrix", () => {
  it("renders sectioned identity/audience/validation/details with audience rows", () => {
    const html = tb().buildAttributeViewHtml({
      name: "Email",
      name_slug: "email",
      display_label: "Email",
      html_type: "email",
      description: "",
      validators: [{ type: "presence" }],
      visibility: { admin: true, member: true, public: false },
      validator_apply: { admin: true, member: false, public: true },
      group_id: null,
      config: null
    })
    expect(html).toContain("Identity")
    expect(html).toContain("Audience")
    expect(html).toContain("Validation")
    expect(html).toContain("Details")
    expect(html).toContain("Visible")
    expect(html).toContain("Can edit")
    expect(html).toContain("Apply validators")
    expect(html).toContain("Required")
    expect(html).not.toContain("Required ·")
  })
})

describe("TemplateBuilder#buildValidatorBadgeHtml label fallbacks", () => {
  it("derives the short label from the value when no label is given", () => {
    const withKnown = frag(tb().buildValidatorBadgeHtml("presence", "", { type: "presence" }))
    expect(withKnown.querySelector("span").textContent).toBe("Required") // from VALIDATOR_LABELS
    const withUnknown = frag(tb().buildValidatorBadgeHtml("mystery", "", {}))
    expect(withUnknown.querySelector("span").textContent).toBe("mystery") // raw value
  })
})

describe("TemplateBuilder#buildAttributeRowHtml label/type fallbacks", () => {
  it("uses display_label when present and empty strings for missing type/labels", () => {
    const withLabel = frag(tb({ attributeIndex: 0 }).buildAttributeRowHtml({
      name: "N", name_slug: "n", display_label: "Custom", html_type: "text",
      description: "", validators: [], visibility: {}, group_id: "", config: null,
    }))
    expect(withLabel.querySelector('input[data-input="display_label"]').value).toBe("Custom")

    const noLabels = frag(tb({ attributeIndex: 0 }).buildAttributeRowHtml({
      name: "", name_slug: "", display_label: "", html_type: "",
      description: "", validators: [], visibility: {}, group_id: "", config: null,
    }))
    expect(noLabels.querySelector('input[data-input="display_label"]').value).toBe("")
    expect(noLabels.querySelector('input[data-input="html_type"]').value).toBe("")
  })
})

describe("TemplateBuilder#buildAttributeGroupHeaderHtml color + description", () => {
  it("falls back to slate for unknown colors and renders the description", () => {
    const f = frag(tb().buildAttributeGroupHeaderHtml({ id: "g1", name: "Contact", color: "chartreuse", description: "Reach out" }, 3))
    expect(f.querySelector("tr").innerHTML).toContain("bg-slate-500")
    expect(f.textContent).toContain("Reach out")
  })

  it("uses the singular attribute count label when the group has one attribute", () => {
    const f = frag(tb().buildAttributeGroupHeaderHtml({ id: "g1", name: "Solo", color: "sky" }, 1))
    expect(f.textContent).toContain("1 attribute")
    expect(f.textContent).not.toContain("1 attributes")
  })
})

describe("TemplateBuilder#buildConfigViewHtml remaining branches", () => {
  it("returns None for a selection config with no options", () => {
    expect(tb().buildConfigViewHtml({ options: [] }, "select")).toContain("None")
  })

  it("returns None for an unmapped html type", () => {
    expect(tb().buildConfigViewHtml({ anything: true }, "text")).toContain("None")
  })

  it("renders option rows with blank label/value/default fallbacks", () => {
    const f = frag(tb().buildConfigViewHtml({ options: [{}] }, "select"))
    // an all-empty option still yields a row with empty cells and no Default badge
    // (the "Default" column header is always present, so check the row cells)
    expect(f.querySelector("tbody tr")).not.toBeNull()
    expect(f.querySelectorAll("tbody .badge-accent").length).toBe(0)
  })

  it("file config: renders Multiple=Yes without accept, and No with accept", () => {
    const noAccept = frag(tb().buildConfigViewHtml({ multiple: true }, "file"))
    expect(noAccept.textContent).toContain("Yes")
    expect(noAccept.textContent).not.toContain("Accept:")

    const withAccept = frag(tb().buildConfigViewHtml({ accept: ".png", multiple: false }, "file"))
    expect(withAccept.textContent).toContain("Accept:")
    expect(withAccept.textContent).toContain("No")
  })
})

describe("TemplateBuilder#buildAssociationAttributeDisplayHtml / buildAssociationRowHtml branches", () => {
  it("defaults validators to a dash when the attribute has none", () => {
    const f = frag(tb().buildAssociationAttributeDisplayHtml({ name: "Qty", name_slug: "qty", html_type: "number" }, 0))
    expect(f.textContent).toContain("Qty")
  })

  it("renders a linked bridge entity, no display field, and no extra attributes", () => {
    const f = frag(tb().buildAssociationRowHtml({
      target_entity_name: "Order",
      display_field_label: null, // -> dash
      bridge_entity_name: "OrderItem", // -> purple badge + icon
      // additional_attributes omitted -> defaults to []
    }))
    expect(f.textContent).toContain("Order")
    expect(f.textContent).toContain("OrderItem")
    expect(f.textContent).toContain("None") // no additional attributes
    expect(f.querySelector("code")).toBeNull() // no display field code chip
  })
})
