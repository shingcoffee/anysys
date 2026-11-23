# Assistant-driven flowchart create/update

Date: 2026-09-03

## Decisions (locked)

- Sequential persist: entity LLM first, then flowchart LLM after a complete non-clarify entity turn.
- One flowchart per persistable turn.
- Create immediately; update only after NL confirmation (same as entities).
- Name match on a live customer-owned flowchart writes a new version and advances the head, including launched rows (status stays launched). Canvas take-offline lock still applies to manual edits.
- Invalid graphs: deterministic layout normalize, then up to two LLM repair calls; save only if valid. Entities from the turn are kept.
- Customer-owned, entity-bound only. No shared/platform CUD. Canvas new/edit pages remain.

## Components

`FlowchartDefinitions::{Palette,Catalog,StructureSchema,Normalizer,GraphValidator,Persist}` and `FlowchartDefinitions::Assistant::{Extraction,UpdatePolicy,SchemaValidator,Processor}`. `SpeechToText::Activities::Reply` runs the second call. Scripted E2E stub returns flowchart chat no-op so entity Playwright stays stable.
