# Email/SMS route-chain audit — 2026-10-11

## Provenance and scope

This records the exhaustive read-only audit that preceded the backend remediation.
The original audit inspected source, the schema and relevant migrations, existing
specs, both developer-reference locales, and relevant installed Rails/SNS/DKIM
library code. No tests, migrations, application runners, or subagents were run.
Original finding citations below refer to **pre-remediation line numbers**; the
implementation appendix distinguishes the subsequent backend changes from audit
evidence. A finding being listed here does not mean another lane has not since
fixed it. Verification remains syntax-only for this backend dispatch.

Excluded: flowchart/page-builder implementations and every file below
`app/services/page_layout_templates/templates/`. Authentication issuance,
billing mailers and unrelated mail-producing routes were not part of the
explicit email/SMS endpoint audit. The explicit help-email route and applicable
generic module routes were also traced.

## Exact route/action coverage

All **77 distinct controller/action pairs** in the requested families were
reviewed. GET implies Rails HEAD support; ordinary resource update accepts PATCH
and PUT. Every template preview/test-send mounting and response-format branch was
included, rather than treating a controller name as proof of coverage.

Prefixes:

- E: `/:customer_id/admin/modules/emails`
- S: `/:customer_id/admin/modules/sms`
- P: `/:customer_id/admin/maintenance/platform/module_settings`

| Controller | Exact actions / route variants |
| --- | --- |
| `Emails::WebhooksController` | `create`: POST `/email/webhooks/:provider` |
| `Sms::WebhooksController` | `create`: POST `/sms/webhooks/:provider/:kind`; delivery, inbound and unknown-kind branches |
| `Emails::TrackingController` | `open`: GET `/email/track/:message_id/open.gif`; `click`: GET `/email/track/:message_id/click` |
| `Emails::UnsubscribesController` | `show`: GET `/unsubscribe/:token`; `create`: POST same path |
| `Admin::Modules::Emails::DashboardController` | `show`: E`/dashboard`, HTML and CSV |
| `Admin::Modules::Emails::HealthController` | `index`: E`/health` |
| `Admin::Modules::Emails::TemplatesController` | `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`; member `status` PATCH; member `preview` GET/POST; collection `preview` POST; member/collection `test_send` POST; member `duplicate` POST |
| `Admin::Modules::Emails::TemplateVersionsController` | `index`, `show`, `create`, `edit`, `destroy`; member `default` PUT, including inherited implementation |
| `Admin::Modules::Emails::AttachmentsController` | `create`, `show` |
| `Admin::Modules::Emails::SendActivitiesController` | `index`, `show`, `new`, `create`, `edit`, `update`, `destroy` |
| `Admin::Modules::Emails::SendActivityDeliveriesController` | `create`: nested delivery POST |
| `Admin::Modules::Emails::SendActivityCancellationsController` | `create`: nested cancellation POST |
| `Admin::Modules::Emails::ListsController` | `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`; collection `preview` POST; index HTML/JSON |
| `Admin::Modules::Emails::ReportsController` | `index`: permanent dashboard redirect |
| `Admin::Modules::Emails::DeliverabilityController` | `index`: permanent health redirect |
| `Admin::Modules::Emails::EngagementController` | `index`: permanent health redirect |
| `Admin::Modules::Emails::SuppressionsController` | `index`; collection `batch_unblock` DELETE |
| `Admin::Settings::Modules::Emails::TemplateTokensController` | `index`, `new`, `create`, `edit`, `update`, `destroy` |
| `Admin::Maintenance::Platform::Emails::CredentialsController` | `index`, `new`, inherited `create`, `edit`, inherited `update`, collection `delivery` PATCH: P`/email/credentials` |
| `Admin::Maintenance::Platform::Sms::CredentialsController` | `index`, `new`, inherited `create`, `edit`, inherited `update`, collection `delivery` PATCH: P`/sms/credentials` |
| `Admin::Maintenance::Platform::Sms::TemplatesController` | `index`, `new`, `create`, `edit`, `update`, `destroy`: P`/sms/templates` |
| `Admin::Modules::Sms::MessagesController` | `index`, `show`: S`/messages` |
| `Admin::Modules::Sms::SendsController` | `create`: S`/sends` |
| `Admin::Modules::Sms::OptOutsController` | `index`: S`/opt_outs` |

Route declarations: `config/routes.rb:94–121`, `334–336`, `595–606`, `726–770`.

Additional applicable action chains reviewed:

- `Admin::ModuleEntriesController#show`
- `Admin::ModuleConfigsController#show, update`
- `Admin::Maintenance::ModulesController#index`
- `Admin::Maintenance::ModuleEnablementsController#create, destroy`
- `Admin::Maintenance::ModuleOwnerConfigurationsController#update`
- `Admin::Maintenance::Platform::ModuleSettingsController#index, show, configuration, developer, update`
- `Admin::HelpEmailsController#create`

