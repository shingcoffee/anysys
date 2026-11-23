# AI Assistant Reliability Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the dashboard AI Assistant into focused services with durable, concurrency-safe generation state and server-authorized updates.

**Architecture:** A tenant-scoped generation record owns asynchronous lifecycle and cancellation. `Activities::Reply` becomes a coordinator over prompt, provider, turn-processing, finalization, persistence, and tool-session collaborators. Update proposals are stored in assistant-message metadata and consumed only after a later explicit user confirmation.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Active Record, Trailblazer-compatible service objects, Reform, RSpec, Turbo Streams, RubyLLM.

**Spec:** `docs/superpowers/specs/2026-09-07-ai-assistant-reliability-refactor-design.md`

## Global Constraints

- Preserve all existing user-facing wording through I18n with English and Simplified Chinese parity.
- Preserve admin/owner authorization and strict customer scoping.
- Keep models thin and business logic in service objects.
- Do not redesign the dashboard or change JavaScript.
- Do not modify `app/services/page_layout_templates/templates/`.
- Do not commit changes.
- Preserve the user's existing change in `spec/e2e/module_settings_layout.app.spec.js`.

---

### Task 1: Durable generation lifecycle

**Files:**
- Create: `db/migrate/20260907130000_create_speech_to_text_generations.rb`
- Create: `app/models/speech_to_text/generation.rb`
- Create: `app/services/speech_to_text/assistant/generation_lifecycle.rb`
- Modify: `app/models/speech_to_text/conversation.rb`
- Modify: `app/services/speech_to_text/activities/send_message.rb`
- Modify: `app/services/speech_to_text/activities/regenerate_last.rb`
- Modify: `app/services/speech_to_text/activities/cancel_reply.rb`
- Modify: `app/jobs/speech_to_text/reply_job.rb`
- Test: `spec/models/speech_to_text/generation_spec.rb`
- Test: `spec/services/speech_to_text/assistant/generation_lifecycle_spec.rb`
- Test: existing send/regenerate/cancel/job specs

**Interfaces:**
- Produces: `GenerationLifecycle.start!(conversation:, user_message:)`
- Produces: `GenerationLifecycle.claim!(generation)` returning `:claimed`, `:cancelled`, or `:stale`
- Produces: `GenerationLifecycle.cancel!(conversation:)`
- Produces: `GenerationLifecycle.finish!(generation, status:, failure_code: nil)`

- [ ] **Step 1: Write failing model and lifecycle specs**

Cover a queued generation, superseding the prior active generation, atomic
single claim, cancellation, duplicate claim, and conditional pointer cleanup.

- [ ] **Step 2: Run the new specs and verify they fail**

Run:

```bash
bundle exec rspec spec/models/speech_to_text/generation_spec.rb spec/services/speech_to_text/assistant/generation_lifecycle_spec.rb
```

Expected: failures because the model, table, and lifecycle do not exist.

- [ ] **Step 3: Add the migration, thin model, associations, and lifecycle**

Use statuses `queued`, `running`, `completed`, `failed`, `cancelled`, and
`superseded`. Add `current_generation_id` to conversations and remove the old
conversation token columns.

- [ ] **Step 4: Update enqueue, regenerate, cancel, and job handoff**

Enqueue `ReplyJob` with the generation ID. Keep existing HTTP result shapes and
Turbo status wording.

- [ ] **Step 5: Run lifecycle and affected activity specs**

```bash
bundle exec rspec spec/models/speech_to_text/generation_spec.rb spec/services/speech_to_text/assistant/generation_lifecycle_spec.rb spec/services/speech_to_text/activities/send_message_spec.rb spec/services/speech_to_text/activities/regenerate_last_spec.rb spec/services/speech_to_text/activities/cancel_reply_spec.rb spec/jobs/speech_to_text/reply_job_spec.rb
```

### Task 2: Job-time authorization and prompt/provider boundaries

**Files:**
- Create: `app/services/speech_to_text/assistant/execution_policy.rb`
- Create: `app/services/speech_to_text/assistant/prompt_builder.rb`
- Create: `app/services/speech_to_text/assistant/provider_client.rb`
- Modify: `app/services/flowchart_definitions/assistant/processor.rb`
- Test: `spec/services/speech_to_text/assistant/execution_policy_spec.rb`
- Test: `spec/services/speech_to_text/assistant/prompt_builder_spec.rb`
- Test: `spec/services/speech_to_text/assistant/provider_client_spec.rb`
- Test: existing flowchart processor specs

**Interfaces:**
- Consumes: a claimed `SpeechToText::Generation`
- Produces: `ExecutionPolicy.call(generation:)` with `allowed?` and `error_code`
- Produces: `PromptBuilder.call(conversation:, mode:)`
- Produces: `ProviderClient#chat(messages, tools: nil)` and `#native_tools(session:)`

