# Platform announcements — design (as built)

Date: 2026-08-29

## Problem

The platform owner (customer `81721200`) needs to push a time-bounded notice to some or all tenants. Logged-in customer admins must see it as a top-most banner on every admin page. This is **not** a four-area feature module: there is no Modules entry, no per-tenant Settings page, and no Maintenance/Modules toggle.

## Decisions (locked)

| Topic | Decision |
|---|---|
| Approach | Platform-global `platform_announcements` + banner in admin `ShellComponent` |
| Targeting | `audience: all` (includes tenants created later) or `audience: selected` + a `target_rules` segment AST over `Customer` columns. Empty/unusable rules match **nobody**, never everybody. |
| Audience (who sees the banner) | Tenant `admin`, and the platform `owner`. Members never see it. Resolution is always against the URL's customer, so the owner acting as a tenant sees exactly that tenant's notices. |
| Dismiss | **Persisted** per `(user, customer, announcement)` in `platform_announcement_dismissals`. Session storage was rejected: it resurrects the banner in every new session, browser and device. |
| Multiple live notices | All live notices stack as independent strips, ordered `critical > warning > info` then newest-first, capped at `MAX_VISIBLE`. Each strip has its own dismiss control. |
| Dismiss transport | Turbo Stream `replace` of the whole stack, so the next queued notice slides up immediately. Plain-HTML `redirect_back` fallback for no-JS. |
| Lifecycle | `draft` / `published` **and** optional `starts_at` / `ends_at`, collapsed into `#lifecycle` → `:draft | :scheduled | :live | :ended` |
| Content | Internal `title` (also shown on the banner), `body_en` + `body_zh`, severity `info` / `warning` / `critical`, optional `link_url` |
| Locale | Banner body follows `I18n.locale` (`zh*` → `body_zh`, else `body_en`) |
| Not in scope | Email/SMS, Action Cable live push, markdown/HTML, images, member/public chrome, notifications bell wiring, four-area module surfaces |

## Data model

### `platform_announcements` (platform-global; **no** `customer_id`)

Same justification as `billing_plans`: catalog owned by the platform, not a tenant. CUD only via `/81721200/admin/maintenance/platform/announcements`.

| Column | Type | Notes |
|---|---|---|
| `title` | string, not null | Max 120; rendered on the banner and in CRUD |
| `body_en` | text, not null | Banner English; max 500 |
| `body_zh` | text, not null | Banner Chinese; max 500 |
| `severity` | string, not null, default `info` | `info`, `warning`, `critical` |
| `link_url` | string, nullable | `http`/`https` only; max 2048 |
| `status` | string, not null, default `draft` | `draft`, `published` |
| `audience` | string, not null, default `all` | `all`, `selected` |
| `target_rules` | json, not null, default `{}` | Segment AST; only meaningful when `audience = selected` |
| `starts_at` | datetime, nullable | Live if null or `<= now` |
| `ends_at` | datetime, nullable | Live if null or `> now` |
| timestamps | | |

Index `idx_platform_announcements_live` on `(status, starts_at, ends_at)` — one composite covering the hot banner lookup rather than three single-column indexes.

### `platform_announcement_dismissals`

| Column | Type | Notes |
|---|---|---|
| `platform_announcement_id` | FK, not null, on delete cascade | |
| `user_id` | bigint, not null, FK on delete cascade | `Authentication::User` |
| `customer_id` | integer, not null, FK on delete cascade | Tenant context the dismissal happened in |
| `created_at` | datetime, not null | No `updated_at`: a dismissal is an event, not a mutable row |

Unique `(user_id, customer_id, platform_announcement_id)` — makes `record!` idempotent under double-submit and lets the owner acknowledge per tenant.

### Segment rules

`target_rules` uses the same recursive AST as `Emails::Audience::SegmentQuery` (per-join AND/OR, left-associative), compiled by `PlatformAnnouncements::CustomerQuery` against a whitelist (`CustomerFieldCatalog`). Safety invariants: fields resolve through the catalog only, values bind as Arel parameters, unparseable conditions are dropped rather than compiled to a match-nobody `NULL` comparison.

## Query budget (why it is shaped this way)

The banner renders on **every** admin page, so resolution is bounded regardless of how many announcements exist:

1. one query for live, not-yet-dismissed candidates (`LIMIT CANDIDATE_LIMIT`, newest-first);
2. **at most one more** to evaluate every segment at once — `CustomerQuery.matching_keys` projects each rule set as `CASE WHEN <predicate> THEN 1 ELSE 0 END` over the single viewing-customer row and reads the flags back positionally.

An all-customers-only page costs exactly one query. `spec/services/platform_announcements/resolver_spec.rb` asserts the count does not grow with the number of segmented announcements.

The index table deliberately does **not** show a per-row match count: that would be a full segment `COUNT` per row. The exact figure lives on the detail page (capped roster + total) and in the in-form audience preview.

## Domain API

```
PlatformAnnouncements::TargetRules.parse(raw)        # JSON string | Hash -> rules, #malformed?, #usable?
PlatformAnnouncements::CustomerQuery
  .call(rules:)                                      # -> Customer relation
  .usable?(rules)                                    # empty rules are NOT "everyone"
  .matching_keys(customer_id:, rules_by_key:)        # many segments, one query
PlatformAnnouncements::Contracts::Announcement       # Reform
PlatformAnnouncements::Activities::Save.call(record:, params:)
  # Result = Struct.new(:success?, :model, :errors, :messages, keyword_init: true)
  # errors is attribute => [messages] so the form can highlight the field
PlatformAnnouncements::Resolver.for_customer(customer_id, dismissed_ids:, now:)
PlatformAnnouncements::Resolver.for_viewer(user:, customer_id:, now:)
```

