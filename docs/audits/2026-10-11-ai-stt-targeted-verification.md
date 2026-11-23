# AI + STT targeted verification — 2026-10-11

**PASS: 1,666 examples, 0 failures.** One targeted RSpec execution covered the complete eight failing files behind the earlier 37 AI/STT failures (groups 31–32 in `2026-10-11-rspec-verification.md`) and adjacent AI/entity-definition/STT/model/job/LLM/request/website apply–Undo regressions. No application-wide suite or subagents were used.

## Isolated database and storage verification

`storage/` was inspected before creation of the new disposable database; `storage/ai_verify.sqlite3` did not exist. The verified Rails connection was:

```json
{
  "environment": "test",
  "database": "storage/ai_verify.sqlite3",
  "schema_version": "20261011190000",
  "fallback_limits": { "page": 50, "entity": 25, "member": 5 },
  "speech_columns": ["conversation_id", "started_at", "transcript"],
  "audio_storage": "/home/ec2-user/anysys/tmp/storage"
}
```

The database is isolated. Active Storage uses the configured test Disk service at `tmp/storage`; no storage-root deletion or global storage reconfiguration was performed. `SKIP_AUTH` and `TEST_ENV_NUMBER` were explicitly unset for these commands.

`db:schema:load` loaded the current schema and recorded migration version `20261011190000`. That newest migration is a data-only historical-payment binding repair; schema loading does **not** execute its backfill. This verification does not claim that production historical data has been migrated.

## Commands and actual result

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER RAILS_ENV=test TEST_DATABASE=storage/ai_verify.sqlite3 bin/rails db:schema:load
```

Exit: **0**.

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER RAILS_ENV=test TEST_DATABASE=storage/ai_verify.sqlite3 bin/rails runner 'db = ActiveRecord::Base.connection_db_config.database; raise "unexpected database" unless Rails.root.join(db).expand_path == Rails.root.join("storage/ai_verify.sqlite3"); raise "unexpected environment" unless Rails.env.test?; puts JSON.pretty_generate(environment: Rails.env, database: db, schema_version: ActiveRecord::Base.connection.select_value("SELECT MAX(version) FROM schema_migrations"), fallback_limits: Billing::Entitlements.fallback.limits, speech_columns: SpeechToText::Clip.column_names & %w[conversation_id started_at transcript], audio_storage: ActiveStorage::Blob.service.root.to_s)'
```

Exit: **0**; output shown above.

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER RAILS_ENV=test TEST_DATABASE=storage/ai_verify.sqlite3 bundle exec rspec \
  spec/services/ai_assistant \
  spec/services/entity_definitions \
  spec/services/speech_to_text \
  spec/models/ai_assistant \
  spec/models/speech_to_text \
  spec/jobs/ai_assistant \
  spec/jobs/speech_to_text \
  spec/services/llm_spec.rb \
  spec/requests/admin/assistant/messages_spec.rb \
  spec/requests/admin/assistant/transcriptions_spec.rb \
  spec/requests/admin/modules/ai_assistant/transcriptions_spec.rb \
  spec/services/websites/assistant/processor_spec.rb \
  spec/services/websites/assistant/undo_spec.rb
```

Exit: **0**.

```text
Finished in 3 minutes 14.6 seconds (files took 8.42 seconds to load)
1666 examples, 0 failures
```

## Reported failures and semantics verified

All examples in these formerly failing files ran, not just the original failing selectors:

* `spec/jobs/speech_to_text/prune_clips_job_spec.rb`
* `spec/requests/admin/assistant/messages_spec.rb`
* `spec/services/ai_assistant/activities/reply_spec.rb`
* `spec/services/ai_assistant/assistant/generate_page_spec.rb`
* `spec/services/ai_assistant/assistant/tools/session_spec.rb`
* `spec/services/entity_definitions/assistant/processor_spec.rb`
* `spec/services/entity_definitions/persist_spec.rb`
* `spec/services/speech_to_text/activities/enqueue_transcription_spec.rb`

Verified by the targeted regressions:

* Valid partial LLM fields acquire omitted slugs through the same normalization used by planning and persistence. Explicit invalid slugs fail strict validation and roll back the complete set.
* Entity writes merge onto the latest persisted head and preserve `based_on_version_id` lineage. Confirmation replays the stored document/snapshot; changed identities or versions and newly occupied names reject stale approval. Confirmed documents are not repaired or self-approved by model output.
* Entity/page quota fixtures accept limits before creating subscription snapshots. Deliberate later catalog increases/decreases do not replace accepted limits. Snapshot results and quota decisions are not stubbed in these regressions.
* Message polling is pending only for an active current generation, not a trailing user row.
* Terminal clip retention captures `updated_at` before Active Storage purge touches the owner. Fixtures independently set creation/end ages and cover the exact retention boundary.
* Actual FFmpeg-generated compressed audio is decoded by the probe specs; clip conversation binding, queue refusal, duplicate processing, recovery and broadcast fallback execute.
* Native RubyLLM recursion, per-completion budget/cancellation guards, generation claiming, and committed website effects/Undo provenance execute through the targeted test seams.
* Existing English I18n values are preserved; obsolete substring assertions use the existing translation keys.

Provider network responses are mocked in the relevant adapter specs; no live vendor/browser journey or historical-payment backfill is claimed. No source/spec fix was needed after this targeted run: the prior owned fixes plus the current finite Starter fallback passed on the first execution.

## Paired developer references

Updated both `en` and `zh-CN` pages for:

* `entity-builder.md`: partial slug normalization, strict validation, approval/version semantics and accepted quotas.
* `speech-to-text.md`: pre-purge terminal retention age and actual targeted verification.
* `ai-assistant.md`: generation-authoritative polling, confirmation/quota semantics, current LLM boundary excerpt and actual targeted verification.

The six changed pages were also loaded through `DeveloperDocs::Repository` and rendered with the application renderer on the isolated test environment. All rendered successfully, contained the verification count and had no unresolved callout placeholders. Locale pairs have matching heading-level sequences and byte-identical rendered Ruby examples:

| Page | Headings per locale | Ruby examples per locale |
| --- | ---: | ---: |
| Entity builder | 12 | 5 |
| Speech to text | 6 | 4 |
| AI assistant | 7 | 6 |

The documentation render/parity check exited **0**. The scoped `git diff --check` also exited **0**. Documentation-only edits did not require repeating the already-passing 1,666-example application slice.

The earlier full-suite report remains historical evidence of its 442 failures; this targeted result does not certify unrelated feature areas.
