# Entity Structure Schema Implementation Plan

> **For agentic workers:** Implement task-by-task. Do **not** git commit unless the user explicitly asks. Steps use checkbox syntax for tracking.

**Goal:** Document the existing entity definition as a JSON Schema the assistant LLM fills, auto-persist related customer-owned entities from that fill, and rename stored bridge participant type `NestedEntity` → `EntityReference`.

**Architecture:** `SpeechToText::Activities::Reply` always asks the chat LLM for a JSON envelope. Chat-only turns write no entities. Apply turns call `EntityDefinitions::ApplyFromRequirements` (one transaction, name-match update, association-driven bridges). Persist type for bridge participant links is `Entity::ENTITY_REFERENCE_TYPE` (`"EntityReference"`).

**Tech Stack:** Rails 8.1.2, Trailblazer Activity, existing Entity versioning / `BridgeEntityManagement` / `EntitySchemaValidation`, speech-to-text assistant reply job, RSpec, I18n en + zh-CN.

## Global Constraints

- Grok 4.6 only (already the parent session).
- No new HTTP routes or UI. Assistant panel is the collector.
- Customer-owned entities only. Never write `customer_id` NULL or mutate shared identity.
- No `NestedEntity` alias. No data migration.
- No hard-coded user-facing strings; en + zh-CN parity.
- Do not git commit unless the user asks.
- `Current.customer` comes from `ReplyJob`, never from the LLM.
- English I18n values must be the exact strings that would have been hard-coded.

## File map

| File | Role |
|------|------|
| `app/models/entity.rb` | Add `ENTITY_REFERENCE_TYPE = "EntityReference"`. |
| `app/models/concerns/bridge_entity_management.rb` | Write `EntityReference` on bridge schema. |
| `app/services/entity_field_organizer.rb` | Filter participant refs by `ENTITY_REFERENCE_TYPE`. |
| `app/services/activity_steps/save_all.rb` | Link source entry via `ENTITY_REFERENCE_TYPE`. |
| Specs/docs listed in Task 1 | Replace `NestedEntity` string. |
| `app/services/entity_definitions/structure_schema.json` | JSON Schema + `$comment` explanations. |
| `app/services/entity_definitions/structure_schema.rb` | Load schema, build LLM prompt fragment. |
| `app/services/entity_definitions/envelope.rb` | Parse LLM text → envelope. |
| `app/services/entity_definitions/apply_from_requirements.rb` | Trailblazer activity: validate + persist related set. |
| `app/services/speech_to_text/activities/reply.rb` | Prompt + parse + optional apply. |
| `config/locales/speech_to_text.en.yml` / `.zh-CN.yml` | Parse/apply/summary strings. |
| Matching `spec/services/entity_definitions/*_spec.rb` and reply spec updates. |

---

### Task 1: Rename persist type NestedEntity → EntityReference

**Files:**
- Modify: `app/models/entity.rb` (add constant next to `ROLLUP_TYPE`)
- Modify: `app/models/concerns/bridge_entity_management.rb`
- Modify: `app/services/entity_field_organizer.rb`
- Modify: `app/services/activity_steps/save_all.rb`
- Modify: every spec and `docs/features/entities/*.md` that contains `NestedEntity`

**Interfaces:**
- Produces: `Entity::ENTITY_REFERENCE_TYPE` => `"EntityReference"`

- [ ] **Step 1:** Add constant on `Entity`:

```ruby
ENTITY_REFERENCE_TYPE = "EntityReference"
ROLLUP_TYPE = "Rollup"
```

- [ ] **Step 2:** In `bridge_property_schema`, set `"type" => Entity::ENTITY_REFERENCE_TYPE` (both participant refs). Update comments to “participant reference” / `EntityReference`.

- [ ] **Step 3:** Replace `f["type"] == "NestedEntity"` in `entity_field_organizer.rb` and `save_all.rb` with `f["type"] == Entity::ENTITY_REFERENCE_TYPE`. Update comments.

- [ ] **Step 4:** Replace the JSON `"type" => "NestedEntity"` / `'type' => 'NestedEntity'` fixtures and expectations with `Entity::ENTITY_REFERENCE_TYPE` (Ruby) or `"EntityReference"` (JSON docs). Update comments in specs.

- [ ] **Step 5:** Run:

```bash
bundle exec rspec spec/models/entity_spec.rb spec/models/concerns/bridge_entity_management_spec.rb spec/services/entity_field_organizer_spec.rb spec/services/activity_steps/save_all_spec.rb spec/services/page_field_populator_spec.rb spec/models/entity_rollup_validation_spec.rb
```

Expected: PASS. Confirm `rg NestedEntity` has no production hits.

---

### Task 2: Structure schema + envelope parser

**Files:**
- Create: `app/services/entity_definitions/structure_schema.json`
- Create: `app/services/entity_definitions/structure_schema.rb`
- Create: `app/services/entity_definitions/envelope.rb`
- Test: `spec/services/entity_definitions/structure_schema_spec.rb`
- Test: `spec/services/entity_definitions/envelope_spec.rb`

**Interfaces:**
- Produces: `EntityDefinitions::StructureSchema.json` → Hash; `.prompt` → String
- Produces: `EntityDefinitions::Envelope.parse(text)` → `{ ok: true, intent:, reply:, entities: }` or `{ ok: false, error: :invalid }`

Envelope keys: `intent` (`chat` | `apply_entities`), `reply` (string), `entities` (array, default `[]`). Accept raw JSON or a fenced `json` block. Unknown intent or missing `reply` → invalid.

JSON Schema must `$comment`-document primary / associated / bridge / EntityReference; association fill key is `associated_entity_name`; rollup config uses `target_entity_name` not `bridge_entity_id`; `EntityReference` is not a fill type.

