# Email & Email Campaign — Pure ActionMailer Transport

**Date:** 2026-06-29
**Status:** Approved (design)

## Goal

Both the Email module and the Email Campaign module must send mail **purely
through ActionMailer**, using only first-class, documented ActionMailer APIs
(a `Mailer` action + `deliver_later`, `register_interceptor`,
`register_observer`). No hand-rolled `Mail.new` + `mail.deliver` transport and
no custom delivery-orchestration job.

This swaps **only the transport layer**. Every piece of business logic that is
*not* transport is preserved verbatim: the `Emails::Message` ledger,
idempotency, the daily send cap, per-mode DB SMTP credentials, campaign
fan-out, DKIM signing, and — critically — the customer-editable rich-text
template content (`has_rich_text :body`, the Lexxy editor, `TemplateRenderer`,
`CompileTemplate`, the variable picker).

> **Scope guard.** A prior same-day attempt (preserved in git tag
> `backup/email-actionmailer-refactor-2026-06-29`) was rolled back because it
> bundled this transport change together with destroying the customer-editable
> template system (replacing DB-stored content with developer-owned `.erb`
> views). The transport idea in that attempt was sound; the content destruction
> was not. **This design changes transport ONLY and must not touch template
> content, rendering, or the editor.**

## Current architecture (post-rollback, what exists today)

Both modules converge on one path:

```
Email::Gateway.{send | send_raw | queue_for_campaign}
  → Emails::Message row created (status: queued)   # ledger: idempotency, audit, campaign dedup
  → Email::DeliveryJob.perform_later(message.id, mode:)
      → CredentialResolver.call(mode:)             # per-mode Emails::Credential from DB
      → Email::Adapters::Smtp#deliver(message)
          → Mail.new { ... }                       # HAND-ROLLED — bypasses ActionMailer
          → Email::DkimSigner.sign!(mail, credential)
          → mail.delivery_method(:smtp, settings_from_db)
          → mail.deliver
      → message.mark_sent!  /  mark_failed!(code:)  (retry_on DeliveryFailed, attempts: 3)
```

`EmailCampaigns::SendCampaignJob` fans out per recipient through
`Gateway.queue_for_campaign`, sharing the exact same transport.

The **only** non-ActionMailer pieces are `Email::Adapters::Smtp` (the
`Mail.new` transport) and `Email::DeliveryJob` (its orchestrator). Everything
upstream — rendering, the ledger row, idempotency, the cap — is business logic
and stays.

## Target architecture (pure ActionMailer)

```
Email::Gateway.{send | send_raw | queue_for_campaign}
  → Emails::Message row created (status: queued)   # UNCHANGED
  → Emails::DeliveryMailer.with(message_id:, mode:).deliver_email.deliver_later
      → ActiveJob → ActionMailer::MailDeliveryJob   # framework default, NOT subclassed
        → interceptor (Emails::DkimInterceptor): DKIM-sign before send
        → SMTP send (delivery_method_options from DB credential, native override)
        → observer (Emails::DeliveryObserver): message.mark_sent!
```

### New components (ActionMailer-native)

1. **`Emails::DeliveryMailer < ApplicationMailer`**
   (`app/mailers/emails/delivery_mailer.rb`)
   - Single action `deliver_email`. Reads `params[:message_id]` and
     `params[:mode]` via `.with(...)`.
   - Loads the `Emails::Message` ledger row, which is **already fully rendered**
     (subject, body_html, body_text, to/from/cc/bcc/reply_to) by
     `TemplateRenderer` upstream. Returns early (delivers nothing) if the row is
     missing — mirrors the existing guard pattern.
   - Builds the multipart body **explicitly from the pre-rendered strings** (no
     ERB view, because content is already rendered):
     ```ruby
     mail(headers) do |format|
       format.text { render plain: message.body_text.to_s }
       format.html { render html: message.body_html.to_s.html_safe }
     end
     ```
   - Resolves the per-mode credential via the existing `CredentialResolver` and
     passes SMTP settings the **native** way through `delivery_method_options:`
     on the `mail(...)` call — the documented per-message override; keeps
     credentials in the DB, not in static `config.action_mailer.smtp_settings`.
   - Inlines tenant-scoped attachment blobs (logic moved **verbatim** from the
     retired adapter: only blobs owned by `message.customer_id`, via
     `ActiveStorage::Blob.for_customer`, with `attachments.inline[...]` +
     `content_id` `<blob-ID>`).
   - Stamps two correlation headers so the interceptor/observer act without
     guessing:
     - `X-Anysys-Message-Id` → `Emails::Message#id`
     - `X-Anysys-Mode`       → the resolved mode (interceptor re-resolves the
       same credential for DKIM)

