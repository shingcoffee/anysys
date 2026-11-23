---
title: "SMS"
summary: "Targeted marketing campaigns and transactional SMS, with consented contacts, platform templates, paced outbox delivery and receipt reconciliation."
---

## Summary

`FeatureModules::Sms::Registration` (module key `sms`) supports targeted marketing campaigns and transactional SMS. Vendors are `Sms::Adapters` subclasses in `app/services/sms/adapters/`: `aliyun.rb` (`delivery_mechanism` `:poll`, and `default!`) and `twilio.rb` (`:webhook`). A new vendor is that one file and `register!`. Shared secrets are `access_key_id` plus encrypted `access_key_secret` on `Sms::Credential`. Vendor-specific non-secrets (sign name, region, from, messaging-service id) live in the JSON `config` blob. There is no per-vendor migration.

`Sms::Template` rows are platform-wide. `provider_template_codes` maps each adapter key to that vendor's template id; `purpose` classifies transactional/marketing content and optional `body_template` mirrors approved content for preview. Tenant data includes contacts, append-only consent evidence, dynamic segments, campaigns, recipient ledgers and messages, plus the opt-out list the tenant is allowed to see. The message ledger is a transactional outbox: admission records `queued`; a background job makes the vendor call after commit. `sent` means API acceptance, not carrier delivery.

The complete **Audience → Content → Schedule → Review** workflow, official Twilio/Braze/Klaviyo/Mailchimp references and implementation APIs are in [SMS audiences and campaigns](sms-campaigns). Manual/explicit Entity contact intake does not grant consent; save and preview do not send, and launch is a separate reviewed action.

## Configure SMS providers

At `/81721200/admin/maintenance/platform/module_settings/sms/credentials`, save a credential for the runtime mode (`production` in Rails production, `sandbox` otherwise), then **assign delivery** to one configured provider in that mode. The app's Sandbox mode does not automatically use a vendor's test credentials. At `/81721200/admin/maintenance/platform/module_settings/sms/templates`, create an **active** template and map its vendor template code and variables for the selected provider. Enable SMS for each tenant before sending from its admin module.

Before enabling a sending task, arrange recipient permission for that purpose, an approved sender/template, permitted destinations and a working opt-out path. SMS marketing permission is recorded separately through append-only grant/revoke evidence on `Sms::Contact`; a new or changed phone starts unknown. Grant never clears suppression, and synchronization never imports consent. Transactional sending retains its core admission rules; an unblocked number or a valid numbering plan is not permission to send.

### Alibaba Cloud SMS (`aliyun`)

