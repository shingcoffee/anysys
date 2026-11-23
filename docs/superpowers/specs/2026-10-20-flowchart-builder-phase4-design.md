# Flowchart builder — Phase 4: element property editor

Date: 2026-10-20 · Parent: `2026-10-16-flowchart-builder-refactor-design.md` · Handoff:
`docs/2026-10-19-flowchart-builder-remaining-work.md` §3 and `docs/2026-10-16-flowchart-builder-remaining-work.md`
§5 · Builds on Phase 3 (complete and verified 2026-10-20: `config_schema ported: true` DSL, server
`ActionCatalog` embedded in the editor, role-based step controls, inline step field errors with
`data-field-error` / `aria-invalid`, reference picker, `flowcharts:migrate_step_actions`).

Phase 4 gives every element (Start, End, Process, Decision, Loop, Subflow) and every connection a
property form that shows the main settings first, stores only what the generator reads, explains itself
in en and zh-CN, and reports errors under the field that caused them. Element fields are declared once,
in Ruby, the way step-action fields already are. Each requirement has an id and the check that proves it.

Owner decisions (binding): Phase 3 → Phase 4 → Phase 5 strictly in sequence; an expanded subflow is a
read-only preview (Phase 5); no backward-compatibility shims — stored data is converted by a rake task.

## 0. Baseline (audited on the working tree, 2026-10-20)

Phase 3 did not touch the element editor. Of the 28 problems listed in the handoff, 26 are still present
and 2 are partial (Start trigger keys are rejected on the server but the client code remains; Loop
messages are translated, the other element generators are not).

| Area | Measured |
|---|---|
| Element schemas | JS `ELEMENT_SCHEMAS` in `app/javascript/flowchart/constants/schemas.js` (264 lines) is the source of truth; `config_schemas:mirror` copies part of it into `lib/code_generators/config_schemas.rb`; CI runs `config_schemas:check`. Element generators use the legacy `field` DSL. |
| Tabs | `tab_manager.js` shows General / I/O / Advanced for every type; End, Loop and Subflow keep every main setting on Advanced; Start and Process show an empty Advanced pane. |
| Layout | Advanced is `grid grid-cols-2` with no breakpoint (`_editor.html.erb:664`, `form_builder.js:129`); condition builders take one column; 61 uses of `text-[9px]`/`[10px]`/`[11px]` under `property_editor/**`. |
| Dead fields | End `http_response` / `httpStatus` / `responseBody` (nothing reads `ctx[:http_status]`); branch `description` / `branchKey` / `matchValue` copies (codegen reads connections only); `defaultBranchIndex` (indexes connection-array order, the UI indexes port order); `accumulatorVariable` on while loops (collects 1..n); connection `priority` (no consumer, the hint text is false). |
| Confusing fields | three loop types; `iterations` defaults 10 (while) vs 100 (for_each, silently truncates); break/skip conditions are raw Ruby; decision mode is implicit (blank operator = value matching); `"true (boolean)"` / `"null"` options compile to strings; duplicate match values are not flagged; Subflow target is free text with a slug-like placeholder. |
| Round trip | cleared numbers redisplay the default; every debounced sync prunes hidden-mode values; non-schema keys survive every save and the server then rejects them; zh-CN auto labels compare with the English type name, so automatic labels stop working for Loop, Process and Decision. |
| Validation | `element_rules.js` results reach the problems panel only; `_validateBeforeSave` returns `true`; `element_config_invalid` problems carry no `field`. |
| Data loss | removing a branch deletes its target element without confirmation. |
| Dead code | `shared/_property_editor_modal.html.erb`, `CanvasBridge`, `_showFieldError`, `buildInlineCondition`, `buildSegmentedControl`, `branchFallbackNameFormat`, `_buildSelectOptions*`, `_buildConditionExpression`, `SUBFLOW_INACCESSIBLE_FIX_HINT`; Start trigger leftovers in `label_derivation.js`, `validation_mixin.js`, `validation_autofix.js`, `flowchart_canvas_controller.js`, `_editor.html.erb`, `maint_core.*.yml`, `flowchart_documenter.rb`. |
| Hard-coded text | `branch_manager.js` (`Branch N`, `Add Branch`, boolean/null options), `canvas_operations.js` (`"Process"`, `Branch: …` persisted into data), `dynamic_ports.js`, `templates/branch.js`, `renderers.js` (`(self)`), `label_derivation.js` (`→ name`), `form_builder.js` (English type name); English messages in the Start / End / Subflow / Decision generators. |
| Assistant seeding | `FlowchartDefinitions::UiConfigSchema.defaults_from` ignores visibility (`end` seeds `httpStatus: 200`, `decision` seeds `defaultBranchIndex: -1`); `Normalizer` labels with `type.capitalize`. |

