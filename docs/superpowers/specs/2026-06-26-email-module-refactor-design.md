# Email Module Refactor — Design Spec

**Date:** 2026-06-26
**Status:** Approved for planning
**Scope:** `emails` (transactional infrastructure) + `email_campaigns` (marketing) modules

---

## 1. Summary

Refactor the email subsystem across five areas:

- **(a)** Rich-text template authoring via **Action Text + Active Storage**, with variable placeholders and **tenant-isolated** image storage.
- **(b)** Variable replacement at send time, resolved from the recipient **User** and associations.
- **(c)** **DKIM** signing of all outgoing mail, configured at the platform level on the email credential.
- **(d)** Campaign audience moves from a separate `Subscriber` entity to a **reflection-driven, tenant-safe query over `Authentication::User`** and its associations. Lists become saved dynamic query definitions.
- **(e)** A **Block-List**: a per-user flag that suppresses **campaign** email only (transactional unaffected), with admin unblock (single + batch).
- **(f)** One enhancement: **test-send / preview-to-me**.

### Guiding architectural change

`EmailCampaigns::Subscriber` and the entire "Subscribers" surface are **retired**. `Authentication::User` becomes the single campaign audience. "Deliverable" = "not blocked". The transactional pipeline (`Email::Gateway.send` / `Email::Activities::Send`) keeps its **public API unchanged**, so flowchart `send_email` code generators and password/payment mail are untouched.

Per AGENTS.md, **no backward compatibility** is required — dropped tables/models are removed outright.

---

## 2. Decisions (locked)

| # | Decision | Choice |
|---|---|---|
| D1 | Subscriber model fate | **Retire** Subscriber + Subscribers menu/schema entirely; Users are the audience |
| D2 | DKIM scope | **Platform-level**, stored on the (global) email credential |
| D3 | Segment query breadth | **Full generic query** over all User associations — implemented as a reflection-driven, schema-whitelisted, parameterized, tenant-scoped builder |
| D4 | List types | **Dynamic query only** (no static manual lists, no join table) |
| D5 | Rich-text editor | **Action Text + Active Storage** (`has_rich_text`), with tenant-isolated storage and CID image embedding for sent mail |
| D6 | Enhancements (f) | **Only test-send/preview-to-me** |
| D7 | Subscribers menu | **Removed** along with controller, views, model, and schema. email_campaigns nav becomes **Campaigns / Lists / Block-List** |

---

## 3. Item (a) — Rich-text template editor

### Behavior
- Install Action Text + Active Storage (`bin/rails action_text:install`).
- `Emails::Template` gains `has_rich_text :body`.
- **`body_html` stays as the email-safe derived cache**, regenerated from `body.to_s` on save by a new `Emails::CompileTemplate` activity. The preview iframe, `Email::TemplateRenderer`, and the SMTP adapter continue to operate on `body_html` unchanged.
- `editor_type`: keep **`rich_text`** (default — Action Text/Trix) and **`code`** (raw-HTML textarea editing `body_html` directly). **Drop the unused `builder`** value from `EDITOR_TYPES`.
- **Variable insertion:** a `template-variable-picker` Stimulus controller adds an "Insert variable ▾" dropdown to the Trix toolbar; selecting a token writes `{{token}}` at the cursor. Token list comes from `EmailCampaigns::FieldCatalog` (see §6) plus the template's declared `variables`.

### `Emails::CompileTemplate` activity
On template save, for `rich_text` templates:
1. Render `body.to_s` → HTML.
2. Rewrite Action Text attachment markup (`<action-text-attachment>` / `<figure>`) into `<img>` tags referencing the attachment blobs by a stable token (resolved to CID at delivery — see §3.1).
3. Store the result in `body_html` (the canonical email body).

For `code` templates, `body_html` is authored directly; no compilation step.

### 3.1 Storage tenant isolation (critical)

Active Storage is **not tenant-aware by default**. The defaults are unsafe here:
- `ActiveStorage::DirectUploadsController` creates blobs with no customer association and no authorization.
- Blob-serving routes authorize only by a global `signed_id`, with no `customer_id` check.
- `action_text_rich_texts` and `active_storage_blobs` have no `customer_id` column.

**Isolation design:**

1. **Stamp every blob with `customer_id`** — add `customer_id` column + index to `active_storage_blobs`, set at upload time. Every admin query/serve verifies `blob.customer_id == current_customer.id`.
2. **Tenant-scoped upload endpoint** — new `POST /:cid/admin/modules/emails/attachments` guarded by `require_admin_or_owner!`, creates the blob and stamps `customer_id`. The Trix editor is pointed at this route (`direct_upload_url` + blob-URL template) instead of `/rails/active_storage/...`. The default unauthenticated direct-upload route is not used for these uploads.
3. **Tenant-scoped admin preview** — a controller that verifies `customer_id` before redirecting to the blob, so an admin of tenant A cannot fetch tenant B's image even with a leaked `signed_id`.
4. **CID inline embedding for delivered mail (default)** — `Emails::CompileTemplate` + the SMTP adapter resolve template image attachments into the `Mail` object with `Content-ID`s and rewrite `<img src>` to `cid:…`. Image bytes travel **inside the MIME body to the addressed recipient only**; there is **no hosted public URL**, hence **zero cross-tenant serving surface** for delivered email. This also makes images email-client-safe.
5. **Storage key partitioned by customer** (`customer_<id>/…` key prefix) — defense-in-depth grouping at the backend.
6. **Action Text content** isolation is transitive through the tenant-scoped `Emails::Template` (lookups use `for_current_customer`), now backed by per-blob `customer_id`.

