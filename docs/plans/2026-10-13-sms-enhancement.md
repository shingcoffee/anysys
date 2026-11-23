# SMS reliability enhancement — 2026-10-13

## Design
- Treat `sms_messages` as a transactional outbox. Admission returns a durable `queued` message (or an audited `suppressed` message); enqueue only after the outermost commit, with recurring recovery as the durable fallback.
- Bind tenant idempotency keys to canonical recipient, template key, scalar variable object, and explicitly requested provider/mode/expiry. Compare before mutable prerequisites, under the quota lock, and after uniqueness races. Blank keys are absent; keys must be strings of at most 128 bytes.
- Pin credential identity/mode, selected provider/template code, required variables, and payload at admission. Template retirement/edits and provider reassignment cannot change an admitted send.
- Claim preparation exclusively with a renewable-by-recovery lease. Atomically persist `dispatch_started_at` immediately before the vendor call. No worker or recovery path may resend an attempted message; crashes/timeouts/malformed acceptance become `unknown`. Proven API rejection becomes `failed`; `sent` means API acceptance, never carrier delivery.
- Recovery retains the sole attempt's claim token when quarantining a crash, allowing a genuinely late response to record its vendor ID without making the message claimable again. Any usable ID in a malformed success is retained for reconciliation.
- Recheck module enablement, recipient opt-out, and expiry immediately before dispatch. Default expiry is one hour. Preserve delivered as the success floor and reconcile retained early receipts once the vendor ID is recorded.
- Preserve tenant-lock quota reservation, SQLite first-write serialization, phone windows, and existing uniqueness protections. Only one admission row and one external attempt account for the payload.

## Implementation / verification
1. Add canonical admission, quota, pinned credential, handoff, dispatch, worker, and recovery services/jobs; extend message transitions with optional claim fencing.
2. Add additive lifecycle migration, schema, recurring recovery, async module output, and matching English/Simplified Chinese lifecycle translations.
3. Update send/model expectations; add focused admission/outbox tests for commit/rollback, enqueue failure, duplicate workers, stale preparation, attempted crashes, ambiguous acceptance, expiry, suppression/module disable, pinned content/account, and early receipts.
4. Migrate development and test additively (no resets); run scoped RSpec only. Gateway/reconciliation/contracts/adapters and reference docs are coordinated in other ownership lanes.

## Verification outcome
- Applied `20261013000100` additively to development and the shared test database.
- Shared-test verification encountered concurrent SQLite locks; created a fresh dedicated verification database at `/tmp/opencode/sms_outbox_verify.sqlite3` without resetting existing databases.
- Scoped verification covers send admission, fingerprint/uniqueness races, model transitions, committed outbox/rollback, distinct concurrent workers, crash/timeout recovery, immediate dispatch guards, pinned payload/account, and early receipt reconciliation.
- Initial focused run, before the release-review changes below: **102 examples, 0 failures** across `spec/services/sms/{activities/send,message_admission,outbox_commit,backend_lifecycle}_spec.rb`, `spec/jobs/sms/delivery_lifecycle_spec.rb`, and `spec/models/sms/message_spec.rb`. Scoped `git diff --check` passed. This historical result is not verification of the later accepted-result completion changes.

## Release review — accepted-result completion
- Retain the adapter result through completion exceptions; preserve any usable vendor ID and raw response when quarantining an ambiguous outcome. Enrich `TransportError` with optional `vendor_message_id` and `payload` so partial SDK responses use the same path.
- Retry only ledger-completion writes for database failures, at most three times per transition. Keep the external call outside every retry block. If acceptance cannot be written, attempt a bounded unknown transition with the same known ID/raw.
- Fence completion by the immutable dispatch-start timestamp plus the original or already-cleared claim token. Preserve an already-recorded acceptance and terminal receipt floor, including a write that succeeded before reload failed. Reconcile receipts using the recorded database identity after completion.
- Verify transient write/reload failures, bounded exhaustion followed by quarantine, partial-response errors, malformed results, late projections, and exactly one vendor call. Provider implementation and reference docs remain in their delegated lanes.
