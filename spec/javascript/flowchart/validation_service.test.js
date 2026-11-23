import { describe, it, expect, afterEach } from "vitest"
import { ValidationService } from "flowchart/validation_service"
import { setElementCatalog } from "flowchart/constants/element_registry"

// Pure logic: takes plain element/connection arrays, returns {errors, warnings}.
const run = (elements, connections = []) =>
  new ValidationService(elements, connections).validate()

const el = (id, type, props = {}, label = id) => ({ id, type, label, properties: props })
const conn = (from, to, extra = {}) => ({ id: `${from}-${to}`, from, to, ...extra })

const typesOf = (list) => list.map((e) => e.type)

describe("ValidationService — structure", () => {
  it("flags a missing Start as an error and a missing End as a warning", () => {
    const { errors, warnings } = run([el("p1", "process")], [])
    expect(typesOf(errors)).toContain("missing_start")
    expect(typesOf(warnings)).toContain("missing_end")
  })

  it("flags duplicate Start elements (all but the first)", () => {
    const { errors } = run(
      [el("s1", "start"), el("s2", "start"), el("e1", "end")],
      [conn("s1", "e1")]
    )
    const dup = errors.filter((e) => e.type === "duplicate_start")
    expect(dup).toHaveLength(1)
    expect(dup[0].elementId).toBe("s2")
  })

  it("flags a Start with no outgoing connection as orphan_start", () => {
    const { errors } = run([el("s1", "start"), el("e1", "end")], [])
    expect(typesOf(errors)).toContain("orphan_start")
  })

  it("flags a fully disconnected non-terminal as orphan_element (not unreachable)", () => {
    const { errors } = run(
      [el("s1", "start"), el("e1", "end"), el("p1", "process")],
      [conn("s1", "e1")]
    )
    expect(typesOf(errors)).toContain("orphan_element")
    // it has no connection, so unreachable is intentionally suppressed
    expect(errors.filter((e) => e.type === "unreachable")).toHaveLength(0)
  })

  it("flags a connected-but-unreachable element", () => {
    // p1<->p2 form an island connected to each other but not to start
    const { errors } = run(
      [el("s1", "start"), el("e1", "end"), el("p1", "process"), el("p2", "process")],
      [conn("s1", "e1"), conn("p1", "p2")]
    )
    expect(typesOf(errors)).toContain("unreachable")
  })

  it("flags every member of a duplicate-label group", () => {
    const { errors } = run(
      [el("s1", "start", {}, "Go"), el("a", "process", {}, "Same"), el("b", "process", {}, "same"), el("e1", "end", {}, "Stop")],
      [conn("s1", "a"), conn("a", "b"), conn("b", "e1")]
    )
    const dupLabels = errors.filter((e) => e.type === "duplicate_label")
    expect(dupLabels.map((e) => e.elementId).sort()).toEqual(["a", "b"])
  })

  it("tolerates elements with no label (blank/whitespace) when grouping by label", () => {
    const { errors } = run(
      [el("s1", "start", {}, "Go"), el("a", "process", {}, null), el("b", "process", {}, "   "), el("e1", "end", {}, "Stop")],
      [conn("s1", "a"), conn("a", "b"), conn("b", "e1")]
    )
    // Neither the null-label nor whitespace-only-label element groups with anything.
    expect(errors.filter((e) => e.type === "duplicate_label")).toEqual([])
  })
})

