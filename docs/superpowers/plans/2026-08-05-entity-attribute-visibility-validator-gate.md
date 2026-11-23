# Entity Attribute Visibility→Validator Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an entity attribute is not Visible to an audience, Apply validators is forced off for that audience in the Add/Edit Attribute modal, in saved schema JSON, and at entry-validation runtime.

**Architecture:** One invariant — `visibility[a] == false ⇒ validator_apply[a] == false` — enforced in three places: (1) Stimulus modal sync (disable + uncheck Apply; re-check on Visible on), (2) JS coerce helper used when collecting/persisting attribute rows and rendering view badges, (3) `EntityEntryContract#validators_apply_for_audience?` skips validators when the field is not visible for the audience.

**Tech Stack:** StimulusJS (entity_form managers), Vitest, Rails Reform contract (`EntityEntryContract`), RSpec.

**Reference spec:** `docs/superpowers/specs/2026-08-05-entity-attribute-visibility-validator-gate-design.md`

## Global Constraints

- No hard-coded user-facing strings in JS/views; reuse existing i18n keys (no new copy required).
- `app/javascript/**` must stay at 100% Vitest lines + branches (`npx vitest run --coverage`).
- Do not auto-commit unless the human explicitly asks; commit steps below are optional checkpoints.
- Audiences are exactly `admin`, `member`, `public`.
- Missing `visibility` means visible to all (same as today’s `normalizeVisibility`).
- Missing `validator_apply` means apply to all **visible** audiences (visibility still wins).
- Audience-nil `EntityEntryContract.build_for` stays backward-compatible (no audience gate).

---

## File Map

### Modified files
- `app/javascript/controllers/entity_form/schema_manager.js` — add `coerceValidatorApply(visibility, validatorApply)`; use in `updateAttributeRow` / `extractAttributeFromRow`
- `app/javascript/controllers/entity_form/modal_manager.js` — sync helpers; call from reset/prefill/visibility change
- `app/javascript/controllers/entity_form_controller.js` — delegate `visibilityAudienceChanged(event)`
- `app/javascript/controllers/entity_form/attribute_manager.js` — coerce inside `collectValidatorApply`
- `app/javascript/controllers/entity_form/template_builder.js` — coerce Apply badges in view/row HTML
- `app/components/admin/maintenance/entities/attribute_modal_component.html.erb` — change action on Visible checkboxes
- `app/contracts/entity_entry_contract.rb` — visibility check inside `validators_apply_for_audience?`

### Test files
- `spec/javascript/controllers/entity_form/schema_manager.test.js`
- `spec/javascript/controllers/entity_form/modal_manager.test.js`
- `spec/javascript/controllers/entity_form/template_builder.test.js`
- Attribute collect coverage via attribute_manager test file if present, else modal/schema suite
- `spec/contracts/entity_entry_contract_spec.rb`
- `spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb`

---

### Task 1: Contract runtime gate (visibility wins)

**Files:**
- Modify: `app/contracts/entity_entry_contract.rb` (`validators_apply_for_audience?`)
- Test: `spec/contracts/entity_entry_contract_spec.rb`

**Interfaces:**
- Consumes: attribute hash with optional `"visibility"` / `"validator_apply"` maps
- Produces: `validators_apply_for_audience?(attr, audience) -> Boolean` — false when visibility for audience is false; else existing validator_apply logic

- [ ] **Step 1: Write the failing examples**

Append inside `describe '.build_for with attribute-level validator_apply'`:

```ruby
def entity_with_visibility(validators:, visibility: nil, validator_apply: nil)
  attr = { 'name' => 'Nickname', 'name_slug' => 'nickname', 'validators' => validators }
  attr['visibility'] = visibility if visibility
  attr['validator_apply'] = validator_apply if validator_apply
  instance_double(Entity, property_schema_json: [attr])
end

it 'skips validators when visibility is false for the audience even if validator_apply is true' do
  klass = described_class.build_for(
    entity_with_visibility(
      validators: [{ 'type' => 'presence' }],
      visibility: { 'admin' => true, 'member' => true, 'public' => false },
      validator_apply: { 'admin' => true, 'member' => true, 'public' => true }
    ),
    audience: :public
  )
  expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be true
end

it 'skips validators when visibility is false and validator_apply is missing' do
  klass = described_class.build_for(
    entity_with_visibility(
      validators: [{ 'type' => 'presence' }],
      visibility: { 'admin' => true, 'member' => true, 'public' => false }
    ),
    audience: :public
  )
  expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be true
end

it 'still applies validators when visible and validator_apply is missing' do
  klass = described_class.build_for(
    entity_with_visibility(
      validators: [{ 'type' => 'presence' }],
      visibility: { 'admin' => true, 'member' => true, 'public' => true }
    ),
    audience: :public
  )
  expect(klass.new(model_struct.new(nickname: nil)).validate({})).to be false
end
```

