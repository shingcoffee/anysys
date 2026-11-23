# Captcha per-page protection — design

**Date:** 2026-09-01
**Status:** Approved (user: approach 1, heuristic C, include checkout + tenant member sign-up; no further confirmation gates)

## Problem

Platform auth captcha is all-or-nothing whenever a provider is active. Customer pages already store `captcha.enabled` on configuration, but Settings → Captcha only shows a count. Owners need per-form toggles on Captcha’s platform module-settings show page; tenant admins need the same for their publicly visible pages on Settings → Captcha.

## Locked decisions

- Platform catalog is **discovered from the route set** (heuristic C), not a handwritten list of three auth forms.
- Include payment checkout and tenant member sign-up.
- Page-builder “Require captcha” stays and stays in lockstep with Settings.
- Customer list = that tenant’s **customer-owned** pages with `visibility = public` (including unpublished).
- Storage: singleton JSON map (not per-vendor credential rows).
- Do not ask for further product confirmation.

## Architecture

### Two catalogs

1. **Platform public forms** — inferred from `Rails.application.routes` at runtime.
2. **Customer public pages** — `Page.for_current_customer.where(visibility: "public")`. Shared pages (`customer_id` NULL) never appear here. The shared `/:cid/page/:uuid` route is **denied** from the platform catalog because it is not a single form.

### Heuristic (platform)

Walk every route. Keep a controller as a candidate when:

1. Path is **public** (does not contain `/admin` or `/member`) — same rule as `RouteAuthorization`.
2. Controller is not on the **denylist** (machine/internal):
   - `rails/*`, `action_mailbox/*`, `active_storage/*`, `turbo/*`, `view_components`
   - `payments/webhooks`, `sms/webhooks`, `emails/webhooks`, `emails/tracking`
   - `oauth/discovery`, `oauth/userinfo`, `doorkeeper/tokens`
   - `locales`, `rails/health`
   - `public_pages` (customer Page records)
3. Controller has at least one **GET** and at least one **POST/PATCH/PUT**.

Then **split** a controller into surfaces when GET form paths differ:

| Surface key | Display path | Notes |
|---|---|---|
| `authentication/sessions` | `/auth/sign_in` | Merge `authentication/sign_in_links` (same form). Fail-closed. **Default on.** |
| `authentication/customer_registrations` | `/auth/sign_up` | Includes resend. Fail-closed. **Default on.** |
| `authentication/passwords` | `/auth/password/new` | Covers request + set-new-password. Fail-closed. **Default on.** |
| `authentication/confirmations` | `/auth/confirmation/new` | Fail-closed. Default off. |
| `authentication/registrations#sign_up` | `/:customer_id/auth/sign_up` | Tenant member sign-up. Fail-closed. Default off. |
| `authentication/registrations#account` | `/auth/edit` | Account edit. Platform fail policy. Default off. |
| `authentication/mfa_sessions` | `/:customer_id/auth/mfa/session` | Fail-closed. Default off. |
| `authentication/mfa_setups` | `/:customer_id/auth/mfa/setup` | Fail-closed. Default off. |
| `authentication/mfa_recoveries` | `/:customer_id/auth/mfa_recovery/new` | Fail-closed. Default off. |
| `emails/unsubscribes` | `/unsubscribe/:token` | Platform fail policy. Default off. |
| `oauth/authorizations` | `/oauth/authorize` | Platform fail policy. Default off. |
| `payments/checkouts` | `/:customer_id/payments/checkout` | Platform fail policy. Default off. |

New public GET+mutate controllers that appear later show up automatically, **off** by default, grouped under “Other” until an i18n name exists.

Display path keeps route placeholders (`:customer_id`, `:token`). Group in the UI: Authentication, Account, MFA, Payments, Email, OAuth, Other.

### Data

**`captcha_surface_settings`** — singleton table (no `customer_id`; platform-wide policy). Justification: these are unscoped/platform forms, not tenant data. Mirror `authentication_platform_settings`.

- `surfaces` JSON object: `{ "<surface_key>": true/false }`
- Missing key → surface `default_enabled?` from the catalog (the three current auth forms true; everything else false)
- Switching captcha **vendor** does not reset this map

**Customer pages** — existing `Page#captcha_enabled?` / `#captcha_enabled=` (`configuration["captcha"]["enabled"]`). Settings toggle writes that flag and saves. Deprovision still strips the `captcha` key.

### Enforcement

`CaptchaProtectable#captcha_required_for_request?`:

- `:page_submit` — unchanged: module enabled for tenant **and** `page.captcha_enabled?`
- Platform surface — `Captcha::ProviderSettings.active` **and** `Captcha::SurfaceSettings.enabled?(key)`
- Widget: `Captcha::WidgetComponent.new(platform: true)` also requires the surface enabled (pass `surface:`). Toggle off → no widget, no verify.

Each catalogued mutating action must call `protect_with_captcha` (auth-grade with `fail: :closed`). Forms that gain protection must render the widget.

`:page_submit` is never gated by the platform map.

### Settings writes

- Owner: `PATCH` nested under platform captcha module settings, body `{ surface_key, enabled }`. Unknown keys rejected. Last write wins.
- Admin: `PATCH` Settings → Captcha page row, scoped `Page.for_current_customer.find(id)`. Shared pages 404.

Trailblazer activities: `Captcha::Activities::TogglePlatformSurface`, `Captcha::Activities::TogglePage`. Reform contracts validate key/boolean and page id.

### Authorization

- Platform list + toggles: existing platform namespace (owner / `81721200` only).
- Customer list + toggles: `/:cid/admin/settings/modules/captcha` (admin or owner). Owner on tenant B sees only B’s pages.
- Member and anonymous: denied (same as today).
- Resolve captcha module by **key**, never hard-code id `2`.

## UI (see companion UX doc)

Platform: Captcha module-settings **show** Settings tab gets a “Protected public pages” card (grouped rows, path + switch using `ModuleToggleComponent` pattern) plus link rows to existing vendor credentials and verification log (those destinations already exist; the show tab is currently empty for captcha).

Customer: replace the count-only panel with the same pattern for public pages (name, public path, launched badge, switch). Keep module-disabled / credentials-missing alerts. Empty state when no public pages.

All new copy: i18n `en` + `zh-CN`. English = the string that would have been hard-coded.

## Error handling

- Provider missing: toggles still persist; widget does not render; forms stay usable.
- Module disabled (tenant): page flags persist; widget/verify stay off.
- Unknown surface key on PATCH: 404, no write.
- Cross-tenant page id: 404.
- Concurrent toggles: last successful write wins.

## Testing

- Catalog spec: denylist exclusions; sessions+sign_in_links merge; public_pages excluded; checkout and tenant sign-up included; `/admin` excluded.
- SurfaceSettings: missing key uses default; explicit false wins.
- CaptchaProtectable: each default-on auth still fail-closed when on; off skips verify; page_submit unchanged.
- Request specs: owner toggle; admin cannot hit platform PATCH; admin toggles own public page; cross-tenant 404; member/anonymous denied.
- Component specs for both lists (empty, grouped, switch aria).
- Widget: `platform: true` + surface off → blank.

## Out of scope

New vendors, fail-policy/score UI, verification log changes, member captcha settings, per-tenant overrides of platform `/auth/*`, changing shared-resource CUD rules.