- [ ] **Step 1: Write failing policy, prompt, and provider specs**

Cover inactive users, same-tenant admins, platform owner cross-tenant use,
members, disabled modules, missing providers, complete-only history, 20-turn
limit, entity and flowchart prompt sections, and OpenAI-only native tools.

- [ ] **Step 2: Run the new specs and verify they fail**

```bash
bundle exec rspec spec/services/speech_to_text/assistant/execution_policy_spec.rb spec/services/speech_to_text/assistant/prompt_builder_spec.rb spec/services/speech_to_text/assistant/provider_client_spec.rb
```

- [ ] **Step 3: Implement the focused collaborators**

Keep provider exception mapping in provider classes. Use the fixed
`Authentication::User#platform_owner?` predicate for cross-tenant owner access.

- [ ] **Step 4: Move flowchart prompt construction to PromptBuilder**

Remove the backwards dependency on `Activities::Reply::HISTORY_LIMIT`.

- [ ] **Step 5: Run the new and flowchart processor specs**

```bash
bundle exec rspec spec/services/speech_to_text/assistant/execution_policy_spec.rb spec/services/speech_to_text/assistant/prompt_builder_spec.rb spec/services/speech_to_text/assistant/provider_client_spec.rb spec/services/flowchart_definitions/assistant/processor_spec.rb
```

### Task 3: Turn processing, finalization, and reply persistence

**Files:**
- Create: `app/services/speech_to_text/assistant/turn_processor.rb`
- Create: `app/services/speech_to_text/assistant/finalizer.rb`
- Create: `app/services/speech_to_text/assistant/reply_writer.rb`
- Modify: `app/services/speech_to_text/activities/reply.rb`
- Modify: `app/services/speech_to_text/assistant/artifact.rb`
- Modify: `app/services/speech_to_text/assistant/generate_page.rb`
- Test: `spec/services/speech_to_text/assistant/turn_processor_spec.rb`
- Test: `spec/services/speech_to_text/assistant/finalizer_spec.rb`
- Test: `spec/services/speech_to_text/assistant/reply_writer_spec.rb`
- Test: existing reply, artifact, generate-page specs

**Interfaces:**
- Consumes: `ProviderClient`, `PromptBuilder`, and generation lifecycle
- Produces: `TurnProcessor::Result(body:, status:, entity_result:, flowchart_result:, effects:, pending_confirmation:)`
- Produces: `Finalizer::Result(body:, status:, metadata:, artifact:)`
- Produces: `ReplyWriter.call(conversation:, finalized:)`

- [ ] **Step 1: Write failing collaborator specs**

Characterize entity/flowchart sequencing, optional flowchart failure policy,
automatic page generation, page-created versus page-reused metadata, artifact
priority, verification suffixes, tenant-safe artifact assignment, database
persistence, and best-effort broadcasts.

- [ ] **Step 2: Run the new specs and verify they fail**

```bash
bundle exec rspec spec/services/speech_to_text/assistant/turn_processor_spec.rb spec/services/speech_to_text/assistant/finalizer_spec.rb spec/services/speech_to_text/assistant/reply_writer_spec.rb
```

- [ ] **Step 3: Implement the collaborators and reduce Reply to orchestration**

`Reply` claims the generation, applies execution policy, calls the provider,
processes and finalizes the turn, writes the reply, and finishes the generation.
It checks cancellation/supersession before every mutation stage.

- [ ] **Step 4: Separate persistence and broadcast error boundaries**

Database failures may raise to the job after lifecycle cleanup. Turbo message
and artifact broadcasts log their own context and do not change persisted
message status.

- [ ] **Step 5: Run all reply-path specs**

```bash
bundle exec rspec spec/services/speech_to_text/activities/reply_spec.rb spec/services/speech_to_text/assistant/turn_processor_spec.rb spec/services/speech_to_text/assistant/finalizer_spec.rb spec/services/speech_to_text/assistant/reply_writer_spec.rb spec/services/speech_to_text/assistant/artifact_spec.rb spec/services/speech_to_text/assistant/generate_page_spec.rb
```

### Task 4: Shared tool session and effect journal

**Files:**
- Create: `app/services/speech_to_text/assistant/tools/session.rb`
- Modify: `app/services/speech_to_text/assistant/loop.rb`
- Modify: `app/services/speech_to_text/assistant/tools/runner.rb`
- Modify: `app/services/speech_to_text/assistant/tools/list_catalog.rb`
- Modify: `app/services/speech_to_text/assistant/tools/generate_page_tool.rb`
- Modify: `app/services/speech_to_text/assistant/tools/verify_artifact_tool.rb`
- Test: `spec/services/speech_to_text/assistant/tools/session_spec.rb`
- Test: existing loop specs

**Interfaces:**
- Produces: `Tools::Session#call(name, arguments = {})`
- Produces: `Tools::Session#native_tools`
- Produces: `Tools::Session#effects`