- [ ] **Step 2: Run to verify fail**

Run: `bundle exec rspec spec/contracts/entity_entry_contract_spec.rb -e "visibility is false" --format documentation`

Expected: FAIL — validators still applied (validate returns false) because visibility is ignored today.

- [ ] **Step 3: Implement minimal gate**

Replace `validators_apply_for_audience?` in `app/contracts/entity_entry_contract.rb` with:

```ruby
# Attribute-level gate: not Visible ⇒ validators do not apply.
# When +validator_apply+ is missing, all *visible* audiences apply (backward compatible).
# When present, false for an audience skips every validator.
def validators_apply_for_audience?(attr, audience)
  return false unless attribute_visible_for_audience?(attr, audience)

  apply = attr.is_a?(Hash) ? (attr["validator_apply"] || attr[:validator_apply]) : nil
  return true if apply.blank?

  apply[audience] != false && apply[audience.to_sym] != false
end

def attribute_visible_for_audience?(attr, audience)
  visibility = attr.is_a?(Hash) ? (attr["visibility"] || attr[:visibility]) : nil
  return true if visibility.blank?

  visibility[audience] != false && visibility[audience.to_sym] != false
end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/contracts/entity_entry_contract_spec.rb --format documentation`

Expected: PASS (including prior validator_apply examples).

- [ ] **Step 5: Commit (only if human asked)**

```bash
git add app/contracts/entity_entry_contract.rb spec/contracts/entity_entry_contract_spec.rb
git commit -m "fix: skip entity validators when attribute is not visible to audience"
```

---

### Task 2: `coerceValidatorApply` helper (save normalize)

**Files:**
- Modify: `app/javascript/controllers/entity_form/schema_manager.js`
- Test: `spec/javascript/controllers/entity_form/schema_manager.test.js`

**Interfaces:**
- Consumes: `normalizeVisibility(visibility)`
- Produces: `coerceValidatorApply(visibility, validatorApply) -> { admin: boolean, member: boolean, public: boolean }` where each key is `normalizeVisibility(visibility)[k] && normalizeVisibility(validatorApply)[k]`

- [ ] **Step 1: Write the failing test**

Use the existing `buildController` / `SchemaManager` imports already in `schema_manager.test.js`:

```js
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
})
```

- [ ] **Step 2: Run to verify fail**

Run: `npx vitest run spec/javascript/controllers/entity_form/schema_manager.test.js -t "coerceValidatorApply"`

Expected: FAIL — `coerceValidatorApply is not a function`.

- [ ] **Step 3: Implement helper + use on row write**

In `schema_manager.js` after `normalizeVisibility`:

```js
coerceValidatorApply(visibility, validatorApply) {
  const v = this.normalizeVisibility(visibility)
  const a = this.normalizeVisibility(validatorApply)
  return {
    admin: v.admin && a.admin,
    member: v.member && a.member,
    public: v.public && a.public
  }
}
```

In `updateAttributeRow`, replace `normalizeVisibility(validator_apply)` with:

```js
const normalizedValidatorApply = this.coerceValidatorApply(visibility, validator_apply)
```

In `extractAttributeFromRow`, after reading visibility, coerce apply:

```js
const visibility = this.normalizeVisibility(this.parseVisibilityJson(getValue("visibility")))
const validatorApply = this.coerceValidatorApply(
  visibility,
  this.parseVisibilityJson(getValue("validator_apply"))
)
```

- [ ] **Step 4: Run to verify pass**

Run: `npx vitest run spec/javascript/controllers/entity_form/schema_manager.test.js`

Expected: PASS.

- [ ] **Step 5: Commit (only if human asked)**

