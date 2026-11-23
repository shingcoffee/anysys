# AI Assistant Final Review Fixes Implementation Plan

> **For agentic workers:** Execute inline in this checkout. Do not dispatch subagents and do not commit. Every correction follows a witnessed RED → GREEN cycle.

**Goal:** Close every high/medium final-review finding plus the regenerate-ID and reused-page correctness findings without changing the approved AI Assistant UX.

**Architecture:** Conversation-row locking is the serialization boundary for generation replacement, cancellation, confirmation consumption, and assistant-turn database writes. Provider calls and Turbo publication remain outside that lock. Confirmations replay one server-stored document in a transaction that locks the conversation, proposal message, and versioned targets; unexpected application/database failures terminalize the generation and then escape to Active Job.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Active Record/PostgreSQL, RSpec, Turbo Streams, ViewComponent.

**Spec:** `docs/superpowers/specs/2026-09-07-ai-assistant-reliability-refactor-design.md`

## Global Constraints

- Preserve `spec/e2e/module_settings_layout.app.spec.js` byte-for-byte.
- Do not dispatch subagents and do not commit.
- Add no JavaScript.
- Keep all user-facing copy in matching English and Simplified Chinese locale files.
- Run the narrow RED command before each implementation correction.
- Run the focused assistant/entity/flowchart/request suite after all corrections are green.

---

### Task 1: Current-generation claim and mutation fences

**Files:**
- Modify: `spec/services/speech_to_text/assistant/generation_lifecycle_spec.rb`
- Modify: `spec/services/speech_to_text/assistant/generation_write_guard_spec.rb`
- Modify: `spec/services/speech_to_text/activities/reply_spec.rb`
- Modify: `app/services/speech_to_text/assistant/generation_lifecycle.rb`
- Modify: `app/services/speech_to_text/assistant/generation_write_guard.rb`
- Modify: `app/services/speech_to_text/activities/reply.rb`

**Interfaces:**
- `GenerationLifecycle.claim!` checks `conversation.current_generation_id` before interpreting terminal status.
- `GenerationWriteGuard#call(required_status: "running")` yields only while the generation is current and has the required status.
- Cancellation reply persistence uses `required_status: "cancelled"`; ordinary mutations use `"running"`.

- [ ] Add a lifecycle spec where a cancelled generation is replaced and its delayed claim returns `:stale`.
- [ ] Add guard/reply specs proving only a current cancelled generation can write `"Stopped."`.
- [ ] Run the three examples and verify the old code fails by returning/persisting cancellation.
- [ ] Reorder claim classification and make the guard status-aware with current-pointer precedence.
- [ ] Run the focused lifecycle/guard/reply examples green.

### Task 2: Atomic pending-confirmation consumption

**Files:**
- Modify: `spec/services/speech_to_text/assistant/pending_confirmation_spec.rb`
- Modify: `spec/services/speech_to_text/assistant/turn_processor_spec.rb`
- Modify: `spec/services/speech_to_text/activities/reply_spec.rb`
- Modify: `app/services/speech_to_text/assistant/pending_confirmation.rb`
- Modify: `app/services/speech_to_text/assistant/turn_processor.rb`
- Modify: `app/services/speech_to_text/activities/reply.rb`

**Interfaces:**
- `PendingConfirmation.consume(conversation:, user_message:, generation:) { |proposal| ... }`
- The method locks the conversation first, then the proposal message, then sorted tenant-owned target rows.
- It verifies current/running generation ownership, proposal shape/tenant/identity, unchanged target heads, and unconsumed metadata.
- The yielded stored document is applied inside the transaction. Successful application removes `pending_confirmation` and records the consuming generation ID.
- `TurnProcessor::Result#confirmation_applied` tells the consumer whether persistence succeeded.

- [ ] Strengthen the stale-version example by changing `property_schema_json`, committing a real new head, and confirming with the current locale token.
- [ ] Add a consumption example that advances the head before apply and proves no stale overwrite.
- [ ] Add a successful one-time consumption example that removes the proposal capability.
- [ ] Run the pending-confirmation examples and verify stale/consumption failures.
- [ ] Implement locked lookup, target identity/version validation, transactional yield, and success consumption.
- [ ] Route confirmed turns through `consume` and apply them without a nested generation guard.
- [ ] Run pending-confirmation, turn-processor, and reply confirmation examples green.

