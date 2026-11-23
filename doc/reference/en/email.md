---
title: "Email"
summary: "Platform email credentials and tenant templates, with SMTP on typed columns and each API vendor in one file."
---

## Summary

`FeatureModules::Email::Registration` (module key `email`) sends transactional and campaign mail. Delivery vendors are `Email::Providers` subclasses in `app/services/email/providers/`: `smtp.rb`, `ses.rb`, and `aliyun.rb`. A new API vendor is that one file and `register!`. Credentials stay on `Emails::Credential`. SMTP is the historical exception that still uses typed columns (`host`, `port`, `username`, authentication, TLS, domain, DKIM). SES and Aliyun store vendor fields in the JSON `config` blob. The encrypted `password` column holds the SMTP password or the API secret.

Credentials are platform-wide, one row per provider and mode. Tenants do not pick a vendor per send. `Email::CredentialResolver` prefers the provider that called `default!` (SMTP) when that row is active, otherwise the first active credential for the mode.

## Configure email delivery

At `/81721200/admin/maintenance/platform/module_settings/email/credentials`, save a credential for the desired provider and mode, then **assign delivery** to one configured provider in that mode. Rails production uses `production`; other Rails environments use `sandbox`. Those app modes do not create vendor test accounts. Enabling the Email module for a tenant does not provision a platform credential. Blank secret fields on edit retain the old value. Test by sending from a tenant email template and checking vendor receipts; a queued or `sent` response is not proof of delivery.

### SMTP (`smtp`)