```bash
git add app/javascript/controllers/entity_form/schema_manager.js spec/javascript/controllers/entity_form/schema_manager.test.js
git commit -m "feat: coerce validator_apply off when attribute visibility is off"
```

---

### Task 3: Modal sync — disable Apply when not Visible

**Files:**
- Modify: `app/javascript/controllers/entity_form/modal_manager.js`
- Modify: `app/javascript/controllers/entity_form_controller.js`
- Modify: `app/components/admin/maintenance/entities/attribute_modal_component.html.erb`
- Test: `spec/javascript/controllers/entity_form/modal_manager.test.js`
- Test: `spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb`

**Interfaces:**
- Consumes: modal visibility + validator-apply checkbox targets
- Produces:
  - `ModalManager#syncValidatorApplyWithVisibility()` — for each audience: if Visible unchecked → Apply `checked=false`, `disabled=true`; if Visible checked → Apply `disabled=false` (leave checked as-is)
  - `ModalManager#visibilityAudienceChanged(event)` — call sync; if the changed Visible checkbox is now checked, set the matching Apply checkbox `checked=true`
  - Controller delegates `visibilityAudienceChanged(event)`

Audience target pairs:

| Visible target | Apply target |
|----------------|--------------|
| `modalVisibilityAdmin` | `modalValidatorApplyAdmin` |
| `modalVisibilityMember` | `modalValidatorApplyMember` |
| `modalVisibilityPublic` | `modalValidatorApplyPublic` |

- [ ] **Step 1: Write the failing Vitest examples**

```js
describe("ModalManager visibility↔validator_apply sync", () => {
  const visHtml =
    `<input type="checkbox" checked data-entity-form-target="modalVisibilityAdmin">` +
    `<input type="checkbox" checked data-entity-form-target="modalVisibilityMember">` +
    `<input type="checkbox" checked data-entity-form-target="modalVisibilityPublic">` +
    `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyAdmin">` +
    `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyMember">` +
    `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyPublic">`

  it("unchecks and disables Apply when Visible is off", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalVisibilityPublicTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    expect(controller.modalValidatorApplyPublicTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyPublicTarget.disabled).toBe(true)
    expect(controller.modalValidatorApplyAdminTarget.disabled).toBe(false)
  })

  it("enables and checks Apply when Visible turns on via visibilityAudienceChanged", () => {
    const { controller } = buildController(visHtml)
    const mm = new ModalManager(controller)
    controller.modalVisibilityPublicTarget.checked = false
    mm.syncValidatorApplyWithVisibility()
    controller.modalVisibilityPublicTarget.checked = true
    mm.visibilityAudienceChanged({
      target: controller.modalVisibilityPublicTarget,
      preventDefault() {},
      stopPropagation() {}
    })
    expect(controller.modalValidatorApplyPublicTarget.disabled).toBe(false)
    expect(controller.modalValidatorApplyPublicTarget.checked).toBe(true)
  })

  it("prefill coerces Apply off+disabled when visibility is false", () => {
    const { controller } = buildController(
      visHtml +
      `<input data-entity-form-target="modalName">` +
      `<input data-entity-form-target="modalNameSlug">` +
      `<input data-entity-form-target="modalDisplayLabel">` +
      `<select data-entity-form-target="modalHtmlType"><option value="text">text</option></select>` +
      `<textarea data-entity-form-target="modalDescription"></textarea>` +
      `<div data-entity-form-target="validatorsContainer"></div>`
    )
    stubbedSiblings(controller)
    new ModalManager(controller).prefillModalWithAttribute({
      name: "X", name_slug: "x", display_label: "X", html_type: "text",
      description: "", validators: [],
      visibility: { admin: true, member: true, public: false },
      validator_apply: { admin: true, member: true, public: true },
      config: null
    })
    expect(controller.modalVisibilityPublicTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyPublicTarget.checked).toBe(false)
    expect(controller.modalValidatorApplyPublicTarget.disabled).toBe(true)
  })
})
```

- [ ] **Step 2: Run to verify fail**

Run: `npx vitest run spec/javascript/controllers/entity_form/modal_manager.test.js -t "visibility"`

Expected: FAIL — methods missing / prefill does not disable Apply.

- [ ] **Step 3: Implement sync + wiring**

Add to `modal_manager.js` (explicit has* checks, matching existing style):

```js
syncValidatorApplyWithVisibility() {
  this._syncAudiencePair(
    this.c.hasModalVisibilityAdminTarget ? this.c.modalVisibilityAdminTarget : null,
    this.c.hasModalValidatorApplyAdminTarget ? this.c.modalValidatorApplyAdminTarget : null
  )
  this._syncAudiencePair(
    this.c.hasModalVisibilityMemberTarget ? this.c.modalVisibilityMemberTarget : null,
    this.c.hasModalValidatorApplyMemberTarget ? this.c.modalValidatorApplyMemberTarget : null
  )
  this._syncAudiencePair(
    this.c.hasModalVisibilityPublicTarget ? this.c.modalVisibilityPublicTarget : null,
    this.c.hasModalValidatorApplyPublicTarget ? this.c.modalValidatorApplyPublicTarget : null
  )
}