**Net:** admin-side (upload/preview/attach/manage) is hard-scoped by `customer_id` on the blob; delivery-side carries no hosted asset (CID).

---

## 4. Item (b) — Variable replacement at send

- `Email::TemplateRenderer.interpolate` (`{{var}}`, `{{nested.path}}`) is kept as-is and runs on `body_html` and `subject`.
- New `Email::VariableContext.for(user:)` builds the interpolation hash from the recipient **User + associations** (e.g. `first_name`, `last_name`, `email`, `customer.name`, and association attributes), so campaign tokens resolve against real User data.
- **Transactional callers are unchanged** — they continue to pass `vars:` explicitly to `Email::Gateway.send`.
- Save/preview validates that `{{tokens}}` referenced in subject/body are resolvable against the declared variables / field catalog.

---

## 5. Item (c) — DKIM signing (platform-level)

- `email_credentials` gains: `dkim_enabled` (bool, default false), `dkim_domain` (string), `dkim_selector` (string), `dkim_private_key` (**encrypted** text).
- New `Email::DkimSigner` service. The SMTP adapter, after building the `Mail` object and **before `deliver`**, adds a `DKIM-Signature` header when the resolved credential has `dkim_enabled`. Canonicalize headers + body and sign with the RSA private key (selector + domain).
- Applies to **all** outgoing mail (transactional **and** campaign) per item (c).
- Platform-owner credential settings UI (Maintenance / Platform area) renders the DKIM fields and **displays the DNS TXT record** (selector + public key) the admin must publish — minimal but required for DKIM to function.

---

## 6. Item (d) — User-based list / segment builder

### Models
- **Retire** `EmailCampaigns::Subscriber`, `EmailCampaigns::ListSubscriber`, tables `email_subscribers` + `email_list_subscribers`, services `SegmentEvaluator` + `UnsubscribeHandler`.
- `EmailCampaigns::List`: `list_type` collapses to **dynamic-only**; stores `segment_rules` (JSON AST). Drop `has_many :email_subscribers`/join associations. `Campaign` still `belongs_to :email_list`.

### `EmailCampaigns::AudienceQuery` (replaces `SegmentEvaluator`)
Reflection-driven builder that compiles the `segment_rules` AST into an `ActiveRecord::Relation` on `Authentication::User`:
- **Always scoped to the current customer** on the root.
- Joins associations as required by the referenced fields; **every joined tenant-scoped table is also constrained by `customer_id`**.
- Returns a **relation** (efficient `.count` + batched `find_each` for sending) — no more `.select` over arrays.

**Generic-but-safe contract (D3):**
- Field identifiers (association path + column) are **validated against AR reflections + column metadata** — a whitelist derived from the schema, never free-form SQL.
- Values are **bound as query parameters**; operators map to safe Arel predicates.
- Unknown/invalid field or operator → rejected (no silent pass-through to SQL).
- Supported operators (carried forward + extended): `equals`, `not_equals`, `contains`, `not_contains`, `greater_than`, `less_than`, `after`, `before`, `is_blank`, `is_present`. AND/OR grouping via `match: all|any` and nested groups.

### `EmailCampaigns::FieldCatalog`
Introspects `Authentication::User` reflections/columns and returns available **entities → fields → operators → value-types**, served to the builder UI (and used to populate the template variable picker).

### List builder UI (`/admin/modules/email_campaigns/lists/new`)
- A condition builder with AND/OR groups and entity/field/operator/value pickers, built as ViewComponents + a Stimulus controller. Designed via the frontend-design plugin / `anysys-ux-designer`.
- The matched-user **count** remains on the list `show` page (already computed there today, repointed to `AudienceQuery`). No in-builder live preview/sample (dropped per D6).

### Campaign send path
- Audience resolved via `AudienceQuery` → `Authentication::User` relation, **excluding blocked users** (see §7), iterated in batches by `SendCampaignJob`. `Email::Gateway.queue_for_campaign` renders per-user via `VariableContext` and `TemplateRenderer`.

---

## 7. Item (e) — Block-List

### Schema (per user instruction — flag on `users`)
- `users.email_campaign_blocked` (boolean, default false, **not null**) + index.
- `users.email_campaign_blocked_at` (datetime, nullable).

### Scope
- The flag is consulted **only for campaign sends** (`message_type: "campaign"`) — applied in `AudienceQuery` / `Gateway.queue_for_campaign` via `where(email_campaign_blocked: false)`.
- **Transactional mail never consults the flag**, so payment / password-setup / confirmation email is unaffected.

