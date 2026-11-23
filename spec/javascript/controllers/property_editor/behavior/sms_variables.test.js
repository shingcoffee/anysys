import { afterEach, describe, expect, it } from "vitest"
import { mountEditor, change, sync } from "./_support.js"

let editor
afterEach(async () => { await editor?.dispose(); editor = null })

const codeInput = () => editor.controller.formTarget.querySelector('[data-config-input="valueExpression"]')
const configFor = valueExpression => ({ valueType: "expression", resultVar: "assigned", valueExpression })

describe("JSON-or-expression config fields through the real property editor", () => {
  it.each([
    { code: "ctx.code" },
    { code: "1234", minutes: 5, zero: 0, fraction: 1.5 },
    {},
    "ctx.sms_vars",
    "ctx.payload.vars",
    "ctx[:sms_vars]"
  ])("preserves saved values %j through an unrelated edit, canvas save, and reopen", async valueExpression => {
    editor = await mountEditor("process", { steps: [{ id: "assign-step", action: "assign_value", config: configFor(valueExpression) }] })
    await change(editor.controller.formTarget.querySelector('[data-config-input="resultVar"]'), "assigned_2")
    expect(sync(editor).steps[0]).toMatchObject({ id: "assign-step", config: { valueExpression, resultVar: "assigned_2" } })
    await editor.reopen()
    expect(editor.controller.stepManager.collectSteps()[0].config.valueExpression).toEqual(valueExpression)
    if (typeof valueExpression === "object") {
      expect(JSON.parse(codeInput().value)).toEqual(valueExpression)
    } else {
      expect(codeInput().value).toBe(valueExpression)
    }
  })

  it("edits JSON objects, switches to an expression and back, then clears without restoring stored values", async () => {
    editor = await mountEditor("process", { steps: [{ id: "assign-step", action: "assign_value", config: configFor({ code: "ctx.code" }) }] })
    const edited = { code: "ctx.new_code", minutes: 10 }
    await change(codeInput(), JSON.stringify(edited, null, 2))
    expect(sync(editor).steps[0].config.valueExpression).toEqual(edited)
    await editor.reopen()
    await change(codeInput(), "ctx.sms_vars")
    expect(sync(editor).steps[0].config.valueExpression).toBe("ctx.sms_vars")
    await editor.reopen()
    await change(codeInput(), "{}")
    expect(sync(editor).steps[0].config.valueExpression).toEqual({})
    await change(codeInput(), "   ")
    expect(sync(editor).steps[0].config).not.toHaveProperty("valueExpression")
    await editor.reopen()
    expect(codeInput().value).toBe("")
    expect(editor.controller.stepManager.collectSteps()[0].config).not.toHaveProperty("valueExpression")
  })

  it("keeps malformed object edits for validation instead of restoring the old hash", async () => {
    editor = await mountEditor("process", { steps: [{ id: "assign-step", action: "assign_value", config: configFor({ code: "ctx.code" }) }] })
    await change(codeInput(), '{"code":')
    expect(sync(editor).steps[0].config.valueExpression).toBe('{"code":')
    await editor.reopen()
    expect(codeInput().value).toBe('{"code":')
  })
})