2. **`Emails::DkimInterceptor`** (`app/mailers/emails/dkim_interceptor.rb`)
   - `delivering_email(mail)` hook — the standard ActionMailer signing seam.
   - Reads `X-Anysys-Mode`, resolves the credential through `CredentialResolver`,
     calls the existing `Email::DkimSigner.sign!(mail, credential)` (KEPT — it
     wraps the mature `dkim` gem and is not transport).
   - No-op when the credential has no DKIM configured (`DkimSigner` already
     guards this internally).

3. **`Emails::DeliveryObserver`** (`app/mailers/emails/delivery_observer.rb`)
   - `delivered_email(mail)` hook — fires only on successful delivery.
   - Reads `X-Anysys-Message-Id`, loads the row, calls `message.mark_sent!`.

4. **Registration** (`config/initializers/email_delivery.rb`)
   - `ActionMailer::Base.register_interceptor(Emails::DkimInterceptor)`
   - `ActionMailer::Base.register_observer(Emails::DeliveryObserver)`

### Changed components

- **`Email::Gateway`** — keeps its three public methods (`send`, `send_raw`,
  `queue_for_campaign`) and all upstream logic (idempotency, credential
  resolution, ledger creation, rendering). The **only** change: each method
  enqueues via
  `Emails::DeliveryMailer.with(message_id: message.id, mode: mode).deliver_email.deliver_later`
  instead of `Email::DeliveryJob.perform_later(...)`.
- **`Email::Activities::Send`** — same single change at its enqueue step
  (line ~54): `DeliveryMailer...deliver_later` instead of `DeliveryJob`.

### Failure handling (ActionMailer-native)

The custom `Email::DeliveryJob`'s `retry_on Errors::DeliveryFailed` +
`mark_failed!` moves onto the mailer:
- `Emails::DeliveryMailer` declares `rescue_from StandardError` (or the specific
  `Net::SMTP*` family) → `@message&.mark_failed!(code:, message:)` then re-raise
  so ActiveJob's retry/backoff still applies.
- Retries use ActiveJob's native retry on the framework
  `ActionMailer::MailDeliveryJob` (configure `retry_on`/backoff at the mailer or
  job layer to match the old `attempts: 3, wait: :polynomially_longer`).
- `Errors::DeliveryFailed` is retained for `mark_failed!` code mapping but is no
  longer raised by a hand-rolled adapter; the mailer maps `Net::SMTP*` errors to
  it for ledger bookkeeping.

### Retired components

- `Email::Adapters::Smtp` — deleted (its `Mail.new` build + blob-inline +
  smtp_settings logic migrates into `DeliveryMailer`).
- `Email::DeliveryJob` — deleted (replaced by the framework
  `ActionMailer::MailDeliveryJob` via `deliver_later`).

## Preserved unchanged (must NOT be touched)

`Emails::Message` ledger + status transitions · idempotency keys · daily cap ·
`CredentialResolver` + per-mode `Emails::Credential` · `Email::DkimSigner`
(`dkim` gem wrapper) · `Email::VariableContext` · `Email::TemplateRenderer` ·
`Emails::CompileTemplate` · `Emails::Template#has_rich_text :body` · the Lexxy
editor + `template_variable_picker_controller.js` · `EmailCampaigns::*`
(audience, fan-out, scheduler) — `SendCampaignJob` continues to call
`Gateway.queue_for_campaign`, unaware the transport beneath changed.

## Part B — Lexxy as the default Action Text editor

Investigation shows Lexxy is **already the default**, not a pending migration:
- `gem "lexxy", "~> 0.1.26.beta"` in the Gemfile; `import "lexxy"` in
  `application.js`; `pin "lexxy"` in `config/importmap.rb`.
- `Emails::Template` uses `has_rich_text :body`; the template form renders
  `f.rich_text_area :body`, which Lexxy overrides to emit `<lexxy-editor>`.
