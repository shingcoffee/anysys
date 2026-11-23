---
title: "Background jobs"
summary: "Active Job on Solid Queue in production, with Solid Cache and Solid Cable on their own SQLite databases."
---

## Summary

Production sets `config.active_job.queue_adapter = :solid_queue` and points Solid Queue at the `queue` database. Solid Cache is `config.cache_store = :solid_cache_store` on the `cache` database. Solid Cable is the production Action Cable adapter on the `cable` database. Jobs are `ApplicationJob` subclasses under `app/jobs`. Recurring work is `config/recurring.yml`. There is no Sidekiq configuration in this app.

Development leaves the queue adapter unset, so Active Job's railtie uses `:async`. Development cache is `:memory_store`. Development cable is `async`. Test uses the `:test` adapter and `:null_store`.

## Flow

```text
perform_later / wait_until
        |
        v
Active Job
        |
        +-- production -> :solid_queue
        |                 database.yml  queue: storage/production_queue.sqlite3
        |                 worker: bin/jobs   or   Puma plugin if SOLID_QUEUE_IN_PUMA
        |                 schedule: config/recurring.yml (production:)
        |
        +-- development -> :async (adapter not set in development.rb)
        +-- test        -> :test

Solid Cache (production)  -> database cache
Solid Cable (production)  -> database cable, polling 0.1s, retention 1 day
```

## Implementation

`config/queue.yml` defines one dispatcher (`polling_interval: 1`, `batch_size: 500`) and one worker pool on queues `"*"`, with 3 threads, `JOB_CONCURRENCY` processes (default 1), and `polling_interval: 0.1`. The same block is used for development, test, and production. `config/puma.rb` loads `plugin :solid_queue` only when `ENV["SOLID_QUEUE_IN_PUMA"]` is set. `bin/jobs` boots the environment and runs `SolidQueue::Cli.start`. The production Docker image sets `SOLID_QUEUE_IN_PUMA=true` so the web container runs that plugin; see [Docker image](docker-image).

`config/database.yml` production has four SQLite databases: `primary` (`storage/production.sqlite3`), `cache` (`storage/production_cache.sqlite3`, migrations in `db/cache_migrate`), `queue` (`storage/production_queue.sqlite3`, `db/queue_migrate`), and `cable` (`storage/production_cable.sqlite3`, `db/cable_migrate`). Development is a single file, `storage/development.sqlite3`. `config/environments/production.rb` sets `config.solid_queue.connects_to = { database: { writing: :queue } }`. `config/cache.yml` production sets `database: cache` and a 256 megabyte `max_size`. `config/cable.yml` production sets `adapter: solid_cable`, `connects_to: { database: { writing: cable } }`, `polling_interval: 0.1.seconds`, and `message_retention: 1.day`.

`ApplicationJob` inherits `ActiveJob::Base`. The deadlock `retry_on` and the deserialization `discard_on` in that file are comments. Concrete jobs set `queue_as :default`. Examples:

- `Billing::DailyBillingJob` runs ReconcileCollections, RenewSubscriptions, CollectDueInvoices, Dunning, TrialEndingNotices, RevokePaymentMethods and DispatchNotices with isolated rescue and Current context. `Billing::CollectionMaintenanceJob` runs reconciliation/revocation/notice dispatch every 15 minutes.
- `Payments::ChargeDueSubscriptionsJob`, `Payments::RedriveWebhookEventsJob`, and `Payments::DailyMaintenanceJob` are the payment crons. `Payments::ProcessWebhookEventJob` retries `StandardError` with `wait: :polynomially_longer` up to `ATTEMPTS` (5), then marks the webhook event `failed`.
- `Emails::DeliverMessageJob` retries up to 3 attempts, then `mark_failed!`. `Emails::SendActivities::SchedulerJob` and `ReconcileSendActivitiesJob` are the send-activity crons. `Emails::ReconcileMessagesJob` reconciles delivery.
- `Sms::Campaigns::SchedulerJob` claims/repairs due campaign work every minute; `Sms::Campaigns::RunJob` snapshots the audience once and processes bounded recipient batches. `Sms::DeliverMessageJob` dispatches the shared outbox with no send retry; `Sms::RecoverMessagesJob` repairs handoff/preparation and quarantines attempted crashes. `Sms::ReconcileMessagesJob` redrives receipts and queries delivery status.
- `AiAssistant::ReconcileGenerationsJob` and `SpeechToText::PruneClipsJob` are the other recurring classes. `AiAssistant::ReplyJob` and `SpeechToText::TranscribeJob` are request-driven.
- `Notifications::BroadcastAnnouncementJob.schedule` queues a scheduled start; `ExpireAnnouncementJob` queues exact end-time refresh with a latest-state/end guard. See [Announcements](announcements).