Supporting route declarations: `config/routes.rb:251`, `290–292`, `357–360`,
`380–384`, `585–590`.

## Backend chains and storage inspected

| Surface | Traced backend chain |
| --- | --- |
| Shared authorization | `ApplicationController` → `TenantContext` → `RouteAuthorization` → `Ability` → MFA; explicit resource tenant scopes |
| Email callbacks | Registry constraint → `verified_provider` → active credentials → SES SNS verifier / Aliyun Basic/query-secret verifier → parser → message transitions → global suppression |
| SMS callbacks | Registry constraint → `verified_adapter` → active credentials → Twilio request validator → receipt transition or inbound parser → `PhoneNumber` → global opt-out |
| Tracking | Message lookup → `MessageVerifier(:email_tracking)` → destination validation → `MessageEvent` → event table / open-only unique index |
| Unsubscribe | Dedicated verifier/purpose → user/address resolution → tenant suppression; token generation in `VariableContext`, SMTP mailer and SES provider |
| Template CRUD / preview / test | Scoped template → callbacks → token codec/catalog → compiler/author preview/renderer → raw gateway → ledger → delivery job |
| Versions | `TemplateVersionsController` → `BaseVersionsController` → `Versionable`, `VersionRecord`, `ContentAddressable` → versions/content/head → scalar and Action Text restoration |
| Attachments | Direct upload → Active Storage tenant stamping → scoped show; SGID resolution, CID generation, browser URL generation and SMTP blob download |
| Campaign build/start | `Build` → parent/join validations → `StartSendActivity` → claim → recurrence/successor → job enqueue |
| Campaign send/cancel | Job quota/throttle → SQL audience union and deduplication → recipient context/render → campaign gateway → keyed ledger → delivery job; cancellation and scheduler/reaper |
| Lists | Parameter parsing and membership replacement → list/membership → `SegmentQuery` / reflection field whitelist → tenant user relation |
| Analytics | `DateRange` → dashboard/report/health/export → message/event/suppression queries; redirect aliases and batch-unblock |
| Tokens | BulkCreate/Update/Destroy; Reform contracts → shape/entity/schema validation → catalog/localized display labels |
| Platform credentials | `BaseCredentialsController` → SaveCredential / AssignDelivery → encrypted secret columns + JSON config → readiness/resolver |
| SMS sends | Gateway → Send activity → E.164 → Reform → idempotency → opt-out → credential/template code → phone/daily limits → ledger → Aliyun RPC / Twilio SDK |
| Reconciliation | Email queued dead-letter cron; campaign scheduler/reaper; SMS poll/unconfirmed cron and job wrappers |
| Infrastructure | `PluginRegistry`, `VendorPlugin`, `OutboundHttp`, `Vendor::AliyunRpc`, daily-cap resolver, registrations/provisioners/customer assignments |
| Help mail | Contract → attachment rules/snapshot → `HelpMailer` → Action Mailer transport |

Models/tables: email credentials, messages, message events, suppressions, templates,
template versions/content/tokens, lists/memberships, campaign/list joins and
campaigns; SMS credentials/templates/messages/opt-outs; customer/user associations;
Active Storage tenant stamp. Both `doc/reference/en/{email,sms}.md` and
`doc/reference/zh-CN/{email,sms}.md` were read.

## Ranked confirmed findings from the original snapshot

These are static/control-flow confirmations, not claims of passing reproductions.
Each trigger is distinct from hypothetical generic risk. Existing specs named
below are the relevant regression homes; they were not executed during the audit.

### P1-01 — Delivery ignores later suppression/cancellation

- Evidence: `app/jobs/emails/deliver_message_job.rb:24–37`, `app/services/emails/gateway.rb:80–105`, `app/models/emails/send_activities/send_activity.rb:115–119`, cancellation controller `:11–18`.
- Trigger: queue mail, then unsubscribe, add bounce/complaint suppression, cancel the campaign, or delete a cancelled campaign before delivery.
- Result: the job checks queued status and module enablement only; already queued mail still sends.
- Proposed fix: dispatch-time suppression/cancellation checks and conditional terminalization; retain cancellation context until queued work has a disposition.
- Specs: `spec/jobs/emails/deliver_message_job_spec.rb`, `spec/requests/admin/modules/emails/send_activity_cancellations_spec.rb`, `spec/requests/emails/unsubscribes_spec.rb`.

### P1-02 — Shared daily cap and campaign minute limit can be exceeded