- [ ] **Step 1:** Write failing envelope specs (raw JSON, fenced, garbage, missing reply).
- [ ] **Step 2:** Implement `Envelope.parse`.
- [ ] **Step 3:** Write structure schema spec (file parses, required keys, prompt mentions EntityReference and associated_entity_name).
- [ ] **Step 4:** Implement JSON Schema + `StructureSchema`.
- [ ] **Step 5:** `bundle exec rspec spec/services/entity_definitions/envelope_spec.rb spec/services/entity_definitions/structure_schema_spec.rb`

---

### Task 3: ApplyFromRequirements

**Files:**
- Create: `app/services/entity_definitions/apply_from_requirements.rb`
- Test: `spec/services/entity_definitions/apply_from_requirements_spec.rb`
- Modify: `config/locales/maint_core.en.yml` and `.zh-CN.yml` only if new validation messages are required (prefer existing association/entity errors). New apply-specific errors go in `speech_to_text` or `maint_core` with both locales.

**Interfaces:**
- Consumes: `Current.customer`; envelope `entities` array
- Produces: `EntityDefinitions::ApplyFromRequirements.call(entities:)` with ctx `[:success]`, `[:created]`, `[:updated]`, `[:bridges]`, `[:errors]` (array of I18n strings)

Algorithm (one `ActiveRecord::Base.transaction`, rollback on any failure):

1. Reject empty name; reject `category` bridge; reject any attribute `type` == `ENTITY_REFERENCE_TYPE`; reject `bridge_entity_id` keys.
2. Pass A: for each proposed entity, `Entity.unscope(where: :status).where(customer_id: Current.customer_id, name: name).first`. If inactive → error (new I18n: do not overwrite; restore first). If `bridge_entity?` → error. If live customer-owned → update. If none → quota check then `Entity.new` + `customer_id` from Current. Assign identity + body except associations and rollup attributes. `save`.
3. Pass B: map names in the batch + live tenant entities. For each association, require `associated_entity_name`, `display_field`, `display_field_label`. Resolve target. Build stored association with `target_entity_id` / `target_entity_name`. `associations_json=`. `save` then `sync_bridge_entities!`.
4. Pass C: for Rollup attributes, resolve `config.target_entity_name` to the primary’s association bridge id; set `config.bridge_entity_id`; save.
5. Return created/updated/bridge names.

Must not find or update `customer_id` NULL rows as a match.

- [ ] **Step 1:** Write failing specs for create, related-set+bridge EntityReference, name-match update, rollback cases (missing target, EntityReference in fill, inactive, other tenant untouched).
- [ ] **Step 2:** Implement the activity.
- [ ] **Step 3:** `bundle exec rspec spec/services/entity_definitions/apply_from_requirements_spec.rb`

---

### Task 4: Wire Reply + I18n

**Files:**
- Modify: `app/services/speech_to_text/activities/reply.rb`
- Modify: `config/locales/speech_to_text.en.yml`
- Modify: `config/locales/speech_to_text.zh-CN.yml`
- Modify: `spec/services/speech_to_text/activities/reply_spec.rb`

**Interfaces:**
- Consumes: Envelope, StructureSchema, ApplyFromRequirements, existing `chat(messages:)`
- System prompt: existing `speech_to_text.assistant.system_prompt` + schema prompt + JSON catalog of live customer-owned non-bridge entities `{ name, name_slug, id }` + instruction to always return the envelope.

On chat success:
1. `Envelope.parse(text)`
2. If not ok → persist_failure with `speech_to_text.assistant.envelope_invalid` (English: `"The assistant could not produce a valid reply. Try again."`)
3. If apply and entities present → `ApplyFromRequirements.call`; on failure persist **complete** assistant message with joined errors; on success persist complete message: LLM `reply` plus `speech_to_text.assistant.apply_summary` interpolating created/updated/bridges (empty lists omitted).
4. Else persist `reply` as today.

Vendor failure unchanged (`reply_failed`).

Existing reply specs that stub `chat` with plain `"Hi!"` must stub a chat envelope JSON instead, **or** Reply must treat non-JSON as envelope_invalid. Update those specs to return `{"intent":"chat","reply":"Hi!","entities":[]}`.

- [ ] **Step 1:** Add I18n keys (en + zh-CN): `envelope_invalid`, `apply_summary` (`Created: %{created}. Updated: %{updated}. Bridges: %{bridges}.` with a variant that omits empty parts — implement omission in Ruby and keep one template with the three lists, using `"none"` / `无` for empty).
- [ ] **Step 2:** Update reply specs (chat envelope, apply envelope creates entity, parse fail, vendor fail).
- [ ] **Step 3:** Implement Reply changes.
- [ ] **Step 4:** `bundle exec rspec spec/services/speech_to_text/activities/reply_spec.rb spec/services/entity_definitions/`

---

### Task 5: Regression sweep

Run the EntityReference-touched spec files from Task 1 plus apply/reply:

```bash
bundle exec rspec \
  spec/models/entity_spec.rb \
  spec/models/concerns/bridge_entity_management_spec.rb \
  spec/services/entity_field_organizer_spec.rb \
  spec/services/activity_steps/save_all_spec.rb \
  spec/services/page_field_populator_spec.rb \
  spec/services/entity_definitions \
  spec/services/speech_to_text/activities/reply_spec.rb \
  spec/models/entity_rollup_validation_spec.rb \
  spec/services/entities/rollup_compiler_spec.rb \
  spec/services/flowchart_runtime/join_resolver_spec.rb
```

Expected: PASS. `rg NestedEntity app/` empty.