### Task 3: Confirmed flowcharts are immutable model input

**Files:**
- Modify: `spec/services/flowchart_definitions/assistant/processor_spec.rb`
- Modify: `app/services/flowchart_definitions/assistant/processor.rb`

**Interfaces:**
- Confirmed stored documents get one validation/persistence attempt.
- Confirmed validation/persistence errors return a normal processor error result.
- Confirmed documents never invoke repair chat and never target a record identity different from the locked proposal target.

- [ ] Add a confirmed invalid Flow A proposal whose repair response targets Flow B; assert the chat callable is never invoked and Flow B is unchanged.
- [ ] Run the example and verify the old processor calls repair/retargets.
- [ ] Short-circuit repair for confirmed documents and return `give_up` errors directly.
- [ ] Run the processor spec green.

### Task 4: Request-path handoff survives Turbo failure

**Files:**
- Modify: `spec/services/speech_to_text/activities/send_message_spec.rb`
- Modify: `spec/services/speech_to_text/assistant/generation_handoff_spec.rb`
- Modify: `app/services/speech_to_text/activities/send_message.rb`
- Modify: `app/services/speech_to_text/assistant/generation_handoff.rb`
- Modify: `app/services/speech_to_text/assistant/generation_lifecycle.rb`

**Interfaces:**
- User-message/status/running broadcasts are best-effort and happen independently of enqueue.
- `GenerationLifecycle.finish!` returns `true` only when it cleared that generation's pointer.
- `GenerationHandoff` publishes idle state only after `finish!` returns true and after the lock is released.

- [ ] Add a SendMessage spec where message publication raises but the generation ID is still enqueued.
- [ ] Add a handoff spec proving an enqueue failure cannot clear a newer generation or publish its idle UI.
- [ ] Add a finish spec proving caller work is not executed under the lock by removing block execution and asserting the boolean result.
- [ ] Run the examples and verify the current ordering/block API fails.
- [ ] Wrap SendMessage publication as best-effort, enqueue afterward, and move idle publication after `finish!`.
- [ ] Run send/handoff/lifecycle specs green.

### Task 5: Exception boundaries and write-tool failures

**Files:**
- Modify: `spec/services/speech_to_text/activities/reply_spec.rb`
- Modify: `spec/services/speech_to_text/assistant/tools/session_spec.rb`
- Modify: `spec/services/flowchart_definitions/assistant/processor_spec.rb`
- Modify: `app/services/speech_to_text/activities/reply.rb`
- Modify: `app/services/speech_to_text/assistant/provider_client.rb`
- Modify: `app/services/speech_to_text/assistant/tools/session.rb`
- Modify: `app/services/speech_to_text/assistant/turn_processor.rb`
- Modify: `app/services/flowchart_definitions/assistant/processor.rb`

**Interfaces:**
- `ProviderClient#chat` maps provider-call exceptions to `{ outcome: :unreachable, text: nil, raw: ... }`.
- Reply maps provider outcomes to the existing failed assistant message.
- Unexpected application/database/lifecycle exceptions close the current generation as failed and re-raise.
- Tool user-input/unknown-tool outcomes remain structured; database/programming exceptions escape.

- [ ] Replace the swallowed-runtime-error reply spec with separate provider-boundary and unexpected-persistence re-raise examples.
- [ ] Add a tool write spec where `GeneratePage.call` raises `ActiveRecord::ActiveRecordError`; assert it escapes.
- [ ] Add flowchart/turn-processor examples proving application exceptions escape rather than become optional model failures.
- [ ] Run the examples and verify the broad rescues hide them.
- [ ] Move provider exception mapping into `ProviderClient`, remove broad rescues from processors/session, and make Reply terminalize then re-raise unexpected failures.
- [ ] Ensure lifecycle-finalization exceptions are never swallowed by `ensure`.
- [ ] Run reply/provider/session/processor specs green.

### Task 6: Atomic reply persistence and post-transaction publication