- Evidence: `app/services/emails/gateway.rb:56–58`, `app/services/emails/activities/send.rb:45–47,59–64`, campaign job `:23–35,53–59,131–148`.
- Triggers: competing raw sends spend the last slot; competing campaigns use the same observed remainder; transactional and campaign mail independently consume a full cap; an empty minute starts a 500-recipient batch despite a limit of 60.
- Result: raw admission is outside the lock, campaigns do not reserve quota, type-specific counts split one configured cap, and the throttle is checked only before the batch.
- Proposed fix: one atomic tenant reservation path across types; reserve each recipient and bound batches by remaining minute/day capacity.
- Specs: `spec/services/emails/gateway_spec.rb`, `spec/services/emails/activities/send_spec.rb`, `spec/jobs/emails/send_activities/send_activity_job_spec.rb`.

### P1-03 — No exclusive delivery claim

- Evidence: delivery job `:25–37`, `app/models/emails/message.rb:38–42`.
- Trigger: two executions read queued before either finishes its vendor call.
- Result: both dispatch normally; ledger idempotency does not prevent duplicate dispatch. This is separate from the documented timeout-after-acceptance retry trade-off.
- Proposed fix: conditional claim, lease/recovery and provider idempotency where actually supported.
- Specs: `spec/jobs/emails/deliver_message_job_spec.rb`.

### P1-04 — Stale instances can regress message states

- Evidence: email message `:38–77`, SMS message `:39–44,69–73`, SMS gateway `:25–32`.
- Trigger: complaint and delivery callbacks hold stale sent copies; or an SMS unknown poll finishes after another operation records delivery.
- Result: instance-state guards permit complaint → delivered or delivered → unknown regressions. SMS locks exist for some transitions but not all.
- Proposed fix: every transition must evaluate current DB state atomically; preserve complaint priority and the SMS delivered floor.
- Specs: `spec/models/emails/message_spec.rb`, `spec/models/sms/message_spec.rb`, `spec/services/sms/gateway_spec.rb`.

### P1-05 — Early receipts are acknowledged and discarded

- Evidence: email webhook `:15–16,63–69`, SMS webhook `:64–73`, delivery job `:36–37`, SMS Send `:71–72`.
- Trigger: authenticated receipt arrives before the send response's vendor ID is saved.
- Result: lookup misses, HTTP 200 stops vendor retries, no durable event remains. Email and Twilio have no polling recovery.
- Proposed fix: authenticated, deduplicated receipt inbox with unmatched-event retry after correlation and through cron.
- Specs: both webhook request specs and `spec/jobs/emails/deliver_message_job_spec.rb`.

### P1-06 — Reassignment loses historical delivery/STOP receipts

- Evidence: email AssignDelivery `:36–39`, SMS AssignDelivery `:35–38`, email webhook `:42–55`, SMS webhook `:48–61`, both credential resolvers `:10–19`, SMS gateway `:18–22`.
- Trigger: send through A; assign B before A's receipt arrives or before its queued/poll work executes.
- Result: active-only resolution rejects A, including suppression and STOP callbacks. Messages do not record original account/mode identity.
- Proposed fix: distinguish eligibility for new sends from historical verification/query; pin credential/account and mode; retain rotation overlap for outstanding work.
- Specs: both AssignDelivery service specs, both webhook request specs, SMS reconciliation service spec.

### P1-07 — SMTP one-click DKIM omits List-Unsubscribe-Post

- Evidence: delivery mailer `:63–64`, DKIM signer `:43,50–59`; installed `dkim-1.1.0/lib/dkim.rb:7–15`.
- Trigger: SMTP campaign uses the app signer without another downstream signer providing the missing coverage.
- Result: the default gem header list includes List-Unsubscribe but not List-Unsubscribe-Post. RFC 8058 §§3.1/4 require both in `h=`; compliant receivers should not offer one-click.
- Proposed fix: explicit signable-header list and final emitted-message assertions.
- Specs: DKIM signer, delivery mailer and DKIM interceptor specs.

### P1-08 — Metadata-only list PATCH expands audience

- Evidence: lists controller `:247–270`, SegmentQuery `:41–45`.
- Trigger: PATCH just a list name/description, omitting list_type and rules.
- Result: static becomes dynamic; filtered dynamic loses its rules; empty rules return every tenant user.
- Proposed fix: preserve omitted values; clearing rules/changing type must be explicit.
- Specs: `spec/requests/admin/modules/emails/lists_spec.rb`; its old metadata-only membership example supplies list_type and misses this case.

### P2-09 — Delivery headers unsubscribe the changed profile address

- Evidence: campaign gateway `:74,87,97–101`, delivery mailer `:60–64`, SES `:134–140`, unsubscribe service `:15–19`.
- Trigger: queue to A, change profile to B, then deliver.
- Result: envelope/body still refer to A while regenerated header authorization targets B.
- Proposed fix: authorize immutable message tenant/address and share that identity between body and headers.
- Specs: delivery mailer, SES provider and SendActivityUnsubscribe specs; old tests change the profile after generating a token, not before header generation.

