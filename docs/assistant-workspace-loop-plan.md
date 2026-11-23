# Assistant Workspace Loop Implementation Plan

**Goal:** Close the Adorable-style loop on the Anysys dashboard assistant: describe → apply → preview → generate page → verify → stream/stop → polish. Keep one conversation thread per user per tenant.

**Constraints:** No extra threads. Customer-owned writes only. I18n en + zh-CN. Stimulus Values for JS copy. Admin `/:cid/admin/` with existing auth. Do not auto-commit.

## Slice 1 — Artifact pane
Conversation `artifact_kind` + `artifact_id`. After persist, pin newest artifact (page > flowchart > entity). Dashboard rail Card + page iframe. Tenant-scoped resolve. Turbo replace `speech_to_text_artifact`.

## Slice 2 — Page generation
`SpeechToText::Assistant::GeneratePage` wraps `Pages::Activities::CreateFromEntityVersion` for created entities. Skip with warning if shared flowchart missing, quota, or page exists (reuse as artifact). Never fail the entity create.

## Slice 3 — Tools + verify
Server-side toolset wrapping existing Activities. Existing JSON intents stay valid; optional `{tool, arguments}` loop (max 8). Verify entity version / flowchart graph / page content before claiming done.

## Slice 4 — Stream + stop
`generation_token` + cancel. Turbo status/running. Stop endpoint. Stimulus busy until reply or cancel.

## Slice 5 — Chat polish (one thread)
Markdown, image attachment, copy, regenerate last turn, collapsible changes trail, continue-last + recent chips. Still `Conversation.for_user`.