## A. One field declaration per element (Ruby)

- **A1** The Start, End, Decision, Loop and Subflow generators move to `config_schema ported: true` with
  role fields (`enum`, `expression`, `input`, `literal`, `integer`, `flag`, `conditions`, `reference`).
  Process declares no element fields (its steps are the Steps tab). A `CodeGenerators::ConnectionSchema`
  declares the connection fields (`label`, `description`).
- **A2** `CodeGenerators::ElementCatalog.export(locale:)` returns, per element type, `{ type, label,
  defaultLabel, tabs, fields }` plus `connection: { fields }` and the condition `operators`, built with
  the Phase 3 `FieldPresenter` so element fields and step fields share one JSON shape (role, label, help,
  placeholder, default, options, visibility, group, min/max). The editor embeds it as
  `data-property-editor-element-catalog-value`.
- **A3** Labels, help texts, placeholders and option labels live in
  `config/locales/flowchart_elements*.{en,zh-CN}.yml` under `flowchart_elements.<type>.fields.<field>.*`
  (identical key sets; `action_i18n_keys_spec` gains an element counterpart).
- **A4** `ELEMENT_SCHEMAS`, `element_i18n.js` and its overlay value, `config_schemas:mirror` /
  `config_schemas:check`, `lib/tasks/extract_config_schemas.mjs`, `lib/code_generators/config_schemas.rb`
  and the CI step are deleted; specs that read the mirror read the Ruby schemas.
  `BRANCH_OPERATORS` moves to the catalog (operator labels come from the server).
- **A5** `UiConfigSchema` seeds element defaults from the ported schemas and honours visibility;
  `Normalizer` labels new elements with the translated `defaultLabel`.
- **A6** Generator validation returns field-addressed, translated errors; `ConfigValidator` forwards
  `field` on `element_config_invalid` exactly as it does for `step_config_invalid`.

Check: `ElementCatalog` spec (every field translated in both locales, round-trips through
`validate_config`); no `ELEMENT_SCHEMAS` or `config_schemas` reference left (`rg`); assistant seeding spec.

## B. Editor shell