### Opt-out flow
- Campaign emails carry an unsubscribe link signed with a Rails message verifier (**no token column needed**).
- The public unsubscribe controller verifies the signed payload and sets `email_campaign_blocked = true` + `email_campaign_blocked_at = now`. This **replaces** the old subscriber-token flow (`email_campaigns/unsubscribes`).

### Block-List admin surface
- New `Admin::Modules::EmailCampaigns::BlockListController` (admin area, `require_admin_or_owner!`).
- **Index:** blocked users (email, name, blocked-at), tenant-scoped to `current_customer`'s users.
- **Unblock one:** clears the flag + timestamp for a single user (ownership-checked: `customer_id == current_customer.id`).
- **Batch unblock:** checkbox-select + "Unblock selected" collection action; all targets re-verified against `current_customer`.
- Nav: new **Block-List** entry in `FeatureModules::EmailCampaigns::Registration.sidebar_contributions`. The **Subscribers** entry is removed. Resulting nav: **Campaigns / Lists / Block-List**.

---

## 8. Item (f) — Test-send / preview-to-me

- From the template (and/or campaign) screen, an admin can send a **test copy to themselves** (or a typed address within their tenant) using **sample variable values** drawn from the field catalog / a chosen sample user.
- Goes through the normal `Email::Gateway` path (DKIM-signed), marked so it is not counted as a campaign delivery.

---

## 9. Data model summary

**Drop:**
- Tables `email_subscribers`, `email_list_subscribers`.
- Models `EmailCampaigns::Subscriber`, `EmailCampaigns::ListSubscriber`.
- Services `EmailCampaigns::SegmentEvaluator`, `EmailCampaigns::UnsubscribeHandler` (subscriber-based).
- Subscribers controller, views, routes, factories, specs.

**Add:**
- `users.email_campaign_blocked` + `email_campaign_blocked_at` (+ index).
- `email_credentials` DKIM columns (`dkim_enabled`, `dkim_domain`, `dkim_selector`, `dkim_private_key` encrypted).
- Action Text + Active Storage tables; `active_storage_blobs.customer_id` (+ index).
- `has_rich_text :body` on `Emails::Template`.

**Change:**
- `EmailCampaigns::List` → dynamic-only `segment_rules`.
- `Emails::Template::EDITOR_TYPES` → drop `builder`.
- Campaign audience resolution → `AudienceQuery`.
- Registration nav → remove Subscribers, add Block-List.
- Routes: drop `email_campaigns/subscribers`; add `email_campaigns/block_list` (index + unblock + batch_unblock); add `emails/attachments` (upload + preview); repoint public unsubscribe to the user-based flow.

**New services / components:**
- `Emails::CompileTemplate` (activity), `Email::DkimSigner`, `Email::VariableContext`, `EmailCampaigns::AudienceQuery`, `EmailCampaigns::FieldCatalog`.
- ViewComponents: list condition builder, variable picker, block-list table; Stimulus controllers: `template-variable-picker`, condition-builder, block-list batch-select.

---

## 10. Security & multi-tenancy

- All admin surfaces under `/:cid/admin/modules/...` guarded by `require_admin_or_owner!`. Public unsubscribe stays public. DKIM/credential config in the platform-owner area only (`81721200`).
- **`AudienceQuery`**: `customer_id` enforced on the root and every joined tenant-scoped table; identifiers whitelisted from schema; values parameterized → no SQL injection.
- **Storage**: per-blob `customer_id`, tenant-scoped upload/preview controllers, CID delivery (§3.1).
- **Block-List**: actions scoped to `current_customer`'s users; ownership-checked on (batch) unblock.
- **Block flag** consulted for campaign mail only; transactional mail bypasses it.

---

## 11. Testing focus (RSpec, multi-tenant + authz emphasis)

- **Models:** `Authentication::User` block flag + scope; `EmailCampaigns::List` (dynamic-only); `Emails::Template` rich-text + `EDITOR_TYPES` change.
- **`AudienceQuery`:** generic coverage across associations; **SQL-injection-safety** (malicious field/operator/value rejected or parameterized); **tenant-isolation** (never returns another customer's users).
- **Storage isolation:** admin of tenant A cannot upload-to / preview / attach a blob owned by tenant B.
- **`DkimSigner`:** signature header present + verifiable; absent when disabled.
- **Send pipeline:** transactional send unaffected by block flag; campaign send excludes blocked users; CID images embedded.
- **Block-List requests:** auth required; batch unblock; cross-tenant denial.
- **Components:** list condition builder, variable picker, block-list table.
- **System:** list builder end-to-end + rich-text editor with variable insertion.
- Scope: this is a **cross-cutting refactor** (auth/tenant scoping + multiple modules) → run the **full suite** per AGENTS.md.

---

## 12. Out of scope

- Static/manual lists (D4).
- In-builder live audience preview / sample recipients, `List-Unsubscribe` one-click headers, auto-suppression on bounce/complaint (deferred per D6).
- Per-customer DKIM identities (platform-level only per D2).
- Inline-image hosting via public CDN URLs (CID embedding is the chosen path).