- `template_variable_picker_controller.js` already targets `<lexxy-editor>`.

Remaining work is **cleanup + verification**, scoped strictly to the Trix
**editor** assets (the editing-UI chrome Lexxy replaces). The Action Text
**content-display** styling stays, because Lexxy emits the same canonical Action
Text HTML and rendered/saved emails still rely on those rules.

**Trix EDITOR assets to remove (editing UI only):**
- `app/assets/stylesheets/actiontext.css` — strip the **editor-chrome** rules:
  everything targeting `trix-editor`, `trix-toolbar`, and `trix-button*`
  (toolbar, dialogs, in-editor attachment controls, caption editors). Lexxy
  ships its own editor styles, so these are dead.
- `template_editor_mode_controller.js` — remove the "Trix" comments/naming;
  the live element is `<lexxy-editor>`.
- `app/controllers/admin/modules/emails/attachments_controller.rb:6` — the
  "Trix / Action Text attachment" comment → "Lexxy / Action Text attachment".

**KEEP (content display, NOT the editor):**
- The `.trix-content` rules in `actiontext.css` (headings, blockquote, lists,
  pre, images, attachment galleries) — these style **displayed** rich text, and
  Lexxy's stored output is the same Action Text HTML, so they remain in effect.
- `app/views/layouts/action_text/contents/_content.html.erb` —
  `<div class="trix-content">` is the canonical Action Text content wrapper
  (shared by Lexxy and Action Text rendering). Left unchanged so saved emails
  keep their styling.

**Cannot be removed (transitive, document only):**
- The `action_text-trix` gem is a **transitive dependency** of Rails'
  `actiontext` (`actiontext 8.1.2 → action_text-trix ~> 2.1.15`). It cannot be
  dropped without removing `actiontext`, which Lexxy and `has_rich_text` both
  require. It remains in `Gemfile.lock` but is unused at runtime — note this in
  the cleanup commit so it isn't mistaken for a leftover.

> **Memory note:** `rails-generators-clobber-spec-helpers` says the Trix CSS was
> "kept as-is by design." That stays largely true — only the dead **editor**
> chrome is removed; the **content-display** styling is retained. Update the
> memory to reflect this finer distinction after implementation.

**Verification (real browser):** `<lexxy-editor>` renders, loads an existing
body, accepts attachment direct uploads, the variable picker inserts `{{token}}`
into it, and previously-saved rich-text content **still displays styled** (the
`.trix-content` display rules are retained).

## Testing strategy (moderate-scope slice)

Delete:
- `spec/services/email/adapters/smtp_spec.rb`
- `spec/jobs/email/delivery_job_spec.rb`

Add:
- `spec/mailers/emails/delivery_mailer_spec.rb` — renders multipart text+html
  from a queued `Emails::Message`; sets correlation headers; native
  `delivery_method_options`; inlines only same-tenant blobs (cross-tenant blob
  id is ignored); early-returns on missing row.
- `spec/mailers/emails/dkim_interceptor_spec.rb` — signs when credential
  configured (delegates to `DkimSigner`); no-op otherwise; resolves credential
  by `X-Anysys-Mode`.
- `spec/mailers/emails/delivery_observer_spec.rb` — `mark_sent!` on the row keyed
  by `X-Anysys-Message-Id`.

Keep green (preserved behavior):
- `spec/services/email/activities/send_spec.rb`, `gateway_spec.rb`,
  ledger/idempotency/cap specs, `spec/jobs/email_campaigns/send_campaign_job_spec.rb`.

Run scope: the `spec/mailers/emails`, `spec/services/email`, `spec/jobs/email*`,
and `spec/jobs/email_campaigns` slices (a feature-slice change spanning both
modules' transport — not a full-suite change).

## Out of scope

- Any change to template content, rendering logic, or the variable picker's
  insertion behavior (the editor stays Lexxy; only dead Trix **editor** chrome
  is removed — content-display styling is retained).
- Removing the Action Text content-display styles (`.trix-content`) or the
  content wrapper — these still style displayed Lexxy/Action Text output.
- Removing the `action_text-trix` transitive gem (impossible without dropping
  `actiontext`).
- Switching SMTP credential storage, DKIM algorithm, or the campaign audience
  engine.
- Drag-and-drop email builders (GrapesJS/Unlayer) — explored and deferred.
