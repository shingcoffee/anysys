---
title: "SMS audiences and campaigns"
summary: "Consented contacts, explicit Entity sync, dynamic audiences, approved-template personalization, reviewed launch, bounded dispatch and ledger-derived reports."
---

## Summary

The SMS campaign workspace follows **Audience → Content → Schedule → Review**, using the same stepped wizard as an email send activity. Save draft and Preview submit the current fields and do not launch. A tenant administrator adds contacts, separately records marketing consent, selects a dynamic segment or all contacts, personalizes a platform marketing template, saves a draft, and reviews it before launching. Execution captures membership at start, respects current permission and dispatch controls, and retains a recipient ledger for reports and CSV export.

This page describes the current source. The architecture plan at `docs/plans/2026-10-13-sms-audience-campaigns.md` is a design contract; implementation details below take precedence where they differ. Provider setup, direct sending, receipt handling and message states are in [SMS](sms); worker configuration is in [Background jobs](background-jobs).

### Official product references

| Reference | Pattern informing this workflow | Anysys implementation |
| --- | --- | --- |
| [Twilio Messaging Services](https://www.twilio.com/docs/messaging/services) | Shared sender configuration, asynchronous delivery callbacks, validity periods and opt-out handling | Platform credentials, receipt reconciliation, shared-account pacing and a pre-attempt deadline; API acceptance is separate from delivery. |
| [Klaviyo SMS campaigns](https://help.klaviyo.com/hc/en-us/articles/360040039971) | Explicit consent, lists/segments, personalized preview, frequency controls, quiet hours and send now/schedule | Dedicated contacts and consent evidence, dynamic segments, sample preview, a campaign-attempt frequency window and recipient-local quiet hours. |
| [Braze SMS campaign creation](https://www.braze.com/docs/user_guide/message_building_by_channel/sms/campaign/create/) | Subscription filtering, personalization, delivery controls, review and reporting; the link redirects to the current SMS/MMS/RCS guide | Audience membership, permission and dispatch eligibility are distinct; permission is rechecked at the final attempt boundary. |
| [Mailchimp marketing SMS](https://mailchimp.com/help/create-send-marketing-sms/) | Subscribed audiences, merge fields/defaults, a review checklist, send duration, reports and cancellation of remaining queued messages | Field/literal/fallback mappings, saved-draft review, an absolute deadline, conditional cancellation and recipient/message reports. |

These are product references, not integrations with Klaviyo, Braze or Mailchimp or claims of feature parity. The shipped workspace manages one-time SMS campaigns using the existing Aliyun/Twilio adapters. It does not provide their MMS/RCS, conversational inbox, A/B testing, recurring campaigns, link-shortening/click/conversion tracking, CSV contact import or public opt-in acquisition features.

## Flow

```text
Manual contact / explicit Entity sync -> consent unknown
        |
        +-- append grant/revoke evidence -> current-phone consent projection
        v
Dynamic audience -> approved marketing template + safe variable mappings
        |
        v
Save draft -> preview/review saved settings -> signed review token
        |
        v
Launch -> freeze settings/content/rules/credential identity -> scheduled
        |
        |  one-minute SchedulerJob -> leased RunJob
        v
Execution start -> atomic recipient/contact/vars snapshot -> running
        |
        |  eligibility / quiet hours / admission rate / quotas / deadline
        v
Sms::Gateway.send_campaign -> one linked Sms::Message -> post-commit handoff
        |
        |  final permission/policy recheck + shared-account dispatch clock
        v
Sole external attempt -> API acceptance / rejection / unknown
        |
        +-- callbacks / queries -> delivery outcomes -> report / CSV
        +-- cancel -> close only remaining unattempted work
```

## Implementation

### Tenant domain and admin surfaces

Five tenant-scoped models carry the campaign domain: `Sms::Contact`, `Sms::ConsentEvent`, `Sms::Audience::Segment`, `Sms::Campaign` and `Sms::CampaignRecipient`. Templates and credentials remain platform-wide. The module entry opens Campaigns. The sidebar groups the workspace into Campaigns, Audience (Contacts, Segments, and Opt-outs tabs), and Messages. Admin controllers inherit `Admin::Modules::Sms::BaseController`, require admin/owner access and SMS enablement, and resolve records under the URL customer even for owner cross-tenant browsing.

`FeatureModules::Sms::Registration.module_description` translates `sms_campaign_http.registration.description` at call time: “Audience-based SMS campaigns and transactional messaging via pluggable providers.” The platform module catalog reads that registration accessor for the SMS card and its searchable description, so locale changes also update a previously registered module without persisting or freezing the display translation.

The route/access-grant catalogs distinguish all eight audience/campaign resources: Contacts, Consent events, Contact synchronization, Audiences, Campaigns, Launch campaigns, Cancel campaigns and Campaign reports. `AccessPoints::SmsRouteLabels` shares their translation keys with `Admin::Settings::Modules::Authentication::GrantRouteLabel`, producing unique English/Chinese names under a single SMS context instead of a generic resource label. Controller subject keys and action/tenant/role enforcement are unchanged. See [Access grants](access-grants) for the exact subject/action matrix.

Let `S = /:customer_id/admin/modules/sms`. Contacts use `S/contacts` (DELETE archives), evidence uses POST `S/contacts/:contact_id/consent_events`, explicit sync uses `S/contacts/entity_sync`, dynamic audiences use `S/segments`, and drafts use `S/campaigns`. Separate POST actions preview, launch (`S/campaigns/:id/launch`) and cancel (`.../cancel`); GET `S/campaigns/:campaign_id/report[.csv]` reads results. Full request roots, helper names, response codes and CSV columns are documented in [SMS](sms).

New segments preview at `POST S/segments/preview` (`admin_modules_sms_preview_segments_path(customer_id)`). Existing edits use `POST S/segments/:id/preview` (`admin_modules_sms_preview_segment_path(customer_id, segment)`). The member action resolves the record in the URL tenant and overlays submitted values without saving. Success and validation rerenders retain its identity, raw form values and submitted `lock_version`, so the returned Save button PATCHes the original record rather than creating a duplicate. Stale versions still conflict on Save; malformed, missing and foreign member IDs return `404`, including owner requests.

Deletion business rules are service-owned; controllers only validate the HTTP envelope and render/redirect the result:

| API | Inputs | Success `Sms::Result#value` / retained-record result |
| --- | --- | --- |
| `Sms::Audience::DeleteSegment.call` | `customer:, actor:, segment:` | Destroyed segment; a draft dependency returns `segment_in_use` (HTTP 409). Historical campaigns keep their frozen audience/content and ledger, with only `segment_id` nullified. |
| `Sms::Campaigns::DeleteDraft.call` | `customer:, actor:, campaign:` | Destroyed empty, unlaunched draft; non-draft states, recipients, a recorded launch or linked-message restrictions return `not_draft` (HTTP 409). |

Both return `Sms::Result`, reauthenticate the persisted active admin/owner actor, validate the record class and supplied tenant, and lock **customer → record** before reloading a tenant-scoped database row and checking dependencies/state. A platform owner may operate under another tenant's URL but cannot use a foreign record under the wrong supplied customer. Missing/stale or forged in-memory tenant identities return `not_found`; disallowed actors return `forbidden`. Conflict messages reuse the existing `sms_campaign_http.errors.segment_in_use` / `.not_draft` keys in both locales. Failed deletion rolls back without partial nullification; contact and consent evidence are retained.

### Manual contacts and explicit bounded Entity sync

A contact's identity is unique per tenant E.164 phone, including archived records. Manual creation supplies phone, country context (default `CN`), optional name/IANA timezone and a scalar custom-attribute object. Country does not determine timezone. Custom attributes allow at most 32 keys and 8 KiB total; keys match `[a-z][a-z0-9_]{0,63}`, strings are at most 1,024 bytes, and values may be strings, finite numbers, booleans or null, not nested arrays/objects. DELETE archives and retains evidence/history; restoring is an explicit contact status update.

`Sms::Contacts::SyncEntity.call(customer:, actor:, attributes:, preview: false)` supports accessible active plain Entities without native-model extensions or bridge traversal. Shared definitions are resolved through `resolved_current_version` for that customer, but entries always use `EntityEntry.for_customer(customer.id)`. `Sms::EntitySources` offers only supported scalar schema fields; the required phone field must actually have `html_type: "tel"`, not merely a phone-like label. Values come from `entry.data_json[field_slug]`.

Preview writes nothing and examines at most 100 entries after `after_entry_id`. It returns the high-water `through_entry_id`; execute processes at most 100 entries per POST, in ID order, and explicit continuation carries that bound, cursor and mapping. Each request revalidates the source and mapping. Results distinguish created, updated, unchanged, invalid and conflicting items. There is no automatic polling or consent import.

Sync matches a source link first, then a tenant phone. An unlinked same-phone contact may acquire the source link; conflicting identities or distinct existing source links are reported, never merged. Mapped attributes replace only their keys, unmapped keys remain, and archived status is preserved. Same-phone updates preserve consent; a changed phone resets it. Source deletion does not silently delete contacts. Replaying a batch does not duplicate contacts or grant permission.

### Append-only consent and suppression

New/manual/synchronized contacts start with `consent_status: "unknown"`. `Sms::Contacts::RecordConsent` appends an admin event for the current locked phone. Grant requires an evidence reference and the actual consent statement; revoke requires a reference, and both may include notes. Each evidence text is bounded to 1,024 bytes, the evidence object to 4 KiB, and `event_key` to 128 bytes. Occurrence time must have an explicit ISO 8601 offset and cannot be in the future. Customer, actor, source and phone are server-derived.

`Sms::ConsentEvent` is read-only after persistence and has no edit/delete route. Matching event-key replay returns the original evidence; reuse for different facts conflicts. The current-phone projection follows recorded insertion order, with `consent_changed_at` set to recording time, not a backdated occurrence time. Changing phone resets the projection to unknown and clears that timestamp even if the replacement phone had an older grant; old-phone evidence remains and a fresh grant is required.

Revoke and signed recipient unsubscribe also establish a tenant `Sms::OptOut`. A grant never removes tenant/global suppression. Verified provider STOP or Twilio `21610` establishes global suppression and can append correlated `provider_opt_out` evidence. Eligibility reads suppression directly; it does not depend on updating every tenant's contact projection. START/HELP does not grant consent or unblock a number. Archived contacts are ineligible regardless of consent.

### Fail-closed dynamic audiences

`Sms::Audience::SegmentQuery` compiles a bounded grouped AND/OR AST using quoted Arel values and curated fields. Joins apply left to right: `[A, B, C]` with `[AND, OR]` means `((A AND B) OR C)`; nested groups have their own joins. An intentional empty root `{}` or a group with empty conditions/joins considers all tenant contacts. Empty nested groups, unknown fields/operators/keys, incorrect joins, invalid casts or exhausted budgets invalidate the whole tree. Save/preview rejects invalid rules; querying invalid stored rules yields `.none`, and campaign start fails before admission rather than broadening the audience.

Rules are limited to 32 KiB, depth 8, 100 nodes and 1,024-byte string values. Root fields are `name`, `phone_e164`, `country_code`, `timezone`, `status`, `consent_status`, `source_kind`, `created_at` and `updated_at`. Up to 128 sorted, consistently typed tenant custom keys are exposed as `attributes.<key>`; mixed types are excluded, and integers/floats share numeric type. Referenced custom types freeze at launch; missing or wrong-type values are nonmatches. Datetime comparisons require a full ISO 8601 value with offset.

Matched membership includes archived/nonconsenting contacts. Audience preview separates matched, eligible and exclusions; campaign preview additionally checks personalization and the campaign frequency window. Quiet-hour delays remain eligible. Selecting a sample outside the audience never adds it to the counts or grants permission. Campaign preview, launch and start are bounded to 10,000 matched contacts, with at most five preview samples. The shared segment builder uses the SMS catalog and the host's native POST preview action.

### Template purpose, preview mirror and variables

Only the platform owner maintains `Sms::Template#purpose` (`transactional` by default, or `marketing`) and optional `body_template`. Campaign selection requires an active marketing template with a provider code for the resolved sending account. The mirror is at most 4 KiB and accepts simple `{{variable_name}}` placeholders from required variables. It is owner-maintained preview text, not a raw body sent to the provider or proof of vendor approval. With no mirror, preview shows variables and the segment estimate is unknown. With a mirror, `Sms::SegmentCalculator` estimates the rendered sample; it is not a billing quote or a guarantee of actual provider segmentation.

`variable_map` keys must exactly match the selected template's required variables at launch. A field mapping has `source: "field"`, an allowlisted field and optional explicit `fallback`; a literal has `source: "literal"` and `value`. Fields are `name`, `phone_e164`, `country_code`, `timezone`, curated `attributes.<key>` and generated `unsubscribe_url`. Missing/null/blank fields use the fallback; without one the recipient is skipped as `personalization_missing`. There is no implicit name fallback. Mapped booleans become strings; literals/fallbacks must be nonblank strings or finite numbers. Limits are 64 variables, 128-byte keys, 1,024-byte resolved values, an 8,192-byte resolved payload and 16 KiB mapping JSON. No expressions, Liquid, ERB, Ruby accessors or Entity traversal are evaluated.

`unsubscribe_url` is a Rails-signed capability for customer/contact/frozen phone, valid for 365 days, generated using validated canonical URL configuration. GET/HEAD `/sms/unsubscribes/:token` only shows a masked number and confirmation; CSRF-protected POST appends an idempotent revocation and tenant suppression. If the contact changed phone, the link revokes the signed old phone without changing the new phone's consent. Preview URL generation has no writes/jobs. Invalid/expired links return localized 404. The approved remote marketing content must actually include a working opt-out mechanism, such as the mapped URL or provider reply instructions; the application does not append opt-out text or shorten the URL automatically.

The capability path is redacted **before log emission** by `config/initializers/sms_unsubscribe_path_filtering.rb`, which narrowly extends `ActionDispatch::Request#filtered_path`. Rails' `Started GET/HEAD/POST` request lines and controller instrumentation `:path` show `/sms/unsubscribes/[FILTERED]`, retaining a mount prefix and Rails-filtered query suffix when present. Matching uses Rails router normalization, covering trailing/repeated slashes and format suffixes. The actual URL, `PATH_INFO`, token path parameter and signature verification stay intact; neighboring SMS and other application paths retain normal logging. The existing `:token` parameter filter masks parameter payloads separately and does not itself redact a capability embedded in a URL path.

### Saved draft, review and two snapshot boundaries

`Sms::Campaigns::Save` may persist incomplete drafts: a missing template, variable mappings or scheduled time appears as a launch blocker. Submitted references/shapes and supplied settings must still be valid. `Preview` overlays inputs on an unsaved copy and performs read-only evaluation without vendor calls, quota reservations or enqueue. Only a persisted draft with no blockers and settings matching that saved draft can obtain a signed 15-minute review token. The draft detail page evaluates saved settings; unsaved form preview is not a launch of those edits.

`Launch.call(customer:, actor:, campaign:, lock_version:, review_token:, at: Time.current)` rechecks the version, settings/content/rule/type digests and credential identity under locks, then reruns current preview gates. Stale/expired review returns `review_changed` (HTTP 409). Enabled SMS, a configured account, valid active marketing content, complete mapping, a bounded positive eligible audience and a future scheduled instant are required. Local schedule parsing uses the campaign IANA zone and rejects nonexistent/ambiguous DST times.

Launch freezes settings, template/provider code/required variables/purpose/mirror, variable mappings, audience rules/referenced types and credential ID/mode. It records launch actor/time, sets an absolute deadline and status `scheduled`, including for immediate sends, then best-effort enqueues the scheduler after commit. Launched settings cannot be edited/relaunched; matching replay identifies the same launch. Credential identity is fixed, but retained secrets, sender configuration and account rate remain live infrastructure.

At first execution, `Run.snapshot_audience` evaluates frozen rules against current tenant contacts under the customer/campaign transaction. It reads batches of 100 and inserts the complete ledger (at most 10,000 matched rows), including contact snapshots, resolved variables and initial eligibility, atomically with `started_at`. Initially excluded rows are immediately skipped. This is the actual batched implementation, not an insert-select. Rollback removes the whole snapshot; recovery never expands committed membership or recomputes personalization. Contact changes before start can change membership; later changes can block sending but cannot replace the frozen destination/content. A later grant/restore does not add initially excluded contacts to the campaign.

### Scheduling, dispatch controls and cancellation

`Sms::Campaigns::SchedulerJob` runs every minute in production, scanning in batches of 100, assigning/reusing a 15-minute execution lease and repairing lost continuation or due-message handoff. `RunJob#perform(customer_id, campaign_id, run_token)` reestablishes `Current.customer`; `Run` checks/renews the live lease/token and processes at most 100 due pending recipients per call. See [Background jobs](background-jobs) for the separate five-minute core recovery and 15-minute receipt reconciliation.

Run samples fresh time after acquiring the customer/campaign locks, again after each recipient's contact/recipient locks, and before completion/stat updates. The effective time is the later of an explicitly supplied `at` and `Time.current`; invocation time cannot keep an expired lease alive after a lock wait. Every write phase validates the current token and lease before renewing a still-valid lease from that locked time. An expired or replaced lease cannot create the audience, admit another recipient, or finish/refresh the campaign.

Each recipient's eligibility, deadline, due time and rolling admission window use that fresh locked time, so admissions committed earlier in the same batch count toward the next recipient's 60-second ceiling. The internal `Gateway.send_campaign` accepts optional `at:` from Run and records a reservation using the later of that time and its current locked clock; ordinary callers omit it. Reservation time is captured before persistence, rather than sampled afterward, and an idempotent replay preserves the existing admission fact. Shared-account pacing remains a separate final-dispatch limit and does not substitute for the campaign's lower admission ceiling.

| Control | Actual rule |
| --- | --- |
| Intended start / deadline | Immediate start uses launch time; scheduled start uses the chosen UTC instant. `expires_at = intended_start + deadline_hours` (1–168, default 24). Delays never reset it. Expiry before the initial snapshot fails the campaign; after start it closes remaining unattempted work. |
| Quiet hours | Integer local hours 0–23, start inclusive/end exclusive and unequal; default 21–09. Use the current valid contact timezone, otherwise the frozen campaign zone (default `Asia/Shanghai`). Defer only while still before the deadline. |
| Campaign frequency | 1–168 hours, default 24. Another campaign's attempt for the same tenant phone, identified by `dispatch_started_at`, blocks the send, including unknown attempts. Direct transactional sends are not campaign-frequency facts; core phone quotas still apply. |
| Campaign admission | 1–60 recipients/minute, default 60, measured by rolling 60-second recipient `admitted_at` reservations. Skipped rows consume none. |
| Shared-account pacing | `Sms::DispatchLimiter` locks the retained credential and uses live `config["sender_rate_per_second"]` (`0 < rate <= 1`, default 1). `dispatch_next_at` serializes durable starts for all tenants/campaigns/direct sends using that row. It reserves only a due start, not future slot batches. |
| Tenant/phone quotas | Existing daily budget and adapter phone windows also apply. Campaigns may defer to a known reset; zero daily capacity skips. Delays reaching the deadline expire. |

The final dispatcher transaction checks current activity, exact phone, positive consent, opt-out, module, campaign cancellation/failure/deadline, quiet hours, frequency and due time before recording the sole attempt. Defer releases preparation without an attempt; recovery cannot bypass `delivery_due_at`. Locks order customer → campaign → contact → recipient → message → credential when those records are present, and commit precedes network I/O. Pacing limits durable dispatch authorization, not carrier deliveries per second. Preview duration uses the lower ceiling of campaign admission and account pacing; shared traffic and quiet hours can extend it.

`Cancel` is idempotent for scheduled/running/already-cancelled campaigns. It invalidates the run token, cancels pending recipients, and suppresses linked queued messages only when `dispatch_started_at` is absent. Message links and admission facts remain. Cancellation and dispatch start share serialization: if start wins, the attempt continues and later receipts can update it. There is no recall of a provider call, pause/resume or unknown-result resend action. Only unlaunched drafts can be deleted; launched campaigns/reports are retained.

### Ledger-derived report and CSV

`Sms::Campaigns::Report.call(customer:, campaign:, refresh: false)` derives results from recipients plus linked same-tenant messages. GET/CSV does not write stats or start execution; `RefreshStats` is the write-side rebuildable cache. Matched is recipient rows, eligible-at-start comes from contact snapshots, admitted means a message link, attempted means `dispatch_started_at`, and API-accepted means `sent_at`. Recipient `pending/admitted/skipped/cancelled` is orchestration state, distinct from message delivery state. Cancellation can leave a historical admission link.

Attempted/API-accepted counts are milestones; delivered/failed/unknown/queued/suppressed/expired are current outcomes. These overlap and must not be summed. Delivery rate is delivered ÷ attempted, unknown with no attempts. Terminal reason counts include skips and blocked/cancelled admitted rows; current deferral counts are separate. Positive provider segment facts are summed with a missing-count metric, not inferred from previews or used as a price quote.

The report supports recipient/message status, reason and name/phone filters. `Sms::CampaignReportCsv` streams all filtered rows in ID order in batches of 100, independent of page size, with localized headers, ISO 8601 times and formula-leading text escaped. It includes contact/destination, recipient/message state, attempt/acceptance/delivery/expiry, failure code and provider segments; variables, raw responses, evidence, signed tokens and credentials are omitted.

## Where to pay attention

:::attention
A phone, Entity entry, login account, segment match or absence of opt-out is not consent. Every new marketing-template send through the direct Gateway/HTTP/workflow path also requires an active same-tenant contact with granted current-phone consent and no suppression. `Sms::Errors::MarketingIneligible` is a `TemplateVarsInvalid` subclass (direct HTTP 422); dispatch rechecks the pinned marketing purpose/contact. Transactional templates retain core module/opt-out/quota semantics.
:::

:::attention
Preview and launch freeze different facts: review is a short-lived check of saved settings, launch freezes rules/content, and execution start freezes membership/contact/vars. Preview counts are not a guaranteed final recipient count. A missing referenced segment or invalid segment input never falls back to all contacts; malformed frozen rules fail before admission.
:::

:::note
`completed` means recipient dispatch orchestration is finished: admitted messages have crossed the attempt boundary or been suppressed/expired. `sent` is provider acceptance, not delivery. `unknown` is unresolved, not a retry instruction. Callbacks/queries can update reports after completion/cancellation; no path resends the attempted payload to resolve ambiguity. Application deadlines cannot recall a message already in a provider/carrier queue.
:::

## Key code

### Explicit sync and segment inputs

Illustrative values below are inputs, not seeded records or automatically granted permission:

```json
{
  "entity_id": 42,
  "phone_field": "mobile",
  "name_field": "full_name",
  "country_code": "CN",
  "timezone": "Asia/Shanghai",
  "attribute_map": { "city": "city", "vip": "vip" },
  "after_entry_id": 0,
  "through_entry_id": 2500
}
```

```json
{
  "type": "group",
  "joins": ["AND"],
  "conditions": [
    { "field": "country_code", "operator": "equals", "value": "CN" },
    { "field": "attributes.vip", "operator": "equals", "value": true }
  ]
}
```

### Field, literal and fallback mappings

Use the selected template's actual required keys (Twilio may use numeric keys); a variable-free template uses `{}`:

```json
{
  "name": { "source": "field", "field": "name", "fallback": "Customer" },
  "offer": { "source": "literal", "value": "20%" },
  "opt_out_url": { "source": "field", "field": "unsubscribe_url" }
}
```

### Trusted campaign admission and scheduler

`Sms::Gateway.send_campaign(customer:, recipient:, at: nil)` is an internal worker API returning `Sms::Message` with core SMS exception types, not `Sms::Result`. It reloads a persisted same-tenant running campaign/recipient, validates launch snapshots, start eligibility, destination and exact variables, rechecks live marketing policy, and pins campaign content/credential. It accepts no arbitrary snapshot or raw body and has no public HTTP endpoint. Stable identity `sms-campaign:<campaign_id>:recipient:<recipient_id>` repairs the same message link; message admission and linking share a transaction, with enqueue only after outermost commit.

```ruby
# app/services/sms/gateway.rb
def send_campaign(customer:, recipient:, at: nil)
  Sms::Activities::Send.call_campaign(customer: customer, recipient: recipient, at: at)
end
```

```yaml
# config/recurring.yml — production
sms_campaign_scheduler:
  class: "Sms::Campaigns::SchedulerJob"
  queue: default
  schedule: every minute
```