1. Provision an SMTP server/relay and an account whose `username` **is the intended, relay-authorized From email address**; this app uses `username` as the message's From address. Fill `host`, `port`, `username`, **password**, HELO `domain`, `authentication` (`plain`, `login` or `cram_md5`), and appropriate STARTTLS/SSL switches. This app requires a username and password even when the relay accepts anonymous mail. Use your relay's documented [SMTP authentication](https://www.postfix.org/SASL_README.html) and [TLS](https://www.postfix.org/TLS_README.html) settings.
2. If enabling DKIM, enter a domain, selector, and private key, then publish the displayed TXT public key at `<selector>._domainkey.<domain>` as specified by [RFC 6376](https://www.rfc-editor.org/rfc/rfc6376#section-3.6.2). Verify the DNS record and send a test template. SMTP has no receipt webhook; message status stops at `sent`.

### Amazon SES (`ses`)

1. In the chosen SES `region`, [verify a sending domain or address](https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html), and obtain an IAM access key allowed to send with SES. Apply for [production access](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html) if the **AWS SES** account is still in its own sending sandbox; the Anysys `sandbox` label does not change that restriction. Enter `access_key_id`, its Secret Access Key in the encrypted **password** field, `region`, and the verified `from_email`.
2. Create a **Standard** SNS topic in that SES region, grant SES `sns:Publish`, then on the SES identity's **Notifications → Feedback notifications** select that topic for **delivery, bounce and complaint**. Subscribe the HTTPS endpoint `https://<host>/email/webhooks/ses` to SNS **with raw message delivery disabled**, and fill `sns_topic_arn` in Anysys. SNS sends a signed POST envelope (`Type`, `TopicArn`, `Signature`, nested `Message`), which this endpoint verifies and uses to confirm valid subscription requests. Do **not** send SES EventBridge events or raw SNS messages directly to this endpoint. See [SES feedback notification setup](https://docs.aws.amazon.com/ses/latest/dg/configure-sns-notifications.html) and [SNS HTTP(S) subscriptions](https://docs.aws.amazon.com/sns/latest/dg/sns-http-https-endpoint-as-subscriber.html).
3. Send a tenant template to a real inbox; optionally exercise SES's [mailbox simulator](https://docs.aws.amazon.com/ses/latest/dg/send-an-email-from-console.html) for success, bounce and complaint. The form does not visibly require `sns_topic_arn`, but the provider's readiness check **does**.

### Alibaba Cloud DirectMail (`aliyun`)

1. Activate [DirectMail](https://help.aliyun.com/zh/direct-mail/user-guide/overview) in the selected region, [verify a sending domain's DNS records](https://help.aliyun.com/zh/direct-mail/user-guide/how-to-configure-sending-domain-names), and [create a sending address](https://help.aliyun.com/zh/direct-mail/user-guide/setup-sender-addresses) matching `from_email`. Obtain an AccessKey authorized for [`SingleSendMail`](https://help.aliyun.com/zh/direct-mail/api-dm-2015-11-23-singlesendmail). Enter `access_key_id`, AccessKey Secret in the encrypted **password** field, `region`, `from_email`, and optional `from_alias`; the sending address's SMTP password is **not** used.
2. Set a `webhook_secret` in Anysys. Follow Aliyun's [DirectMail EventBridge event distribution](https://help.aliyun.com/zh/direct-mail/user-guide/set-up-eventbridge) steps: enable distribution and select `acs.dm` **delivery success/failure** events in the sending region. Forward events to `POST https://<host>/email/webhooks/aliyun` through an HTTP target or intermediary that adds `Authorization: Basic <base64(aliyun:<webhook_secret>)>`, or an URL-encoded `?token=<webhook_secret>`. A plain EventBridge POST is rejected with 403; simply saving the secret in Anysys does not authenticate callbacks. Preserve `data.env_id`, `data.rcpt`, and `data.status` in the forwarded body. Older MNS notifications need the same authenticated forwarding path.
3. Inspect a real callback: `0` means delivered; `2`/`3` suppress invalid/spam recipients; `4` is a nonsuppressing failure. Other feedback-report shapes are not complaint events here. The implemented `SingleSendMail` transport rejects CC, BCC, arbitrary Reply-To, CID/inline attachments and campaign one-click messages with `UNSUPPORTED_FEATURE` before quota/queue acceptance and again at dispatch. Campaign one-click headers are not implemented on this transport; use a supported provider for campaigns. Sending readiness does not prove receipt authentication.

## Flow

```text
Emails::Activities::Send
        |  Email::Contracts::Send
        |  TemplateRenderer
        |  Email::CredentialResolver
        |  Emails::Suppression.suppressed? -> status suppressed
        |  customer.with_lock + daily cap
        v
Emails::Message status queued
        |
        v
Emails::DeliverMessageJob
        |  Email::Providers.for(provider)#deliver
        |  SMTP -> Emails::DeliveryMailer.deliver_now, status stops at sent
        |  SES / Aliyun -> API, then webhook
        v
POST /email/webhooks/:provider
        |
        v
Emails::WebhooksController
        |  verify retained credentials, parse_events -> ReceiptInbox
        v
mark_delivered! / mark_bounced! / mark_complained!
        |
        v
Emails::Suppression.record_global! when the event says suppress
```

Opens and clicks are `Emails::TrackingController` at `/email/track/:message_id/...`. Unsubscribe is `Emails::UnsubscribesController` at `/unsubscribe/:token`. Those routes are public.

## Implementation

### Providers

`Email::Providers::Base` declares `key`, `default_display_name`, `config_fields`, `configured?(credential)`, and `delivery_mechanism`. `:none` means status stops at `sent` (SMTP). `:webhook` means the vendor posts delivery, bounce, and complaint events. `uses_webhook_secret?` defaults to true for webhook vendors. SES returns false and verifies the SNS certificate instead of `webhook_secret`. Instance `deliver(message:)` returns `{ provider_message_id:, raw: }` and raises `Email::Errors::ApiError` or `TransportError`. Webhook vendors implement `verify_webhook!(request)` and `parse_events(request)` with event types `:delivered`, `:bounced`, and `:complained`.

`Email::Activities::SaveCredential` writes typed SMTP columns from `TYPED` and puts other fields in `config`. Blank `password`, `dkim_private_key`, and `webhook_secret` keep the stored secret. `Email::Activities::AssignDelivery` activates one credential per mode and disables the others. An active row must pass `configured?`.

`Emails::Credential` validates SMTP-specific fields only when `smtp?`; DKIM fields are required when enabled. `Email::DkimSigner` explicitly signs both List-Unsubscribe headers. `from_address` uses username for SMTP and `config_value(:from_email)` for API providers; a leftover SMTP username cannot override an API sender.

### Send, templates, cap

`Emails::Activities::Send.call` validates with `Email::Contracts::Send`, renders `Emails::Template`, resolves a credential, and records a suppressed message when `Emails::Suppression.suppressed?` matches the tenant and address. The daily cap runs inside `customer.with_lock`. The cap is `FeatureModules::DailyCap` reading `daily_send_cap` on the customer assignment, default `Emails::Activities::Send::DEFAULT_DAILY_CAP` (1000). The platform owner sets that customer's non-negative daily cap from `/:cid/admin/maintenance/modules` beside Email; the tenant sees the current value read-only at `/:cid/admin/settings/modules/emails/daily_cap` (or `/emails`). A new row is `queued` and handed to `Emails::DeliverMessageJob`. A duplicate idempotency key returns the existing message.

`Emails::DeliverMessageJob` conditionally claims due queued mail with a 30-minute lease and up to three attempts, rechecking module, suppression and campaign cancellation before dispatch. Definitive API rejection fails without retry; transport failure releases for retry/recovery. Claims prevent ordinary overlapping dispatch, not vendor exactly-once delivery after an acceptance timeout or expired lease.

`Emails::Template` is tenant-scoped and versioned (`Emails::TemplateVersion`, `Emails::TemplateContent`). Statuses are `draft`, `active`, and `retired`. The new-template form initializes `status: "active"`, so **Activate template immediately** starts checked; unchecking it submits `draft`. A failed creation re-renders the submitted status. Campaign sends are `Emails::SendActivities::SendActivity` against `Emails::Audience::List`. `Email::Cron::ReconcileMessages` and `Emails::SendActivities::Cron::ReconcileSendActivities` are the follow-up jobs.

At `/:cid/admin/settings/modules/emails/template_tokens`, the **Built-in fields** list and the template editor picker use `Emails::TemplateToken#display_label` to show localized names based on each platform token's `source_key`, including legacy rows with labels like `Dispute.provider`. An unrecognized platform field shows a readable name derived from its stored label instead of the same generic title for every row. The built-in list is a closed-by-default disclosure; opening it reveals the read-only tokens and their value sources: recipient account or organization details, a generated unsubscribe URL, or data explicitly supplied by the sending workflow. `Emails::VariableContext.for(user:)` provides recipient account attributes, customer attributes, and the unsubscribe URL for sends that use that context; other platform values must be present in the supplied `vars`, and unavailable values render blank. The **Custom fields** section groups customer-specific tokens by entity ID. Every entity group starts closed, shows its entity name and field count, and opens to show the token names, entity attribute labels, and edit/delete actions. Deleted entities display the localized **Entity unavailable** fallback. The empty state remains visible when no custom fields exist.

At `/:cid/admin/settings/modules/emails/template_tokens/new`, the **Entity** picker lists active tenant-owned or shared Entity definitions. Choosing one shows its not-yet-added schema attributes, all checked by default, with the schema's field names prefilled as editable display names. Admins can clear or select all and submit any nonempty selection in one request. `Emails::TemplateTokens::Operation::BulkCreate` verifies entity access, schema membership, duplicate selections, and existing tokens before creating the batch atomically; invalid submissions keep the chosen entity, selections, and labels. At `/:cid/admin/settings/modules/emails/template_tokens/:id/edit`, the entity-first form shows one field mapping alongside its display name. It preserves the existing custom name on load; choosing another entity picks its first available field and suggests that field's name, and choosing another field suggests its name. Already-added mappings on other tokens are excluded from the dropdown and rejected on update if submitted directly. Custom entity-attribute tokens are insertable into templates, but currently resolve to blank on send because recipient-to-EntityEntry linkage is not yet implemented; both forms state this explicitly.

`FeatureModules::Email::Provisioner.call` and `.revoke` are empty. Enabling creates no credential and disabling deletes no templates. Physical customer deletion delegates to the ownership-aware `Customers::Purge`; it is not an email-wide FK cascade promise. See [Customers](customers).

The handoff contract is `to`, `template_id`, `vars`, and optional `cc`, `bcc`, `reply_to`, `idempotency_key`. The output is `message_id` and `status` (`queued`, `sent`, or `failed`). See [flowchart runtime](flowchart-runtime).

### Flowchart step: send_template_email

The `send_template_email` step action sends a tenant email template from a flowchart. `templateId` (required) is a reference to the `email_templates` source (the customer's active templates), `to` (required) is a ctx path, `vars` maps literal keys to literal values, and `cc`, `bcc`, `replyTo` and `idempotencyKey` are optional expressions. The step calls `Emails::Gateway.send(customer: Customer.find_by(id: ctx[:customer_id]), …)` inside `Step.attempt("send_template_email.failed", Email::Errors::Error)` and writes the message id to `resultVar` (default `email_message_id`). The customer always comes from the run context, never from step input. See [Flowchart step actions](flowchart-step-actions).

### Webhooks

`POST /email/webhooks/:provider` accepts registered webhook providers only. The controller verifies every retained provider credential, including disabled rows. When several rows share a key/topic, `WebhookCredentialBinding` resolves each normalized event using the recorded provider/vendor ID, credential ID/mode and recipient envelope; SES's authenticated sending account must agree with the configured topic account. All events are resolved before inbox/suppression writes. A unique verified identity is passed to `Emails::ReceiptInbox.record!`; an unmatched event with that unique identity is durably retained for post-send/cron correlation. Ambiguous events return HTTP 409 without assigning an arbitrary mode or accepting a request-mode hint. Suppression can apply before message correlation once credential identity is unique. Overwritten keys and metadata-less historical rows are not guessed/backfilled.

### Four surfaces

| Surface | Path | Controller |
| --- | --- | --- |
| Entries | `/:cid/admin/modules/emails/templates`, `/send_activities`, `/lists`, `/dashboard`, plus health, reports, deliverability, engagement, suppressions | `Admin::Modules::Emails::TemplatesController`, `TemplateVersionsController`, `SendActivitiesController`, `SendActivityDeliveriesController`, `SendActivityCancellationsController`, `ListsController`, `DashboardController`, `HealthController`, `ReportsController`, `DeliverabilityController`, `EngagementController`, `SuppressionsController`, `AttachmentsController` |
| Customer settings | `/:cid/admin/settings/modules/emails` (including `/daily_cap`) and `/template_tokens` | `Admin::ModuleConfigsController` displays `daily_send_cap` read-only; `Admin::Settings::Modules::Emails::TemplateTokensController` |
| Enable / disable and customer cap | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController`, `ModuleEnablementsController`; owner-only `ModuleOwnerConfigurationsController` writes `daily_send_cap` |
| Platform settings | `/:cid/admin/maintenance/platform/module_settings/email/credentials` | `Admin::Maintenance::Platform::Emails::CredentialsController`; shared panes on `ModuleSettingsController` |

The module key is `email`. URL segments are `emails`.

## Where to pay attention

### Route audit: admission, outbox, campaign and content invariants

`Emails::Quota.reserve` is the shared tenant-serialized reservation for raw, transactional and campaign mail. Replay precedes mutable validation/cap/provider checks; blanks normalize to nil and duplicate persistence races reload the same ledger. Daily usage excludes suppressed/failed rows across message types; campaign reservation also checks the rolling minute allowance (default 60). Individual scheduled mail books quota on admission day, not physical delivery day.

Idempotency lookups bypass the Active Record query cache, including the lookup after a uniqueness loser rolls back its savepoint. The competing winner must exist outside that savepoint and match the same customer/key. Validation recovery is limited to an `idempotency_key` `:taken` error; unrelated validation/index failures propagate. Delivery due times use the database's microsecond precision; queue scheduling comparisons use the persisted UTC instant.

`Emails::MessageAdmission.validate!(credential:, attributes:)` inspects an unsaved envelope before quota/queue acceptance. `validate_campaign!(template:, credential: nil)` is used by campaign Build/start; template test-send renders controlled UnsupportedMessage feedback. `Email::Providers::Base#supports_message?`/`#validate_message!` share protected `unsupported_features(message:)` with dispatch. Aliyun rejects campaign one-click, CC/BCC/Reply-To and inline MIME features with `UNSUPPORTED_FEATURE`; its adapter implements To plus HTML/text only. The vendor API's Headers/BccAddress/ReplyAddress fields are not implemented here, so campaign admission is rejected rather than promising one-click headers.

Queued messages persist due/enqueued/claim/attempt markers. `DeliveryHandoff` accelerates enqueue; `Emails::Cron::RecoverMessages` repairs due outbox rows and reconciles receipts without prematurely failing future-due mail. Campaign runs have exclusive leases, bounded batches, durable deferral/progress, ledger-derived resume/stats and retryable transient fan-out errors. Build validates active same-tenant template and at most ten lists, then saves parent/joins atomically. Fresh edit/delete guards coordinate with scheduler claims; failed destroy is surfaced. Template subject, body, and editor type cannot change while a non-terminal send activity references the template; a name change still saves. List metadata-only PATCH preserves omitted type/rules.

Template head promotion atomically applies scalar and Action Text content; every version write checks module enablement. Invalid token updates retain the submitted label/entity/attribute values separately from the persisted token, including escaped invalid selections, and render model errors at HTTP 422 without syncing rejected input. Entity access and array/hash bulk shapes remain validated; UUID fallbacks round-trip and colliding labels are qualified rather than choosing an ambiguous winner. Subject/plain text use text normalization; HTML uses HTML normalization. Custom entity-token recipient linkage remains unimplemented.

A selected snapshot is a complete definition, not a patch over live columns: omitted/null `subject` and `body_html` become empty strings, optional `body_text` remains null, and an omitted/null editor type uses the schema's `code` default. Applying an image snapshot restores Action Text attachment identity/metadata and embeds together with compiled CID HTML. Authored markup is preserved without a legacy layout-unwrapping shim. Browser preview replaces CID sources only for blobs owned by the template's customer; unowned/foreign blobs remain CID and never receive a signed browser URL. Token subtitles use the catalog's current localized editor label. Compact table-row actions are scoped separately from the dashboard's accessible menus.

The lifecycle migration `20261011173041` refuses pre-existing queued email rows whose scheduling state is unresolved: resolve or quarantine them before upgrading. Their old primary-ledger data cannot distinguish immediate from deferred delivery, and production Solid Queue is a separate database. The migration adds no historical queue import or runtime old-envelope fallback. Signed unsubscribe payloads require the recorded user, email, and customer; incomplete/invalid payloads are rejected rather than borrowing the current profile's address or tenant.

SMTP and SES use the immutable message tenant/address for body/header unsubscribe tokens. SES uses Mail-built raw MIME for inline attachments, preserves envelope CC/BCC/Reply-To, validates SNS envelope/certificate URL shape before SDK verification, and emits one receipt per affected recipient. Public token unsubscribe skips session MFA. Analytics and campaign `RefreshStats.sent_count` count only `sent`/`delivered`/`bounced`/`complained`; pending, queued, failed and suppressed rows are separate outcomes. Campaign statistics additionally expose `materialized_count`, `pending_count`, `queued_count`, `failed_count` and `suppressed_count`. The device heading has a separate translated key. Generated email/callback URLs share `APP_HOST`, `APP_PROTOCOL` and optional `APP_PORT` (development localhost/http/3000; production requires host and defaults HTTPS).

Email and SMS credential CRUD each share their module's transactional delivery-assignment path with sibling deactivation. Retain historical credentials for outstanding work; recorded IDs cannot recover overwritten secrets. See [SMS](sms), [Background jobs](background-jobs), [Authentication](authentication).

:::note
Provider, admission/receipt, campaign, quota and token/version APIs are source-documented. On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**. Real vendor, queue, and browser results remain outside that suite.
:::

:::attention
`Emails::Audience::SegmentQuery.valid?(rules)` rejects the whole tree when any field/operator/value/group/join is invalid; persisted malformed trees select nobody and write/preview rejects invalid input. Depth/node/value bounds are 12/500/4 KB, typed numeric/date/boolean values are strict, and LIKE wildcards are literal. Only an intentionally empty root selects all tenant users; an all-invalid tree never broadens the list. Aliyun capability rejection occurs before reservation/enqueue and is repeated at dispatch.
:::

:::attention
A new API vendor is one file under `app/services/email/providers/` subclassing `Email::Providers::Base`, then `register!`. Put vendor fields in `config_fields` so they land in `Emails::Credential#config`. `Email::Providers::Smtp` is the exception: `config_fields` is empty, and `Email::Activities::SaveCredential::TYPED` writes `host`, `port`, `username`, authentication, TLS, domain, and DKIM columns. Do not add a column for SES or Aliyun.
:::

:::attention
`Emails::Credential` has no `customer_id`. `Email::CredentialResolver` and `Email::Activities::AssignDelivery` treat credentials as one active provider per mode for the whole platform. `AssignDelivery` disables every other row in that mode. A tenant daily cap is the only per-customer send setting: `FeatureModules::DailyCap` reads it, while only `Admin::Maintenance::ModuleOwnerConfigurationsController` may write it. `Admin::ModuleConfigsController` excludes it from updates. `FeatureModules::Email::Provisioner` does not create credentials.
:::

:::attention
SMTP has no webhook. Receipt verification uses retained credential identity, and blank vendor IDs never correlate to a NULL-ID message. Acknowledgment of an authenticated unmatched event means durable inbox acceptance, not completed message projection.
:::

:::attention
`Emails::DeliverMessageJob` retries transport failures and can deliver twice. The class comment says neither SMTP nor the API call sends a client idempotency key, so a timeout after the vendor accepts the message is sent again on retry. `Emails::Activities::Send` still deduplicates its own `idempotency_key` before enqueue.
:::

## Key code

```ruby
# app/services/email/providers/smtp.rb
def key                  = "smtp"
def default_display_name = "SMTP"
def delivery_mechanism   = :none

def config_fields = []

def configured?(credential)
  credential.host.present? && credential.username.present? && credential.password.present?
end
```

```ruby
# app/services/email/providers.rb
module Providers
  extend PluginRegistry.build(label: "email provider", dir: "app/services/email/providers")
end
```

```ruby
# app/models/emails/credential.rb
# SMTP (the standard protocol) keeps its typed columns (host/port/username/auth/ssl/starttls/
# domain/dkim_*); API vendors (SES, Aliyun, …) store their config in the JSON
# `config` blob.
```

```ruby
# app/services/emails/receipt_inbox.rb — after provider verification
Emails::ReceiptInbox.record!(credential: verified_credential, event: {
  type: :delivered, provider_message_id: vendor_id, email: recipient,
  suppress: false, raw: normalized_data
})
```

```ruby
# config/routes.rb
post "/email/webhooks/:provider",
     to: "emails/webhooks#create",
     as: :email_webhook,
     constraints: ->(req) {
        provider = req.path_info.match(%r{\A/email/webhooks/([^/.]+)(?:\.[^/]+)?\z})&.[](1)
       Email::Providers.keys.map(&:to_s).include?(provider)
     }
```