- **B1 Tabs.** General (label, the element's main fields, Notes), Steps (Process) or Branches
  (Decision), I/O, and Advanced only when the type declares a visible `group: :advanced` field. The form
  opens on Steps / Branches for Process / Decision and on General otherwise. No tab renders empty.
- **B2 Layout.** One column. Condition builders, segmented controls and branch rows take the full
  width. Minimum type size `text-xs`; no `text-[9px]`/`[10px]`/`[11px]` remains under
  `property_editor/**`. The sidebar keeps `w-full sm:w-[420px]`; nothing overflows at 375 px.
- **B3 Notes.** `description` (key unchanged) renders as a collapsed "Notes" disclosure at the end of
  General; it opens when it has content.
- **B4 Controls.** Element fields render through the same role controls as step fields (Phase 3
  `config_fields` renderers, extracted into a shared module), so help text, "None" for optional enums,
  the reference picker and the conditions control behave identically.
- **B5 Inline errors.** Client checks (`element_rules.js`, each result now carrying `field`) and server
  `element_config_invalid` problems paint `data-field-error` under the field with `aria-invalid="true"`,
  reveal the tab and disclosure that holds it, and clear on edit. Save is blocked while a client error
  of severity `error` is present; warnings never block. `_validateBeforeSave` becomes this check.
- **B6 Round trip.** A cleared number stays empty and shows the default in its placeholder
  ("Default: 100"); nothing is stored and the generator default applies. Hidden-mode values survive
  while the form is open (switching back restores them); Save stores only visible schema fields plus
  `io_overrides`, `steps` and `condition`, so legacy keys disappear on the next save.
- **B7 Automatic labels.** A label is automatic when it is blank, equals the translated `defaultLabel`,
  or equals the label derived from the previous settings; only then does it follow the settings. The
  header shows the translated type label.

Check: Vitest for the tab, layout, error, round-trip and label rules; Playwright at 375 px and 1280 px.

## C. Conditions control (Decision and Loop)

- **C1** One conditions control for steps and elements: `controls/conditions.js` grows to cover the
  element needs and `branch_manager/condition_builder.js` + `query_count.js` are deleted after their
  behaviour is ported (field rows and record-count rows).
- **C2** Rows: left operand, operator, right operand (hidden for unary operators). Operators come from
  the catalog with translated labels and include `is_true`, `is_false`, `is_empty`, `is_not_empty`; the
  literal `true (boolean)` / `false (boolean)` / `null` operand options are removed. Every row needs an
  operator.
- **C3** Left operands offer upstream outputs and bound-entity fields as suggestions and accept any
  `ctx` path; right operands are literals unless they start with `ctx.` (unchanged generator rule).
- **C4** Rows join with AND / OR per gap, as stored today (`joins`). The control edits one flat group;
  nested groups are converted by the migration (K).

Check: Vitest per row kind and operator; generator specs for `is_true` / `is_false` / `is_empty`.

## D. Decision

- **D1** `routeBy`: `value` (route by the value of one operand, `subject`) or `condition` (Yes / No from
  condition rows). Stored explicitly; the blank-operator convention is removed.
- **D2** Branches tab: one row per outgoing connection in port order — Name (the connection label),
  Match value (text in value mode, Yes / No select in condition mode), and one "Otherwise" choice (empty
  match value). Add Branch adds a connection and a new box as today; labels default to the translated
  "Branch N".
- **D3** Branch data lives only on the connection (`label`, `matchValue`). `properties.branches`,
  `defaultBranchIndex`, branch `description` and `branchKey` are removed; ports derive from the outgoing
  connections ordered by `fromPort`.
- **D4** Rules (client and generator, translated, field-addressed): at least two branches; match values
  unique after trimming; at most one Otherwise; every non-Otherwise branch has a match value; condition
  mode needs Yes plus No or Otherwise.
- **D5** Switching `routeBy` clears match values except Otherwise and shows an inline notice; Undo
  restores them.
- **D6** Removing a branch removes its connection only; the target box stays on the canvas (the
  validator reports it if it becomes unreachable). No confirmation is needed because nothing is deleted.

Check: Vitest for branch rows and rules; decision generator specs (both modes, duplicates, Otherwise);
Playwright: add, rename, set match values, switch mode, remove a branch and see the box remain.

## E. Loop

- **E1** `loopType`: `while` ("Repeat while") or `for_each` ("For each item"), plus a `runOnceFirst`
  flag for while loops (replaces `do_while`).
- **E2** While: `condition` required (an error, not a warning). For each: `collection` (required `ctx`
  path) and `itemVariable` (default `item`).
- **E3** `maxIterations` 1–10,000, default 100 for both types, with a help text per type. Reaching the
  limit fails the run with the translated `flowchart_runtime.errors.loop_limit` (`max`) instead of
  stopping silently or truncating the collection.
- **E4** Advanced: "Stop early when" (`stopWhen`, conditions), "Skip item when" (`skipWhen`, conditions,
  for each only), `indexVariable` (for each only), "Collect items into" (`collectInto`, for each only).
  Raw-Ruby `breakCondition` / `skipCondition` and `accumulatorVariable` are removed.

Check: loop generator specs (both types, `runOnceFirst`, limit error, stop / skip conditions, collect);
Vitest for visibility; Playwright for a for-each loop with a skip condition.

## F. End, Start, Subflow, Connection

- **F1 End.** `responseType`: `none` ("Nothing") or `value` ("Return a value"); `returnValue` shown and
  required for `value`, placeholder `ctx.result`, help text. `http_response`, `httpStatus` and
  `responseBody` leave the generator, schema, rules, autofix, navigation and label derivation.
- **F2 Start.** Label and Notes only. Every trigger leftover is deleted (client code, values, ERB,
  locale keys, documenter).
- **F3 Subflow.** `flowchartId` is a `reference` field backed by a `flowcharts` reference source: the
  searchable picker lists launched flowcharts the editor's customer can use (own + shared), excludes the
  flowchart being edited, stores the numeric id and shows the name. The source is owner-gated like the
  editor and scoped to the URL customer.
- **F4 Connection.** Label and Notes; `priority` leaves the form, serialization and locales.

Check: generator / validator specs per element; reference-source request spec (tenant isolation, owner
gate, excludes self); Playwright for End, Start, Subflow and a connection.

## G. Cleanup and I18n

- **G1** Delete the dead code listed in §0 (and its specs and values).
- **G2** Every user-facing string in the element editor comes from Stimulus values with English
  defaults and server-passed `data-*-value`; nothing English is written into stored element data
  (`canvas_operations.js` uses the translated labels).
- **G3** Element generators and validators use `I18n.t`; en and zh-CN key sets and `%{}` variables match.

Check: `rg` for the deleted symbols returns nothing; `raise_on_missing_translations` request specs;
locale parity spec.

## K. Stored data: `flowcharts:migrate_element_properties`

> **Dropped (owner, 2026-10-20):** existing flowcharts will be deleted manually, so no stored-data
> migration ships. Old shapes are simply rejected by the generators. The table below is kept for history only.

Modelled on `flowcharts:migrate_step_actions` (dry run by default, `APPLY=1` writes a new version per
changed flowchart and regenerates its activity, report of changed / unchanged / blocked / failed, exit
non-zero while anything is blocked or fails, customer heads handled like the step migration).

| Stored | Becomes |
|---|---|
| End `http_response` | `none` (report notes the dropped status and body; nothing read them) |
| Decision with blank-operator single row | `routeBy: value`, `subject` = the operand |
| Decision `defaultBranchIndex` ≥ 0 | that connection's match value cleared (Otherwise), blocked if another Otherwise exists |
| `properties.branches`, branch `description` / `branchKey` | dropped (labels and match values already on connections; a branch-only match value is copied to its connection first) |
| Nested condition groups | flattened when all joins in the nesting agree; otherwise blocked |
| Loop `do_while` | `while` + `runOnceFirst: true` |
| Loop `iterations` | `maxIterations` (blank → default) |
| `breakCondition` / `skipCondition` | a single `is_true` row when the text is a plain `ctx` path; otherwise blocked |
| `accumulatorVariable` | `collectInto` on for each; dropped on while |
| Connection `priority`, Start trigger keys, other non-schema keys | dropped |

Check: migration spec per row; dry run on development.

## L. Developer docs (en and zh-CN in lockstep)

`flowchart-builder.md` (element forms, tabs, branches, inline errors), `code-generators.md` (element
schemas in Ruby, `ElementCatalog`, mirror removal), `flowchart-runtime.md` (`loop_limit`), and the
migration task in the deploy notes.

## M. Verification

`npm run coverage` at 100/100/100/100; full parallel RSpec (known reds only); Playwright per editor in en
and one zh-CN pass, at 375 px and 1280 px; migration dry run; dev-server smoke; tech-lead and
code-reviewer in parallel until both pass.

## Tasks (waves; files within a wave are disjoint)

| Wave | Task | Scope | Owns |
|---|---|---|---|
| 1 | BE-1 | A1–A6 for Start, End, Subflow, Connection; `ElementCatalog` (incl. operators); mirror removal; seeding; `flowcharts` reference source (F3 server half); F1/F2 generator side | element_types/{start,end,subflow}, `element_catalog.rb`, `connection_schema.rb`, `ui_config_schema.rb`, `normalizer.rb`, reference sources, `flowchart_elements.*.yml`, `lib/tasks/config_schemas.rake` |
| 1 | BE-2 | D1, D3, D4 generator side; C2 operators in `ConditionBuilder` | element_types/decision, `shared/condition_builder.rb`, `shared/operand_converter.rb`, `flowchart_elements_decision.*.yml` |
| 1 | BE-3 | E1–E4 generator and runtime | element_types/loop, runtime loop error, `flowchart_elements_loop.*.yml` |
| 2 | FE-1 | B1–B7; editor embed of the catalog | `property_editor_controller.js`, `tab_manager.js`, `form_builder.js`, `field_visibility.js`, `element_config.js`, `label_derivation.js`, `ui_feedback.js`, `_editor.html.erb`, shared control renderer |
| 3 | FE-2 | C1–C4 | `controls/conditions*.js`, delete `condition_builder.js` / `query_count.js` |
| 3 | FE-3 | D2, D5, D6 and the client half of D3/D4 | `branch_manager*.js`, `templates/branch.js`, `connection_manager.js`, `dynamic_ports.js`, `canvas_operations.js`, `element_rules.js` |
| 3 | FE-4 | F1–F4 client side, G1/G2 leftovers outside FE-1–FE-3 | `validation_*`, `flowchart_canvas_controller.js`, subflow picker wiring, connection form, `canvas_bridge.js`, templates |
| 4 | ~~MIG~~ (dropped) | K | `FlowchartDefinitions::ElementPropertyMigration`, rake task, specs |
| 4 | E2E | Playwright per editor | `spec/e2e/**` |
| 4 | DOCS | L | `doc/reference/{en,zh-CN}/**` |
| 5 | VERIFY | M | — |

## Open questions (recommended defaults are applied unless the owner says otherwise)

1. **Notes key.** Keep the stored key `description` and label it "Notes". *Default: yes.*
2. **Branch storage.** Drop `properties.branches` and derive ports from connections. *Default: yes.*
3. **Removing a branch.** Remove the connection, keep the box (no confirmation). Alternative: confirm,
   then delete the box. *Default: keep the box.*
4. **Loop limit reached.** Fail the run with a translated error. Alternative: stop silently (today's
   behaviour, which also truncates for-each collections). *Default: fail.*
5. **Nested condition groups.** The control edits one flat group; the migration flattens or blocks.
   *Default: yes.*
6. **Raw-Ruby stop / skip conditions.** Convert plain `ctx` paths, block the rest for a person to
   rewrite. *Default: yes.*
7. **End `http_response`.** Convert to `none` without blocking (nothing consumed it). *Default: yes.*

## Out of scope

Canvas behaviour (Phase 5): placement, saving conflicts, undo/redo, expanded subflows, read-only
guards, validation de-duplication, glyph-width truncation, shortcuts. Element I/O pin rendering stays
as Phase 2 left it.
