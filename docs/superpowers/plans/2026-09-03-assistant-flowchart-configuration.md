# Assistant-driven flowchart implementation plan

> Implemented in-session. Sequential persist + repair loop.

**Goal:** After the dashboard assistant persists entities, generate and save one customer-owned flowchart from the same conversation.

**Done:**
- Palette + structure schema prompt (categories, ~100 actions, element types)
- Extraction / UpdatePolicy / SchemaValidator / Normalizer / GraphValidator / Persist
- Processor with max 2 LLM repairs
- Reply sequential second call; ScriptedCompletion flowchart no-op for E2E
- Create immediate, update on confirm, launched → new version