1. [Activate SMS](https://help.aliyun.com/zh/sms/getting-started/get-started-with-sms) and create a RAM AccessKey with SMS API permissions. For China domestic sending, complete the required enterprise qualification and real-name registration, and apply for an approved **signature** and **message template**. Follow Aliyun's [API setup](https://help.aliyun.com/zh/sms/getting-started/use-sms-api).
2. Enter `access_key_id`, encrypted `access_key_secret`, approved `sign_name` and `region` (default `cn-hangzhou`), then map the approved `SMS_...` template and variables. `QuerySendDetails` now reads the actual `SmsSendDetailDTOs.SmsSendDetailDTO` response and handles malformed shapes as unknown. There is no Aliyun SMS webhook.
3. Send via `POST /:cid/admin/modules/sms/sends` and inspect the message plus the vendor console's delivery record. Anysys `sent` / `unknown` is **not** a confirmed delivery receipt for this adapter; merely saving the signature or template does not prove vendor approval.

`QuerySendDetails.SendDate` uses `dispatch_started_at`, falling back to `sent_at` and then `created_at` for historical rows, converted to China Standard Time (`Asia/Shanghai`) before formatting the calendar date. Admission time and a response received after midnight do not change the dispatch's query date.

### Twilio (`twilio`)

1. Set up an SMS-capable sender, preferably a [Messaging Service with a sender](https://www.twilio.com/docs/messaging/services). Obtain the **Account SID** and primary **Auth Token**. Enter the SID as `access_key_id`, the Auth Token as encrypted `access_key_secret`, and either `messaging_service_sid` or an SMS-capable `from` number. The Auth Token also verifies incoming callback signatures.
2. In [Twilio Content Template Builder](https://www.twilio.com/docs/content/create-templates-with-the-content-template-builder), create an SMS-capable template and enter its `HX...` Content SID as the platform template's Twilio code. Match the app template variables to its [ContentVariables placeholders](https://www.twilio.com/docs/content/send-templates-created-with-the-content-template-builder) (often `"1"`, `"2"`).
3. Set `APP_HOST` to the external host used for Twilio callbacks. The app generates a status callback at `/sms/webhooks/twilio/delivery` for each message; separately register `POST https://<host>/sms/webhooks/twilio/inbound` on the Twilio number or Messaging Service to receive STOP replies. **Check the generated delivery URL:** this app's production `force_ssl` generates HTTPS, but development defaults to HTTP unless its route URL protocol is configured otherwise. Twilio [signs callback requests](https://www.twilio.com/docs/usage/security) against the **exact public URL**; public scheme/host (and proxy-forwarded scheme) must match the Rails request URL. Test this Content-template flow and a STOP reply with live credentials and a permitted recipient; Twilio [test credentials produce no callbacks and do not support `MessagingServiceSid` on test SMS](https://www.twilio.com/docs/iam/test-credentials).

## Flow

```text
Sms::Gateway.send
        |
        v
Sms::Activities::Send
        |  canonical request / tenant idempotency replay
        |  module / template / vars / marketing consent / opt-out / credential / quota
        v
Sms::Message queued (template snapshot + credential identity + expiry)
        |
        |  outermost commit -> Sms::DeliveryHandoff (best effort)
        |  Sms::RecoverMessagesJob -> repair missed/stale handoff
        v
Sms::DeliverMessageJob
        |  fenced preparation claim -> recheck expiry / module / permission / policy
        |  shared-account pacing -> persist only a due dispatch authorization
        |  persist dispatch_started_at -> adapter.send_message (one attempt)
        +-- API acceptance -> sent + vendor_message_id
        +-- proven rejection -> failed
        +-- ambiguous acceptance / attempted crash -> unknown (no resend)
        |
        +-- Sms::Cron::ReconcileMessages -> query_supported? -> adapter.query
        |
        +-- :webhook (Twilio)
              POST /sms/webhooks/:provider/delivery
              POST /sms/webhooks/:provider/inbound
                    |
                    v
              Sms::WebhooksController -> Sms::ReceiptInbox
                    |  delivery -> Sms::DeliveryProjection
                    |  verified opt-out -> Sms::OptOut.record_global!
```

`Admin::Modules::Sms::SendsController#create` is the admin HTTP handoff. It calls `Sms::Gateway.send` for the URL-derived current customer. New admission to a disabled module returns 404; a genuine idempotency replay still returns its existing ledger row.

## Implementation

### Audience and campaign HTTP surfaces

The SMS module entry opens **Campaigns**. The Modules hub and sidebar follow the Email module: **Campaigns**, **Audience** (Contacts, Segments, and Opt-outs as in-page tabs), and **Messages**. Route access-point descriptors are derived from the registered routes and have localized SMS labels. Each new controller inherits `Admin::Modules::Sms::BaseController`, explicitly checks admin/owner authorization and SMS enablement, and scopes every contact, segment, campaign, recipient, and evidence lookup to the URL-selected customer, including platform-owner browsing.

Segment deletion delegates to `Sms::Audience::DeleteSegment.call(customer:, actor:, segment:)`; draft deletion delegates to `Sms::Campaigns::DeleteDraft.call(customer:, actor:, campaign:)`. These `Sms::Result` APIs own tenant/actor checks, customer-first locking, fresh dependency/state checks and transactional destruction. A draft-referenced segment or retained campaign returns its existing localized 409 conflict; historical segment references are nullified without changing frozen campaign snapshots, contacts, evidence or ledger rows. The platform SMS catalog description reads `Registration.module_description` at render time using paired `sms_campaign_http.registration.description` translations. See [SMS audiences and campaigns](sms-campaigns) for the exact API rules.

Contacts are manually added or explicitly synchronized from supported plain Entities in preview/execute batches of at most 100, with a carried cursor/high-water bound. Consent is recorded separately; phone changes reset it to unknown. Dynamic rules fail closed, and matched is distinct from eligible. Campaigns use field/literal/fallback variables and an optional signed `unsubscribe_url`, save an incomplete draft if needed, then preview/review saved settings before launch. Launch freezes rules/content/settings; execution start atomically captures current membership, contact data and resolved variables (at most 10,000 contacts). Quiet hours, campaign frequency, admission capacity, shared-account pacing, tenant quotas and an absolute deadline govern sending; cancellation stops only unattempted work. Reports/CSV derive from retained recipient/message ledgers. See [SMS audiences and campaigns](sms-campaigns) for the full contract.

Let `S = /:customer_id/admin/modules/sms`. Static Entity-sync routes precede contact `/:id` routes.

| Surface | Routes | Helper prefix `admin_modules_sms_` |
| --- | --- | --- |
| Contacts | Standard CRUD `S/contacts`; DELETE archives | `contacts`, `contact`, `new_contact`, `edit_contact` |
| Consent evidence | POST `S/contacts/:contact_id/consent_events`; append-only | `contact_consent_events` |
| Explicit Entity sync | GET `S/contacts/entity_sync/new`; POST `.../preview`; POST `S/contacts/entity_sync` | `new_contacts_entity_sync`, `preview_contacts_entity_sync`, `contacts_entity_sync` |
| Dynamic segments | Standard CRUD `S/segments`; POST collection/member `preview` | `segments`, `segment`, `new_segment`, `edit_segment`, `preview_segments`, `preview_segment` |
| Campaign drafts | Standard CRUD `S/campaigns`; POST collection/member `preview` | `campaigns`, `campaign`, `new_campaign`, `edit_campaign`, `preview_campaigns`, `preview_campaign` |
| Launch / cancel | POST `S/campaigns/:id/launch`; POST `.../cancel` | `launch_campaign`, `cancel_campaign` |
| Report | GET `S/campaigns/:campaign_id/report`, optionally `.csv` | `campaign_report` |

All admin helpers take customer ID first. New segments preview at `POST S/segments/preview`; existing edits preview at `POST S/segments/:id/preview`, with the segment resolved in the URL tenant. Preview overlays submitted values without saving and retains that record's identity plus the submitted `lock_version`; the returned Save button PATCHes the original segment. Validation rerenders keep the same identity and raw input, and a stale version still conflicts on Save. Missing, malformed, or foreign member IDs return `404`, including owner requests; they never fall back to a new segment.

Canonical input is produced by `Sms::RequestAttributes`; the HTTP body limit is 64 KiB. Unknown/protected parameters, nonscalar form inputs, malformed IDs/integers, malformed JSON, duplicate object keys, and nonobject JSON fields fail before domain mutation. Optional empty IDs become nil; malformed/foreign IDs never become “all contacts.” Input roots are:

```text
sms_contact: phone, name, country_code, timezone, status, custom_attributes_json, lock_version
sms_consent_event: action, occurred_at, reference, statement, notes, event_key
sms_entity_sync: entity_id, phone_field, name_field, country_code, timezone,
                 attribute_map_json, after_entry_id, through_entry_id
sms_segment: name, description, segment_rules_json, lock_version
sms_campaign: name, template_id, segment_id, variable_map_json, send_timing,
              scheduled_local, timezone, quiet_hours_start, quiet_hours_end,
              frequency_window_hours, send_rate_per_minute, deadline_hours, lock_version
```

JSON textarea inputs become canonical `custom_attributes`, `attribute_map`, `segment_rules`, or `variable_map` objects. `Sms::FormValues` retains the original textarea text on validation errors/previews and populates GET forms from persisted data. Consent occurrence times require an explicit ISO 8601 offset; source/actor/phone/customer are fixed by the consent service. `scheduled_local` is `YYYY-MM-DDTHH:mm`; the adapter converts it to UTC `scheduled_at` using the campaign's IANA zone and rejects DST gaps and ambiguous wall times. A blank schedule can remain an incomplete draft. No provider, credential, raw message body, consent projection, campaign state, snapshot, stats, or lease can be set through these forms.

Preview accepts the same campaign fields plus root-level `preview_contact_id`, scoped to this tenant. The shared native form also posts this sample selector on Save: it is validated as tenant-scoped read-only metadata and never forwarded to draft persistence. Rails submit `commit` is transport metadata, not a domain input. Launch accepts only root-level `lock_version` and signed `review_token`; cancellation accepts no editable settings. Archive accepts root-level `lock_version`. The controllers call the frozen `Sms::Contacts::*`, `Sms::Audience::*`, and `Sms::Campaigns::*` result APIs; preview is separate from save and admission.

HTML saves/actions redirect `303` to the record; validation rerenders `422` with full picker/form assigns; stale edit/review and non-draft mutations return `409`. Missing/inaccessible resources and disabled SMS return `404`. JSON uses `{data: ...}` or `{error: {code:, errors: ...}}`, with create `201`, update/action `200`, and launch `202`. JSON campaign data excludes execution tokens and credential snapshots.

Indices expose `@records` as a page array, `@columns`, `@pagination` (`page/per_page/total/total_pages`), and `@filters`; page size defaults to 25 and is capped at 100. Forms expose `@form_values` and `@errors`. Contact detail also supplies paginated `@consent_events`, current `@eligibility`, and `@consent_form_values`. Segment forms supply `@catalog` and `@preview`. Campaign forms/review supply hash pickers `@templates` (active platform marketing templates), `@segments` (tenant-owned), and `@contacts` (at most 20, including a selected sample). Entity sync supplies `@entities`, `@source_fields`, and bounded `@sync_result`. All query work remains in controllers/services.

Reports call `Sms::Campaigns::Report` with `refresh: false`; GET/CSV never persist stats or start execution. Filters are allowlisted `q/status/message_status/skip_reason/page/per_page/sort/dir`. CSV streams every matching recipient in ID order in batches of 100, independently of UI pagination. Fixed columns are `campaign_id, recipient_id, contact_id, name, phone_e164, recipient_status, skip_reason, message_id, message_status, dispatch_started_at, sent_at, delivered_at, expires_at, failure_code, provider_segments`. Headers are localized; timestamps are ISO 8601; formula-leading text is apostrophe-escaped. Variables, raw responses, evidence, signed tokens, and credentials are excluded.

Public `GET /sms/unsubscribes/:token` and `POST` share `sms_unsubscribe_path(token)`. `Sms::UnsubscribesController` skips authentication/MFA only for these actions and retains browser CSRF verification. It delegates signature/purpose/expiry and tenant/contact/phone resolution to `Sms::Campaigns::Unsubscribe`, never to query parameters. GET/HEAD render only `{masked_phone:, already_unsubscribed:}` and do not mutate/enqueue. POST is idempotent; invalid/expired links return localized `404`.

`config/initializers/sms_unsubscribe_path_filtering.rb` extends Rails' display-only `ActionDispatch::Request#filtered_path` for the SMS unsubscribe route. It replaces the complete capability segment with `[FILTERED]` **before** the Rails `Started GET/HEAD/POST` message or controller instrumentation `:path` is emitted, including format suffixes, mounted paths, and router-normalized trailing/repeated slashes. Rails query filtering is retained. The real `PATH_INFO`, URL, path parameters, routing, and signed-token verification are unchanged. Other request paths retain their normal logging. The existing `:token` parameter filter separately masks the token/review-token values in parameter payloads; it does not itself redact tokens embedded in a URL path.

Only the platform owner at customer `81721200` may edit template `purpose` (`transactional/marketing`) and optional `body_template`. Template preview validation uses `Sms::Contracts::TemplatePreview`; a partial PATCH preserves omitted variable/provider-code fields. Platform credential forms accept common `sender_rate_per_second` in addition to registered vendor fields: a finite `0 < rate <= 1`, saved to JSON `config` through `Sms::PlatformCredentialSave` and the existing credential activity. Invalid rate input is retained in the unsaved form model. `dispatch_next_at` remains runtime-only.

### Gateway and HTTP contract

`Sms::Gateway.send(customer:, to:, template_key:, vars:, idempotency_key: nil, mode: nil, provider: nil, expires_at: nil)` returns an `Sms::Message`, normally `queued`, or an audited `suppressed` row for a blocked transactional recipient. New marketing-template admission requires a same-tenant active contact, granted current-phone consent and no suppression; otherwise `Sms::Errors::MarketingIneligible` (a `TemplateVarsInvalid` subclass) is raised. This applies to direct Ruby, HTTP and workflow calls, and the pinned purpose/contact is rechecked at dispatch. Genuine idempotency replay returns the existing message without another send. Ruby `vars: nil` normalizes to `{}`. Outside an enclosing transaction the row is committed before return. Inside a caller transaction it participates in that transaction: rollback removes the row and no delivery job is enqueued. `expires_at: nil` gives a one-hour lifetime from admission; trusted Ruby callers may supply a `Time` or `ActiveSupport::TimeWithZone`. Expiry prevents an unattempted dispatch, not a delivery already in flight.

`Sms::Gateway.send_campaign(customer:, recipient:, at: nil)` is a trusted internal worker API returning `Sms::Message`. It reloads the persisted same-tenant running campaign/recipient, validates frozen content/vars/eligibility, applies current marketing policy and quotas, and atomically admits/links the recipient's sole message using `sms-campaign:<campaign_id>:recipient:<recipient_id>`. Run may supply `at:`; the admission reservation uses the later of that value and `Time.current` sampled after locks, while ordinary callers omit it and idempotent replay preserves the existing admission fact. It uses the launch-pinned template and credential identity, not an arbitrary caller snapshot or today's live template selection. It has no public HTTP endpoint; callers use draft, preview and launch surfaces. See [SMS audiences and campaigns](sms-campaigns).

```ruby
message = Sms::Gateway.send(
  customer: customer,
  to: "+8613800138000",
  template_key: "verify_code",
  vars: { "code" => "1234" },
  idempotency_key: "verification-42"
)
```

`POST /:cid/admin/modules/sms/sends` accepts `to`, `template_key`, optional object `vars` (omission or null means `{}`), and optional `idempotency_key`. The controller applies `Sms::SendStandards` before the Gateway; arrays, strings and other malformed variable shapes remain invalid rather than being coerced into an object. An omitted/null key or a valid bounded blank string becomes absent. Length/encoding checks run before blank normalization, and HTTP rejects control characters, so oversized whitespace or a newline-containing key returns `422`. HTTP clients cannot set `expires_at`; supplying it, even as null, is invalid. Provider/mode, sender, raw text and vendor credentials are not forwarded from the request. Role and tenant guards run before admission.

```json
{
  "to": "+8613800138000",
  "template_key": "verify_code",
  "vars": { "code": "1234" },
  "idempotency_key": "verification-42"
}
```

| HTTP | Meaning |
| --- | --- |
| `202` | Returned message is `queued`, including a queued replay. |
| `200` | Returned row is in any other state, including `suppressed` or a replayed `failed` / `unknown` / `expired`; inspect `status`. |
| `409` | `idempotency_conflict`: the tenant key identifies different request content. |
| `404` | SMS is disabled for a new admission. |
| `422` | `invalid_request`: invalid shapes, phone, template/variables, provider mapping, unsupported HTTP expiry or ineligible marketing contact/consent. |
| `429` | `rate_limited` (with `window`) or `daily_cap_exceeded`. |
| `503` | `credentials_missing`. |

The response contains `message_id`, `status`, `vendor_message_id`, `failure_code`, `failure_message` (translated canned failures; vendor text as recorded), and ISO 8601 `expires_at`. Queue admission is not a receipt; vendor outcomes arrive later in the ledger. The controller retains a `502 transport_error` rescue, but asynchronous vendor failures normally update the message rather than the already-completed HTTP response.

### Adapters and credentials

`Sms::Adapters::Base` requires `key`, `default_display_name`, `config_fields`, `configured?(credential)`, and `send_message(to:, template:, template_params:)` returning `{ vendor_message_id:, raw: }`. Default `delivery_mechanism` is `:poll`, but `query_supported?` defaults to false: an adapter that implements `query(message:)` must opt in. Both Aliyun and Twilio opt in; Twilio uses the official `twilio-ruby` SDK's Message fetch as a fallback for lost callbacks. Webhook adapters implement `verify_webhook!`, `parse_delivery_receipt`, and `parse_inbound` (`{ phone:, keyword: }` for an adapter-classified opt-out). `rate_limit_windows` defaults to one send per minute, five per hour, and ten per day for a phone.

Queries return `{ status:, raw: }`; delivery parsers return an array with `vendor_message_id`, `status` and `raw`. Optional normalized keys are `phone`, `provider_status`, `failure_code`, `failure_message`, `occurred_at` and `segments`; account identity such as Twilio `account_sid` supports binding to the original credential. Normalize status to `:delivered`, `:failed` or `:unknown`, not API acceptance.

Malformed or ambiguous successful-looking vendor responses raise `Sms::Errors::TransportError`, which exposes optional `vendor_message_id` and `payload` readers. Twilio can retain a syntactically validated SID from a malformed resource; Aliyun can retain a validated BizId from an ambiguous SendSms response. Adapters pass the available response/audit hash as `payload`, not an assumed acceptance. The worker records `unknown` with a usable ID and raw/audit facts from either a partial result or that error. After persistence, it reloads the recorded identity to reconcile early receipts; a retained ID also enables queries against the original credential. Neither an ID nor preserved raw facts prove acceptance or delivery. Missing usable IDs or failed persistence can still leave an unresolved outcome, and ambiguity never authorizes another send.

For create/fetch, Twilio keeps the official client for that call and uses `client.http_client.last_response`, when available, to validate the parsed response JSON rather than trusting SDK-coerced dates or error codes. An HTTP `201` with a safe SID but a numeric Message `status`, invalid date or malformed `error_code` raises `TransportError` with that SID and selected audit facts; the attempted message becomes `unknown`, not a false failure or opt-out. Authenticated receipts or valid queries can later resolve it without resending. Only the `AUDIT_FIELDS` allowlist is retained, excluding whole original bodies and extra message-content/credential-echo fields. Transport and signature verification remain with the official SDK; the adapter adds no hand-rolled HTTP protocol.

REST exception envelopes use a separate contract: optional integer `status` must match the SDK's actual HTTP status in `400..599`, rather than the string `status` of a successful Message resource. For a send attempt, a valid HTTP `400` with provider code `21610` is a proven rejection (`failed`) and records global opt-out; code `21211` produces `failed` without creating an opt-out, while missing/HTTP-fallback provider codes, malformed envelopes and HTTP `5xx` remain ambiguous (`unknown`).

`Sms::Credential` is one row per provider and mode, with no `customer_id`. Status `active` requires `configured?`. `Sms::CredentialResolver` prefers `Sms::Adapters.default_key` when that credential is active, otherwise the first active row for the mode. Mode is `production` in production and `sandbox` otherwise. `Sms::Activities::AssignDelivery` activates one credential per mode and disables the rest. `Sms::Activities::SaveCredential` persists the platform form through `AssignDelivery.persist`, using the same locked transaction and rolling back sibling disablement when validation fails.

Missing credential selection raises `Sms::Errors::CredentialsMissing` with the call-time translation of `admin_modules.sms.errors.credentials_missing`; A flowchart `send_sms` step reports it through `FlowchartRuntime::Step.fail` as `send_sms.credentials_missing`. The missing-credential message does not expose internal mode/provider selection details.

`FeatureModules::Sms::Provisioner.call` and `.revoke` return nil. Credentials and templates are not created per tenant. The per-tenant knob is `daily_send_cap` on `FeatureModules::CustomerAssignment`, default `Sms::Activities::Send::DEFAULT_DAILY_CAP` (1000), read by `FeatureModules::DailyCap`. The platform owner sets the non-negative cap beside SMS at `/:cid/admin/maintenance/modules`; tenant admins see the value read-only at `/:cid/admin/settings/modules/sms/daily_cap` (or `/sms`).

### Templates, send, opt-out

`Sms::Template` keys match `\A[a-z0-9_]+\z`. Statuses are `active` and `retired`. `provider_code` reads `provider_template_codes[provider]`. `Send` raises `Sms::Errors::TemplateVarsInvalid` when that code is blank for the resolved provider.

`Send` binds a tenant idempotency key to a SHA-256 canonical request fingerprint: E.164 recipient, template key, sorted scalar variables, and explicitly requested provider, mode and expiry (UTC with microseconds). Resolved defaults and the computed one-hour expiry are excluded, so a genuine replay survives template retirement, provider reassignment or module disablement. Symbol/string variable keys and insertion order normalize alike; changed content raises `Sms::Errors::IdempotencyConflict` (HTTP `409`). Replay checks run before mutable prerequisites, again under the quota lock, and after a uniqueness race. Valid bounded blank keys become nil in Ruby and HTTP; they do not identify a replay.

New internal, workflow and HTTP sends all pass the core module gate. Phone windows across all templates and the tenant day budget reserve together with insertion under `Sms::Quota.synchronize` / `customer.with_lock`; SQLite takes a first write before reads. Suppressed rows do not consume either budget; the daily count also excludes failed/expired rows, while phone windows exclude only suppressed rows.

Admission pins `metadata.template_snapshot` (`key`, selected `provider`, `provider_code`, `required_vars`, `vars`, `purpose`) and `credential_id` / `credential_mode`; marketing messages also link the typed `contact_id`, and campaign messages link `campaign_id`. Delivery builds a template from that snapshot; later template edits/retirement and delivery reassignment cannot replace the admitted payload or select a different credential row. **This is not a credential-secret revision snapshot:** keys and sender/sign/service configuration are read from the retained row at dispatch/query/verification time. Editing or deleting that row can affect outstanding messages and callback verification; no key-rotation guarantee is implied.

`Sms::OptOut` is not `TenantScoped`: verified STOP writes a global NULL-customer suppression; tenant rows apply only locally. `OptOutsController` passes phones from nonsuppressed messages with actual `sent_at` to `visible_to_customer`. Merely probing a suppressed number cannot reveal its global opt-out metadata.

`Sms::WebhooksController` is an API controller; registered poll adapters return 404. Delivery/inbound callbacks verify every retained credential, including disabled rows; a supplied signed Twilio `AccountSid` must match the candidate account. `WebhookCredentialBinding` resolves shared-key modes using recorded vendor ID, credential ID/mode and the authenticated delivery recipient. Inbound STOP can use a unique recorded actual-contact credential when account proof alone remains ambiguous. The resolved identity is passed to `Sms::ReceiptInbox`; uniquely authenticated early receipts persist until correlation, and uniquely authenticated STOP can apply globally without a message match. Unresolved ambiguity returns HTTP 409 before inbox/opt-out writes; no arbitrary mode or request-mode hint is used.

For inbound opt-outs the contact is the adapter's normalized `From`, not inbound `To` (the platform's sender). Delivery correlation uses normalized `To`. A legacy delivery envelope without `phone` may supply raw `To`; the controller validates it, normalizes it to E.164 and copies it into `event[:phone]` before inbox processing. Thus recipient matching still applies when only one credential verified the signature. An invalid supplied contact returns `400 invalid_request` before receipt/opt-out writes; a valid mismatched delivery recipient is not projected onto the recorded message. Missing recipient data is distinct from a supplied invalid value.

Twilio's signed `OptOutType=STOP` is authoritative even for a localized body. Without that classification, recognized keywords are `STOP`, `STOPALL`, `UNSUBSCRIBE`, `CANCEL`, `END`, `QUIT`, `REVOKE` and `OPTOUT`. Signed START/HELP classifications and unclassified START/HELP bodies are ignored. A matched Twilio rejection/receipt code `21610` records global suppression for the recorded recipient. There is no automated global unblock or re-consent path; an inbound reply does not establish positive consent. Inbound Twilio responses are empty `<Response/>` XML and do not generate a reply message. The controller rejects known `Content-Length` above 64 KiB before parsing; streaming limits belong at the edge.

### Phone and payload standards

`Sms::PhoneNumber` wraps maintained Phonelib numbering-plan data behind a strict lexical gate. International input needs `+` or `00`; national input defaults to China (`CN`). Spaces, dots, hyphens and balanced parentheses are display separators; prose, vanity letters, extensions, control characters, malformed parentheses and bare international country-code prefixes are rejected. Input is at most 64 UTF-8 bytes and output is E.164. `Sms::PhoneNumber.normalize(raw, country: "US")` is the app-owned helper's optional country context; the Gateway/HTTP surface does not expose a country override. Validity does not prove assignment, reachability or SMS capability.

`Sms::SendStandards` is the shared SQL-free shape validator used by `Sms::Contracts::Send` and `Sms::MessageAdmission`. Admission bounds the payload before canonical copying, fingerprint generation or idempotency lookup; mutable template/provider prerequisites are checked only for new admission. Limits are bytes, not character counts:

| Input | Bound |
| --- | --- |
| Template key | UTF-8 string, `[a-z0-9_]+`, at most 128 bytes. |
| Idempotency key | Optional UTF-8 string, at most 128 bytes; valid blank strings become absent. HTTP also rejects control-containing keys. |
| Variables | Object with at most 64 unique string/symbol keys; each nonblank UTF-8 key is at most 128 bytes. |
| Variable value | Nonblank UTF-8 string or finite integer/float/decimal; at most 1,024 bytes of text representation. No nested objects/arrays, booleans or nulls. |
| Variable payload | At most 8,192 JSON bytes, including key overhead and escaping. |

Provided variable keys must exactly match the active template's required keys: missing and extra keys both fail validation. These payload bounds are distinct from SMS segment capacities.

### Outbox, dispatch and recovery

`ActiveRecord.after_all_transactions_commit` starts `Sms::DeliveryHandoff` only after the outermost commit. `Sms::DeliverMessageJob` enqueue is best effort: failure clears the accelerator stamp when possible and leaves committed acceptance intact. `Sms::RecoverMessagesJob` scans the ledger every five minutes in the production `config/recurring.yml` schedule. `DeliveryHandoff::RECOVERY_AFTER` is a separate five-minute enqueue-stamp threshold; `DeliveryDispatch::CLAIM_TTL` is a 30-minute preparation lease. These are eligibility thresholds, not delivery-time guarantees.

A conditional claim token fences preparation. Recovery may re-enqueue an unattempted queued row after missed enqueue or stale preparation; a stale worker cannot pass the atomic `DeliveryDispatch.start` update once its token is replaced. Immediately before the vendor call, the worker rechecks expiry, module enablement and opt-out, then persists `dispatch_started_at` and increments `delivery_attempts`. Completion matches that immutable dispatch marker and the original or already-cleared claim token, so an early receipt can clear the token without reopening the attempt. An unattempted expired row becomes `expired`; a disabled module or new opt-out becomes `suppressed`. A STOP after the final check can still race dispatch.

`Sms::Campaigns::DeliveryPolicy` also checks current marketing contact/phone/consent, plus campaign cancellation/failure/deadline, quiet hours and campaign frequency. All sends using the same retained credential share `Sms::DispatchLimiter` and `dispatch_next_at`, with live `sender_rate_per_second` (default 1, finite `0 < rate <= 1`). A future `delivery_due_at` delays handoff/claim/start/recovery without an attempt or a fresh expiry. The one-minute campaign scheduler repairs due work separately from five-minute core recovery; account pacing limits durable starts, not carrier delivery. See [SMS audiences and campaigns](sms-campaigns) and [Background jobs](background-jobs).

Once the attempted marker exists, no worker/recovery path sends the payload again. A proven API rejection becomes `failed`; timeout, malformed acceptance or an attempted worker crash becomes `unknown`. Recovery keeps the sole attempt's token when quarantining a crash, allowing its genuinely late response to record the vendor ID without making the row claimable again. The delivery job has no send retry policy.

Ledger completion alone retries statement/connection failures for at most three attempts per transition (`LEDGER_COMPLETION_ATTEMPTS`). The adapter call and receipt projection are outside that retry block. If acceptance cannot be durably completed, the worker attempts a bounded unknown transition using any retained ID/raw facts. A database update that succeeded before reload failed is not downgraded; a late acceptance may fill missing acceptance facts without overwriting terminal carrier status, raw receipt or failure facts. Exhausting ledger-write attempts is not permission to resend or a guarantee that every fact was saved.

`Sms::Cron::ReconcileMessages` runs every 15 minutes, redrives receipts and queries capable adapters for `pending` / `sent` / `unknown` rows with vendor IDs between a two-minute grace and three-day maximum age. Both eligibility and aging use `COALESCE(dispatch_started_at, sent_at, created_at)`: dispatch first, then historical acceptance/admission fallbacks, rather than new-message admission time. Older unresolved pending/sent rows become `unknown`, not failed dead letters. Queued dispatch recovery is separate. Authenticated late delivery can repair `unknown` or `failed`; later failure/unknown cannot downgrade `delivered`. Expiry stops only an unattempted send.

| State | Meaning |
| --- | --- |
| `queued` | Admitted outbox row; may be preparing or awaiting a worker. |
| `pending` | Existing historical state, not the new-send default. |
| `sent` | Vendor API accepted the sole attempt. |
| `delivered` | Delivery receipt confirms success. |
| `failed` | Proven rejection or actual failed/undelivered receipt. |
| `unknown` | Acceptance/delivery is unresolved; never permission to resend. |
| `suppressed` | Blocked before an external attempt. |
| `expired` | Deadline passed before an external attempt. |

`20261013000100_enhance_sms_delivery_lifecycle` is additive: it adds expiry, enqueue/claim/attempt columns and an outbox index, and changes the new-row default to `queued`. It does not reset databases or convert/retro-send existing `pending` rows. See [Background jobs](background-jobs).

### Receipt diagnostics, segments and logging

`Sms::DeliveryProjection` applies the same normalized facts from callbacks and queries, requiring a supplied recipient to match the recorded E.164 destination. Provider failure code/text feed the ledger. For a normalized delivered event, `delivered_at` uses a valid supplied occurrence time or falls back to processing time. Metadata retains `provider_status`, positive actual `provider_segments` and ISO 8601 `provider_occurred_at` when supplied, including on failed/unknown events. **Provider event time is diagnostic metadata, not delivery proof:** Twilio REST `date_updated` is the resource update time, and a timestamp or segment count alone does not imply `delivered`. Ambiguous zone-less Twilio carrier timestamps stay raw rather than acquiring an invented zone; Aliyun's documented times are parsed in `Asia/Shanghai`.

`Sms::SegmentCalculator.call(text:, **limits)` is a pure advisory counter for **fully rendered text**. GSM-7 default characters cost one septet and extension characters two; non-GSM text uses UTF-16 code units (astral characters cost two). Default single/multipart capacities are 160/153 septets and 70/67 UTF-16 units. Packing never splits a GSM escape sequence or surrogate pair; capacity overrides are supported. Results are `encoding`, `units`, `segments` and `segment_units`:

```ruby
Sms::SegmentCalculator.call(text: "a" * 152 + "^" + "a" * 152)
# => { encoding: :gsm7, units: 306, segments: 3, segment_units: [152, 153, 1] }
Sms::SegmentCalculator.call(text: "😀" * 67)
# => { encoding: :utf16, units: 134, segments: 3, segment_units: [66, 66, 2] }
```

Templates without a preview mirror do not supply rendered text, so a pre-send estimate is unknown; do not infer it from codes/variables. Campaign preview may render the owner's optional `body_template` and estimate that sample, but the mirror is not sent as raw text or substituted for actual provider segments. Neither the calculator nor provider segment metadata is a billing quote.

Parameter logging filters the exact names `vars`, `to`, `From`, `To` and `Body`, including nested `vars[...]` query keys. It does not broadly filter every `body`/`phone` substring. This protects request logs, not the stored payload/raw receipt.

`Sms::DeliverMessageJob`'s own `[sms.deliver]` warning records only the message ID and error class, omitting exception text and provider payloads. Its `sms.send` instrumentation contains outcome, provider and duration. Preserved response/audit facts belong in the ledger.

The message show view renders `Sms::Admin::MessageDetailsComponent` (`app/components/sms/admin/message_details_component.rb` and `.html.erb`). Its responsive details grid shows a localized status explanation, recipient, template key, provider, vendor ID, dispatch start, attempt count, API acceptance time, delivered time, expiry, provider event time/status and actual provider-reported segments. Valid times render as semantic `<time datetime="…">` elements. Missing expiry/segments display Unknown; other missing facts and malformed provider event timestamps display Not recorded. Failure code/text appears only for `failed`. Variable names are shown, but **all values are redacted**; raw response data, template snapshots and credential secrets are not rendered. Stored payloads remain available to backend processing, so screen redaction is not data erasure.

### Four surfaces

| Surface | Path | Controller |
| --- | --- | --- |
| Entries | `/:cid/admin/modules/sms/campaigns`, `/contacts`, `/segments`, `/messages`, `/opt_outs`, and `POST .../sends` | `Admin::Modules::Sms::*`; campaign launch/cancel/report, consent and explicit sync are nested module actions |
| Customer settings | `/:cid/admin/settings/modules/sms` (including `/daily_cap`) | `Admin::ModuleConfigsController` displays `daily_send_cap` read-only and excludes it from PATCH |
| Enable / disable and customer cap | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController`, `ModuleEnablementsController`; owner-only `ModuleOwnerConfigurationsController` writes `daily_send_cap` |
| Platform settings | `/:cid/admin/maintenance/platform/module_settings/sms/credentials` and `/templates` | `Admin::Maintenance::Platform::Sms::CredentialsController`, `TemplatesController`; shared panes on `ModuleSettingsController` |

`MessagesController` scopes `Sms::Message.for_current_customer`. The registration `entries_for("messages")` is the generic module-entries relation for the same model. The sidebar path is the dedicated index.

The module handoff input is `to`, `template_key`, optional `vars`, `idempotency_key` and trusted `expires_at`; output is `message_id` and a status from `Sms::Message::STATUSES`, including `queued` and `expired`. Flowcharts send SMS with the `send_sms` step action, which replaced the SMS channel of the old notify action. Its fields are `templateKey` (a searchable reference to an active platform SMS template), `to` (default `model.phone`), `vars` (literal keys mapped to expression values) and optional `idempotencyKey`; it writes the message id to `resultVar` (default `sms_message_id`). The step calls `FlowchartRuntime::SmsDelivery.deliver`, which goes through `FlowchartRuntime::Sms.send_template` and the Gateway with platform templates and credentials, and maps `Sms::Errors` to `send_sms.*` failure codes (`suppressed`, `quota`, `credentials_missing`, `module_disabled`, `idempotency_conflict`, `marketing_ineligible`, `template_missing`, `api_error`, `invalid_number`, `provider_code_missing`, `invalid_vars`, `failed`). Any returned message that is not `suppressed` is workflow success, not proof of delivery. SMS outcomes/errors never trigger another channel. See [Flowchart runtime](flowchart-runtime) and [Flowchart step actions](flowchart-step-actions).

## Where to pay attention

### Route audit: reservation and receipt invariants

`Sms::ReceiptInbox.record!(credential:, event:, event_key: nil)` accepts authenticated normalized delivery/inbound events, deduplicating credential plus event identity (raw data is excluded). After the vendor ID is recorded, recovery and reconciliation redrive pending receipts. Persisted-state transitions preserve the delivered floor against stale poll/failure/unknown responses. Tenant/user guards remain on admin routes; the core gate controls new admissions without hiding genuine replays. Public callbacks rely on vendor proof, not a browser session. See [Email](email), [Tenancy and roles](tenancy-and-roles), [Background jobs](background-jobs).

SMS idempotency lookups bypass the Active Record query cache. After a real unique-index loser rolls back its persistence savepoint, the service reloads the same customer/key winner without calling the vendor again. That winner must live outside the loser's savepoint; records inserted inside it are correctly rolled back. An index error without a matching tenant/key winner propagates instead of returning another customer's row or pretending the send succeeded.

:::note
Missing receipts, lost vendor IDs and aged query windows can remain unresolved. The ledger distinguishes uncertainty from proven failure; operational verification should exercise live callback signing, query fallback and worker recovery against the configured account.
:::

:::attention
A new vendor is one file under `app/services/sms/adapters/` subclassing `Sms::Adapters::Base` and calling `register!`. The webhook route constraint reads `Sms::Adapters.keys`. Non-secret vendor fields belong in `config` via `config_fields`. `access_key_secret` stays on the encrypted column shared by every adapter. `Sms::Adapters::Aliyun` is `:poll` and is the `default!` adapter. `Sms::Adapters::Twilio` is `:webhook`.
:::

:::attention
`verified_adapters` rejects non-webhook adapters as 404. Delivery/inbound parsing runs only after retained credentials verify the request; original-send identity is resolved before receipt recording. Active-only selection is for new sends.
:::

:::attention
Global NULL-customer opt-outs suppress every tenant. Visibility requires actual sent contact; admission-time suppressed rows are insufficient. Multiple opt-out checks narrow the race but cannot recall a vendor operation already in flight.
:::

:::attention
`Sms::Activities::AssignDelivery` leaves a single active `Sms::Credential` per mode for the whole platform. `FeatureModules::Sms::Provisioner` does not copy credentials onto the customer. The tenant setting on this module is `daily_send_cap`, enforced by `Sms::Quota` under the customer write lock. `Sms::Activities::Send` checks `FeatureModules::Module.enabled?` after genuine replay; dispatch checks it again before the sole external attempt.
:::

## Key code

```ruby
# app/services/sms/adapters.rb
module Adapters
  extend PluginRegistry.build(label: "sms adapter", dir: "app/services/sms/adapters")
end
```

```ruby
# app/models/sms/opt_out.rb
def self.opted_out?(customer_id:, phone_e164:)
  phone = Sms::PhoneNumber.normalize(phone_e164)
  return false unless phone

  where(phone_e164: phone).where(customer_id: [nil, customer_id]).exists?
end

def self.record_global!(phone_e164:, provider: nil, reason: nil)
  upsert_row(customer_id: nil, phone_e164: phone_e164, provider: provider, reason: reason)
end
```

```ruby
# app/controllers/sms/webhooks_controller.rb
provider_class = Sms::Adapters.for(provider)
unless provider_class.delivery_mechanism == :webhook
  raise ArgumentError, "provider #{provider} has no webhook endpoint"
end
```

```ruby
# app/services/sms/activities/send.rb
if created && message.status == "queued"
  ActiveRecord.after_all_transactions_commit { DeliveryHandoff.call(message) }
end
```

```ruby
# config/routes.rb
post "/sms/webhooks/:provider/:kind",
     to: "sms/webhooks#create",
     as: :sms_webhook,
     constraints: ->(req) {
       provider = req.path_info.split("/")[3]
       Sms::Adapters.keys.map(&:to_s).include?(provider)
     }
```