_syncAudiencePair(visEl, applyEl) {
  if (!visEl || !applyEl) return
  if (!visEl.checked) {
    applyEl.checked = false
    applyEl.disabled = true
  } else {
    applyEl.disabled = false
  }
}

visibilityAudienceChanged(event) {
  const target = event?.target
  this.syncValidatorApplyWithVisibility()
  if (!target?.checked) return
  if (this.c.hasModalVisibilityAdminTarget && target === this.c.modalVisibilityAdminTarget && this.c.hasModalValidatorApplyAdminTarget) {
    this.c.modalValidatorApplyAdminTarget.checked = true
  } else if (this.c.hasModalVisibilityMemberTarget && target === this.c.modalVisibilityMemberTarget && this.c.hasModalValidatorApplyMemberTarget) {
    this.c.modalValidatorApplyMemberTarget.checked = true
  } else if (this.c.hasModalVisibilityPublicTarget && target === this.c.modalVisibilityPublicTarget && this.c.hasModalValidatorApplyPublicTarget) {
    this.c.modalValidatorApplyPublicTarget.checked = true
  }
}
```

Call `this.syncValidatorApplyWithVisibility()` at the end of `resetModalFields` (after reset visibility/apply) and at the end of `prefillModalWithAttribute` (after `applyVisibility` + `applyValidatorApply`).

In `entity_form_controller.js` near other modal delegates:

```js
visibilityAudienceChanged(event) { this.modalManager.visibilityAudienceChanged(event) }
```

On each Visible checkbox in `attribute_modal_component.html.erb` add:

```erb
data-action="change->entity-form#visibilityAudienceChanged"
```

- [ ] **Step 4: Component spec for action wiring**

In `attribute_modal_component_spec.rb`, add:

```ruby
it "wires visibility checkboxes to visibilityAudienceChanged" do
  %w[modalVisibilityAdmin modalVisibilityMember modalVisibilityPublic].each do |target|
    expect(page).to have_css(
      "input[type='checkbox'][data-entity-form-target='#{target}'][data-action*='visibilityAudienceChanged']"
    )
  end
end
```

- [ ] **Step 5: Run tests**

```bash
npx vitest run spec/javascript/controllers/entity_form/modal_manager.test.js
bundle exec rspec spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb --format documentation
```

Expected: PASS.

- [ ] **Step 6: Commit (only if human asked)**

```bash
git add app/javascript/controllers/entity_form/modal_manager.js \
  app/javascript/controllers/entity_form_controller.js \
  app/components/admin/maintenance/entities/attribute_modal_component.html.erb \
  spec/javascript/controllers/entity_form/modal_manager.test.js \
  spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb
git commit -m "feat: disable Apply validators when attribute Visible is off"
```

---

### Task 4: Collect path + view/row badge coerce

**Files:**
- Modify: `app/javascript/controllers/entity_form/attribute_manager.js`
- Modify: `app/javascript/controllers/entity_form/template_builder.js`
- Test: `spec/javascript/controllers/entity_form/template_builder.test.js`
- Test: attribute_manager Vitest file if present; otherwise cover collect via a small AttributeManager test in an existing entity_form suite

**Interfaces:**
- Consumes: `SchemaManager#coerceValidatorApply`
- Produces: modal collect never returns apply=true for hidden audiences; view/row Apply data matches coerced map

- [ ] **Step 1: Failing tests**

In `template_builder.test.js`, add:

```js
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
```

