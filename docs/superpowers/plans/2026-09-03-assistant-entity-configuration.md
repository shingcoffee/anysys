# Assistant Entity Configuration Implementation Plan

> **For agentic workers:** Implement task-by-task. Do **not** git commit unless the user explicitly asks.

**Goal:** Guided extract-clarify-validate-apply for dashboard assistant entity create/update, with a server-enforced create vs confirm-update gate.

**Architecture:** Enrich the fill JSON Schema; require JSON object chat output; parse `clarify` / `updates_confirmed`; validate with json_schemer; ApplyGate blocks unconfirmed name-match updates; ApplyFromRequirements remains the persist API.

**Tech Stack:** Rails 8.1.2, json_schemer, ruby-openai, Trailblazer ApplyFromRequirements, RSpec, I18n en + zh-CN.

## Global Constraints

- Grok 4.6 only.
- No new HTTP routes or Confirm UI.
- Customer-owned entities only. Never write customer_id NULL or mutate shared identity.
- No git commit unless the user asks.
- English I18n values are the exact strings that would have been hard-coded.
- Do not change EntitiesController.

## File map

| File | Role |
|------|------|
| Gemfile | add json_schemer |
| app/services/entity_definitions/structure_schema.json | descriptions + clarify + updates_confirmed |
| app/services/entity_definitions/structure_schema.rb | prompt + few-shots |
| app/services/entity_definitions/envelope.rb | clarify, updates_confirmed |
| app/services/entity_definitions/fill_validator.rb | JSON Schema via json_schemer |
| app/services/entity_definitions/apply_gate.rb | create vs update confirmation |
| app/services/speech_to_text/providers/openai_whisper.rb | json_object response_format |
| app/services/speech_to_text/activities/reply.rb | validate + gate + apply |
| config/locales/speech_to_text.en.yml / .zh-CN.yml | schema_invalid + create prompt |
| Matching specs | envelope, schema, validator, gate, reply, openai chat |

## Tasks

1. Envelope: `clarify` intent; `updates_confirmed` boolean default false.
2. Structure schema: descriptions on every section/field; prompt few-shots; intents include clarify.
3. FillValidator wrapping json_schemer; ApplyGate for live customer-owned non-bridge name match.
4. OpenAI `response_format: json_object`.
5. Reply: schema validate on apply; gate; clarify never writes.
6. I18n + starter prompt `create_entity` as a create request.
7. Targeted rspec for touched files.

Do not commit.