describe("ValidationService — completeness per element type", () => {
  afterEach(() => setElementCatalog(null))

  it("prefixes rule messages with the element label and translated type", () => {
    setElementCatalog({ types: { process: { type: "process", label: "流程", fields: [] } } })
    const messages = { elementProblemFormat: "{label}（{type}）：{message}", emptyProcess: "请添加步骤" }
    const { warnings } = new ValidationService(
      [el("s1", "start"), el("p1", "process", { steps: [] }, "Save"), el("e1", "end")],
      [conn("s1", "p1"), conn("p1", "e1")],
      messages
    ).validate()
    expect(warnings.find((w) => w.type === "empty_process").message).toBe("Save（流程）：请添加步骤")
  })

  it("falls back to the raw type and English wording without a catalog", () => {
    const { warnings } = run(
      [el("s1", "start"), el("p1", "process", { steps: [] }, "Save"), el("e1", "end")],
      [conn("s1", "p1"), conn("p1", "e1")]
    )
    expect(warnings.find((w) => w.type === "empty_process").message).toBe("Save (process): Add at least one step")
  })

  it("warns on a process with no steps", () => {
    const { warnings } = run(
      [el("s1", "start"), el("p1", "process", { steps: [] }), el("e1", "end")],
      [conn("s1", "p1"), conn("p1", "e1")]
    )
    expect(typesOf(warnings)).toContain("empty_process")
  })

  it("errors on a decision with fewer than two outgoing connections", () => {
    const { errors } = run(
      [el("s1", "start"), el("d1", "decision", { routeBy: "value" }), el("e1", "end")],
      [conn("s1", "d1"), conn("d1", "e1")]
    )
    expect(typesOf(errors)).toContain("too_few_branches")
  })

  it("errors on a condition Decision that is missing a Yes branch", () => {
    const { errors } = run(
      [el("s1", "start"), el("d1", "decision", { routeBy: "condition" }), el("a", "end"), el("b", "end")],
      [conn("s1", "d1"), conn("d1", "a", { matchValue: "false" }), conn("d1", "b")]
    )
    expect(typesOf(errors)).toContain("missing_yes_branch")
  })

  it("does not flag leftover duplicate-label Decision warnings", () => {
    const { warnings, errors } = run(
      [el("s1", "start"), el("d1", "decision", { routeBy: "value" }), el("a", "end"), el("b", "end")],
      [conn("s1", "d1"), conn("d1", "a", { label: "Yes", matchValue: "a" }), conn("d1", "b", { label: "yes", matchValue: "b" })]
    )
    expect(typesOf(warnings)).not.toContain("decision_branch_duplicate_label")
    expect(typesOf(errors)).not.toContain("decision_branch_duplicate_label")
  })

  it("errors on subflow with no target and end that returns a value with no expression", () => {
    const { errors } = run(
      [el("s1", "start"), el("sf", "subflow", {}), el("e1", "end", { responseType: "value", returnValue: "" })],
      [conn("s1", "sf"), conn("sf", "e1")]
    )
    const t = typesOf(errors)
    expect(t).toContain("subflow_no_target")
    expect(t).toContain("end_no_return_value")
  })

  it("errors on subflow with a whitespace-only target, and end returning a whitespace-only value", () => {
    const { errors } = run(
      [
        el("s1", "start"),
        el("sf", "subflow", { flowchartId: "   " }),
        el("e1", "end", { responseType: "value", returnValue: "   " }),
      ],
      [conn("s1", "sf"), conn("sf", "e1")]
    )
    const t = typesOf(errors)
    expect(t).toContain("subflow_no_target")
    expect(t).toContain("end_no_return_value")
  })

  it("errors on unsupported structural Switch elements", () => {
    const { errors } = run(
      [el("s1", "start"), el("sw", "switch"), el("e1", "end")],
      [conn("s1", "sw"), conn("sw", "e1")]
    )
    expect(errors).toEqual(expect.arrayContaining([
      expect.objectContaining({ elementId: "sw", type: "unsupported_structural_element" })
    ]))
  })

  it("errors on unsupported structural Timer elements", () => {
    const { errors } = run(
      [el("s1", "start"), el("t1", "timer"), el("e1", "end")],
      [conn("s1", "t1"), conn("t1", "e1")]
    )
    expect(errors).toEqual(expect.arrayContaining([
      expect.objectContaining({ elementId: "t1", type: "unsupported_structural_element" })
    ]))
  })

})

describe("ValidationService — element configuration", () => {
  const wrap = (element, connections = []) =>
    run([el("s1", "start"), element, el("e1", "end")], [conn("s1", element.id), ...connections, conn(element.id, "e1")])

  it("does not flag a leftover defaultBranchIndex", () => {
    const { errors } = run(
      [el("s1", "start"), el("d1", "decision", { routeBy: "value", defaultBranchIndex: 4 }), el("a", "end"), el("b", "end")],
      [conn("s1", "d1"), conn("d1", "a", { matchValue: "Yes" }), conn("d1", "b", { matchValue: "No" })]
    )
    expect(errors.find((e) => e.type === "decision_default_branch_out_of_range")).toBeUndefined()
  })

  it("uses the injected localized message for an orphan Start", () => {
    const service = new ValidationService(
      [el("s1", "start", {}, "Go")],
      [],
      { orphanStartFormat: '本地化：开始"{label}"没有出口' }
    )
    const problem = service.validate().errors.find((item) => item.type === "orphan_start")
    expect(problem.message).toBe('本地化：开始"Go"没有出口')
  })

  it("flags a Subflow that targets the flowchart being edited", () => {
    const service = new ValidationService(
      [el("s1", "start"), el("sf", "subflow", { flowchartId: "42" })],
      [conn("s1", "sf")],
      {},
      { flowchartId: 42 }
    )
    const { errors } = service.validate()
    expect(typesOf(errors)).toContain("subflow_self_reference")
    expect(typesOf(errors)).not.toContain("subflow_no_target")
  })

  it("treats an element with no properties object as fully unconfigured", () => {
    const service = new ValidationService([{ id: "p1", type: "process", label: "P" }], [])
    expect(typesOf(service.validate().warnings)).toContain("empty_process")
  })

  it("falls back to an empty string for an unknown structural message key", () => {
    const service = new ValidationService(
      [el("s1", "start", {}, "Go"), el("e1", "end")],
      [],
      { orphanStartFormat: undefined }
    )
    const { errors } = service.validate()
    expect(errors.find((e) => e.type === "orphan_start").message).toBe("")
  })

  it("renders an element with no label as an empty label rather than the string null", () => {
    const service = new ValidationService([el("s1", "start", {}, null), el("e1", "end")], [])
    const { errors } = service.validate()
    expect(errors.find((e) => e.type === "orphan_start").message).toBe('Start element "" has no outgoing connections')
  })
})