In `attribute_manager.test.js` (next to `collectVisibility`):

```js
describe("AttributeManager#collectValidatorApply", () => {
  it("coerces apply false when the matching Visible checkbox is off", () => {
    const { controller } = buildController(
      `<input type="checkbox" checked data-entity-form-target="modalVisibilityAdmin">` +
      `<input type="checkbox" checked data-entity-form-target="modalVisibilityMember">` +
      `<input type="checkbox" data-entity-form-target="modalVisibilityPublic">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyAdmin">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyMember">` +
      `<input type="checkbox" checked data-entity-form-target="modalValidatorApplyPublic">`
    )
    controller.schemaManager = new SchemaManager(controller)
    expect(new AttributeManager(controller).collectValidatorApply()).toEqual({
      admin: true, member: true, public: false
    })
  })
})
```

Import `SchemaManager` in that test file if not already imported.

- [ ] **Step 2: Run to verify fail**

Run: `npx vitest run spec/javascript/controllers/entity_form/template_builder.test.js -t "coerces Apply"`

Expected: FAIL (public still shown as applying).

- [ ] **Step 3: Implement**

In `attribute_manager.js`:

```js
collectValidatorApply() {
  const visibility = this.collectVisibility()
  const raw = {
    admin: this.c.hasModalValidatorApplyAdminTarget ? this.c.modalValidatorApplyAdminTarget.checked : true,
    member: this.c.hasModalValidatorApplyMemberTarget ? this.c.modalValidatorApplyMemberTarget.checked : true,
    public: this.c.hasModalValidatorApplyPublicTarget ? this.c.modalValidatorApplyPublicTarget.checked : true
  }
  return this.c.schemaManager.coerceValidatorApply(visibility, raw)
}
```

In `template_builder.js` `buildAttributeViewHtml`:

```js
const visibilityBadges = this._buildVisibilityBadgesForView(visibility)
const coercedApply = this.c.schemaManager.coerceValidatorApply(visibility, validator_apply)
const validatorApplyBadges = this._buildVisibilityBadgesForView(coercedApply)
```

In `buildAttributeRowHtml`, after normalizing visibility:

```js
const normalizedValidatorApply = this.c.schemaManager.coerceValidatorApply(visibility, validator_apply)
```

- [ ] **Step 4: Run to verify pass**

```bash
npx vitest run spec/javascript/controllers/entity_form/
```

Expected: PASS.

- [ ] **Step 5: Commit (only if human asked)**

```bash
git add app/javascript/controllers/entity_form/attribute_manager.js \
  app/javascript/controllers/entity_form/template_builder.js \
  spec/javascript/controllers/entity_form/
git commit -m "feat: coerce validator_apply on attribute collect and view badges"
```

---

### Task 5: Full verification

**Files:** none (run only)

- [ ] **Step 1: Vitest coverage for touched JS**

Run: `npx vitest run --coverage spec/javascript/controllers/entity_form/`

Expected: PASS; touched files at 100% lines + branches.

If coverage gaps remain on new branches (`visibilityAudienceChanged` audience branches, missing targets in `_syncAudiencePair`), add focused Vitest cases that omit individual targets and exercise admin/member/public toggles.

- [ ] **Step 2: RSpec contract + component**

```bash
bundle exec rspec \
  spec/contracts/entity_entry_contract_spec.rb \
  spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb \
  --format documentation
```

Expected: PASS.

- [ ] **Step 3: Manual smoke (optional)**

```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

Open Add Attribute → uncheck Public Visible → confirm Apply validators for Public is unchecked and disabled → re-check Visible → Apply is checked again → save attribute → inspect hidden `validator_apply` JSON.

---

## Spec coverage checklist (self-review)

| Spec requirement | Task |
|------------------|------|
| UI: Visible off → Apply unchecked + disabled | Task 3 |
| UI: Visible on → Apply enabled + checked | Task 3 |
| Sync on reset / prefill | Task 3 |
| Save coerce never persists apply=true with visible=false | Tasks 2 + 4 |
| View badges coerce | Task 4 |
| Runtime contract visibility wins | Task 1 |
| Missing validator_apply still applies when visible | Task 1 |
| Audience-nil build unchanged | Task 1 (existing example) |
| Vitest 100% on touched JS | Task 5 |
