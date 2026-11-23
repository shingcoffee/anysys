# Generator Authoring Checklist

This checklist is the rubric every generator under `app/services/code_generators/element_types/` is held to. It exists because the code-generator layer had drifted from its canonical shape (the Trailblazer Railway example in the project spec), and we needed a written standard so the next drift stays caught.

**Mechanical rules (1, 2, 4, 5, 7, 8, 10, 11, 12, 13 in the spec) are checked by `scripts/audit_generators.rb` and `scripts/audit_generator_ui.rb`.** Run them before shipping a new generator:

```bash
bundle exec rake audit:generators
bundle exec ruby scripts/audit_generator_ui.rb
```

Both must exit 0.

**Judgment rules (3, 6, 9)** are listed below. Self-review against them before opening a PR.

---

## Judgment rule 3 — Single responsibility per step body

The canonical example has four steps — `model`, `contract`, `validate`, `save` — and each one does exactly one thing:

- `model` creates an empty model.
- `contract` wraps the model in a Reform contract.
- `validate` validates the contract with params.
- `save` persists.

If your generator's body does more than one of the conceptual operations below, it's probably two steps fused together:

- Create / find a record
- Wrap a record in a contract
- Assign attributes to a record
- Validate
- Save
- Touch / reload
- Destroy
- Cascade-delete associations
- Enqueue a job
- Send a notification
- Log

If you're unsure, ask: "Would the canonical example fuse these two things?" If the example would keep them separate, so should your generator.

## Judgment rule 6 — Build-time vs runtime knobs

The step body is runtime code. Every `config["..."]` read in the body becomes a runtime decision that ships with the generated file. Check each config key you read and ask: **would this knob be a sensible call signature on the canonical example?**

If the answer is no, the knob is build-time metadata and does not belong in the step body. Examples from the pre-refactor code:

- `cachePerClass`, `cacheContract`, `validateOnBuild` — these described how to construct the contract, not how it runs. They belonged in a factory or were pure overengineering. The canonical example has none of them.
- `strictMode`, `includeWarnings` — these described validator internals. In the canonical example, `validate` is one line. A "strict" validator is a different contract class, not a strict-mode flag on the step.
- `integratePermission`, `permissionType`, `policyAction` — permission checking is a separate step (`authorize`), not a flag on `validate`.

Build-time metadata that's worth keeping usually lives on the class itself (via `generator_metadata` DSL), not in the emitted body.

## Judgment rule 9 — Multi-tenancy: customer_id scoping

Every model read and write in a step body must respect multi-tenancy:

- **Reads:** Queries through `EntityEntry.build_for(ctx[:bound_entity])` must apply `.where(customer_id: ctx[:customer_id])`. Direct `Model.find(id)` calls are forbidden unless the model is known to be non-tenant (rare).
- **Writes on create:** `ctx[:model].customer_id = ctx[:customer_id]` (or set via contract sync).
- **Writes on update:** inherited from the existing record; don't change it.

If your generator operates on raw strings / non-model data (e.g. a string formatter or a cache read), rule 9 doesn't apply.

---

## When a new rule is needed

If a reviewer repeats the same judgment call across multiple generators, promote the pattern to a mechanical rule in `scripts/audit_generators.rb`. Add the check, regenerate the baseline, commit the new baseline alongside the code change. The prose checklist and the script should never disagree.