### P2-10 — Persist/enqueue handoff can lose mail

- Evidence: email Send `:47–55`, gateway `:57–58,84–105`, fan-out job `:76–79,95–98`, production config `:53–54`, database config `:35–46`.
- Trigger: crash/enqueue failure after primary ledger commit; Solid Queue is a separate database.
- Result: campaign resume treats the persisted user ledger as already sent; the old email reaper fails it instead of repairing the handoff.
- Proposed fix: durable queued-ledger outbox with due/enqueue markers and recovery; distinguish materialization from delivery.
- Specs: gateway, email Send, fan-out job and email reconciliation specs.

### P2-11 — Transient fan-out errors silently skip recipients

- Evidence: fan-out job `:53–65,83–98,109–117`.
- Trigger: temporary render/persist/enqueue failure for a recipient in a run that subsequently finishes.
- Result: all StandardError is swallowed, failed recipients can have no ledger row, and campaign becomes succeed without retrying them.
- Proposed fix: transient failures propagate/retry; permanent failures need a durable disposition; finalize only materialized recipients.
- Specs: fan-out job spec.

### P2-12 — API providers drop supported message features

- Evidence: compiler `:183–190`, SES `:107–125`, Aliyun email `:120–135`, SMTP mailer `:67–79`.
- Triggers/results: compiled CID images have no API MIME parts; Aliyun campaign headers omit one-click unsubscribe; CC/BCC are flattened into ToAddress; reply_to's actual address is not transmitted.
- Proposed fix: implement actual transport support or explicitly reject unsupported features before queueing; preserve BCC semantics.
- Specs: SES/Aliyun provider and compiler specs. CC/BCC/reply_to are backend gateway features; attachment/header loss is directly reachable through the audited HTTP routes.

### P2-13 — Aliyun SMS uses incorrect poll response fields

- Evidence: Aliyun SMS `:75–79`, adapter spec `:91–124`; vendor QuerySendDetails documentation.
- Trigger: real response contains `SmsSendDetailDTOs.SmsSendDetailDTO`.
- Result: code reads `SendDetailDTOs.SendDetailDTO` and returns unknown, then stops polling after three days.
- Proposed fix: use actual schema and genuine fixture shapes, with malformed-shape handling.
- Specs: Aliyun SMS adapter and SMS reconciliation specs. Both developer-doc locales already acknowledge this at `sms.md:19`.

### P2-14 — SES suppresses only the first affected recipient

- Evidence: SES provider `:186–194,206–211`.
- Trigger: multiple bouncedRecipients/complainedRecipients in one notification.
- Result: only element zero is emitted and suppressed.
- Proposed fix: normalized event per affected recipient, with explicit message-level roll-up semantics.
- Specs: SES provider and email webhook request specs.

### P2-15 — Email replay fails at quota and validation races

- Evidence: email Send `:14–21,45–49`, raw gateway `:56–58`, PersistMessage `:13–17`, email message `:29`.
- Triggers: replay after first send fills the cap; duplicate arrives between existing lookup and real uniqueness validation.
- Result: cap rejects an existing result; Active Record raises RecordInvalid rather than the rescued RecordNotUnique.
- Proposed fix: replay before mutable prerequisites; narrow validation/index duplicate recovery inside a safe persistence transaction.
- Specs: email Send/gateway/PersistMessage specs; old race examples force only RecordNotUnique.

### P2-16 — Blank SMS idempotency keys replay another recipient

- Evidence: SMS Send `:25–28,87–94`, schema `:1179`.
- Trigger: two distinct sends in one tenant use empty string keys.
- Result: blank fast path is skipped but non-NULL unique index applies, returning the first send for the second phone.
- Proposed fix: normalize blank to nil before lookup/persist and validate meaningful key shape.
- Specs: SMS sends request, Send activity and message specs.

### P2-17 — SMS phone limits are split by template

- Evidence: SMS Send `:46–47,111–122`, SMS message `:31–34`, adapter base `:25–30`.
- Trigger: send different templates to one phone within the declared one/minute window.
- Result: separate counters permit sequential bypass. The pre-reservation concurrency race is separately acknowledged in old comments.
- Proposed fix: aggregate/reserve the actual phone window atomically; document intended tenant partition.
- Specs: SMS Send and message specs.

### P2-18 — Failed campaign updates persist audience joins

- Evidence: Build `:20–26,70–78`.
- Trigger: replace lists and submit an invalid parent field such as blank name.
- Result: collection assignment commits before parent save fails; 422 can accompany an audience change.
- Proposed fix: validate then save parent/list changes under one transaction.
- Specs: campaign request specs; old invalid examples keep original lists.

