# Email Template — ActionText Source + Persisted body_html

**Date:** 2026-07-23
**Status:** Approved (design)
**Related:** `2026-06-29-email-pure-actionmailer-transport-design.md` (transport stays ActionMailer; this spec is content/compile only)

## Goal

Align rich-text email templates with Rails ActionText as the **authoring** source of truth, while **always persisting** the email-ready HTML the author compiled into `email_templates.body_html`. Preview, test-send, and production send must all consume that same persisted HTML — no divergent compile path.

Do not reinvent ActionMailer transport or drop the customer-editable Lexxy / ActionText editor.

## Hard constraints

1. **Authored content is persisted**
   - `rich_text` → ActionText via `has_rich_text :body` (`action_text_rich_texts`)
   - `code` → authored HTML in `email_templates.body_html`
2. **`body_html` is always the canonical email HTML** for the template row (`null: false` stays). For `rich_text`, it is derived from ActionText on save; for `code`, it is authored directly.
3. **Single HTML path after save:** preview / test-send / Gateway send / campaign queue all interpolate and deliver from `body_html` (via `Emails::TemplateRenderer` → ledger → `Emails::DeliveryMailer`). No preview-only recompile that can diverge from what was saved.
4. **Transport remains ActionMailer** (`Emails::DeliveryMailer`, inline `attachments.inline`). Do not revive hand-rolled `Mail.new` SMTP.
5. **Customer-editable templates stay** (Lexxy + `{{vars}}`). Do not replace DB content with developer-owned `.erb` mailer views.

## Problem (current)

Two divergences made preview ≠ editor:

1. `Emails::CompileTemplate` historically used `ActionText::RichText#to_s`, which wraps content in the ActionText layout (`trix-content` + ERB debug comments). The Lexxy editor shows the content fragment only.
2. Live preview sometimes recompiled / applied tracking independently of the authored HTML, so authors saw tracking pixels and link rewrites that are not part of what they wrote.

Additionally, `CompileTemplate` still owns a hand-rolled Nokogiri CID rewrite. CID attachment at **delivery** already belongs on ActionMailer (`DeliveryMailer#attach_inline_blobs`); the save-time compiler should not invent a parallel email stack.

## Target architecture

```
Author (Lexxy) ──persist──► ActionText body          (rich_text)
Author (HTML)  ──persist──► body_html                 (code)
                              │
                              ▼ on save (rich_text only)
                    sync ActionText fragment → body_html
                              │
                              ▼ preview / test / send
                    TemplateRenderer ({{vars}}, optional tracking at deliver)
                              │
                              ▼
                    Emails::Message ledger → DeliveryMailer
                         (inline blobs via attachments.inline)
```

### Persistence rules

| `editor_type` | ActionText `body` | `body_html` |
|---|---|---|
| `rich_text` | Required (authoring) | Required; synced from ActionText fragment on validation/save |
| `code` | Unused / blank | Required; authored by the user |

Switching editor modes in the UI continues to sync Lexxy ↔ textarea before submit so the active surface's content is what gets saved.

### Save-time sync (rich_text)

Replace the “full email compiler” mental model with a thin **ActionText → body_html sync**:

1. Read the ActionText **content fragment** (`body.body.to_html`), not `body.to_s` (no layout chrome).
2. Rewrite image `action-text-attachment` nodes to `cid:blob-<id>` in persisted `body_html` (single ownership: save-time sync only — same contract `DeliveryMailer#attach_inline_blobs` already expects). Do not rewrite again at preview or deliver.
3. Write result to `body_html`.
4. Collect blob ids via the same helper used by Gateway / campaign (`blob_ids_for`) for `metadata[:attachment_blob_ids]`.

### Preview / test-send

- Load template attrs from the form (unsaved draft) or DB.
- For rich_text **unsaved** drafts: sync fragment → temporary `body_html` with the **same** sync helper used on save (one function), then render.
- Do **not** inject open/click tracking in author preview (`tracking: false`). Tracking remains a deliver-time concern (`DeliverMessageJob` / stream settings).
- Subject + HTML + text come from `TemplateRenderer` against that `body_html`.

### Production send

Unchanged at the orchestration layer:

`Gateway` / `Activities::Send` / campaign job → render from template.`body_html` → persist `Emails::Message` → `DeliverMessageJob` → provider → `DeliveryMailer` for SMTP.

Ensure rich_text templates always have up-to-date `body_html` before enqueue (save path already syncs; unsaved test-send uses the shared sync helper).

## What we will not do

- Drop `body_html` or make ActionText the only stored form for send.
- Replace Lexxy / DB templates with static ActionMailer ERB views.
- Reintroduce custom SMTP `Mail.new` transport.
- Leave a preview path that compiles differently from save.

## Testing

- Unit: ActionText fragment sync produces HTML without `trix-content` / `BEGIN` layout comments; preserves `{{tokens}}`; image attachments become `cid:blob-<id>` (if CID-at-save is chosen).
- Request: preview for rich_text returns fragment-equivalent HTML, no tracking URLs; code templates unchanged.
- Model: saving rich_text updates `body_html` from ActionText; saving code leaves authored `body_html`.
- Regression: `DeliveryMailer` still inlines same-tenant blobs; Gateway / campaign still pass `attachment_blob_ids`.
- Browser (optional): compose in Lexxy → Preview pane matches editor text; no ActionText chrome in iframe.

## Out of scope

- Changing ESP / Postmark providers, streams, suppressions, or campaign fan-out.
- Redesigning the Compose · Preview · Test workspace chrome (already shipped).
- Migrating historical `body_html` rows that already contain layout chrome (optional one-off backfill can be a follow-up plan task if needed).

## Success criteria

1. Author saves rich_text or code → correct content persisted (ActionText and/or `body_html` per rules above).
2. Preview HTML matches the authored fragment the editor shows (modulo `{{var}}` sample interpolation).
3. Send path still uses ActionMailer + persisted `body_html` on the message ledger.
4. No second, divergent HTML compiler for preview vs save.
