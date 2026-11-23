# Assistant entity configuration (schema, clarify, gated apply)

Date: 2026-09-03
Status: locked for implementation
Supersedes assistant-fill behavior in `docs/entity-structure-schema-design.md` (2026-09-01): auto-apply on `apply_entities` is replaced by a create/update gate. Persist API, tenant rules, and EntityReference vocabulary are unchanged.

## Problem

The dashboard AI Assistant can already fill and persist customer-owned entities, but it does so in one shot: dump schema, parse `{intent, reply, entities}`, write immediately. There is no field-level schema documentation for the LLM, no few-shot extraction, no structured JSON mode, no clarification loop, and no confirmation before name-match updates.

## Decisions

- Audience: tenant `admin` / `owner` on a tenant URL. Customer-owned entities only.
- Chat panel unchanged (no new routes or Confirm UI).
- Persist: `EntityDefinitions::ApplyFromRequirements` (not `EntitiesController`).
- Creates: persist immediately when the fill is valid.
- Updates (exact live customer-owned non-bridge `name` match): persist only when `updates_confirmed` is true (LLM reading of the latest user message as a yes).
- State: conversation history only. No draft column.
- One chat completion per turn. No second validation LLM.
- OpenAI chat uses `response_format: { type: "json_object" }` (not strict json_schema).
- JSON Schema validation via `json_schemer`, wrapped by `EntityDefinitions::FillValidator`.

## Envelope

```json
{
  "intent": "chat | clarify | apply_entities",
  "reply": "string shown in the thread",
  "entities": [],
  "updates_confirmed": false
}
```

- `chat`: Q&A; `entities` empty; no write.
- `clarify`: gathering; `entities` may be a partial fill; no write.
- `apply_entities`: persist subject to the create/update gate.
- `updates_confirmed`: true only when the latest user message is an unambiguous yes to a proposed update. “Yes, and also add X” is `clarify` / new extract, not apply.

## Schema

`EntityDefinitions::StructureSchema` is the LLM contract. Every `$defs` object and property has a `description` (purpose, when to emit, default if omitted, forbidden values). Vocabulary: primary / associated / bridge / EntityReference. Forbidden on fill: `id`, `customer_id`, `category: bridge`, `EntityReference`, `bridge_entity_id`.

## Data flow

1. Admin sends text/STT into the existing per-(customer, user) thread.
2. `Reply` builds system prompt: persona I18n + schema prompt (descriptions + few-shots + rules) + tenant catalog JSON.
3. OpenAI chat with `json_object`. Envelope parse failure → failed turn, no write.
4. `chat` / `clarify` / empty entities → persist `reply`, no write.
5. `apply_entities` with entities: JSON Schema validate → ApplyGate (create vs update) → ApplyFromRequirements in one transaction.
6. Gate blocks updates without confirmation: persist `reply` only.
7. Apply success: `reply` plus created/updated/bridge names. Failure: rollback, complete turn with I18n errors.

## Out of scope

Shared entity CUD, member assistant, new HTTP routes, changing EntitiesController, second LLM, conversation draft column, page/flowchart generation.