### P2-19 — Eleven lists produce an unhandled callback exception

- Evidence: Build `:78`, campaign model `:179–189`; installed Rails collection replacement callback implementation.
- Trigger: submit eleven accessible lists.
- Result: before_add raises RecordNotSaved before ordinary model validation can return false.
- Proposed fix: bound selected lists before callbacks and return localized contract errors.
- Specs: campaign request spec `:222–239` already expects 422; static flow conflicted with that expectation, not a recorded test result.

### P2-20 — Campaign template integrity is insufficient

- Evidence: campaign model `:26–27,51,230–233`, StartSendActivity `:22–24`, schema campaign table/FK section.
- Trigger: draft/retired same-tenant template, or a nonblank nonexistent template ID.
- Result: active status is not required; optional nil association bypasses tenant validation and no FK requires existence; a campaign can start and fail later in its job.
- Proposed fix: existing active same-tenant template at build/start and an appropriate database association constraint.
- Specs: campaign requests/model and StartSendActivity specs.

### P2-21 — Edit/destroy guards race with scheduler claims

- Evidence: campaign controller `:86–92,110–115`, Build `:20–26`, campaign model `:78–81`.
- Trigger: controller passes a pending-instance guard, scheduler claims, controller then saves/deletes.
- Result: processing campaign changes or disappears after claim.
- Proposed fix: persistence-time atomic state precondition coordinated with claiming.
- Specs: campaign request and scheduler job specs; old tests start with already-blocked statuses.

### P2-22 — Default version pointer does not apply live content

- Evidence: BaseVersionsController `:45–48`, Versionable `:284–293`, template model `:103–108,120–132`.
- Trigger: save A, change live template to B, PUT A/default.
- Result: pointer changes but template inherits an empty reload_definition_from_head! hook; preview/send still use B.
- Proposed fix: atomically apply scalar/Action Text definition when changing the head.
- Specs: template versions request spec `:146–156`, template model spec. Old request example does not change live scalar subject when creating its second version.

### P2-23 — Version writes bypass module disablement

- Evidence: template versions controller `:9–18`, base versions `:12,38–64,93`, templates controller `:19,396–399`.
- Trigger: disable Email, invoke version create/default/destroy.
- Result: inherited write guard is empty; ordinary template mutations are gated but version writes are not.
- Proposed fix: shared module write gate for every version mutation.
- Specs: template versions request spec.

### P2-24 — Quota deferral is killed after reset

- Evidence: campaign job `:124–128`, campaign reaper `:22–30`, campaign model `:97–100`.
- Trigger: overnight quota wait; after reset reaper runs before delayed fan-out.
- Result: current at-cap exception disappears, old started_at exceeds two hours and legitimate work is failed.
- Proposed fix: explicit deferral reason/due marker, with recovery aware of waiting/progress.
- Specs: campaign job and campaign reconciliation service specs.

### P2-25 — Malformed unsigned SNS envelope raises 500

- Evidence: SES `:59–65`, email webhook `:17–24`, installed SNS MessageVerifier `:54–57,127–130`.
- Trigger: active SES account, recognized Type, SignatureVersion 1, malformed SigningCertURL such as `%`.
- Result: SDK URI parsing occurs before authenticity and escapes its VerificationError rescue; controller does not handle InvalidURIError.
- Proposed fix: normalized envelope shape/URL validation and narrow authentication-error translation.
- Specs: SES provider/email webhook specs; mocking authentic? masks the SDK path.

### P2-26 — Unsubscribe inherits session MFA redirects

- Evidence: unsubscribe controller `:4–12`, EnforcesMfa `:42–53`.
- Trigger: signed-in browser has pending MFA when using a valid public unsubscribe token.
- Result: unrelated session state redirects instead of completing token authorization.
- Proposed fix: exempt the public token action from the session MFA gate.
- Specs: unsubscribe request spec with signed-in verification/enrollment obligations.

### P2-27 — Analytics include unsent mail and omit delivery failures

- Evidence: DashboardStats `:13,56`, Report `:45,71`, campaign show view `:107–111`.
- Triggers: suppressed/pre-send-failed messages; delivery jobs fail after successful fan-out.
- Result: status-not-pending/queued counts suppressed/failed as sent; campaign failed card uses only fan-out failure stats.
- Proposed fix: separate queued/attempted/sent outcomes and derive actual failures from ledger; define cohort/event-time denominators.
- Specs: dashboard stats/report services and campaign requests.

### P2-28 — Token update accepts dangling mappings and drops form errors