- [ ] **Step 1: Write failing session and loop specs**

Cover the allowlist, tenant isolation, shared native adapters, created/reused
page effects, unknown tools, provider failure, and explicit tool-limit failure.

- [ ] **Step 2: Run the specs and verify they fail**

```bash
bundle exec rspec spec/services/speech_to_text/assistant/tools/session_spec.rb spec/services/speech_to_text/assistant/loop_spec.rb
```

- [ ] **Step 3: Implement Session and adapt native/fallback tools**

Keep `Runner` as a compatibility-free internal alias only if needed by
autoloading; otherwise replace it fully because backward compatibility is not
required.

- [ ] **Step 4: Merge session effects in Finalizer**

Every successful write tool must appear in metadata, artifact selection, and
verification.

- [ ] **Step 5: Run tool, finalizer, provider, and reply specs**

```bash
bundle exec rspec spec/services/speech_to_text/assistant/tools/session_spec.rb spec/services/speech_to_text/assistant/loop_spec.rb spec/services/speech_to_text/assistant/finalizer_spec.rb spec/services/speech_to_text/activities/reply_spec.rb
```

### Task 5: Server-held update proposals

**Files:**
- Create: `app/services/speech_to_text/assistant/pending_confirmation.rb`
- Modify: `app/services/entity_definitions/assistant/processor.rb`
- Modify: `app/services/flowchart_definitions/assistant/processor.rb`
- Modify: `app/services/speech_to_text/assistant/turn_processor.rb`
- Modify: `app/services/speech_to_text/assistant/finalizer.rb`
- Test: `spec/services/speech_to_text/assistant/pending_confirmation_spec.rb`
- Test: existing entity processor, flowchart processor, and reply specs

**Interfaces:**
- Produces: `PendingConfirmation.resolve(conversation:, user_message:)`
- Produces: `PendingConfirmation.build(kind:, document:, customer:, record:)`
- Entity and flowchart processors accept a trusted `confirmed:` keyword and
  expose a pending proposal when an update is not yet authorized.

- [ ] **Step 1: Write failing proposal specs**

Cover exact confirmation messages in English and Simplified Chinese, same
conversation/customer scope, latest-proposal selection, stale target version,
one-time consumption through generation idempotency, and model
`updates_confirmed: true` being ignored without a server proposal.

- [ ] **Step 2: Run the specs and verify they fail**

```bash
bundle exec rspec spec/services/speech_to_text/assistant/pending_confirmation_spec.rb spec/services/entity_definitions/assistant/processor_spec.rb spec/services/flowchart_definitions/assistant/processor_spec.rb
```

- [ ] **Step 3: Implement pending proposal creation and resolution**

Store normalized proposal data in assistant-message metadata. Confirmed turns
apply the stored document directly and bind it to the recorded target version.

- [ ] **Step 4: Add matching en and zh-CN confirmation tokens or errors**

Keep keys and interpolation variables in parity.

- [ ] **Step 5: Run processor and end-to-end reply specs**

```bash
bundle exec rspec spec/services/speech_to_text/assistant/pending_confirmation_spec.rb spec/services/entity_definitions/assistant/processor_spec.rb spec/services/flowchart_definitions/assistant/processor_spec.rb spec/services/speech_to_text/activities/reply_spec.rb spec/e2e/assistant_entity_create.app.spec.js
```

### Task 6: QA, migration, and review

**Files:**
- Modify: relevant request/job/service specs only when additional coverage is required
- Verify: `db/schema.rb`

**Interfaces:**
- Consumes: all prior task interfaces
- Produces: a verified assistant flow with no unresolved high-severity review findings

- [ ] **Step 1: Run migrations in test and development**

```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```

- [ ] **Step 2: Run the moderate-scope Ruby suite**

```bash
bundle exec rspec spec/models/speech_to_text spec/services/speech_to_text spec/services/entity_definitions/assistant spec/services/flowchart_definitions/assistant spec/jobs/speech_to_text spec/requests/admin/modules/speech_to_text spec/requests/admin/assistant spec/components/speech_to_text
```

- [ ] **Step 3: Run the deterministic browser assistant flow**

Start development with `SKIP_AUTH=1 E2E_STUB_ASSISTANT=1`, then run:

```bash
APP_BASE_URL=http://127.0.0.1:3000 PLAYWRIGHT_BROWSERS_PATH=/home/ec2-user/.cache/ms-playwright npx playwright test spec/e2e/assistant_entity_create.app.spec.js --config config/javascript/playwright.config.js --project chromium
```

- [ ] **Step 4: Run tech-lead and correctness/security reviews**

Resolve every confirmed critical, high, or AGENTS.md convention violation.

- [ ] **Step 5: Inspect final diff and working tree**

Confirm the unrelated pre-existing e2e change is untouched and no commit was
created.