**Files:**
- Modify: `spec/services/speech_to_text/assistant/reply_writer_spec.rb`
- Modify: `spec/services/speech_to_text/activities/reply_spec.rb`
- Modify: `app/services/speech_to_text/assistant/reply_writer.rb`
- Modify: `app/services/speech_to_text/activities/reply.rb`
- Modify: `app/services/speech_to_text/assistant/finalizer.rb`

**Interfaces:**
- `ReplyWriter.call(conversation:, finalized:, write_guard:)` runs message creation and artifact assignment in one transaction inside the generation write fence.
- Artifact persistence failures roll back the assistant message and raise.
- Message/artifact Turbo publication runs after the transaction and guard, with separate best-effort logging.
- `Finalizer` uses the guard only around automatic page creation, never around verification or publication.

- [ ] Add a writer spec that forces artifact assignment failure and asserts no assistant message remains.
- [ ] Add a writer/guard spec that inspects lock ownership and proves broadcasts occur after the guard yields.
- [ ] Run the examples and verify the current writer suppresses the error/publishes under lock.
- [ ] Split writer persistence/publication, make persistence atomic, and pass the write guard into writer/finalizer.
- [ ] Run writer/finalizer/reply examples green.

### Task 7: Explicit tool-loop terminal outcomes

**Files:**
- Modify: `spec/services/speech_to_text/assistant/loop_spec.rb`
- Modify: `spec/services/speech_to_text/assistant/turn_processor_spec.rb`
- Modify: `spec/services/speech_to_text/assistant/finalizer_spec.rb`
- Modify: `app/services/speech_to_text/assistant/loop.rb`
- Modify: `app/services/speech_to_text/assistant/turn_processor.rb`
- Modify: `app/services/speech_to_text/assistant/finalizer.rb`

**Interfaces:**
- `Loop::Result(text:, outcome:)` uses `:success`, `:provider_failure`, or `:max_steps`.
- `TurnProcessor` maps both terminal failures to `reply_failed`, status `"failed"`, while retaining tool effects.
- `Finalizer` does not auto-generate pages for failed turns, but it selects/verifies/pins an already-created tool effect.

- [ ] Add provider-failure and eight-step exhaustion specs that reject pending tool JSON.
- [ ] Add TurnProcessor mapping examples and a failed-turn Finalizer example with a prior page effect.
- [ ] Run the examples and verify pending JSON/no artifact finalization.
- [ ] Implement explicit loop results, failure mapping, and effect artifact finalization.
- [ ] Run loop/turn/finalizer/reply specs green.

### Task 8: Regenerate generation ID and reused-page rendering

**Files:**
- Modify: `spec/requests/admin/modules/speech_to_text/messages_spec.rb`
- Modify: `spec/components/speech_to_text/assistant_panel_component_spec.rb`
- Modify: `app/components/speech_to_text/message_component.rb`
- Modify: `config/locales/speech_to_text.en.yml`
- Modify: `config/locales/speech_to_text.zh-CN.yml`

**Interfaces:**
- Regenerate request assertions compare the enqueued argument to `conversation.current_generation_id`, not the user-message ID.
- Change metadata action `"reused"` renders through `speech_to_text.assistant.changes.reused`.

- [ ] Force message/generation IDs apart and run the existing message-ID request expectation RED.
- [ ] Correct the request assertion to the current generation ID and run green.
- [ ] Add a component example for `"reused"` and run RED.
- [ ] Add `reused` handling plus en/zh-CN locale parity and run green.

### Task 9: Focused verification and report

**Files:**
- Create: `.superpowers/sdd/2026-09-07-ai-assistant-reliability-refactor/final-fix-report.md`

- [ ] Run the focused assistant/entity/flowchart/request/component suite.
- [ ] Run `bundle exec rails zeitwerk:check`.
- [ ] Run `git diff --check`.
- [ ] Verify locale key/interpolation parity.
- [ ] Verify the protected E2E file SHA-256 remains `2388ae722c823dbaccfbb77f3dbd10d3ea4aff334a0b8c638f34c9b309c79181`.
- [ ] Write a complete RED/GREEN command-and-result report, files changed, and unresolved concerns.