- Evidence: token model `:17–18,103–126`, Update operation `:14–17`, token controller `:47–57`, token form component `:2–3`.
- Triggers: nonexistent nonblank entity ID; blank/overlong label; bulk fields submitted as an allowed array rather than a values-bearing hash.
- Result: optional nil entity skips validators; controller discards Reform errors/submitted state; BulkCreate.values raises NoMethodError on arrays.
- Proposed fix: accessible active entity validation, render validated form state, validate bulk container shape.
- Specs: token requests/model/editor component specs.

### P2-29 — Subject/plain text use an HTML serializer

- Evidence: template model `:74–79`, codec `:23–31,79–82`, renderer `:15–18,38–41`.
- Trigger: literal ampersands or markup-like angle brackets in plain fields.
- Result: HTML parsing/serialization changes text semantics/entities that later become actual plain subject/text content.
- Proposed fix: text-only normalization for text fields, HTML-aware normalization only for HTML/chips.
- Specs: codec/template/renderer specs.

### P2-30 — Editing removes fallbacks; labels collide

- Evidence: codec `:49–56,103–106`, editor component `:53–59`, token model `:25`.
- Triggers: edit/resave UUID token with fallback; custom label collides with platform label such as Unsubscribe URL.
- Result: presentation rewrite removes fallback; label index overwrites identity and can map unsubscribe/personalization to a blank custom token.
- Proposed fix: lossless fallback conversion, identity independent of labels, disambiguation/duplicate-label validation.
- Specs: codec/catalog/token request specs.

### P2-31 — Credential CRUD bypasses single-active assignment

- Evidence: email credential controller `:117–120`, SMS credential controller `:116–117`, both SaveCredential activities, schema `:407,1158`.
- Trigger: activate B through CRUD while A remains active in that mode.
- Result: no sibling deactivation or active-mode unique index; resolver can continue selecting A.
- Proposed fix: activation only through assignment and database-enforced invariant.
- Specs: both platform credential request specs and AssignDelivery service specs.

### P2-32 — Suppressed SMS probes reveal global opt-out metadata

- Evidence: opt-out controller `:23–24`, OptOut model `:26–27`, SMS Send `:35–36,97–105`.
- Trigger: tenant with no actual contact submits a send to a guessed/supplied globally opted-out phone.
- Result: suppressed ledger row unlocks global provider/reason/timestamp visibility despite the stated actual-contact policy. This is metadata leakage for supplied numbers, not automatic arbitrary-number disclosure.
- Proposed fix: visibility must require an actual contact/send event.
- Specs: SMS opt-out request spec; old positive fixture does not prove contact.

### P2-33 — Public email URL origin is wrong/inconsistent

- Evidence: production config `:61`, development config `:49`, renderer `:54–57`, unsubscribe service `:26–28`.
- Triggers: production deployed off example.com; development unsubscribe URL generation; missing mailer protocol.
- Result: placeholder host, lost port 3000, tracking defaults explicitly to HTTP.
- Proposed fix: canonical external origin and shared host/protocol/port/prefix handling.
- Specs: renderer/unsubscribe/mailer/provider specs, asserting exact origins.

### P2-34 — Scheduled individual email is prematurely dead-lettered

- Evidence: email Send `:51–54`, email reconciliation `:15–20`, email message schema.
- Trigger: backend schedules an individual email more than an hour ahead.
- Result: queued row has no stored due time; created_at-based reaper fails it before the delayed job is due.
- Proposed fix: persist due time and measure stalled dispatch from due/claim time.
- Specs: email Send and email reconciliation specs. scheduled_at is a traced backend API parameter, not exposed by the enumerated HTTP controllers.

### P3-35 — I18n heading collision and stored/raw reason wording

- Evidence: both admin_modules locales `:274,283–286`, health component `:62–67`; raw suppression reason at `:56`; reaper failure wording at `:24`; FieldCatalog `:70–75`.
- Trigger: render device heading; view canned reasons in another locale.
- Result: duplicate devices YAML key overwrites heading with a map; raw/stored wording bypasses viewer-locale translation.
- Proposed fix: separate heading/items keys in both locales and translate stable reason keys at display time.
- Specs: health request/service, field catalog and bilingual presentation assertions.

## Checks that held up

- Controller-layer admin authentication/role checks and URL-derived tenant rejection exist.
- Template/version/campaign/list/blob/message/custom-token lookups use explicit tenant scopes.
- Campaign/list assignment and existing-template tenant validation reject foreign associations.
- Static membership synchronization searches only current-tenant users.
- Batch unblock cannot remove global or another tenant's suppressions.
- Click authorization binds message ID and exact URL; URL validation rejects non-HTTP schemes, userinfo and missing host.
- Tracking failure/missing-message responses share 404; open deduplication has a partial unique index.
- Unsubscribe uses a dedicated verifier/purpose and a signed address that survives profile changes.
- Twilio uses the official request validator; SES uses signed SNS + topic binding; Aliyun uses configured Basic/query secret.
- SMTP/poll-only adapters are rejected on callback endpoints.
- Authored preview HTML is sandboxed; POST preview returns JSON.
- SMTP blob download and CID browser URL generation are tenant filtered.