`config/recurring.yml` under `production:` runs `SolidQueue::Job.clear_finished_in_batches` every hour at minute 12, the email and SMS campaign schedulers every minute, SMS recovery every five minutes, the email, SMS, and AI reconcile jobs every 15 minutes, billing collection maintenance every 15 minutes and daily billing at 3am, payment charge at minute 5, payment webhook redrive at minute 20, payment maintenance at 4am, and speech-clip prune at 4:45am. The `development:` entries in that file are comments. The file's own comment says to run `Billing::DailyBillingJob.perform_now` from `bin/rails runner` when you want the billing cron locally.

### SMS outbox lifecycle

`Sms::Gateway.send` records `queued` in the primary database, with a one-hour default expiry, an immutable template/provider-code/variable snapshot and credential ID/mode. It does not call the vendor during admission. `ActiveRecord.after_all_transactions_commit` defers `Sms::DeliveryHandoff` until all enclosing transactions commit; rollback removes the admission and its enqueue callback. Queue enqueue is best effort and a failure leaves the committed ledger available to recovery. Pinned credential identity does not pin a secret/config revision: workers and receipt verification read the retained row's current values.

Recovery scans committed queued rows on the recurring cadence above. A missing or five-minute-old enqueue stamp permits handoff repair; a 30-minute stale preparation claim may be reclaimed with a new token. `Sms::DeliveryDispatch.start` atomically checks the current token and writes `dispatch_started_at` / increments `delivery_attempts` before the external operation. Token replacement fences a stale preparation worker. Expiry, module enablement and recipient opt-out are rechecked immediately before that boundary; unattempted rows can become `expired` or `suppressed`.

`Sms::Campaigns::DeliveryPolicy` adds current marketing contact/activity/phone/consent checks, including for direct marketing messages, and campaign quiet-hours/frequency/cancel/failure/deadline gates. Future `delivery_due_at` gates handoff, preparation, start and recovery. `Sms::DispatchLimiter` locks the retained credential, reads live `sender_rate_per_second` (`0 < rate <= 1`, default 1) and advances `dispatch_next_at` only with a durable due attempt. This shared clock covers every tenant, campaign and direct send using that credential. Deferral releases preparation without a vendor call or new lifetime; `wait_until` enqueue is an accelerator, not a substitute for database due checks. Account pacing limits dispatch authorizations, not carrier deliveries.

An attempted payload is never resent. Timeouts, malformed acceptance and attempted crashes become `unknown`, while proven rejection becomes `failed`. Available validated vendor IDs and response/audit hashes survive partial results or enriched transport errors for query/early-receipt correlation. Completion matches the immutable dispatch marker and the original or already-cleared token; recovery preserves the sole attempt's token for a genuinely late result, without making the row claimable again. Statement/connection failures retry only the fenced ledger write, at most three attempts per transition; the external call and receipt projection remain outside retries. Exhausted completion can attempt bounded unknown recording with retained facts, without downgrading an acceptance or terminal receipt already saved. Recovery eligibility and scheduling do not guarantee a recovery or delivery time.

`Sms::ReconcileMessagesJob` runs every 15 minutes. It redrives authenticated receipts and queries adapters that declare `query_supported?` (Aliyun and Twilio, including Twilio Message fetch for lost callbacks). Its two-minute grace and three-day maximum age, including unresolved-row aging, use `COALESCE(dispatch_started_at, sent_at, created_at)`: dispatch first, historical acceptance/admission fallbacks next. Aliyun's query SendDate uses the same timestamp priority converted to `Asia/Shanghai`. Unresolved older pending/sent rows become `unknown`, not failed dead letters. Late delivery can repair unknown/failed, and delivered cannot be downgraded by a later failure. The additive lifecycle migration changes only the new-row default to queued; it does not retro-send existing pending rows. See [SMS](sms) for API, suppression and diagnostic metadata, and [Flowchart runtime](flowchart-runtime) for transactional `send_sms` admission.

### Flowchart step: enqueue_job

The `enqueue_job` step action schedules an `ApplicationJob` subclass from a flowchart. `jobClass` is a reference to the `job_classes` source (job classes under `app/jobs`), resolved again at runtime by `FlowchartRuntime::Invocable.job!`, so a class outside that allow-list cannot be enqueued. `when` is `now`, `at` (`runAt` expression, required), `after` (`waitSeconds`, up to 30 days) or `recurring` (`cronExpression` and `timezone`, or `intervalSeconds` with `recurrenceLimit`; the horizon is capped at 30 days, and an invalid cron or time zone fails validation). `jobArgs`, `queueName` and `priority` (0–1000) are optional. Scheduling goes through `FlowchartRuntime::JobSchedule`; the step writes the job id to `resultVar` (default `enqueued_job_id`) and fails with `enqueue_job.failed`. `JobSchedule` calls `perform_later` directly, so whether an enqueue made inside a public submission waits for that transaction to commit follows Active Job's `enqueue_after_transaction_commit` for the job class; keep enqueued jobs idempotent. Fields are listed on [Flowchart step actions](flowchart-step-actions).