describe("ValidationService — connections & cycles", () => {
  it("flags dangling, self, and duplicate connections", () => {
    const { errors, warnings } = run(
      [el("s1", "start"), el("e1", "end")],
      [conn("s1", "e1"), conn("s1", "e1"), conn("s1", "ghost"), conn("ghost2", "e1"), conn("s1", "s1")]
    )
    expect(typesOf(errors).filter((t) => t === "dangling_connection")).toHaveLength(2)
    expect(typesOf(errors)).toContain("self_connection")
    expect(typesOf(warnings)).toContain("duplicate_connection")
  })

  it("carries the connection id on every connection-level problem so the panel can select the edge", () => {
    const { errors, warnings } = run(
      [el("s1", "start"), el("e1", "end")],
      [conn("s1", "e1"), conn("s1", "e1"), conn("s1", "ghost"), conn("s1", "s1")]
    )
    expect(errors.find((e) => e.type === "dangling_connection").connectionId).toBe("s1-ghost")
    expect(errors.find((e) => e.type === "self_connection").connectionId).toBe("s1-s1")
    expect(warnings.find((w) => w.type === "duplicate_connection").connectionId).toBe("s1-e1")
  })

  it("reports a node caught in a cycle once, however many paths reach it", () => {
    // s1 reaches the a→b→a cycle through two routes; the old recursive walk
    // emitted one warning per route.
    const { warnings } = run(
      [el("s1", "start"), el("a", "process"), el("b", "process"), el("c", "process"), el("e1", "end")],
      [conn("s1", "a"), conn("s1", "c"), conn("c", "a"), conn("a", "b"), conn("b", "a"), conn("a", "e1")]
    )
    expect(warnings.filter((w) => w.type === "cycle")).toHaveLength(1)
  })

  it("reports each distinct cycle separately", () => {
    const { warnings } = run(
      [el("s1", "start"), el("a", "process"), el("b", "process"), el("c", "process"), el("d", "process")],
      [conn("s1", "a"), conn("a", "b"), conn("b", "a"), conn("s1", "c"), conn("c", "d"), conn("d", "c")]
    )
    expect(warnings.filter((w) => w.type === "cycle").map((w) => w.elementId).sort()).toEqual(["a", "c"])
  })

  it("does not follow a dangling edge into a node that has no adjacency entry", () => {
    const { errors, warnings } = run([el("s1", "start"), el("e1", "end")], [conn("s1", "e1"), conn("e1", "ghost")])
    expect(typesOf(errors)).toContain("dangling_connection")
    expect(typesOf(warnings)).not.toContain("cycle")
  })

  it("warns about a cycle", () => {
    const { warnings } = run(
      [el("s1", "start"), el("a", "process"), el("b", "process"), el("e1", "end")],
      [conn("s1", "a"), conn("a", "b"), conn("b", "a"), conn("a", "e1")]
    )
    expect(typesOf(warnings)).toContain("cycle")
  })

  it("does not warn about a cycle that involves a Loop element", () => {
    const { warnings } = run(
      [el("s1", "start"), el("l1", "loop", { loopType: "while", condition: { leftOperand: "x" } }), el("a", "process"), el("e1", "end")],
      [conn("s1", "l1"), conn("l1", "a"), conn("a", "l1"), conn("l1", "e1")]
    )
    expect(typesOf(warnings)).not.toContain("cycle")
  })

  it("rejects unsupported structural elements such as join", () => {
    const { errors } = run(
      [el("s1", "start"), el("j1", "join"), el("e1", "end")],
      [conn("s1", "j1"), conn("j1", "e1")]
    )
    expect(errors).toEqual(expect.arrayContaining([
      expect.objectContaining({ elementId: "j1", type: "unsupported_structural_element" })
    ]))
  })

  it("isValid reflects the presence of errors", () => {
    const service = new ValidationService([el("p1", "process")], [])
    service.validate()
    expect(service.isValid).toBe(false)

    const ok = new ValidationService(
      [el("s1", "start"), el("e1", "end")],
      [conn("s1", "e1")]
    )
    ok.validate()
    expect(ok.isValid).toBe(true)
  })

  it("_safe returns the raw label (renderer escapes once, avoiding double-encoding)", () => {
    const { errors } = run([el("s1", "start", {}, "Tom & Jerry"), el("e1", "end")], [])
    const orphan = errors.find((e) => e.type === "orphan_start")
    expect(orphan.message).toContain("Tom & Jerry")
  })

  it("_safe returns an empty string for a null/undefined label", () => {
    const { errors } = run([el("s1", "start", {}, null), el("e1", "end")], [])
    const orphan = errors.find((e) => e.type === "orphan_start")
    expect(orphan.message).toBe('Start element "" has no outgoing connections')
  })
})