No direct controller cross-tenant IDOR or arbitrary unsigned delivery/STOP forgery
was confirmed. Async lifecycle guarantees were materially weaker than ordinary
controller tenant scopes.

## Original DB/doc/verification gaps

### Constraints

- Email/SMS idempotency indexes are unique per tenant for non-NULL keys.
- Credentials are unique provider × mode, without active-per-mode uniqueness.
- Global suppression/opt-out uniqueness uses NULL-customer partial indexes.
- Memberships and campaign/list joins have pair uniqueness and ordinary FKs.
- Template history/content/head has FKs and version-number uniqueness.
- SMS messages reference customers/templates.
- Vendor/provider IDs have nonunique indexes, without account identity linkage.
- Email messages lack credential/mode, campaign and customer FKs; campaign template has no FK.
- Static membership tenant equality is protected by the audited controller, not model/DB.

### Docs

- Both email reference locales `:87` and Email::Provisioner.revoke comments claim customer FK cascade; schema/customer associations do not supply it.
- Both email pages `:73` claim provider-specific From selection; Credential#from_address prefers leftover username even for API rows.
- The cap docs omit split budgets/non-atomic campaign reservations.
- Both SMS pages `:19` accurately acknowledge the Aliyun response-field defect.
- Both email pages `:31` accurately describe Aliyun CC/BCC flattening; documentation does not preserve the gateway contract.
- Header DKIM coverage, queue-time cancellation/suppression, early receipt loss and historical-account lifecycle need documentation.

### Unverified/accepted boundaries

1. No tests or concurrent live reproductions were run. Many prior race specs inject errors or execute sequentially.
2. Actual cross-account vendor-ID collisions were not demonstrated; absence of identity binding was established.
3. Missing final Twilio receipts and SMS rows older than the poll window can remain nonterminal.
4. SNS tests mock authenticity; verifier certificate fetch uses its own timeout defaults and per-request cache.
5. Rails signed Active Storage URLs remain capability-based; foreign SGID/leaked capability integration was not tested.
6. Invalid segment conditions deliberately drop out; all-invalid means all tenant users. Existing specs pin this fail-open policy. AST bounds are absent.
7. Email generic config rendering ignores password field type/masking; current vendors do not declare such fields, but the promised one-file extension contract would fail.
8. Owner gating does not restrict the URL customer for platform credential/template operations to 81721200; this is a path convention mismatch, not admin escalation.
9. Some specs have stale instrument-collision comments and incomplete SES activation fixtures.
10. Vendor-acceptance timeouts remain ambiguous and can duplicate mail; a local claim does not create vendor exactly-once delivery.

## Backend remediation handoff

### Owned changes

Backend implementation owns jobs under `app/jobs/emails`, allowed services under
`app/services/emails`, email message/campaign/receipt models, SMS services/models,
the new lifecycle migration and relevant specs. It does not edit controllers,
mailers, views, JS, provider/email-activities namespace, shared schema, or the
other lane's template/compiler/renderer/token files. Changes in those paths by
concurrent lanes are not attributed to this backend dispatch.

Implemented here:

- Conditional dispatch leases and DB-evaluated monotone email/SMS transitions.
- Suppression/cancellation checks after claim and immediately before dispatch.
- Unified email day reservations and atomic campaign minute reservations across producers.
- Replay before validation/cap/credential selection; blank key normalization; narrow real-validation/index race recovery.
- Durable queued outbox with due/enqueue/claim/attempt markers and periodic recovery.
- Recorded credential ID/mode metadata for new email/SMS rows and historical resolution.
- Authenticated receipt inboxes with deduplication, pending correlation, account-bound lookup, suppression/STOP processing, post-send and cron redrive.
- Exclusive campaign run leases, bounded batches, retryable transient fan-out failures, ledger-derived resumability/stats, explicit deferrals and progress-aware reaping.
- Transactional campaign parent/list save, Reform validation before callbacks, active same-tenant template existence, fresh scheduler/edit/destroy guards.
- Actual Aliyun SMS poll fields and atomic phone/day reservations across templates.

### Migration

`db/migrate/20261011173041_harden_email_sms_backend_lifecycle.rb` adds:

- email_messages: delivery_due_at, delivery_enqueued_at, delivery_claimed_at,
  delivery_claim_token, delivery_attempts and due index;
- email_send_activities: deferred_until, deferred_reason, progressed_at,
  fanout_claimed_at, fanout_claim_token and deferral index;