### SMS campaign scheduling and recovery

Draft save/preview are not sending jobs. Reviewed launch commits frozen content/settings/audience rules and credential identity, sets `scheduled`, and best-effort enqueues `Sms::Campaigns::SchedulerJob` after the outermost commit. The production `sms_campaign_scheduler` recurrence runs every minute on `default`; development has no enabled recurrence. The one-minute cadence is a scan interval, not a guaranteed exact send time.

The scheduler scans scheduled/running campaigns in batches of 100, skips future schedules and establishes URL-independent tenant context with `Current.set`. It creates a random execution token and 15-minute lease if missing/expired; otherwise it reuses the live token. It also repairs due pending continuations and due queued-message handoff (with a one-minute handoff recovery threshold) without waiting for lease expiry. Duplicate jobs are fenced by lease/token, recipient locks and stable message keys.

`Sms::Campaigns::RunJob#perform(customer_id, campaign_id, run_token)` scopes the campaign to the supplied customer and restores `Current.customer`. `Run` checks/renews the lease, then on first execution builds the complete recipient ledger, contact snapshots, resolved variables and initial eligibility in batches of 100 within one transaction, atomically with `started_at`. The maximum matched audience is 10,000. Frozen launch rules are evaluated against current contact data only once; recovery never adds members or recomputes personalization after snapshot commit. Invalid snapshots/rules or oversized audiences fail before admission. Expiry before snapshot fails the campaign; after snapshot it closes remaining unattempted work.

Subsequent runs process at most 100 due pending recipients per call, using quiet hours, campaign frequency, rolling admission rate, daily/phone budgets and the absolute deadline. `Sms::Gateway.send_campaign` admits through the existing core outbox and atomically links one message per recipient; rollback removes both and no handoff runs. Deferred recipients/messages keep their due times/reasons; the run job best-effort schedules continuation at the next due time (at least one second ahead), with database/scheduler recovery as authority.

Cancellation invalidates the execution token and closes only pending/unattempted queued work under the same serialization as final dispatch start. Failed/expired campaigns similarly close unattempted work. Once `dispatch_started_at` exists, core unknown quarantine and receipt/query handling apply without another send. `completed` denotes finished dispatch orchestration, not confirmed delivery to every recipient. Reports derive from recipient/message ledgers, with write-side stats refresh on execution/cancellation and best-effort receipt-triggered refresh; report/CSV GETs are read-only. See [SMS audiences and campaigns](sms-campaigns) for contacts/consent, start-time membership, policy details and report semantics.

### Test database and upload isolation

The RSpec harness uses the test Disk service in `config/storage.yml`. Its root is the expanded absolute path of `ACTIVE_STORAGE_ROOT` (when nonblank), otherwise `<Rails.root>/tmp/storage`, followed by `TEST_ENV_NUMBER`. Expanding before suffixing removes trailing slashes so workers stay siblings. The blank first worker uses `tmp/storage`; worker `2` uses the sibling `tmp/storage2`. Explicit prefixes remain partitioned: `/tmp/my-run/storage` becomes `/tmp/my-run/storage2` for worker `2`. Development/production retain their `local` service and `storage/` root.

`TEST_DATABASE` selects an explicit disposable SQL database; without it, test workers use `storage/test<TEST_ENV_NUMBER>.sqlite3`. Independent verification runs need distinct database files and upload prefixes. Preparing and running a single isolated Website cohort uses the same environment throughout:

```bash
ls -ld storage tmp /tmp/opencode
env -u SKIP_AUTH -u TEST_ENV_NUMBER -u COVERAGE RAILS_ENV=test TEST_DATABASE=storage/website_verify.sqlite3 ACTIVE_STORAGE_ROOT=/home/ec2-user/anysys/tmp/storage-website-verify bin/rails db:schema:load
env -u SKIP_AUTH -u TEST_ENV_NUMBER -u COVERAGE RAILS_ENV=test TEST_DATABASE=storage/website_verify.sqlite3 ACTIVE_STORAGE_ROOT=/home/ec2-user/anysys/tmp/storage-website-verify bundle exec rspec spec/config/active_storage_isolation_spec.rb spec/services/websites spec/services/feature_modules/website spec/requests/websites spec/models/website_spec.rb spec/models/website_page_spec.rb
```

