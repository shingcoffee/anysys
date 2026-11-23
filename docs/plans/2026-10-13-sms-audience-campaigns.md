# SMS audiences and campaigns — frozen architecture and implementation plan

Date: 2026-10-13 · Status: **READY FOR PARALLEL IMPLEMENTATION — contract v1**

UX specification: [SMS campaigns UX](../superpowers/specs/2026-10-13-sms-campaigns-ux.md).

This is a proposed implementation contract, not a description of shipped behavior. The schema, class names, parameters, result shapes, controller assigns, and state meanings below are the shared interface for implementation owners. Changes to an interface require updating both design documents before dependent work proceeds.

## 1. Product goal and reference decisions

A tenant administrator manages SMS contacts, records positive marketing consent, selects a dynamic audience, personalizes a platform-approved marketing template, and follows **Audience → Content → Schedule → Review**. Saving creates or updates a draft. Launching is a separate action. Execution supports cancellation of remaining unattempted messages and a ledger-derived delivery report with CSV export.

Official references consulted on 2026-10-13:

| Reference | Observed pattern | Anysys decision |
| --- | --- | --- |
| [Twilio Messaging Services](https://www.twilio.com/docs/messaging/services) | Sender/configuration grouping, asynchronous status callbacks, validity periods, Advanced Opt-Out | Reuse the existing adapter, credential, receipt, expiry, and suppression foundation. Provider acceptance is distinct from delivery. |
| [Klaviyo SMS campaigns](https://help.klaviyo.com/hc/en-us/articles/360040039971) | A phone number is not consent; campaigns target lists/segments; personalized previews, Smart Sending, quiet hours, send now/schedule | Dedicated consented contacts; dynamic segments; explicit frequency window; recipient-local quiet hours; final review. |
| [Braze SMS campaign creation](https://www.braze.com/docs/user_guide/message_building_by_channel/sms/campaign/create/) | The supplied URL redirects to the current SMS/MMS/RCS creation guide; subscription filtering, personalization, scheduling, frequency controls, review and reporting | Separate audience membership from permission and dispatch eligibility; recheck permission immediately before an external attempt. |
| [Mailchimp marketing SMS](https://mailchimp.com/help/create-send-marketing-sms/) | Subscribed audiences, segmentation, merge fields/defaults, checklist, send duration, reports, cancellation of remaining queued messages | Cohesive campaign workspace, sample personalization, absolute finish deadline, and conditional cancellation. |

These references inform product interaction, not a requirement to reproduce their provider-specific features. The initial slice includes manual contacts, explicit Entity synchronization, dynamic segments, one-time campaigns, recipient unsubscribe, cancellation, and delivery reports. MMS/RCS, conversational inboxes, A/B tests, recurrence, click/conversion tracking, public opt-in acquisition, CSV contact import, and automatic re-consent are later slices.

## 2. Foundation and bounded reuse

The current workspace contains the SMS reliability enhancement described in [2026-10-13-sms-enhancement.md](2026-10-13-sms-enhancement.md). Implement against the current workspace files:

- `Sms::PhoneNumber.normalize(raw, country:)` wraps Phonelib and yields E.164; default country is `CN`.
- `Sms::Gateway.send` and `Sms::Activities::Send` admit a transactional outbox message, reserve tenant/phone quotas, and enqueue only after the outermost commit.
- `Sms::DeliveryDispatch`, `Sms::DeliverMessageJob`, recovery, credential pinning, `Sms::ReceiptInbox`, and `Sms::DeliveryProjection` already fence a sole external attempt and reconcile asynchronous receipts.
- `Sms::Template` and `Sms::Credential` are platform-wide. Templates contain remote provider codes and required variable names; remote message text is currently absent.
- `Sms::OptOut` contains global and tenant suppressions. STOP and Twilio `21610` can establish global suppression. START/HELP do not remove it.
- `Sms::SegmentCalculator` can estimate a fully rendered text sample, not text inferred from a remote code.
- Email audiences query `Authentication::User`; that audience model is not the SMS contact domain and users have no phone column. Reuse the grouped AST semantics and `Emails::Audience::SegmentBuilderComponent` with an SMS catalog, not the Email user relation.

Implement a small SMS-specific compiler in `Sms::Audience::SegmentQuery`, following Email's parameterized, fail-closed pattern. This slice does not require a generalized Email/compiler extraction. Use the existing generic builder with `preview: false`; its built-in preview action is Email-specific, so the SMS host form supplies a native POST preview button.

## 3. Frozen schema — exactly five new domain tables

All five tables have a standard primary key and `created_at`/`updated_at`, non-null. IDs use the repository's database reference type. JSON below means native Rails `json`, with object defaults `{}` unless specified. Times are stored in UTC. Every new table includes non-null `customer_id` and `TenantScoped`; references and services enforce the same tenant for all related tenant records.

### 3.1 `sms_contacts` — `Sms::Contact`

| Column | Type / null / default | Meaning |
| --- | --- | --- |
| `customer_id` | reference, required | URL-selected tenant |
| `phone_e164` | string, required | Canonical identity; unique per tenant, including archived contacts |
| `name` | string, optional | Display name, at most 200 UTF-8 bytes |
| `country_code` | string, required, `CN` | ISO 3166-1 alpha-2 normalization context; not inferred timezone |
| `timezone` | string, optional | Valid IANA zone; blank falls back to campaign timezone |
| `status` | string, required, `active` | `active` or `archived` |
| `consent_status` | string, required, `unknown` | Projection: `unknown`, `granted`, `revoked`; never directly writable through contact forms/sync |
| `consent_changed_at` | datetime, optional | Recorded time of the current-phone projection's last event |
| `custom_attributes` | json object, required, `{}` | At most 32 scalar attributes, at most 8 KiB serialized |
| `source_kind` | string, required, `manual` | `manual` or `entity` |
| `source_entity_id` | reference, optional | Explicit Entity provenance |
| `source_entry_id` | reference, optional | Explicit EntityEntry provenance |
| `source_mapping` | json object, required, `{}` | Last explicit mapping used for this source |
| `synced_at` | datetime, optional | Last successful explicit Entity sync |
| `lock_version` | integer, required, `0` | Optimistic edit concurrency |

Indexes: unique `(customer_id, phone_e164)`; `(customer_id, status, consent_status)`; partial unique `(customer_id, source_entity_id, source_entry_id)` where both source references are non-null. Source references can be nullified when their source is deleted; contact identity, consent evidence, and campaign history remain.

Custom keys match `[a-z][a-z0-9_]{0,63}`. Values are UTF-8 strings up to 1,024 bytes, finite numbers, booleans, or null; objects/arrays are rejected. A manual delete is an archive operation, not physical removal. Archive does not revoke consent or erase evidence; archived contacts are always ineligible. Explicit restore uses contact update with `status: active`.

### 3.2 `sms_consent_events` — `Sms::ConsentEvent`

| Column | Type / null / default | Meaning |
| --- | --- | --- |
| `customer_id` | reference, required | Contact's tenant |
| `contact_id` | reference to `sms_contacts`, required | Retained contact |
| `phone_e164` | string, required | Phone to which the evidence applies |
| `action` | string, required | `granted` or `revoked`; scope is SMS marketing |
| `source` | string, required | `admin`, `recipient_unsubscribe`, or `provider_opt_out` |
| `occurred_at` | datetime, required | Evidence occurrence time; must not be in the future |
| `actor_user_id` | reference to `users`, optional | Admin actor; nil for recipient/provider events |
| `evidence` | json object, required | Bounded audit evidence, at most 4 KiB |
| `event_key` | string, required | Server/form-generated deduplication identity, at most 128 bytes |

Indexes: unique `(customer_id, event_key)`; `(customer_id, contact_id, id)`; `(customer_id, phone_e164, id)`. No update/destroy route; application services prohibit editing/deleting evidence rows. The contact is retained, so deleting it cannot cascade away evidence.

Admin grant evidence requires `reference` and `statement`, each nonblank, at most 1,024 bytes. Optional `notes` is at most 1,024 bytes. Admin revoke requires `reference` and may include notes. Recipient/provider evidence is server-generated and cannot be submitted through the admin evidence form. Projection order is recorded insertion order (`id`), not a client-supplied historical `occurred_at`.

### 3.3 `sms_segments` — `Sms::Audience::Segment`

| Column | Type / null / default | Meaning |
| --- | --- | --- |
| `customer_id` | reference, required | Tenant scope |
| `name` | string, required | At most 200 bytes |
| `description` | text, optional | At most 2,048 bytes |
| `segment_rules` | json object, required, `{}` | Valid grouped AST; intentional empty root matches all tenant contacts |
| `lock_version` | integer, required, `0` | Concurrent edit guard |

Index: `(customer_id, name)`. Dynamic segments only; no membership/join table. Deletion is allowed only when no draft references it. A launched campaign retains frozen rules and may nullify its historical `segment_id` if the segment is deleted; it never falls back from a missing segment to all contacts.

### 3.4 `sms_campaigns` — `Sms::Campaign`

| Column | Type / null / default | Meaning |
| --- | --- | --- |
| `customer_id` | reference, required | Tenant scope |
| `name` | string, required | At most 200 bytes |
| `template_id` | reference to `sms_templates`, optional in incomplete draft | Active marketing template required at launch |
| `segment_id` | reference to `sms_segments`, optional | Nil explicitly means all contacts, subject to positive consent and eligibility |
| `variable_map` | json object, required, `{}` | Safe field/literal/fallback mappings |
| `send_timing` | string, required, `immediate` | `immediate` or `scheduled` |
| `scheduled_at` | datetime, optional | UTC instant parsed from scheduled local input plus campaign timezone |
| `timezone` | string, required, `Asia/Shanghai` | Schedule zone and recipient quiet-hours fallback |
| `quiet_hours_start` | integer, required, `21` | Local start hour, inclusive; range 0..23 |
| `quiet_hours_end` | integer, required, `9` | Local end hour, exclusive; range 0..23; cannot equal start |
| `frequency_window_hours` | integer, required, `24` | Range 1..168; one campaign attempt per tenant phone within this window |
| `send_rate_per_minute` | integer, required, `60` | Range 1..60; campaign admission ceiling |
| `deadline_hours` | integer, required, `24` | Range 1..168; TTL measured from frozen intended start |
| `status` | string, required, `draft` | `draft`, `scheduled`, `running`, `completed`, `cancelled`, `failed` |
| `created_by_id` | reference to `users`, required | Authenticated actor recorded by server |
| `launched_by_id` | reference to `users`, optional | Authenticated launch actor |
| `launched_at` | datetime, optional | Snapshot commit time |
| `started_at` | datetime, optional | Once-only execution/audience snapshot time |
| `expires_at` | datetime, optional | Absolute deadline: intended start + deadline hours |
| `finished_at` | datetime, optional | Orchestration terminal time, not necessarily final receipt time |
| `cancelled_at` | datetime, optional | Cancel transaction commit fact |
| `settings_snapshot` | json object, required, `{}` | Frozen content/settings/credential identity |
| `audience_snapshot` | json object, required, `{}` | Frozen segment name/rules and referenced custom field types |
| `stats` | json object, required, `{}` | Rebuildable ledger-derived report cache |
| `stats_refreshed_at` | datetime, optional | Cache freshness |
| `run_token` | string, optional | Fenced execution lease token |
| `run_lease_expires_at` | datetime, optional | 15-minute renewable campaign lease |
| `heartbeat_at` | datetime, optional | Last successful worker heartbeat |
| `failure_code` | string, optional | Stable orchestration failure code, translated at display time |
| `lock_version` | integer, required, `0` | Draft/launch optimistic concurrency |

Indexes: `(customer_id, status, created_at)`; `(status, scheduled_at)`; `(status, run_lease_expires_at)`; references. Draft removal is a physical delete and allowed only before launch with no recipients. Launched campaigns and reports are retained.

### 3.5 `sms_campaign_recipients` — `Sms::CampaignRecipient`

| Column | Type / null / default | Meaning |
| --- | --- | --- |
| `customer_id` | reference, required | Same tenant as campaign/contact/message |
| `campaign_id` | reference to `sms_campaigns`, required | Campaign ledger owner |
| `contact_id` | reference to `sms_contacts`, required | Retained audience member |
| `phone_e164` | string, required | Destination frozen at audience snapshot |
| `contact_snapshot` | json object, required | Frozen contact fields and start-time eligibility; exact keys below |
| `vars` | json object, required, `{}` | Once-resolved scalar variables, persisted before admission |
| `status` | string, required, `pending` | `pending`, `admitted`, `skipped`, `cancelled` |
| `skip_reason` | string, optional | Stable reason code; no translated text stored |
| `deferral_reason` | string, optional | Current `quiet_hours/campaign_rate/account_rate/daily_cap/phone_window` delay; cleared when resolved |
| `message_id` | reference to `sms_messages`, optional | The recipient's sole admitted core outbox row |
| `delivery_due_at` | datetime, optional | Next admission/dispatch eligibility time; not a fresh TTL |
| `admitted_at` | datetime, optional | Tenant admission rate ledger fact |
| `processed_at` | datetime, optional | Recipient orchestration terminal time |

Indexes: unique `(campaign_id, contact_id)`; unique `(campaign_id, phone_e164)`; partial unique `message_id` where non-null; `(campaign_id, status, delivery_due_at, id)`; `(customer_id, phone_e164, admitted_at)`.

`admitted` means linked to the core message, whose outcome can still be queued, attempted, suppressed, expired, failed, unknown, or delivered. Do not copy carrier status into the recipient status. A recipient terminal before admission has no message. A cancelled admitted recipient retains its message link and historical admission timestamp.

### 3.6 Additions to existing tables

| Table | Frozen addition | Rules |
| --- | --- | --- |
| `sms_templates` | `purpose` string, non-null, default `transactional` | Values `transactional`, `marketing`. Platform owner controls classification. Campaigns require `marketing`. |
| `sms_templates` | `body_template` text, nullable | Optional owner-maintained preview mirror of approved remote content; at most 4 KiB; simple `{{variable_name}}` substitutions only. |
| `sms_messages` | `campaign_id`, nullable FK to `sms_campaigns` | Trusted internal campaign admission only; indexed. |
| `sms_messages` | `contact_id`, nullable FK to `sms_contacts` | Optional typed contact association; indexed. |
| `sms_messages` | `delivery_due_at` datetime, nullable | Nil means immediately eligible; gates handoff, claim, recovery, and final start. Add `(status, dispatch_started_at, delivery_due_at)` index. |
| `sms_credentials` | `dispatch_next_at` datetime, nullable | Vendor-neutral mutable dispatch clock under credential-row lock; distinct from JSON configuration. |

No sixth dispatch-slot table. Generic account rate configuration is `Sms::Credential#config["sender_rate_per_second"]`, default `1.0`. For contract v1 accept finite numbers `0 < rate <= 1`; owner can lower the shared ceiling. It is common platform configuration, not an adapter-specific credential field. Runtime state goes exclusively in `dispatch_next_at`. No per-vendor columns or tenant credentials are introduced.

### 3.7 Frozen JSON snapshot keys

Snapshot objects store string keys, JSON scalar values, and ISO 8601 UTC times; never model instances, Ruby symbols, credential secrets, or translated display labels.

```text
settings_snapshot = {
  "schema_version": 1, "draft_lock_version": Integer,
  "name": String, "send_timing": "immediate"|"scheduled",
  "intended_start_at": ISO8601, "expires_at": ISO8601,
  "timezone": String, "quiet_hours_start": Integer, "quiet_hours_end": Integer,
  "frequency_window_hours": Integer, "send_rate_per_minute": Integer,
  "deadline_hours": Integer, "variable_map": Object,
  "provider": String, "credential_id": Integer, "credential_mode": String,
  "account_rate_per_second_at_launch": Number,
  "template": {"id": Integer, "key": String, "purpose": "marketing",
               "provider_code": String, "required_vars": [String],
               "body_template": String|null}
}
audience_snapshot = {
  "schema_version": 1, "kind": "all_contacts"|"segment",
  "segment_id": Integer|null, "segment_name": String|null,
  "segment_rules": Object,
  "field_specs": {"attributes.<key>": "string"|"float"|"boolean"}
}
contact_snapshot = {
  "name": String|null, "phone_e164": String, "country_code": String,
  "timezone": String|null, "custom_attributes": Object,
  "status": "active"|"archived", "consent_status": String,
  "consent_changed_at": ISO8601|null,
  "eligibility_at_start": {"eligible": Boolean, "reason": String|null}
}
```

`source_mapping` stores only `phone_field`, `name_field`, `country_code`, `timezone`, and `attribute_map`; batch cursors are request state. `stats` stores the report keys in section 6, serializing its times to ISO 8601. Existing message `metadata.template_snapshot` retains its foundation shape and adds `purpose`; trusted marketing admission also sets typed `contact_id`. Campaign admission copies its pinned template into that same core snapshot shape rather than inventing another payload format.

Provider account rate/configuration is live infrastructure read from the retained credential; the launch rate is only an audit/estimate fact. Credential identity is pinned, not a revision of its secrets or sender configuration, consistent with the existing foundation.

## 4. Contacts, consent, and Entity synchronization

### 4.1 Identity and consent invariants

1. Contact creation/sync defaults to `unknown`. Neither possession of a phone, a login account, Entity data, segment membership, nor absence of suppression implies consent.
2. Grant/revoke is a separate append-only event operation under the customer/contact lock. Grant applies only to that contact's current normalized phone and requires evidence. An event replay returns the original result; a reused event key with different content conflicts.
3. Changing `phone_e164` resets `consent_status` to `unknown` and `consent_changed_at` to nil, even when that phone appeared in an older event. Prior events remain evidence for the old phone; a fresh grant is required for the replacement. Unique phone conflicts are validation errors, never implicit merges.
4. Revoke appends evidence, updates the current-phone projection, and records a tenant `Sms::OptOut`. Recipient unsubscribe does the same for its signed destination. Grant never removes an existing local or global suppression; UI distinguishes consent from sendability.
5. Verified STOP/`21610` continues to record authoritative global suppression. A correlated existing contact may also receive a deduplicated `provider_opt_out` evidence event. Eligibility always reads `Sms::OptOut`; it does not depend on cross-tenant fan-out or a contact projection being immediately refreshed.
6. START/HELP remain non-consenting and never automatically unblock a number. The initial slice has no unblock action.
7. Every marketing admission, including a direct send of a marketing-classified template through the existing Gateway, requires a same-tenant active contact with current-phone `granted` consent. Transactional templates retain their foundation's admission semantics. All sends retain core suppression/module/quota gates.

### 4.2 Explicit manual Entity sync

Source: `Entity.accessible.active` under the URL tenant context, then only `EntityEntry.for_customer(customer.id)` for the chosen Entity. Shared definitions are permissible; another tenant's entries are not. Read the definition through `resolved_current_version` and its resolved schema. Contract v1 supports ordinary, non-bridge, non-extension Entities backed by `EntityEntry`; extending Authentication or other native models is a later source adapter.

Require an explicit `phone_field` whose resolved Entity value type is `tel`. The schema's actual value-type metadata is authoritative; do not infer telephone suitability from a field label or guess the first phone-like property. The server supplies valid `name_slug` choices and reads values through `entry.data_json[field_slug]`, not dynamic Ruby expressions.

Mapping input:

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

- `name_field` is optional; country/timezone are explicit batch inputs, not guesses from a country dial code. `attribute_map` is optional, curated scalar field mappings under the contact bounds.
- Preview calculates the first 100 entries after the cursor, reports invalid/missing phones and identity/source conflicts, and supplies the initial high-water `through_entry_id`. It writes nothing.
- Execute processes at most 100 entries per POST in ascending entry ID. The form carries the mapping, `after_entry_id`, and high-water bound for explicit continuation. Revalidate scope/schema/mapping on every POST. No persistent source/configuration table or automatic background polling is required.
- Upsert by source identity first, otherwise canonical tenant phone. Attach an unlinked same-phone contact to the source; an existing different source is a reported conflict. Never merge contacts or overwrite a distinct source link.
- A linked source's changed phone uses the contact phone-change rule and resets consent. A same-phone update preserves the consent projection. Replace only the mapped custom keys; retain unmapped keys. Contact status is preserved, so sync never restores an archived contact.
- Batch-level malformed/inaccessible input fails before writes. Valid batches report per-entry failures and continue; unique races become item conflicts. Idempotent replay of a batch does not create consent or duplicate contacts.
- Source deletion, missing entries, and later schema changes do not silently delete contacts. Synchronization is a deliberate data operation; it never grants consent.

## 5. Dynamic audience and personalization contracts

### 5.1 Segment rules

Canonical AST matches the shared builder's grouped protocol:

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

Joins combine left-associatively: `[A, B, C]` with `[AND, OR]` means `((A AND B) OR C)`. Nested groups have independent joins. An intentional empty root `{}` or `{type: group, conditions: [], joins: []}` selects all tenant contacts. Empty nested groups, unknown keys/fields/operators, wrong join counts, malformed JSON, invalid scalar casts, and exhausted budgets invalidate the entire tree.

Frozen limits: 32 KiB rules JSON, depth 8, at most 100 nodes including groups, scalar value strings at most 1,024 bytes. Save/preview rejects invalid trees with `422`; execution of invalid stored/frozen rules fails closed with no recipients, never all contacts.

Curated fields: `name`, `phone_e164`, `country_code`, `timezone`, `status`, `consent_status`, `source_kind`, `created_at`, `updated_at`, and `attributes.<key>`. Exclude customer/credential IDs, arbitrary associations, SQL paths, and Ruby accessors. Custom field catalog exposes at most 128 sorted valid keys seen in this tenant, only when non-null values have a consistent scalar type; integer/float share numeric type. Mixed-type attributes are not queryable. Freeze the referenced custom field types at launch; SQL checks JSON scalar type before comparing and treats missing/wrong-type values as nonmatches.

Operators: string `equals/not_equals/contains/not_contains/is_blank/is_present`; number `equals/not_equals/greater_than/less_than/is_blank/is_present`; boolean `equals/not_equals`; datetime `after/before/is_blank/is_present`. Parse full ISO 8601 datetimes with an explicit offset. For presence operators the builder's empty string value is ignored. String matching uses escaped LIKE values; user values and JSON keys are quoted/bound through adapter-aware Arel. No raw SQL or JSON path comes from a request.

Catalog `type` values use the existing builder vocabulary: `:string`, `:float` for all custom numeric scalars, `:boolean`, and `:datetime`. Boolean comparison accepts JSON booleans or the builder's exact strings `true`/`false`; arbitrary truthy text is invalid. Frozen `field_specs` is used for custom-field resolution during start, even if the live catalog has changed; wrong-type contact values remain nonmatches.

Segment membership includes contacts of any status/consent. Preview/report shows **matched** separately from **eligible**; the campaign eligibility intersection is mandatory.

### 5.2 Variable maps

Canonical stored `variable_map` is an object whose keys exactly match the selected template's `required_vars` at launch:

```json
{
  "name": { "source": "field", "field": "name", "fallback": "Customer" },
  "offer": { "source": "literal", "value": "20%" },
  "opt_out_url": { "source": "field", "field": "unsubscribe_url" }
}
```

- Field mappings allow only `source`, `field`, optional `fallback`. Fields are `name`, `phone_e164`, `country_code`, `timezone`, permitted `attributes.<key>`, and the server-generated personalization-only `unsubscribe_url`.
- Literal mappings allow only `source` and `value`. Values/fallbacks are nonblank strings or finite numbers and must satisfy `Sms::SendStandards`; mapped scalar booleans become strings `true`/`false`. Null, missing, or blank field values use fallback; without it that recipient is `personalization_missing`. No implicit human-name fallback exists.
- Map bounds match foundation limits: at most 64 variables, 128 bytes per key, 1,024 bytes per resolved value, 8,192 bytes for a resolved variables payload. Raw mapping JSON is at most 16 KiB. Unknown mapping keys/sources are errors.
- No ERB, interpolation expressions, Liquid programs, `eval`, `send`, arbitrary Ruby, or Entity traversal. Body preview substitutes already-resolved scalar variables into the owner's simple mirror, escaping when rendering HTML.
- `body_template` is optional and preview-only. It is not sent as a raw body or substituted for approved remote content. Present mirrors must contain valid simple placeholders from required variables; owner verifies the actual vendor-approved content and its opt-out mechanism. Missing mirror produces variable-only preview and unknown segment estimate.
- `unsubscribe_url` is a pure server-generated signed URL for this tenant/contact/phone; generating it in preview does not create evidence, recipients, messages, or jobs. Marketing remote content must contain a real opt-out route, whether the mapped URL or supported provider reply instructions. Do not append text to an approved remote template behind the owner's back.

## 6. Frozen application APIs and result shapes

Services use Reform contracts and thin Trailblazer-style orchestration consistent with the project. Contact/consent/sync, segment save/preview, campaign save/preview/launch/cancel/report/stats, and unsubscribe APIs return **`Sms::Result`**, with `success?`, `value`, `errors`, and `code`. `errors` is a hash of field symbols to arrays of translated messages; `code` is a stable symbol or nil. The catalog and compiler explicitly return the catalog/relation/boolean shown below; worker/core APIs have their own stated return shapes. Infrastructure failures propagate for job recovery rather than masquerading as validation errors.

| API | Inputs | Success `value` |
| --- | --- | --- |
| `Sms::Contacts::Save.call` | `customer:, actor:, contact: nil, attributes:` | `Sms::Contact` |
| `Sms::Contacts::Archive.call` | `customer:, actor:, contact:, lock_version:` | `Sms::Contact` |
| `Sms::Contacts::RecordConsent.call` | `customer:, actor:, contact:, attributes:` | `{contact:, event:, replayed:}` |
| `Sms::Contacts::SyncEntity.call` | `customer:, actor:, attributes:, preview: false` | Sync hash below |
| `Sms::Audience::FieldCatalog.new` | `customer:` | `#fields`, `#resolve(identifier)`; entries `{field:, label:, type:, operators:}` |
| `Sms::Audience::SegmentQuery.call` | `customer:, rules:, field_specs: nil` | Tenant-scoped `Sms::Contact` relation; invalid rules return `.none` |
| `Sms::Audience::SegmentQuery.valid?` | `customer:, rules:, field_specs: nil` | Boolean, SQL-free shape checks plus tenant catalog validation |
| `Sms::Audience::SaveSegment.call` | `customer:, actor:, segment: nil, attributes:` | `Sms::Audience::Segment` |
| `Sms::Audience::Preview.call` | `customer:, rules:, at: Time.current` | Audience hash below |
| `Sms::Campaigns::Save.call` | `customer:, actor:, campaign: nil, attributes:` | `Sms::Campaign` draft |
| `Sms::Campaigns::Preview.call` | `customer:, actor:, campaign:, attributes: {}, contact_id: nil, at: Time.current` | Campaign preview hash below; no writes or enqueue |
| `Sms::Campaigns::Launch.call` | `customer:, actor:, campaign:, lock_version:, review_token:, at: Time.current` | `Sms::Campaign` |
| `Sms::Campaigns::Cancel.call` | `customer:, actor:, campaign:, at: Time.current` | `Sms::Campaign` |
| `Sms::Campaigns::Report.call` | `customer:, campaign:, refresh: false` | Report hash below; GET paths use `refresh: false` |
| `Sms::Campaigns::RefreshStats.call` | `customer:, campaign:, at: Time.current` | Persisted report hash; jobs/write operations only |
| `Sms::Campaigns::Unsubscribe.preview` | `token:, at: Time.current` | `Sms::Result` containing `{masked_phone:, already_unsubscribed:}`; read-only |
| `Sms::Campaigns::Unsubscribe.call` | `token:, at: Time.current` | `Sms::Result` containing `{already_unsubscribed:}`; idempotent POST write |

`Save` attributes are canonical hashes, not raw request parameters. HTTP adapters parse bounded `custom_attributes_json`, `segment_rules_json`, `variable_map_json`, and `attribute_map_json` once, then validate the parsed type. They retain the original text for validation rerender. Invalid JSON never becomes `{}`. Duplicate JSON object keys are rejected, especially in variable maps.

Canonical service attributes retain section 9's permitted names except JSON-text inputs become `custom_attributes`, `segment_rules`, `variable_map`, or `attribute_map` objects, and campaign `scheduled_local` is parsed to `scheduled_at`. Contact `phone` remains raw input to `Contacts::Save`, which normalizes with `country_code`; the actor/customer/source and all protected columns remain server-derived. Preview/Save receive the same canonical campaign attributes. `RecordConsent`'s admin entry receives the permitted evidence fields and fixes `source: admin`; unsubscribe/provider paths use the internal evidence writer, never a client-writable source field.

Sync result:

```text
{ preview: Boolean, scanned: Integer, created: Integer, updated: Integer,
  unchanged: Integer, invalid: Integer, conflicts: Integer,
  items: [{entry_id:, contact_id: Integer|nil, outcome:, error_code: Symbol|nil}],
  next_after_entry_id: Integer|nil, through_entry_id: Integer, has_more: Boolean }
```

Audience result: `{matched_count:, eligible_count:, excluded_counts:, samples:, evaluated_at:}`. `samples` is an array of at most five hashes `{contact_id:, name:, phone_e164:, consent_status:, eligible:, reason: Symbol|nil}`. Every count is an integer; timestamps are `Time` internally and ISO 8601 in JSON.

Campaign preview:

```text
{ matched_count:, eligible_count:, excluded_counts:, deferred_counts:,
  samples: [{contact_id:, name:, phone_e164:, vars:, rendered_body: String|nil,
             encoding: Symbol|nil, units: Integer|nil, segments: Integer|nil,
             eligible:, reason: Symbol|nil}],
  intended_start_at:, expires_at:, earliest_dispatch_at: Time|nil,
  account_rate_per_second:, effective_rate_per_minute:,
  estimated_minimum_duration_seconds: Integer|nil,
  blockers: [Symbol], evaluated_at:, review_token: String|nil }
```

Report:

```text
{ matched_count:, eligible_at_start_count:, pending_count:, admitted_count:,
  attempted_count:, api_accepted_count:, delivered_count:, failed_count:,
  unknown_count:, queued_count:, suppressed_count:, expired_count:,
  skipped_count:, cancelled_count:, skip_counts: Hash<String,Integer>,
  deferred_counts: Hash<String,Integer>, provider_segments_total: Integer,
  provider_segments_missing_count: Integer, delivery_rate: Float|nil,
  snapshot_at: Time|nil, refreshed_at: Time|nil }
```

Counts overlap by design: attempted/API-accepted are historical milestones; delivery outcomes are current message states. `delivery_rate = delivered_count / attempted_count`, nil with zero attempts. Provider segments sum only positive recorded facts, with a missing-data count, never a billing quote. Preview exclusions have one precedence-based primary reason so `matched = eligible + excluded`; deferred contacts remain eligible.

Report derivation is fixed: matched = recipient rows; eligible at start = `contact_snapshot.eligibility_at_start.eligible`; pending/skipped/cancelled = each corresponding recipient status; admitted = any non-null message link, including a later cancelled recipient; attempted = linked message with `dispatch_started_at`; API accepted = linked message with `sent_at`. Delivered/failed/unknown/queued/suppressed/expired = current linked message statuses. `skip_counts` groups all non-null terminal `skip_reason` facts, including blocked admitted rows and cancellation reasons; `deferred_counts` groups non-null current `deferral_reason` on still-pending or unattempted-admitted rows. These separate fields prevent delay counts from appearing as permanent skips. When the core dispatcher suppresses/expires a campaign message, it also records the terminal reason and `processed_at` on its recipient under the same write transaction.

Audience-only eligibility checks activity, consent, and suppression. Campaign eligibility additionally checks mapping resolution and campaign frequency; quiet hours/rates are deferrals. A specifically selected sample outside the segment uses sample-only reason `outside_audience` and never alters counts. Include that selected sample within the five-sample bound. The lower-bound duration uses `min(send_rate_per_minute, account_rate_per_second * 60)`; shared traffic and quiet hours can make actual dispatch take longer.

Primary reason precedence: `contact_archived`, `phone_changed`, `consent_missing`, `opted_out`, `personalization_missing`, `frequency_capped`, `campaign_cancelled`, `campaign_failed`, `campaign_expired`, `module_disabled`. Operational admission failures may additionally use `template_invalid`, `credentials_missing`, `daily_cap_exceeded`, `rate_limited`. Deferral reasons: `quiet_hours`, `campaign_rate`, `account_rate`, `daily_cap`, `phone_window`. Values are stable codes translated at rendering time; defer beyond the deadline becomes `campaign_expired`. Expiry, cancellation, and failed-campaign gates still dominate any allow/defer outcome; precedence selects presentation only.

### 6.1 Worker/core boundary — one sending path

| Frozen interface | Contract |
| --- | --- |
| `Sms::Gateway.send_campaign(customer:, recipient:)` | Trusted internal entry; returns `Sms::Message` with the foundation's error types. Validates persisted campaign/recipient ownership, immutable launch snapshot, exact vars, and current marketing eligibility. No arbitrary caller-supplied snapshot or HTTP exposure. |
| `Sms::Campaigns::Run.call(customer:, campaign:, run_token:, at: Time.current, limit: 100)` | Processes at most 100 recipient rows per invocation; validates live lease/token on every write; returns `{processed_count:, has_more:, next_run_at:}`. |
| `Sms::Campaigns::DeliveryPolicy.call(message:, at: Time.current)` | SQL/read-only decision `{action:, due_at:, reason:}`; action is `:allow`, `:defer`, `:suppress`, or `:expire`; due_at is Time/nil and reason Symbol/nil. Applied by the core dispatcher under its final-start lock transaction. |
| `Sms::DispatchLimiter.acquire(credential:, message:, claim_token:, at:)` | Internal final-start operation under locked credential; returns `{action:, due_at:, reason:, attempt_started_at:}`; action is `:started`, `:defer`, `:lost_claim`, `:suppress`, or `:expire`; due_at/attempt_started_at are Time/nil and reason Symbol/nil. No vendor call, sleep, or future-slot prebooking. |

`send_campaign` shares the existing core admission/quota/persistence/handoff implementation. It uses the campaign's launch-pinned provider code, required variables, credential ID/mode, and purpose; later edits/retirement cannot replace admitted campaign content. It does not require the live template to remain active for every recipient. Snapshot validation and marketing dispatch eligibility cannot be bypassed by calling a lower-level persistence helper.

`DeliveryPolicy` also applies current activity/phone/consent checks to direct marketing messages with pinned `purpose: marketing` and `contact_id`, even when `campaign_id` is nil. Campaign-specific quiet/frequency/cancel/deadline settings only apply with a campaign link. Transactional messages still pass the foundation gates and shared account limiter.

Core message idempotency key: `sms-campaign:<campaign_id>:recipient:<recipient_id>`. Campaign/contact association participates in campaign admission identity. Transactionally admit the message and link `recipient.message_id`; outer rollback removes both and prevents enqueue. On a crash/race, the stable key repairs the same link. Never admit a second message for an existing recipient.

## 7. Launch, snapshot, scheduling, dispatch, and cancellation

### 7.1 Draft and review

Draft saves validate field bounds, valid selected references, JSON shapes, supplied mappings, and supplied schedule fields. They may be incomplete: missing template, missing variable keys, or missing scheduled time are review blockers, not obstacles to saving partial work. A selected template must be active and marketing; an invalid selected segment is never treated as nil.

Preview overlays submitted attributes on a separate unsaved draft instance and uses read-only queries. It invokes neither Gateway nor vendor APIs, persists nothing, reserves no quota, and enqueues no jobs. Bound previews to 10,000 matched contacts, streaming read batches of 100; above the bound return `audience_too_large` and require narrowing the segment. This same audience bound applies at launch and execution start.

For a persisted draft, the review token is a Rails signed, 15-minute token binding customer/campaign IDs, draft `lock_version`, canonical draft digest, segment rule/type digest, template/selected provider content digest, and resolved credential identity. Unsaved edits can render a preview but cannot yield a launch token for the persisted draft. Tokens are stateless, not evidence or audience snapshots. Launch recomputes the digest under locks; stale review returns `409 review_changed`. Audience counts can still change; the review explicitly explains start-time membership.

Launch requires complete valid settings, same-tenant segment, enabled SMS, active marketing template, exact mapping keys, valid provider mapping, configured credential, positive currently eligible audience, and the bounded audience size. Schedules must be future instants. Parse `scheduled_local` in the supplied IANA zone; reject DST gaps/ambiguous wall times rather than silently choosing one. Immediate launch sets intended start to launch time. Store intended start in `settings_snapshot.intended_start_at`.

Launch atomically pins settings/content/audience-rule/credential identity, sets `launched_at`/actor, computes absolute `expires_at`, and changes draft to `scheduled`. After commit, best-effort enqueue accelerates due campaigns. Repeated launch of an already-launched campaign is a same-row no-op when the supplied version matches `settings_snapshot.draft_lock_version` and the signed review identifies that same launch; it never compares against a version advanced by worker bookkeeping. Differing edits or a cancelled campaign conflict. Settings cannot be edited or relaunched after launch.

### 7.2 Snapshot once at execution start

`Sms::Campaigns::SchedulerJob` scans every minute, claims due `scheduled` campaigns and stale `running` campaigns with a random token and 15-minute lease. It also accelerates due pending work and due queued messages for a running campaign with its still-valid current token, repairing a lost continuation enqueue without waiting 15 minutes. Rotate only expired leases; duplicate current-token jobs remain harmless through locked recipient checks and stable message keys. `Sms::Campaigns::RunJob#perform(customer_id, campaign_id, run_token)` invokes Run; heartbeat renews the lease before each bounded batch. Jobs reestablish `Current` tenant context; the token fences every campaign/recipient write. Scheduler scans are themselves batched at 100 rows, with queue `default`.

For the first execution only, acquire the customer/campaign lock, verify the token/cancellation/deadline, reevaluate **frozen rules** against **current tenant contact data**, and create the complete recipient ledger plus `started_at` in one atomic transaction. Use a bounded database snapshot/insert-select (at most 10,000 matched rows), not a Ruby all-contact load. Copy personalization/contact input columns and persist `eligibility_at_start`. All matched contacts, including currently excluded ones, get an auditable recipient row; initial exclusions are immediately `skipped` with their primary reason and `processed_at`. Only initially eligible rows begin `pending`; a later grant/restore cannot expand that campaign's sending audience. Store the start counts in `stats`; they can be rebuilt from these frozen ledger facts. This bounded bulk snapshot is distinct from subsequent Run batches, which each process at most 100 recipients.

If the transaction rolls back, `started_at` and all recipient rows roll back together. If it commits, recovery never reevaluates membership or adds contacts. This avoids a half-built audience changing between continuation jobs. Segment changes after launch cannot change rules; contact changes before start may change membership; changes after start may only reduce sendability, not change destinations or personalized content.

If intended start + TTL has passed before the campaign starts, set `failed`, `failure_code: campaign_expired`, and `finished_at` without snapshot/sending. Crossing the audience bound or invalid frozen rules fails the campaign before any admission. Other permanent orchestration errors set `failed` with an explicit reason and close remaining unattempted work using `campaign_failed`, under the same conditional boundary as cancellation. Transient database/enqueue failures remain recoverable by lease/scheduler. A deadline reached after snapshot marks remaining pending recipients skipped with `campaign_expired` and conditionally expires linked unattempted messages; once that work is closed, the campaign completes with the expiry counts retained.

### 7.3 Bounded admission and final dispatch

Run processes at most 100 pending rows. Resolve vars from `contact_snapshot` exactly once, including signed unsubscribe URL; pin resolved vars before admission. Current contact status, current phone matching snapshot phone, consent, suppression, cancellation, deadline, module, and frequency are checked before admission.

- Campaign admission rate is a rolling 60-second ceiling using recipient `admitted_at`, serialized by customer/campaign locks. `send_rate_per_minute` is 1..60; at capacity defer until the oldest reservation leaves the window. Skipped rows do not consume this allowance.
- Quiet hours use current valid contact timezone, or frozen campaign timezone. Start inclusive/end exclusive; overnight and same-day intervals work. Delay to the next permitted local instant, handling timezone transitions with the timezone library. Quiet hours are not a fresh TTL.
- Frequency cap counts another campaign's `Sms::Message.dispatch_started_at` for the same tenant E.164 phone within `frequency_window_hours`, including unresolved attempts. It excludes this recipient's own message and never substitutes API acceptance/delivery time. Serialize dispatch-start checks under the tenant lock so concurrent campaigns cannot both pass. Foundation per-phone and daily admission quotas also apply.
- Foundation rate/day capacity may defer only to a determinable next window. Missing credentials or invalid pinned mappings are explicit failures; daily cap zero skips with `daily_cap_exceeded`. Every deferral is bounded by the campaign deadline.

The final start transaction in the existing dispatcher rechecks core expiry/module/opt-out plus `Sms::Campaigns::DeliveryPolicy`: current contact activity/phone/consent, campaign cancelled/failed/deadline, quiet hours, frequency, and `delivery_due_at`. Contact and cancellation checks are synchronized with writers. Update current recipient `deferral_reason` with due-time changes and clear it when a delay resolves; terminal blocks set `skip_reason` without discarding the message link. No queued row can bypass this by recovery or an early enqueue.

Account-wide pacing is independent of campaign admission: under the **retained credential row lock**, compare `dispatch_next_at` with current database time. If it is in the future, update `delivery_due_at`, release preparation, and enqueue a best-effort job for that time. Otherwise atomically persist the existing fenced `dispatch_started_at` marker and advance `dispatch_next_at = now + 1/rate`. Reserve only a due start, never a batch of future slots. Apply to campaign and direct transactional sends using the same credential, across all tenants. Skipped/deferred/lost-claim rows do not advance it.

Lock order for new paths: **customer → campaign (when present) → contact (when present) → recipient (when present) → message → credential**. All paths that combine these records follow that order. Commit before calling the adapter; never hold a database transaction across network I/O. The clock limits durable dispatch authorizations; worker/network stalls and provider/carrier queues mean it is not a carrier-delivery-per-second guarantee.

Message handoff, preparation claim, core recovery, and one-minute campaign recovery select only due messages (nil or `delivery_due_at <= now`). Future due times receive `wait_until` job acceleration, with database recovery as authority. A claim is released on defer without marking an attempt; TTL and the sole-attempt invariant are preserved. After `dispatch_started_at`, foundation outcome handling applies, including unknown quarantine and no resend.

### 7.4 Cancellation and completion

Cancel is idempotent for `scheduled`, `running`, and already `cancelled`. A draft uses draft deletion; a `completed`/`failed` campaign cannot be cancelled. Under the customer/campaign lock, set `cancelled_at`, invalidate the run token, mark pending recipients cancelled, and conditionally suppress linked queued messages **only where `dispatch_started_at IS NULL`**. Set their recipient state `cancelled` and reason `campaign_cancelled`. Already attempted recipients remain admitted; callbacks/queries still update their message/report.

Dispatch start uses the same customer/campaign serialization, so either cancellation wins and blocks the start, or the sole dispatch marker wins and cancellation cannot recall that attempt. A successful provider call has no cancellation API in this slice. UI reports the number cancelled and the attempts that continue to resolve.

`completed` means all recipient orchestration has finished and every admitted message has either crossed the sole-attempt boundary or become suppressed/expired. Unresolved provider delivery can remain `sent`/`unknown` and arrive later. Refresh stats on admission/cancellation and via scheduler/receipt-triggered best-effort refresh; reports can always rebuild from recipients plus messages. No retry/resend button for unknown outcomes.

## 8. Recipient unsubscribe

Public routes: `GET /sms/unsubscribes/:token` and `POST /sms/unsubscribes/:token`, controller `Sms::UnsubscribesController`, helpers `sms_unsubscribe_path(token)` for both verbs.

Use Rails signed token/verifier facilities, scope `sms_marketing_unsubscribe`, carrying contact ID, customer ID, and the frozen E.164 phone, expiring after 365 days. Validate signature/purpose/expiry and contact tenant before reading or writing; do not select a tenant from an unsigned query parameter. Filter token parameters and redact the capability path segment through Rails `Request#filtered_path` before request-start logging and controller instrumentation, without changing the routed URL or token. GET/HEAD only render masked phone and a confirmation form, with no writes, jobs, opt-outs, or consent events; link scanners cannot unsubscribe.

POST has the public browser form's CSRF protection and performs an idempotent revocation using a deterministic token-derived event key. Record a tenant suppression for the signed phone. If the contact has since changed phone, retain the evidence for the old phone without revoking consent for its different current phone. An archived contact can still revoke. Replay succeeds without duplicate evidence. Invalid/expired tokens render a localized `404` page. This capability grants no other contact access or opt-in action.

## 9. HTTP, routes, parameters, and frontend assigns — frozen

All admin paths begin `/:cid/admin/modules/sms`; Rails currently exposes the URL parameter as `customer_id`, so helper calls use `current_customer_id`. Controllers are under `Admin::Modules::Sms` and explicitly guard admin/owner access and SMS enablement. Every tenant lookup uses the URL-derived customer, including owner cross-tenant browsing. All creation IDs/actors/status/snapshots/stats/leases are server-derived. New route grants/navigation entries must follow the existing module registration/access-point conventions; no new role.

### 9.1 Route contract

| HTTP / suffix | Controller action | Helper name prefix `admin_modules_sms_` |
| --- | --- | --- |
| GET/POST `/contacts`; GET `/contacts/new`; GET `/contacts/:id`; GET `/contacts/:id/edit`; PATCH `/contacts/:id`; DELETE `/contacts/:id` | `ContactsController` standard CRUD; delete archives | `contacts`, `new_contact`, `contact`, `edit_contact` |
| POST `/contacts/:contact_id/consent_events` | `ConsentEventsController#create` | `contact_consent_events` |
| GET `/contacts/entity_sync/new`; POST `/contacts/entity_sync/preview`; POST `/contacts/entity_sync` | `EntitySyncsController#new/#preview/#create` | `new_contacts_entity_sync`, `preview_contacts_entity_sync`, `contacts_entity_sync` |
| Standard CRUD `/segments`, with new/edit/show | `SegmentsController` | `segments`, `segment`, `new_segment`, `edit_segment` |
| POST `/segments/preview`; POST `/segments/:id/preview` | `SegmentsController#preview`; member preview retains the tenant-scoped record identity and submitted edit version | `preview_segments`, `preview_segment` |
| Standard CRUD `/campaigns`, with new/edit/show; destroy draft only | `CampaignsController` | `campaigns`, `campaign`, `new_campaign`, `edit_campaign` |
| POST `/campaigns/preview`; POST `/campaigns/:id/preview` | `CampaignsController#preview` | `preview_campaigns`, `preview_campaign` |
| POST `/campaigns/:id/launch` | `CampaignLaunchesController#create` | `launch_campaign` |
| POST `/campaigns/:id/cancel` | `CampaignCancellationsController#create` | `cancel_campaign` |
| GET `/campaigns/:campaign_id/report`; GET same `.csv` | `CampaignReportsController#show` | `campaign_report` |

Declare collection/static contact routes before `/:id`. Existing `/messages`, `/opt_outs`, and POST `/sends` remain foundation entry surfaces. Standard helper suffixes include `_path`; every admin helper takes customer ID first.

Successful HTML save/action responds `303` to the record show page. Validation rerenders the same form with `422` and all assigns/picker lists. Stale edit/review/non-draft mutation returns `409` with a localized explanation. Inaccessible IDs and disabled module return `404`; unauthenticated/forbidden requests follow the project's existing authorization response. Side-effect-free previews return `200` HTML; malformed input `422`. JSON responses use `{data: ...}` or `{error: {code:, errors: ...}}`; create `201`, update/action `200`, queued launch `202`. Preview responses are never interpreted as admission.

### 9.2 Form root and permitted inputs

| Root | Permitted inputs |
| --- | --- |
| `sms_contact` | `phone` (raw input, normalized to `phone_e164`), `name`, `country_code`, `timezone`, `status`, `custom_attributes_json`, `lock_version` |
| `sms_consent_event` | `action`, `occurred_at`, `reference`, `statement`, `notes`, `event_key`; server sets source/actor/contact/phone/customer |
| `sms_entity_sync` | `entity_id`, `phone_field`, `name_field`, `country_code`, `timezone`, `attribute_map_json`, `after_entry_id`, `through_entry_id` |
| `sms_segment` | `name`, `description`, `segment_rules_json`, `lock_version` |
| `sms_campaign` | `name`, `template_id`, `segment_id`, `variable_map_json`, `send_timing`, `scheduled_local`, `timezone`, `quiet_hours_start`, `quiet_hours_end`, `frequency_window_hours`, `send_rate_per_minute`, `deadline_hours`, `lock_version` |
| Campaign preview extras | Root-level `preview_contact_id` only; same-tenant selectable contact |
| Launch | Root-level `lock_version`, `review_token` only; launch always reads the saved draft |
| Cancel / archive | Cancel has no editable settings; archive uses root-level `lock_version` |

Empty optional IDs normalize to nil; supplied malformed/foreign IDs fail, never become nil. `scheduled_local` is a virtual input (`YYYY-MM-DDTHH:mm`); `scheduled_at` is not client-writable. Numeric inputs use strict integer parsing. Unknown/domain-protected inputs are rejected. Request payload bound for new forms/previews is 64 KiB before JSON parsing. Controllers never forward provider/mode, credential identity, raw text, consent projection, status transitions, or arbitrary source snapshots from clients.

Native-form transport clarification: `authenticity_token`, `_method`, `locale`, and submit-button `commit` are framework metadata, never canonical service attributes. The shared campaign form also submits its root-level `preview_contact_id` selector on Save; validate the same-tenant ID, retain it for form rendering, and exclude it from draft persistence. It affects samples only on Preview. Rails automatic JSON parameter wrapping is disabled for these strict form roots.

### 9.3 Controller/frontend assign hashes

Every new index: **`{records: @records, columns: @columns, pagination: @pagination, filters: @filters}`**. `@records` is the current page array, not a relation to enumerate in a view. Pagination is `{page:, per_page:, total:, total_pages:}`, default 25, max 100. Filters are the accepted query hash. Components pass `records` as `rows:` to existing `AdminTableComponent`.

| Surface / render | Required assigns and component input hash |
| --- | --- |
| Contacts new/edit/422 | `{contact: @contact, form_values: @form_values, errors: @errors}` |
| Contact show | `{contact: @contact, consent_events: @consent_events, eligibility: @eligibility, consent_form_values: @consent_form_values, errors: @errors}`; consent_events `{records:, pagination:}` with default 25/max 100; eligibility `{eligible:, reason:}` |
| Entity sync new/preview/create result | `{form_values: @form_values, entities: @entities, source_fields: @source_fields, sync_result: @sync_result, errors: @errors}` |
| Segment new/edit/422 | `{segment: @segment, catalog: @catalog, form_values: @form_values, preview: @preview, errors: @errors}` |
| Segment show | `{segment: @segment, preview: @preview}`; read-only audience result |
| Campaign new/edit/preview/422 | **`{campaign: @campaign, templates: @templates, segments: @segments, contacts: @contacts, form_values: @form_values, preview: @preview, errors: @errors}`** |
| Campaign show/review/action error | `{campaign: @campaign, templates: @templates, segments: @segments, contacts: @contacts, preview: @preview, report: @report, errors: @errors}` |
| Campaign report | `{campaign: @campaign, report: @report, records: @records, columns: @columns, pagination: @pagination, filters: @filters}`; records are recipient rows preloaded with message/contact |
| Public unsubscribe | `{unsubscribe: @unsubscribe, errors: @errors}`; `@unsubscribe` is only the masked read model from `Unsubscribe.preview` |

`@form_values` is a symbol-keyed hash of permitted form input names, preserving posted text on errors/previews and populated from the model on GET. `@errors` always exists (default `{}`). `@preview`, `@sync_result`, and `@report` can be nil where not yet computed. Views/components use these assigned hashes, not opaque Trailblazer contexts or direct SQL.

Picker contracts: `@templates` = array `{id:, key:, label:, required_vars:, body_template: String|nil}` of active marketing platform templates; `@segments` = `{id:, name:}` for this tenant; `@contacts` = at most 20 `{id:, name:, phone_e164:}` sample choices from this tenant, including a valid specifically selected preview contact. Never load the entire contact database for a select. `@entities` = `{id:, label:}` accessible eligible sources; `@source_fields` = `{phone: [{value:, label:}], scalar: [{value:, label:, type:}]}` for the selected source. Picker labels from stored user data remain user data; application-added wording is translated.

### 9.4 Reporting/export

Report filters: `q`, `status` (recipient status), `message_status`, `skip_reason`, `page`, `per_page`, `sort`, `dir`, all allowlisted. GET/CSV reads never refresh persistent stats or start execution. When cached stats are stale, compute a fresh read-only report and expose `refreshed_at`; jobs separately persist it.

CSV streams all matching recipient ledger rows in ID order, in batches of 100, without truncating at UI pagination. Fixed column keys/order: `campaign_id, recipient_id, contact_id, name, phone_e164, recipient_status, skip_reason, message_id, message_status, dispatch_started_at, sent_at, delivered_at, expires_at, failure_code, provider_segments`. Header labels are localized in both languages. Escape spreadsheet formula-leading user strings using the existing CSV export pattern; timestamps use ISO 8601. Export omits vars, raw responses, evidence, signed tokens, and credentials.

## 10. Implementation ownership and integration sequence

Ownership lanes below are handoff boundaries for downstream parallel implementation. This documentation task performs no delegation or source edits.

| Lane | Owned work | Depends on / shared boundary |
| --- | --- | --- |
| A — domain/data | Additive migrations/schema, five models, template additions, `Sms::Result`, contacts/consent/sync, SMS field catalog/compiler, Reform contracts, segment save/preview | Publish exact schemas/results first; core message/credential columns belong to the same migration owner |
| B — campaign execution/core integration | Campaign save/preview/launch/cancel, snapshots, signed unsubscribe, run/scheduler/stats/report, `Gateway.send_campaign`, core admission and dispatch policy/limiter, due-time recovery integration | A's model/schema/API contract; sole owner of existing SMS delivery/admission files |
| C — controllers/security/navigation | Routes/helpers, explicit authorization, parameter adapters, controller assigns, module registration/access-point catalog, CSV response plumbing | A/B services; frozen section 9. Coordinate reference-helper paths before UI integration. |
| D — frontend/UX | New SMS ViewComponents and thin ERB mounts, forms/tables/review/report/public confirmation, translation keys, platform purpose/preview/common rate fields | Section 9 assigns, UX component props; zero new JavaScript is the default |
| E — verification/docs/release | Integration/spec coverage, paired reference/customer docs, scheduler/config verification, asset/smoke check when source ships | Completed slice artifacts; no assertions of provider delivery without receipt facts |

Recommended integration checkpoints:

1. Freeze this contract; migration/model/result owner publishes interfaces so controller/frontend work can use fixtures with these exact fields/hashes.
2. Implement contacts/append-only evidence/Entity batch sync and fail-closed segment compiler; prove tenant/phone isolation.
3. Implement read-only preview and draft/review surfaces against the fixed input/output hashes.
4. Implement atomic launch/start snapshot, fenced batches, signed unsubscribe, and existing outbox admission linking.
5. Integrate delivery policy/account clock/cancellation in the core final-start path, then recurring recovery/report projections.
6. Integrate reports/CSV/nav/platform classification settings and matching locale/reference docs.
7. Execute scoped and cross-cutting verification, then responsive smoke testing. Backend owners add no adapter-specific campaign send path.

## 11. Acceptance and verification plan for implementation

- Contacts: normalization with explicit country; unique phone/source races; phone change resets permission; archive/restore retains audit; manual/sync input cannot set consent; stale edits fail.
- Entity sync: accessible shared definitions with resolved tenant override; tenant-owned entries only; explicit tel field; missing/incompatible field fails closed; 100-row continuation/high-water bound; replay does not duplicate or grant; source/phone conflicts reported.
- Consent/unsubscribe: append-only audit; evidence requirements; event replay/conflict; revocation precedence; GET/HEAD no writes; signed POST revokes only signed phone/tenant; changed-phone/archived contact cases; START cannot grant/unblock.
- Segments/maps: correct nested left-associative joins, empty root only, wrong casts/custom JSON types, injection/wildcard handling, node/depth/byte bounds, exact vars/fallback semantics, no Ruby evaluation, missing body gives unknown estimate.
- Preview: real read-only run produces counts/samples without messages/recipients/evidence/quota reservations/job enqueue; selected preview contact is tenant-scoped; malformed JSON is preserved for correction.
- Launch/start: save never launches; stale review/schedule/DST/provider readiness rejected; immutable launch snapshots; contact audience snapshots once; atomic snapshot rollback/resume; execution bound; absolute deadline does not slide after quiet hours or outage.
- Delivery: marketing permission through direct/core admission; same contact phone at final gate; pending STOP/revoke/archive blocks; due-time gates in every recovery route; 1..60 campaign admissions/minute; shared credential clock across tenants and direct sends; limiter defer does not create attempt; frequency concurrency serialized; expired/cancelled sends never start.
- Concurrency/outbox: two workers and stale lease tokens; outer transaction rollback; failed enqueue repaired by minute scheduler; unique recipient/message linking; cancel/start race; no resend after ambiguous acceptance/crash; late receipts repair report without changing membership or terminal orchestration status.
- Reports: milestone versus current-state counts, excluded/deferred distinction, skip/cancel reason attribution, unknown not failed, provider segment missing-data count, CSV streaming/filter scope/formula escaping, cross-tenant report denial.
- UI: responsive at 360/768/1280 px; keyboard/semantic forms; server-rendered preview retains unsaved inputs; no-launch action on ordinary save; all wording and validation translated in `en` and `zh-CN` with parity.

Run targeted RSpec for each new model/service/controller/component during implementation. Final delivery-gate/tenant/authorization changes are cross-cutting: use `bin/rails parallel:prepare && bin/rails parallel:spec` when available, otherwise the full RSpec suite. Any added/changed JavaScript requires its corresponding Vitest tests and a real `npx vitest run --coverage` showing 100% lines/branches/functions for touched files; genuinely browser-only behavior also requires Playwright per project policy.

At implementation time update `doc/reference/en/sms.md` and `doc/reference/zh-CN/sms.md` together, plus both `background-jobs.md` pages and both customer SMS guides for these surfaces. Reuse the registered SMS reference page rather than creating a redundant catalog slug. Document Gateway campaign entry, consent/Entity sync/AST/map contracts, account-clock column/configuration, one-minute scheduler, cancellation boundary, and reports. Existing reference descriptions remain current-runtime documentation until code lands.

No runtime tests are required to validate this docs-only deliverable; check Markdown structure, cross-links, field/parameter/assign consistency, and diff whitespace. Runtime verification above is a release requirement for downstream implementation.
