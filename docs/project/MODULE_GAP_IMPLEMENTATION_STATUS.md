# Module Functionality Gap Implementation — Status

**Branch/worktree:** `worktree-examin-module-functionality` (`.worktrees/examin-module-functionality`)
**Status: COMPLETE.** All 11 in-scope gaps implemented, specced, and verified.

**Context:** Audited all 6 feature modules on `/81721200/admin/maintenance/platform/module_settings/` for backend features lacking a frontend UI. Found 12 gaps; scoped to **11** (dropped the auth platform-wide settings page as unneeded — auth is mandatory-always-on with per-customer config only).

**Design rule:** Mirror the existing admin design system (`AdminTableComponent`, `AdminPageComponent`, payment raw-`<table>` cards, `BadgeComponent`, `.card`/`.btn`/`.input-field`, `Member::PageSectionComponent`). No new aesthetics — consistency was the requirement. Every user-facing string is I18n with both `en` and `zh-CN`.

---

## Verification (all green)
- **RSpec: 174 examples pass** — 25 new specs + 149 regression specs across every touched area (ability, member security, payment components, module_settings, email templates, auth users, auth/email registrations, email_campaigns).
- **I18n:** all 26 new keys resolve in both `en` and `zh-CN`; en/zh-CN key parity holds across all 8 touched locale files; all locale YAML valid.
- **Routes:** all new routes resolve; helper names match usage.
- **Boot:** clean.
- Request specs render every new view end-to-end (assert 200 + expected content), so views compile and render correctly.

**Not yet done (optional):** manual browser screenshot pass. Request specs already render all new views; pages reuse established, already-styled components, so visual-regression risk is low. Run a browser smoke if a visual sign-off is wanted.

---

## Gaps implemented

### Payment
- **Reconciliation bill download** — `member { get :download }`; `reconciliations_controller#download` (send_data, tenant-scoped, `attached?` guard); download cell in `reconciliation_table_component`.
- **Webhook event ledger + redrive** (platform-owner, cross-tenant) — `webhook_events_controller` (index + redrive re-enqueues `ProcessWebhookEventJob`); `webhook_event_table_component`; nav card in platform `module_settings/show`.
- **Module-level subscription creation** — `activities/create_subscription.rb` (card-recurring against a member's vaulted card); `subscriptions_controller` new/create with `Contracts::Subscribe` via OpenStruct; `subscription_form_component`; "New subscription" button on the table.

### Email
- **Template test-send recipient input** — inline `form_with` on templates/edit (controller already read `params[:to]`).
- **DKIM DNS TXT copy button** — reused `clipboard_controller.js` (no JS change); record was already rendered.
- **Daily send cap editable** — added `configuration_schema`/`configuration_keys` to `FeatureModules::Email::Registration` (mirrors SMS). Requires server restart to re-seed schema.

### Email Campaigns
- **Stalled failure-reason banner** — danger banner on campaign show when `status == "failed"` (renders the stored string verbatim).

### Captcha
- **Verification history browser** (platform-owner, cross-tenant) — `verifications_controller` (AdminTableComponent + resolver, provider/outcome/window filters); index view; "View verifications" link on the settings card.

### Authentication
- **Audit-log viewer** (Modules / Authentication) — `events_controller` over `Authentication::Event.for_customer(cid)`; index view; sidebar entry.
- **Trusted-device management** — admin card + `user_trusted_devices_controller#destroy` on the user show page; member section + `member/trusted_devices_controller#destroy` on the security page. Added `:route_member_trusted_devices` to `Ability#member_route_subjects` (required for the member DELETE to pass CanCan).
- **Deleted dead `user_role_assignment_dialog` stub** — assignment already works via `user_role_dialog_controller.js`.

---

## Key facts / gotchas (for future work in this area)
- **Auth is path-based** (`RouteAuthorization` in `ApplicationController`): `/admin/*` → `admin_or_owner?`; `/admin/maintenance/platform/*` → `platform_owner?`; `/member/*` → `member?`. Do NOT add per-controller role `before_action`s. Still MUST scope queries by `customer_id` (+`user_id` for member-owned).
- **New member routes need a CanCan grant:** add the route subject to `Ability#member_route_subjects` (`app/models/ability.rb`) or the member DELETE/POST 302-redirects to `/#{cid}` via `handle_access_denied`. Admins/owners get `can :manage, :all` so admin routes need no allowlist entry.
- **Not-tenant-scoped models (cross-tenant by design):** `Authentication::Event` (use `for_customer(cid)` for the tenant view), `Captcha::Verification`, `Payments::WebhookEvent` (ledger MUST be global — `customer_id` is nil for the received/failed events needing redrive).
- **Payment admin tables use raw `<table>`** (mirror `transaction_table_component`); auth/captcha listings use `AdminTableComponent` + `ModuleEntriesResolver` (mirror `emails/messages` + `users#index` for filters). The `filters:` hash carries both resolver keys (`scope:`/`column:`) and component keys (`label:`/`options:`).
- **`ReconciliationBill`:** provider ∈ `wechat_pay|alipay`, bill_type ∈ `all|success|refund`.
- **Never put `I18n.t` in a `configuration_schema`** — serialized to JSON at boot, freezes locale; label localized in the generic form via `admin_misc.module_config.fields.<key>.<field>`.
- **`Payments::Subscription#mark_active!` requires `psp_agreement_id`** which card-recurring subs lack — activate via explicit `update!(status: "active", next_charge_at: ...)`.
- **App renders `RecordNotFound` as a 404 response** in test env (assert `have_http_status(:not_found)`, not `raise_error`).