Unset `SKIP_AUTH` for real authorization checks and `TEST_ENV_NUMBER` for a single process. Load schemas only into the deliberately selected disposable test database. Prefer normal blob/attachment purge; whole-directory cleanup must be limited to an exclusively allocated worker/run root. Never remove the shared parent or development/production uploads. No global upload-directory deletion hook was found in `spec/support`; the storage-isolation regression removes only its own newly allocated second-worker directory and checks the first worker's real bytes survive.

Attachment fixtures must explicitly establish `Current.customer` or an authoritative tenant stamp. A foreign ambient customer can trigger a tenancy refusal with the same public error as missing storage, so assert source existence when investigating an import failure. See [Websites](websites) and [Website builder](website-builder) for actual-byte MIME and import contracts. Record commands, scope and raw counts/logs; targeted passes do not replace historical full-suite evidence.

## Where to pay attention

### Route audit: durable handoff and recovery invariants

Primary ledger commit and Solid Queue enqueue are not one cross-database transaction. [SMS](sms) uses the committed queued ledger, post-commit best-effort enqueue and recurring recovery, with a fenced sole attempt and no resend after ambiguity. [Email](email) uses due/enqueued/claim/attempt markers plus `Emails::Cron::RecoverMessages`; campaign deferral/progress and receipt inboxes repair handoff/correlation. [Payments](payments) retains verified webhook body/account, retries projection failure and hourly-redrives failed/stale received events. [Billing](billing) uses permanent attempts and transactional notice intent, then `DispatchNoticeJob` after commit; deduplicated business/enqueue intent is not exactly-once SMTP.

AI failed enqueue terminalizes the generation and creates a visible failure turn; polling only treats live generations as pending. Speech checks enqueue acceptance, claims processing conditionally and purges after durable terminalization. Prune's five-minute staleness threshold is checked on its existing daily 4:45am schedule, so recovery is not guaranteed within five minutes. Support reply broadcasts only after all transactions commit. See [AI assistant](ai-assistant), [Speech to text](speech-to-text), [Support tickets](support-tickets).

:::note
Job/outbox/receipt/expiry and lifecycle storage APIs are source-documented, including the current schema dump. The Website follow-up loaded only a disposable test schema and passed 572 targeted Website/storage examples. On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**. Live queue and worker-restart evidence remain separate.
:::

:::attention
`config/environments/production.rb` is the only place that sets `config.active_job.queue_adapter = :solid_queue`. `config/environments/development.rb` does not set an adapter. Active Job's railtie then assigns `:async` outside test, and `:test` when `Rails.env.test?`. A `perform_later` in development runs in-process. It does not land in the Solid Queue tables unless the adapter is set.
:::

:::attention
`config/recurring.yml` puts the live schedules under the `production:` key. The `development:` key in that file is comments. The scheduler that reads the file is Solid Queue, started by `bin/jobs` (`SolidQueue::Cli`) or by `plugin :solid_queue` in `config/puma.rb` when `SOLID_QUEUE_IN_PUMA` is set. `SolidQueue::RecurringTask#enqueue` inserts with `SolidQueue::Job.enqueue` when that job's adapter is `:solid_queue`. Neither file selects Sidekiq.
:::

:::attention
`Payments::ProcessWebhookEventJob` calls `Current.reset` in `ensure`. `Current` is request state. A worker thread that sets `Current.customer` and returns without resetting it leaves that customer on the next job on the same thread.
:::

:::attention
Production Solid Queue, Solid Cache, and Solid Cable each use the database name in `config/database.yml` (`queue`, `cache`, `cable`), not the primary file. Development has no `queue` connection in `database.yml`. `config.solid_queue.connects_to` is set in production only.
:::

## Key code

```yaml
# config/storage.yml
test:
  service: Disk
  root: <%= "#{File.expand_path(ENV['ACTIVE_STORAGE_ROOT'].presence || Rails.root.join('tmp/storage'))}#{ENV['TEST_ENV_NUMBER']}" %>
```

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store

config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }
```

```yaml
# config/queue.yml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
      polling_interval: 0.1
```

```yaml
# config/recurring.yml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12
  sms_recover_messages:
    class: "Sms::RecoverMessagesJob"
    queue: default
    schedule: every 5 minutes
  sms_campaign_scheduler:
    class: "Sms::Campaigns::SchedulerJob"
    queue: default
    schedule: every minute
  billing_daily:
    class: "Billing::DailyBillingJob"
    queue: default
    schedule: every day at 3am
```

```ruby
# app/jobs/notifications/broadcast_announcement_job.rb
def self.schedule(announcement)
  return unless announcement.scheduled?
  return if announcement.starts_at.blank?

  set(wait_until: announcement.starts_at).perform_later(announcement.id)
end
```

```ruby
# config/puma.rb
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
```