- sms_messages: metadata and tenant-phone-time index;
- email_backend_receipts / sms_backend_receipts: credential/event unique identity,
  vendor correlation, payload, processed time and optional resolved customer.
  The nullable customer is intentional for authenticated events arriving before
  tenant correlation. Receipt credential foreign keys retain the ingress identity.

The migration was not applied and `db/schema.rb` was not edited. QA must migrate
the intended test/development databases before executing the added specs.

### Interfaces for controller/provider integration

After authentication, retain the **exact credential that verified the callback**.
Do not reselect an active/default credential after verification.

```ruby
Emails::ReceiptInbox.record!(
  credential: verified_credential,
  event: { type: :delivered, provider_message_id: vendor_id, email: recipient,
           suppress: false, raw: normalized_vendor_data },
  event_key: optional_stable_vendor_event_key
)

Sms::ReceiptInbox.record!(
  credential: verified_credential,
  event: { type: :delivery, vendor_message_id: vendor_id,
           status: :delivered, raw: normalized_vendor_data },
  event_key: optional_stable_vendor_event_key
)

Sms::ReceiptInbox.record!(
  credential: verified_credential,
  event: { type: :inbound, phone: e164_phone, keyword: adapter_classified_stop,
           raw: normalized_vendor_data },
  event_key: optional_stable_vendor_event_key
)
```

Email supports delivered/bounced/complained; SMS delivery supports delivered,
failed and interim status. Adapter classification/authentication precedes the
inbox. The service is not an authentication mechanism. Raw vendor data is not
part of event identity. The stored key hashes both the optional vendor envelope
key and normalized event identity, so multiple recipient/type events inside one
notification do not collapse even when the caller supplies the same envelope ID.

Messages persist `metadata["credential_id"]` and
`metadata["credential_mode"]`. Email job resolution is
`Emails::DeliveryCredential.for_message(message, mode: optional_mode)`, using the
provider lane's `Email::CredentialResolver.for_recorded` for bound messages.
SMTP provider/mailer/interceptor must pass the resolved ID/mode through; the
concurrent provider lane exposes that interface. SMS resolution accepts
`credential_id:` on `Sms::CredentialResolver.call`; Gateway.query passes stored
identity. Historical resolution permits disabled-but-configured accounts.

Email dispatch is accelerated by `Emails::DeliveryHandoff.call`; the scheduled
`Emails::ReconcileMessagesJob` invokes `Emails::Cron::RecoverMessages.call`.
Direct legacy callers of the singular Email cron need to delegate/cooperate with
this recovery path, rather than restoring created_at-only dead-lettering.

### Remaining integration and verification

- Callback controllers must adopt inbox recording and historical verification keys. Until they do, public early-receipt loss is not fully fixed.
- If several mode rows share a verifying secret/topic/account, authentication must select the original recorded credential when correlation exists, or retain all successfully verified identities for early events. Arbitrarily choosing the first matching row can strand a receipt pinned to another mode row; do not infer identity from an unverified request parameter.
- Do not mutate a retained credential into a different account; key rotation/history retention remains a platform credential concern. IDs/modes alone cannot recover overwritten historical secrets.
- Rows created outside the new admission APIs without identity metadata cannot be safely account-correlated; no guessed identity backfill was performed.
- Controller campaign destroy must honor a false destroy result/errors after the backend's fresh state guard.
- SMS opt-out visibility must require actual contact (e.g. sent_at) in the controller lane.
- Template version live application, token/HTML fixes, URL origins, public MFA exemption, provider MIME/DKIM support, credential activation invariants, analytics views and I18n remain in their respective lanes.
- Claims use a bounded 30-minute lease; a worker stalled beyond the lease and ambiguous vendor acceptance are still at-least-once boundaries.
- Individual scheduled mail books quota at admission; reservation-day and physical-delivery-day policy must be distinguished in reference docs.
- Reference-doc owners must update BOTH `doc/reference/en/email.md` / `zh-CN/email.md` and BOTH SMS pages for lifecycle, quotas, receipt identity, due markers and corrected Aliyun polling. This audit file is the sole documentation file owned by this dispatch.
- Added/updated specs cover claim overlap, stale transitions, suppression/cancel after queue, due-time recovery, queue failure recovery, tenant/account isolation, shared quota, genuine validation duplicate recovery, malformed/oversized campaign selections, stale edit/scheduler guards, transient resume, deferral reset, blank SMS keys and cross-template phone limits.
- Only Ruby syntax and diff-whitespace checks are authorized here. No RSpec result, runtime migration result, or production concurrency guarantee is asserted.

### Verification evidence

All 45 Ruby files changed by this backend dispatch were parsed with `ruby -c`;
every parse returned exit 0 / `Syntax OK`. The final amended receipt/dispatch files
were parsed again after their last edits. Scoped `git diff --check` returned exit
0. RSpec, database migrations, Rails runners and subagents were not run.
