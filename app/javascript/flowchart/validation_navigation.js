/**
 * Maps validation rule codes to property-editor navigation targets.
 * tab: which property-editor tab to activate (general|steps|io|advanced).
 * anchor: CSS selector resolved INSIDE the editor form; falls back to
 *         tab-switch only when it doesn't resolve.
 * anchorFn(problem): dynamic selector built from problem.meta.
 * fixHint: default hint shown under the problem message.
 *
 * Anchors verified against the real form:
 * - element label renders as [name="label"] on the "general" tab
 * - every catalog field renders inside [data-element-field="<name>"]
 *   (field_renderer.js); main fields live on "general"
 * - decision branches render [data-element-field="branches"] on "branches"
 * - I/O rows render [data-element-io-input][data-pin="<raw pin>"]
 *   (element_io/renderers.js) — data-pin is the RAW pin name
 * Where no stable selector exists, anchor is omitted (tab-switch only).
 * Flowchart-level rules with no element to open are null.
 *
 * i18n seam: `fixHint` strings below are the English defaults for this plain
 * lookup module (no controller reference). ValidationMixin threads translated
 * overrides into `navFor(problem, hints)` from flowchart_canvas_controller.js's
 * `fixHint*` Values; omitting `hints` (as existing calls/specs do) keeps this
 * table's English output byte-identical.
 */
const field = (name) => `[data-element-field="${name}"]`
const BRANCHES = { tab: "branches", anchor: field("branches") }
const ADVANCED_FIELDS = new Set(["stopWhen", "skipWhen", "indexVariable", "collectInto"])
const PROBLEM_FIELD = {
  tabFn: (p) => ADVANCED_FIELDS.has(p.field) ? "advanced" : "general",
  anchorFn: (p) => p.field ? field(CSS.escape(p.field)) : null
}

export const RULE_NAV = {
  duplicate_start:                 { tab: "general", fixHint: "Delete the extra Start element" },
  orphan_start:                    null, // canvas-level: connect it — zoom only
  orphan_end:                      null,
  orphan_element:                  null,
  unreachable:                     null,
  duplicate_label:                 { tab: "general", anchor: '[name="label"]', fixHint: "Rename this element to a unique label" },
  empty_process:                   { tab: "steps", fixHint: "Add at least one step" },
  too_few_branches:                BRANCHES,
  duplicate_match_value:           BRANCHES,
  multiple_otherwise:              BRANCHES,
  invalid_condition_match:         BRANCHES,
  missing_yes_branch:              BRANCHES,
  condition_invalid:               PROBLEM_FIELD,
  loop_invalid_collection:         PROBLEM_FIELD,
  loop_reserved_variable:          PROBLEM_FIELD,
  loop_colliding_variables:        PROBLEM_FIELD,
  loop_no_collection:              { tab: "general", anchor: field("collection"), fixHint: "Specify the collection to iterate" },
  empty_loop_condition:            { tab: "general", anchor: field("condition"), fixHint: "Define the loop condition" },
  step_config_invalid:             { tab: "steps",    fixHint: "Fix this step's configuration" },
  element_config_invalid:          { tab: "general", anchorFn: (p) => p.field ? `[data-element-field="${CSS.escape(p.field)}"]` : null, fixHint: "Fix this element's configuration" },
  subflow_no_target:               { tab: "general", anchor: field("flowchartId"), fixHint: "Select a target flowchart" },
  subflow_inaccessible:            { tab: "general", anchor: field("flowchartId"), fixHint: "Select a flowchart that belongs to this customer or is shared" },
  subflow_cycle:                   { tab: "general", anchor: field("flowchartId"), fixHint: "Remove the circular subflow reference" },
  subflow_self_reference:          { tab: "general", anchor: field("flowchartId"), fixHint: "Point this Subflow at a different flowchart" },
  end_no_return_value:             { tab: "general", anchor: field("returnValue"), fixHint: "Provide the Return Value expression" },
  missing_input:                   { tab: "io", anchorFn: (p) => p.meta?.pinKey ? `[data-element-io-input][data-pin="${CSS.escape(p.meta.pinKey)}"]` : null, fixHint: "Pick a producer for this input or add an upstream step that emits it" },
  codegen_todo:                    { tab: "steps", fixHint: "This step/element has no code generator — change the action or element type" },
  // flowchart-level rules (no element): missing_start, missing_end,
  // dangling_connection, duplicate_connection, self_connection, cycle,
  // codegen_failed, codegen_check_timeout, server_check_unavailable → null
}

/**
 * @param {Object} problem
 * @param {Object} [hints] - Translated fixHint overrides keyed by rule type,
 *   sourced from flowchart_canvas_controller.js's `fixHint*` Values (see the
 *   i18n seam comment atop RULE_NAV). English callers/specs that omit `hints`
 *   fall through to each entry's own (English) `fixHint`, keeping this
 *   byte-identical to the pre-i18n behavior.
 */
export function navFor(problem, hints = {}) {
  const entry = RULE_NAV[problem.type]
  if (!entry) return null
  const anchor = entry.anchorFn ? entry.anchorFn(problem) : (entry.anchor || null)
  const tab = entry.tabFn ? entry.tabFn(problem) : entry.tab
  return { tab: tab || null, anchor, fixHint: problem.fixHint || hints[problem.type] || entry.fixHint || null }
}