Model (thin): `SEVERITIES`, `STATUSES`, `AUDIENCES`; scopes `published`, `within_window`, `live`, `newest_first`, `dismissed_by`; predicates `all_customers?`, `segmented?`, `live?`, `scheduled?`, `ended?`, `lifecycle`; `targeted_at?`, `matching_customers`, `body_for(locale)`.

Validation lives in the Reform contract, not the model: presence/length of `title`/`body_en`/`body_zh`; inclusion of `severity`/`status`/`audience`; `link_url` `\Ahttps?://`; `ends_at` after `starts_at`; and for `audience = selected`, rules must parse and be usable.

Presentation lives in `Admin::Maintenance::Platform::AnnouncementPresenter` (badges, audience wording, timestamps), not in the controller.

## URLs & auth

### Owner CRUD (platform namespace — path gate already requires `platform_owner?`)

`/:customer_id/admin/maintenance/platform/announcements` — `index`, `new`, `create`, `show`, `edit`, `update`, `destroy`, plus `POST .../audience_preview` (in-form audience sizing; POST because the AST travels in the body).

Controller: `Admin::Maintenance::Platform::AnnouncementsController`. `:"platform_announcements"` is in `Ability#platform_owner_subjects`. Sidebar: Maintenance → Platform → Announcements (after Customers).

### Dismiss (tenant admin URL — **not** platform namespace)

`POST /:customer_id/admin/platform_announcement_dismissals` → `Admin::PlatformAnnouncementDismissalsController#create`.

Tenant admins cannot reach `/admin/maintenance/platform/`, so this must live under the plain admin prefix, where `RouteAuthorization` already requires `admin_or_owner?`. A posted id is only honoured when the `Resolver` would currently return it for `Current.customer_id`, so a forged id cannot write rows for notices the viewer cannot see.

## Banner (admin shell)

Hook: `app/components/shell_component.html.erb` — first child of the shell column, above `Platform::ContextBannerComponent`.

`Platform::AnnouncementBannerComponent`:

- `render?` is true for any admin/owner viewer — the `#platform-announcements` wrapper must stay in the DOM even when empty, because it is the Turbo Stream target a dismissal replaces.
- Severity chrome: info → `bg-info text-white` (`role=status`); warning → `bg-warning text-amber-950` (`role=status`); critical → `bg-danger text-white` (`role=alert`). Wrapper is `aria-live="polite"`.
- Each strip: severity icon, bold title + body, optional `Learn more` (`target=_blank rel="noopener noreferrer"`), and an icon dismiss button labelled `Dismiss announcement: <title>`.
- Responsive: `flex-col` on mobile, `sm:flex-row` from small up; actions never overflow.

## Owner UI

`AdminPageComponent` + `AdminTableComponent` on index; `AnnouncementFormComponent` on new/edit, grouped into Content / Display / Audience cards.

The Audience card mounts `platform-announcement-audience`, which hides the segment builder for "All customers" and drives **Preview audience** — a fetch to `audience_preview` that reports how many tenants match before publishing. All of its copy arrives as Stimulus values from `t()`; the JS holds English defaults only.

The segment builder is reused from `Emails::Audience::SegmentBuilderComponent`, which accepts `output_data:` so this form can hang its own Stimulus target on the hidden JSON field without reaching into the shared markup.

Show page: read-only summary, lifecycle badge, and the matched-tenant roster capped at `MATCHING_CUSTOMERS_LIMIT` with the total reported.

## I18n

| Prefix | File | Content |
|---|---|---|
| `maint_platform.announcements.*` | `maint_platform.en.yml` / `.zh-CN.yml` | CRUD copy, table headers, form labels, audience/lifecycle/severity vocab, preview strings |
| `maint_platform.flash.announcements.*` | same | created / updated / deleted |
| `comp_platform.announcement_banner.*` | `comp_platform.*.yml` | `dismiss_titled`, `learn_more` |
| `chrome.sidebar.maintenance.announcements` | `chrome.*.yml` | `Announcements` / `公告` |

English values are the exact UI strings. Banner **bodies** are data, not I18n keys.

## Testing

- Model: live window, lifecycle states, scopes, all-vs-segment targeting (including a tenant created after an `all` publish), bilingual `body_for`
- Query/rules: `TargetRules` parsing and malformed handling; `CustomerQuery.matching_keys` batching, dropped rule sets, invisible customer
- Resolver: **query budget does not grow with segment count**, candidate cap, dismissal filtering
- Presenter: badge variants, lifecycle labels, count-free audience label, timestamp formatting
- Component: `render?` gates, stacking, severity ordering, cap, stable dom ids, empty wrapper, accessible dismiss label
- Request: owner CRUD; tenant admin/member/anonymous denied on platform CRUD and preview; dismissal persistence across sessions, per-user isolation, idempotency, Turbo Stream response, cross-tenant rejection
- Stimulus: `platform_announcement_audience_controller` at 100% lines/branches/functions

## Out of scope

Feature-module toggle, member/public banners, rich text, scheduling cron jobs (the time window is evaluated at render), live websocket push.
